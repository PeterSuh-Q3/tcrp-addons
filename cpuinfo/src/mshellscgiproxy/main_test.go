package main

import (
	"bytes"
	"testing"
)

func TestInjectFieldIntoContainingObject(t *testing.T) {
	body := []byte(`{"success":true,"data":{"firmware_ver":"DSM 7.4.1","sys_temp":60}}`)
	got := injectField(body, "firmware_ver", "acpi_temp", `,"acpi_temp":28`)
	want := []byte(`{"success":true,"data":{"firmware_ver":"DSM 7.4.1","sys_temp":60,"acpi_temp":28}}`)
	if !bytes.Equal(got, want) {
		t.Fatalf("unexpected JSON: %s", got)
	}
}

func TestInjectFieldDoesNotDuplicateKey(t *testing.T) {
	body := []byte(`{"data":{"firmware_ver":"DSM","acpi_temp":28}}`)
	got := injectField(body, "firmware_ver", "acpi_temp", `,"acpi_temp":99`)
	if !bytes.Equal(got, body) {
		t.Fatalf("existing field was modified: %s", got)
	}
}
