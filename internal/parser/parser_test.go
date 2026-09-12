package parser_test

import (
	"path/filepath"
	"strings"
	"testing"

	"ravpkg/internal/parser"
)

func TestParseManifestFile_Valid(t *testing.T) {
	fixturePath := filepath.Join("..", "..", "tests", "fixtures", "valid-manifest.json")
	m, err := parser.ParseManifestFile(fixturePath)
	if err != nil {
		t.Fatalf("expected valid manifest to parse successfully, got: %v", err)
	}

	if m.Name != "ravterm" {
		t.Errorf("expected name 'ravterm', got %q", m.Name)
	}
	if m.Version != "1.0.0" {
		t.Errorf("expected version '1.0.0', got %q", m.Version)
	}
	if m.Description != "Terminal emulator for ravynOS" {
		t.Errorf("unexpected description: %q", m.Description)
	}
	if len(m.InstallPaths) != 2 {
		t.Fatalf("expected 2 install paths, got %d", len(m.InstallPaths))
	}
	if m.InstallPaths[0].Source != "bin/ravterm" || m.InstallPaths[0].Destination != "/usr/local/bin/ravterm" {
		t.Errorf("unexpected install_path[0]: %+v", m.InstallPaths[0])
	}
}

func TestParseManifestFile_WithDeps(t *testing.T) {
	fixturePath := filepath.Join("..", "..", "tests", "fixtures", "with-deps-manifest.json")
	m, err := parser.ParseManifestFile(fixturePath)
	if err != nil {
		t.Fatalf("expected with-deps manifest to parse successfully, got: %v", err)
	}

	if len(m.Dependencies) != 2 {
		t.Fatalf("expected 2 dependencies, got %d", len(m.Dependencies))
	}
	if m.Dependencies[0].Name != "ravyn-base-system" || m.Dependencies[0].Constraint != ">=0.5.0" {
		t.Errorf("unexpected dependency[0]: %+v", m.Dependencies[0])
	}
}

func TestParseManifestFile_MissingFields(t *testing.T) {
	fixturePath := filepath.Join("..", "..", "tests", "fixtures", "missing-fields-manifest.json")
	_, err := parser.ParseManifestFile(fixturePath)
	if err == nil {
		t.Fatal("expected error for missing-fields manifest, got nil")
	}

	if !strings.Contains(err.Error(), "missing required field") {
		t.Errorf("expected missing required field error, got: %v", err)
	}
}

func TestParseManifestFile_BadChecksum(t *testing.T) {
	fixturePath := filepath.Join("..", "..", "tests", "fixtures", "bad-checksum-manifest.json")
	_, err := parser.ParseManifestFile(fixturePath)
	if err == nil {
		t.Fatal("expected error for bad-checksum manifest, got nil")
	}

	if !strings.Contains(err.Error(), "invalid checksum") {
		t.Errorf("expected invalid checksum error, got: %v", err)
	}
}

func TestParseManifest_EmptyData(t *testing.T) {
	_, err := parser.ParseManifest([]byte(""))
	if err == nil {
		t.Fatal("expected error on empty manifest data, got nil")
	}
}

func TestParseManifest_MalformedJSON(t *testing.T) {
	_, err := parser.ParseManifest([]byte("{not a json}"))
	if err == nil {
		t.Fatal("expected error on malformed JSON, got nil")
	}
	if !strings.Contains(err.Error(), "malformed manifest JSON") {
		t.Errorf("expected malformed manifest JSON error, got: %v", err)
	}
}

func TestParseManifest_EmptyInstallPaths(t *testing.T) {
	jsonBlob := `{
		"name": "testpkg",
		"version": "1.0.0",
		"description": "A test pkg",
		"checksum": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"install_paths": []
	}`
	_, err := parser.ParseManifest([]byte(jsonBlob))
	if err == nil {
		t.Fatal("expected error for empty install_paths, got nil")
	}
	if !strings.Contains(err.Error(), "install_paths") {
		t.Errorf("expected install_paths error, got: %v", err)
	}
}

func TestParseManifest_InvalidInstallPathEntry(t *testing.T) {
	jsonBlob := `{
		"name": "testpkg",
		"version": "1.0.0",
		"description": "A test pkg",
		"checksum": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"install_paths": [
			{"source": "", "destination": "/usr/local/bin/pkg"}
		]
	}`
	_, err := parser.ParseManifest([]byte(jsonBlob))
	if err == nil {
		t.Fatal("expected error for empty source in install_paths, got nil")
	}
	if !strings.Contains(err.Error(), "source") {
		t.Errorf("expected source error, got: %v", err)
	}
}
