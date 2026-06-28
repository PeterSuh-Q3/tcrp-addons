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
//     In SYNO.Core.System.info (matched by "firmware_ver"):
//       firmware_ver : appended with " / <bootloader version>"
//       sys_temp     : first non-zero hwmon temp*_input value (°C)
//       fan_list     : every non-zero hwmon fan*_input value (RPM)
//
//     In SYNO.Core.System.GpuInfo.list (matched by "support_gpu"), which is
//     where DSM 7.4's Info Center reads the GPU section from:
//       support_gpu  : flipped false -> true when a gpu_info array exists
//       gpu_info     : GPU array from /run/mshell_gpu_info.json (see gpuInfoFile)
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
	versionFile  = "/usr/mshell/VERSION"

	// gpuInfoFile holds the SYNO.Core.System "gpu_info" array (a JSON array
	// of GPU objects) precomputed by cpuinfo.sh, which resolves the adapter
	// name via lspci and the clock/memory via sysfs. DSM 7.4 rewrote the
	// Info Center GPU section to render from the response fields
	// `support_gpu` + `gpu_info[]` (replacing 7.3's client-side `t.gpu`
	// object gated by support_nvidia_gpu). Injecting these here makes the
	// section appear on 7.4; older DSMs ignore the unknown fields, so the
	// legacy admin_center.js patch still covers them. See cpuinfo.sh.
	gpuInfoFile = "/run/mshell_gpu_info.json"

	// Hard cap for buffered responses. Larger payloads are streamed through
	// without inspection. SYNO.Core.System.info is well under this.
	maxBufferedBytes = 4 * 1024 * 1024
)

var (
	loaderVerFlag    = flag.String("LOADERVERSION", "", "Override bootloader version (default: read from "+versionFile+")")
	upstreamSockFlag = flag.String("upstream", "/run/synoscgi.sock", "upstream SCGI unix socket path")
	listenSockFlag   = flag.String("listen", "/run/synoscgi_ms.sock", "listen unix socket path")
)

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

// gpuInfoArray returns the trimmed contents of gpuInfoFile when it holds a
// non-empty JSON array (i.e. starts with '[' and is not the empty array).
// Returns "" when the file is absent, unreadable, or empty so the caller
// injects nothing on GPU-less hosts.
func gpuInfoArray() string {
	b, err := os.ReadFile(gpuInfoFile)
	if err != nil {
		return ""
	}
	s := strings.TrimSpace(string(b))
	if len(s) < 2 || s[0] != '[' || s == "[]" {
		return ""
	}
	return s
}

// gpuTempsFromSysfs reads per-card GPU temperatures from DRM hwmon sysfs.
// Returns a map of card-index → °C.
func gpuTempsFromSysfs() map[int]int {
	out := map[int]int{}
	// /sys/class/drm/cardN/device/hwmon/hwmonM/temp1_input
	entries, _ := filepath.Glob("/sys/class/drm/card*/device/hwmon/hwmon*/temp1_input")
	for _, p := range entries {
		// extract card index from "cardN" segment
		parts := strings.Split(p, "/")
		for _, seg := range parts {
			if !strings.HasPrefix(seg, "card") {
				continue
			}
			n, err := strconv.Atoi(strings.TrimPrefix(seg, "card"))
			if err != nil {
				break
			}
			b, err := os.ReadFile(p)
			if err != nil {
				break
			}
			v, err := strconv.Atoi(strings.TrimSpace(string(b)))
			if err == nil && v > 0 {
				out[n] = v / 1000
			}
			break
		}
	}
	return out
}

// gpuInfoArrayWithTemp wraps gpuInfoArray(), injecting "temperature_c" into
// array entries that lack it, using positional DRM hwmon sysfs data.
func gpuInfoArrayWithTemp() string {
	s := gpuInfoArray()
	if s == "" {
		return ""
	}
	temps := gpuTempsFromSysfs()
	if len(temps) == 0 {
		return s
	}

	result := []byte(s)
	cardIdx := 0
	depth := 0
	inStr, esc := false, false
	objStart := -1

	for i := 0; i < len(result); i++ {
		c := result[i]
		if esc {
			esc = false
			continue
		}
		if inStr {
			if c == '\\' {
				esc = true
			} else if c == '"' {
				inStr = false
			}
			continue
		}
		switch c {
		case '"':
			inStr = true
		case '{':
			depth++
			if depth == 1 {
				objStart = i
			}
		case '}':
			if depth == 1 && objStart >= 0 {
				obj := result[objStart : i+1]
				// 이미 temperature_c가 있으면 skip
				if !bytes.Contains(obj, []byte("temperature_c")) {
					if t, ok := temps[cardIdx]; ok {
						snippet := fmt.Sprintf(`,"temperature_c":%d`, t)
						tmp := make([]byte, 0, len(result)+len(snippet))
						tmp = append(tmp, result[:i]...)
						tmp = append(tmp, snippet...)
						tmp = append(tmp, result[i:]...)
						result = tmp
						i += len(snippet)
					}
				}
				cardIdx++
				objStart = -1
			}
			depth--
		}
	}
	return string(result)
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
	gpuFalseRe   = regexp.MustCompile(`"support_gpu"\s*:\s*false`)
	contentLenRe = regexp.MustCompile(`(?im)^(Content-Length:[ \t]*)\d+`)
)

func patchJSON(body []byte) []byte {
	// SYNO.Core.System.info — append the loader version and splice in live
	// CPU temperature / fan readings (read client-side from t.sys_temp etc).
	if bytes.Contains(body, []byte(`"firmware_ver"`)) {
		if ver := bootloaderVer(); ver != "" {
			body = fwRe.ReplaceAllFunc(body, func(m []byte) []byte {
				sub := fwRe.FindSubmatch(m)
				return []byte(fmt.Sprintf(`"firmware_ver":"%s / %s"`, sub[1], ver))
			})
		}
		if t := cpuTempC(); t > 0 {
			body = injectField(body, "firmware_ver", "sys_temp",
				fmt.Sprintf(`,"sys_temp":%d`, t))
		}
		if fans := fanSpeeds(); len(fans) > 0 {
			parts := make([]string, len(fans))
			for i, f := range fans {
				parts[i] = strconv.Itoa(f)
			}
			body = injectField(body, "firmware_ver", "fan_list",
				fmt.Sprintf(`,"fan_list":[%s]`, strings.Join(parts, ",")))
		}
	}
	// SYNO.Core.System.GpuInfo "list" — DSM 7.4's Info Center reads the GPU
	// section from THIS api via processGpuInfo() (GetValByAPI(...,
	// "SYNO.Core.System.GpuInfo","list")), not from SYNO.Core.System. The
	// genuine response is {"support_gpu":false} on loader/non-GPU hosts, so
	// flip the gate to true and splice our gpu_info array into the same
	// object. (DSM <= 7.3 uses a different, client-side path covered by the
	// admin_center.js patch in cpuinfo.sh.)
	if gpu := gpuInfoArrayWithTemp(); gpu != "" && bytes.Contains(body, []byte(`"support_gpu"`)) {
		body = gpuFalseRe.ReplaceAll(body, []byte(`"support_gpu":true`))
		body = injectField(body, "support_gpu", "gpu_info",
			fmt.Sprintf(`,"gpu_info":%s`, gpu))
	}
	return body
}

// injectField splices snippet immediately before the closing `}` of the
// JSON object that contains the anchor key. No-op if key is already present
// or the surrounding object cannot be parsed.
func injectField(body []byte, anchor, key, snippet string) []byte {
	if bytes.Contains(body, []byte(`"`+key+`"`)) {
		return body
	}
	aIdx := bytes.Index(body, []byte(`"`+anchor+`"`))
	if aIdx < 0 {
		return body
	}
	depth := 0
	inStr := false
	esc := false
	for i := aIdx; i < len(body); i++ {
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

		// Patch SYNO.Core.System.info (firmware_ver) and/or
		// SYNO.Core.System.GpuInfo.list (support_gpu) payloads, whether they
		// arrive as separate responses or bundled in one compound response.
		if !bytes.Contains(body, []byte(`"firmware_ver"`)) &&
			!bytes.Contains(body, []byte(`"support_gpu"`)) {
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

func handleConnection(client net.Conn, upstreamSock string) {
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

	upstream := *upstreamSockFlag
	listen := *listenSockFlag

	_ = os.Remove(listen)
	l, err := net.Listen("unix", listen)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Failed to listen on %s: %v\n", listen, err)
		os.Exit(1)
	}
	if err := os.Chmod(listen, 0o666); err != nil {
		fmt.Fprintf(os.Stderr, "chmod %s: %v\n", listen, err)
	}

	sig := make(chan os.Signal, 1)
	signal.Notify(sig, syscall.SIGINT, syscall.SIGTERM)
	go func() {
		<-sig
		_ = l.Close()
		_ = os.Remove(listen)
		os.Exit(0)
	}()

	for {
		c, err := l.Accept()
		if err != nil {
			continue
		}
		go handleConnection(c, upstream)
	}
}
