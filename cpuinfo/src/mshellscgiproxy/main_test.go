package main

import (
	"bytes"
	"fmt"
	"io"
	"net"
	"net/url"
	"strings"
	"testing"
	"time"
)

func scgiRequest(headers map[string]string, body string) []byte {
	if _, ok := headers["CONTENT_LENGTH"]; !ok {
		headers["CONTENT_LENGTH"] = fmt.Sprint(len(body))
	}
	headers["SCGI"] = "1"
	var h bytes.Buffer
	for k, v := range headers {
		h.WriteString(k)
		h.WriteByte(0)
		h.WriteString(v)
		h.WriteByte(0)
	}
	return []byte(fmt.Sprintf("%d:%s,%s", h.Len(), h.String(), body))
}

func TestRequestClassification(t *testing.T) {
	cases := []struct {
		name    string
		headers map[string]string
		body    string
		patch   bool
	}{
		{"system query", map[string]string{"QUERY_STRING": "api=SYNO.Core.System&method=info"}, "", true},
		{"gpu body", map[string]string{"CONTENT_TYPE": "application/x-www-form-urlencoded"}, "api=SYNO.Core.System.GpuInfo&method=list", true},
		{"compound body", map[string]string{"QUERY_STRING": "api=SYNO.Entry.Request&method=request", "CONTENT_TYPE": "application/x-www-form-urlencoded"}, "compound=" + url.QueryEscape(`[{"api":"SYNO.Core.System","method":"info"}]`), true},
		{"ordinary json", map[string]string{"QUERY_STRING": "api=SYNO.AudioStation.Search&method=list"}, "", false},
		{"stream path", map[string]string{"REQUEST_URI": "/radio/live"}, "", false},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			r := bytes.NewReader(scgiRequest(tc.headers, tc.body))
			var forwarded bytes.Buffer
			patch, err := forwardRequest(r, &forwarded)
			if err != nil {
				t.Fatal(err)
			}
			if patch != tc.patch {
				t.Fatalf("patch=%v want %v", patch, tc.patch)
			}
			if int64(forwarded.Len()) != r.Size() {
				t.Fatalf("forwarded %d, want %d", forwarded.Len(), r.Size())
			}
		})
	}
}

func TestStreamingFirstByteBeforeEOF(t *testing.T) {
	upstream, writer := net.Pipe()
	client, reader := net.Pipe()
	defer upstream.Close()
	defer writer.Close()
	defer client.Close()
	defer reader.Close()
	done := make(chan error, 1)
	go func() { done <- proxyResponse(upstream, client, false) }()
	chunk := []byte("Content-Type: audio/mpeg\r\n\r\nID3audio")
	go func() { _, _ = writer.Write(chunk) }()
	_ = reader.SetReadDeadline(time.Now().Add(time.Second))
	got := make([]byte, len(chunk))
	if _, err := io.ReadFull(reader, got); err != nil {
		t.Fatalf("first bytes delayed: %v", err)
	}
	if !bytes.Equal(got, chunk) {
		t.Fatalf("got %q", got)
	}
	_ = writer.Close()
	select {
	case err := <-done:
		if err != nil {
			t.Fatal(err)
		}
	case <-time.After(time.Second):
		t.Fatal("proxy did not exit on EOF")
	}
}

func TestTargetedAudioStreamsBeforeEOF(t *testing.T) {
	upstream, writer := net.Pipe()
	client, reader := net.Pipe()
	defer upstream.Close()
	defer writer.Close()
	defer client.Close()
	defer reader.Close()
	done := make(chan error, 1)
	go func() { done <- proxyResponse(upstream, client, true) }()
	chunk := []byte("Content-Type: audio/mpeg\r\n\r\nID3audio")
	go func() { _, _ = writer.Write(chunk) }()
	_ = reader.SetReadDeadline(time.Now().Add(time.Second))
	got := make([]byte, len(chunk))
	if _, err := io.ReadFull(reader, got); err != nil {
		t.Fatalf("targeted audio delayed: %v", err)
	}
	if !bytes.Equal(got, chunk) {
		t.Fatalf("got %q", got)
	}
	writer.Close()
	select {
	case err := <-done:
		if err != nil {
			t.Fatal(err)
		}
	case <-time.After(time.Second):
		t.Fatal("proxy did not finish")
	}
}

func TestTargetedContentLengthBeforeEOF(t *testing.T) {
	old := *loaderVerFlag
	*loaderVerFlag = "TEST"
	defer func() { *loaderVerFlag = old }()
	upstream, writer := net.Pipe()
	client, reader := net.Pipe()
	defer upstream.Close()
	defer writer.Close()
	defer client.Close()
	defer reader.Close()
	done := make(chan error, 1)
	go func() { done <- proxyResponse(upstream, client, true) }()
	body := `{"firmware_ver":"7.4"}`
	go func() {
		_, _ = writer.Write([]byte(fmt.Sprintf("Content-Type: application/json\r\nContent-Length: %d\r\n\r\n%s", len(body), body)))
	}()
	_ = reader.SetReadDeadline(time.Now().Add(time.Second))
	got := make([]byte, 256)
	n, err := reader.Read(got)
	if err != nil || !bytes.Contains(got[:n], []byte(`"firmware_ver":"7.4 / TEST"`)) {
		t.Fatalf("patched response delayed or missing: %q, %v", got[:n], err)
	}
	select {
	case err := <-done:
		if err != nil {
			t.Fatal(err)
		}
	case <-time.After(time.Second):
		t.Fatal("proxy waited for EOF")
	}
}

func TestPassThroughEOFAndLarge(t *testing.T) {
	for _, tc := range []struct {
		payload []byte
		patch   bool
	}{
		{[]byte("Status: 200 OK\r\n\r\nabc"), false},
		{append([]byte("Content-Type: application/octet-stream\r\n\r\n"), bytes.Repeat([]byte("0123456789"), maxBufferedBytes/10+2)...), false},
		{append([]byte("Content-Type: application/json\r\n\r\n"), bytes.Repeat([]byte("0123456789"), maxBufferedBytes/10+2)...), true},
	} {
		payload := tc.payload
		var out bytes.Buffer
		source, sink := net.Pipe()
		target, drain := net.Pipe()
		done := make(chan error, 1)
		go func() { done <- proxyResponse(source, target, tc.patch); target.Close() }()
		go func() { _, _ = sink.Write(payload); sink.Close() }()
		_, err := io.Copy(&out, drain)
		if err != nil {
			t.Fatal(err)
		}
		if err := <-done; err != nil {
			t.Fatal(err)
		}
		source.Close()
		drain.Close()
		if !bytes.Equal(out.Bytes(), payload) {
			t.Fatalf("size %d: received %d", len(payload), out.Len())
		}
	}
}

func TestPatchedSystemAndCompound(t *testing.T) {
	old := *loaderVerFlag
	*loaderVerFlag = "TEST"
	defer func() { *loaderVerFlag = old }()
	for _, body := range []string{`{"firmware_ver":"7.4"}`, `{"data":{"SYNO.Core.System":{"firmware_ver":"7.4"},"SYNO.Core.System.GpuInfo":{"support_gpu":false}}}`} {
		response := []byte(fmt.Sprintf("Content-Type: application/json\r\nContent-Length: %d\r\n\r\n%s", len(body), body))
		got := patchResponse(response)
		if !bytes.Contains(got, []byte(`"firmware_ver":"7.4 / TEST"`)) {
			t.Fatalf("not patched: %s", got)
		}
		parts := bytes.SplitN(got, []byte("\r\n\r\n"), 2)
		if !bytes.Contains(parts[0], []byte(fmt.Sprintf("Content-Length: %d", len(parts[1])))) {
			t.Fatalf("wrong length: %s", parts[0])
		}
	}
}

func TestUntargetedResponseUnmodified(t *testing.T) {
	for _, body := range []string{`{"success":true}`, "\x00\x01\xff"} {
		response := []byte("Content-Type: application/octet-stream\n\n" + body)
		if got := patchResponse(response); !bytes.Equal(got, response) {
			t.Fatal("changed unrelated response")
		}
	}
}

func TestMalformedSCGI(t *testing.T) {
	for _, input := range []string{"x:bad,", "4:abc,", "3:abc,", "100:a"} {
		var out bytes.Buffer
		_, err := forwardRequest(strings.NewReader(input), &out)
		if err == nil {
			t.Fatalf("accepted %q", input)
		}
	}
}

type byteReader struct{ r io.Reader }

func (b byteReader) Read(p []byte) (int, error) { return b.r.Read(p[:1]) }

func TestSplitSCGIAndPrematureEOF(t *testing.T) {
	req := scgiRequest(map[string]string{"QUERY_STRING": "api=SYNO.Core.System"}, "payload")
	var out bytes.Buffer
	patch, err := forwardRequest(byteReader{bytes.NewReader(req)}, &out)
	if err != nil || !patch || !bytes.Equal(out.Bytes(), req) {
		t.Fatalf("split request: patch=%v err=%v", patch, err)
	}
	_, err = forwardRequest(bytes.NewReader(req[:len(req)-2]), io.Discard)
	if err == nil {
		t.Fatal("accepted truncated request body")
	}
}

func TestUpstreamWriteError(t *testing.T) {
	req := scgiRequest(map[string]string{"REQUEST_URI": "/radio/live"}, "")
	_, err := forwardRequest(bytes.NewReader(req), errorWriter{})
	if err == nil {
		t.Fatal("ignored upstream write error")
	}
}

type errorWriter struct{}

func (errorWriter) Write([]byte) (int, error) { return 0, io.ErrClosedPipe }
