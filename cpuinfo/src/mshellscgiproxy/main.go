// mshellscgiproxy is an SCGI proxy that sits between nginx and DSM's
// synoscgi daemon, augmenting SYNO.Core.System.info responses with the
// MSHELL bootloader version and live sensor data.
//
// Wire layout:
//
//	nginx --unix:/run/synoscgi_ms.sock--> mshellscgiproxy --unix:/run/synoscgi.sock--> synoscgi
//
// SCGI protocol (RFC-ish): one request per connection.
//
//	Request : <netstring-length>:CONTENT_LENGTH\0<n>\0SCGI\01\0...,<body>
//	Response: HTTP-style headers \r\n\r\n body
//
// Behavior:
//   - Request leg (client → upstream) is forwarded byte-for-byte.
//   - Response leg (upstream → client) is buffered up to maxBufferedBytes.
//     When the buffered body contains a `"firmware_ver"` field we treat it
//     as a SYNO.Core.System.info payload and inject:
//
//       firmware_ver : appended with " / <bootloader version>"
//       sys_temp     : first non-zero hwmon temp*_input value (°C)
//       fan_list     : every non-zero hwmon fan*_input value (RPM)
//
//     Content-Length is rewritten when present. Responses larger than the
//     buffer cap stream through unmodified.
//
// Reimplementation of wjz304's synoscgiproxy for the MSHELL loader.
package main

import (
	"bytes"
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

	// Hard cap for buffered responses. Larger payloads are streamed through
	// without inspection. SYNO.Core.System.info is well under this.
	maxBufferedBytes = 4 * 1024 * 1024
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
	contentLenRe = regexp.MustCompile(`(?im)^(Content-Length:[ \t]*)\d+`)
)

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
// present or the surrounding object cannot be parsed.
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

// patchResponse splits a CGI/SCGI response at the first header/body
// boundary (\r\n\r\n or \n\n), patches the body if it looks like
// SYNO.Core.System.info, and rewrites Content-Length when present.
// Returns the input unchanged when no patch applies.
func patchResponse(resp []byte) []byte {
	for _, sep := range []string{"\r\n\r\n", "\n\n"} {
		idx := bytes.Index(resp, []byte(sep))
		if idx < 0 {
			continue
		}
		headers := resp[:idx]
		body := resp[idx+len(sep):]

		if !bytes.Contains(body, []byte(`"firmware_ver"`)) {
			return resp
		}

		patched := patchJSON(body)
		if bytes.Equal(patched, body) {
			return resp
		}

		newHeaders := contentLenRe.ReplaceAll(headers,
			[]byte(fmt.Sprintf("${1}%d", len(patched))))

		out := make([]byte, 0, len(newHeaders)+len(sep)+len(patched))
		out = append(out, newHeaders...)
		out = append(out, sep...)
		out = append(out, patched...)
		return out
	}
	return resp
}

// proxyResponse reads up to maxBufferedBytes from upstream so it can splice
// patches into the body. If the response exceeds the cap, the buffered
// prefix is flushed and the remainder is streamed through unmodified.
func proxyResponse(upstream, client net.Conn) error {
	limited := io.LimitReader(upstream, maxBufferedBytes+1)
	buf, err := io.ReadAll(limited)
	if err != nil && len(buf) == 0 {
		return err
	}

	if len(buf) > maxBufferedBytes {
		// Response is larger than the buffer; flush prefix verbatim and
		// stream the rest without inspecting it.
		if _, werr := client.Write(buf); werr != nil {
			return werr
		}
		_, werr := io.Copy(client, upstream)
		return werr
	}

	patched := patchResponse(buf)
	_, werr := client.Write(patched)
	return werr
}

func handleConnection(client net.Conn) {
	defer client.Close()

	upstream, err := net.Dial("unix", upstreamSock)
	if err != nil {
		fmt.Fprintf(os.Stderr, "upstream dial %s: %v\n", upstreamSock, err)
		return
	}
	defer upstream.Close()

	var wg sync.WaitGroup
	wg.Add(2)

	// Request leg: client → upstream, byte-for-byte.
	go func() {
		defer wg.Done()
		_, _ = io.Copy(upstream, client)
		if uc, ok := upstream.(*net.UnixConn); ok {
			_ = uc.CloseWrite()
		}
	}()

	// Response leg: upstream → client, with body patching.
	go func() {
		defer wg.Done()
		if err := proxyResponse(upstream, client); err != nil {
			fmt.Fprintf(os.Stderr, "proxyResponse: %v\n", err)
		}
		if uc, ok := client.(*net.UnixConn); ok {
			_ = uc.CloseWrite()
		}
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
