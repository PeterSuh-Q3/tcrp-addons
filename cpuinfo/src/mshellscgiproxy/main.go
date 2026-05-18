// mshellscgiproxy is a FastCGI proxy that sits between nginx and DSM's
// synoscgi daemon, augmenting SYNO.Core.System.info responses with the
// MSHELL bootloader version and live sensor data.
//
// Wire layout:
//
//	nginx --unix:/run/synoscgi_ms.sock--> mshellscgiproxy --unix:/run/synoscgi.sock--> synoscgi
//
// Behavior:
//   - Forwards every FastCGI record verbatim except FCGI_STDOUT from upstream.
//   - Buffers STDOUT records per request, parses the trailing JSON body, and
//     injects `firmware_ver` suffix, `sys_temp`, and `fan_list` fields when
//     the body looks like a SYNO.Core.System.info response.
//   - Rewrites HTTP Content-Length to match the modified body, then re-emits
//     the body as a stream of STDOUT records terminated by an empty record.
//
// Reimplementation of wjz304's synoscgiproxy for the MSHELL loader.
package main

import (
	"bytes"
	"encoding/binary"
	"flag"
	"fmt"
	"io"
	"net"
	"os"
	"os/signal"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
	"sync"
	"syscall"
)

const (
	upstreamSock = "/run/synoscgi.sock"
	listenSock   = "/run/synoscgi_ms.sock"
	versionFile  = "/usr/mshell/VERSION"
)

var loaderVerFlag = flag.String("LOADERVERSION", "",
	"Override bootloader version (default: read from "+versionFile+")")

func bootloaderVer() string {
	if v := strings.TrimSpace(*loaderVerFlag); v != "" {
		return v
	}
	b, err := os.ReadFile(versionFile)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error reading bootloader version: %v\n", err)
		return ""
	}
	return strings.TrimSpace(string(b))
}

// cpuTempC returns the first non-zero hwmon CPU temperature in degrees C.
func cpuTempC() int {
	matches, _ := filepath.Glob("/sys/class/hwmon/hwmon*/temp*_input")
	for _, m := range matches {
		b, err := os.ReadFile(m)
		if err != nil {
			continue
		}
		v, err := strconv.Atoi(strings.TrimSpace(string(b)))
		if err == nil && v > 0 {
			return v / 1000
		}
	}
	return 0
}

// fanSpeeds returns every non-zero hwmon fan RPM reading.
func fanSpeeds() []int {
	matches, _ := filepath.Glob("/sys/class/hwmon/hwmon*/fan*_input")
	var out []int
	for _, m := range matches {
		b, err := os.ReadFile(m)
		if err != nil {
			continue
		}
		v, err := strconv.Atoi(strings.TrimSpace(string(b)))
		if err == nil && v > 0 {
			out = append(out, v)
		}
	}
	return out
}

var (
	fwRe         = regexp.MustCompile(`"firmware_ver"\s*:\s*"([^"]+)"`)
	contentLenRe = regexp.MustCompile(`(?i)(Content-Length:\s*)\d+`)
)

// patchJSON modifies a SYNO.Core.System.info JSON body in place semantically.
// Returns the original buffer untouched when no `firmware_ver` field is present.
func patchJSON(body []byte) []byte {
	if !bytes.Contains(body, []byte(`"firmware_ver"`)) {
		return body
	}

	if ver := bootloaderVer(); ver != "" {
		body = fwRe.ReplaceAllFunc(body, func(m []byte) []byte {
			sub := fwRe.FindSubmatch(m)
			return []byte(fmt.Sprintf(`"firmware_ver":"%s / %s"`, sub[1], ver))
		})
	}

	if t := cpuTempC(); t > 0 {
		body = injectField(body, "sys_temp", fmt.Sprintf(`,"sys_temp":%d`, t))
	}

	if fans := fanSpeeds(); len(fans) > 0 {
		parts := make([]string, len(fans))
		for i, f := range fans {
			parts[i] = strconv.Itoa(f)
		}
		body = injectField(body, "fan_list",
			fmt.Sprintf(`,"fan_list":[%s]`, strings.Join(parts, ",")))
	}

	return body
}

// injectField splices snippet immediately before the closing `}` of the
// JSON object that contains "firmware_ver". No-op if the key is already
// present or the object cannot be parsed.
func injectField(body []byte, key, snippet string) []byte {
	if bytes.Contains(body, []byte(`"`+key+`"`)) {
		return body
	}
	fwIdx := bytes.Index(body, []byte(`"firmware_ver"`))
	if fwIdx < 0 {
		return body
	}
	depth := 0
	inStr := false
	esc := false
	for i := fwIdx; i < len(body); i++ {
		c := body[i]
		if esc {
			esc = false
			continue
		}
		if inStr {
			switch c {
			case '\\':
				esc = true
			case '"':
				inStr = false
			}
			continue
		}
		switch c {
		case '"':
			inStr = true
		case '{':
			depth++
		case '}':
			if depth == 0 {
				out := make([]byte, 0, len(body)+len(snippet))
				out = append(out, body[:i]...)
				out = append(out, snippet...)
				out = append(out, body[i:]...)
				return out
			}
			depth--
		}
	}
	return body
}

// fixContentLength rewrites the HTTP Content-Length header so it matches the
// post-patch body. The CGI response is expected to use CRLF separators.
func fixContentLength(data []byte) []byte {
	sep := bytes.Index(data, []byte("\r\n\r\n"))
	if sep < 0 {
		return data
	}
	bodyLen := len(data) - sep - 4
	return contentLenRe.ReplaceAll(data, []byte(fmt.Sprintf("${1}%d", bodyLen)))
}

// FastCGI record header (RFC: 8 bytes, big-endian).
type fcgiHeader struct {
	Version       uint8
	Type          uint8
	RequestID     uint16
	ContentLength uint16
	PaddingLength uint8
	Reserved      uint8
}

const (
	fcgiVersion1   = 1
	fcgiStdout     = 6
	maxRecordBytes = 65535
)

func writeRecord(w io.Writer, recType uint8, reqID uint16, content []byte) error {
	hdr := fcgiHeader{
		Version:       fcgiVersion1,
		Type:          recType,
		RequestID:     reqID,
		ContentLength: uint16(len(content)),
	}
	if err := binary.Write(w, binary.BigEndian, hdr); err != nil {
		return err
	}
	if len(content) > 0 {
		if _, err := w.Write(content); err != nil {
			return err
		}
	}
	return nil
}

// upstreamToClient is the response leg: it parses upstream FCGI records,
// rebuilds STDOUT bodies, patches them, and re-emits chunked STDOUT records.
// Non-STDOUT records pass through unchanged.
func upstreamToClient(up, client net.Conn) {
	defer func() {
		if uc, ok := client.(*net.UnixConn); ok {
			_ = uc.CloseWrite()
		}
	}()

	buffers := make(map[uint16]*bytes.Buffer)

	for {
		var hdr fcgiHeader
		if err := binary.Read(up, binary.BigEndian, &hdr); err != nil {
			return
		}

		content := make([]byte, hdr.ContentLength)
		if hdr.ContentLength > 0 {
			if _, err := io.ReadFull(up, content); err != nil {
				return
			}
		}
		if hdr.PaddingLength > 0 {
			pad := make([]byte, hdr.PaddingLength)
			if _, err := io.ReadFull(up, pad); err != nil {
				return
			}
		}

		if hdr.Type != fcgiStdout {
			if err := binary.Write(client, binary.BigEndian, hdr); err != nil {
				return
			}
			if len(content) > 0 {
				if _, err := client.Write(content); err != nil {
					return
				}
			}
			if hdr.PaddingLength > 0 {
				if _, err := client.Write(make([]byte, hdr.PaddingLength)); err != nil {
					return
				}
			}
			continue
		}

		buf := buffers[hdr.RequestID]
		if buf == nil {
			buf = &bytes.Buffer{}
			buffers[hdr.RequestID] = buf
		}

		if hdr.ContentLength > 0 {
			buf.Write(content)
			continue
		}

		// Empty STDOUT signals end-of-stream for this request.
		patched := fixContentLength(patchJSON(buf.Bytes()))
		for len(patched) > 0 {
			n := len(patched)
			if n > maxRecordBytes {
				n = maxRecordBytes
			}
			if err := writeRecord(client, fcgiStdout, hdr.RequestID, patched[:n]); err != nil {
				return
			}
			patched = patched[n:]
		}
		if err := writeRecord(client, fcgiStdout, hdr.RequestID, nil); err != nil {
			return
		}
		delete(buffers, hdr.RequestID)
	}
}

func handleConnection(client net.Conn) {
	defer client.Close()

	up, err := net.Dial("unix", upstreamSock)
	if err != nil {
		fmt.Fprintf(os.Stderr, "upstream dial %s: %v\n", upstreamSock, err)
		return
	}
	defer up.Close()

	var wg sync.WaitGroup
	wg.Add(2)

	go func() {
		defer wg.Done()
		_, _ = io.Copy(up, client)
		if uc, ok := up.(*net.UnixConn); ok {
			_ = uc.CloseWrite()
		}
	}()

	go func() {
		defer wg.Done()
		upstreamToClient(up, client)
	}()

	wg.Wait()
}

func main() {
	flag.Parse()

	_ = os.Remove(listenSock)
	l, err := net.Listen("unix", listenSock)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Failed to listen on local socket: %v\n", err)
		os.Exit(1)
	}
	if err := os.Chmod(listenSock, 0o666); err != nil {
		fmt.Fprintf(os.Stderr, "chmod %s: %v\n", listenSock, err)
	}

	sig := make(chan os.Signal, 1)
	signal.Notify(sig, syscall.SIGINT, syscall.SIGTERM)
	go func() {
		<-sig
		_ = l.Close()
		_ = os.Remove(listenSock)
		os.Exit(0)
	}()

	for {
		c, err := l.Accept()
		if err != nil {
			continue
		}
		go handleConnection(c)
	}
}
