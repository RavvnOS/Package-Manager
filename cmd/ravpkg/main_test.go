package main

import (
	"bytes"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"ravpkg/internal/db"
	"ravpkg/internal/model"
)

func TestCLI_EndToEnd(t *testing.T) {
	tempDir := t.TempDir()
	testDBPath := filepath.Join(tempDir, "test.db")

	// Initialize DB and populate sample package
	database, err := db.Open(testDBPath)
	if err != nil {
		t.Fatalf("failed to open test db: %v", err)
	}

	samplePkg := &model.InstalledPackage{
		Name:         "ravterm",
		Version:      "1.0.0",
		InstallDate:  time.Date(2026, 9, 10, 10, 30, 0, 0, time.UTC),
		ManifestPath: "/var/db/ravpkg/manifests/ravterm.json",
		InstalledFiles: []string{
			"/usr/local/bin/ravterm",
			"/usr/local/share/man/man1/ravterm.1",
		},
	}
	if err := database.AddPackage(samplePkg); err != nil {
		t.Fatalf("failed to insert package: %v", err)
	}
	_ = database.Close()

	// 1. Test list command
	rootCmd := newRootCmd()
	var listBuf bytes.Buffer
	rootCmd.SetOut(&listBuf)
	rootCmd.SetArgs([]string{"list", "--db", testDBPath})
	if err := rootCmd.Execute(); err != nil {
		t.Fatalf("list command failed: %v", err)
	}

	// 2. Test info command
	infoCmd := newRootCmd()
	var infoBuf bytes.Buffer
	infoCmd.SetOut(&infoBuf)
	infoCmd.SetArgs([]string{"info", "ravterm", "--db", testDBPath})
	if err := infoCmd.Execute(); err != nil {
		t.Fatalf("info command failed: %v", err)
	}

	// 3. Test stub install command
	installCmd := newRootCmd()
	var installBuf bytes.Buffer
	installCmd.SetOut(&installBuf)
	installCmd.SetArgs([]string{"install", "pkg.rav"})
	if err := installCmd.Execute(); err != nil {
		t.Fatalf("install command failed: %v", err)
	}

	// 4. Test stub remove command
	removeCmd := newRootCmd()
	var removeBuf bytes.Buffer
	removeCmd.SetOut(&removeBuf)
	removeCmd.SetArgs([]string{"remove", "ravterm"})
	if err := removeCmd.Execute(); err != nil {
		t.Fatalf("remove command failed: %v", err)
	}

	// 5. Test stub search command
	searchCmd := newRootCmd()
	var searchBuf bytes.Buffer
	searchCmd.SetOut(&searchBuf)
	searchCmd.SetArgs([]string{"search", "term"})
	if err := searchCmd.Execute(); err != nil {
		t.Fatalf("search command failed: %v", err)
	}
}

func TestCLI_Info_NotFound(t *testing.T) {
	tempDir := t.TempDir()
	testDBPath := filepath.Join(tempDir, "test.db")

	database, err := db.Open(testDBPath)
	if err != nil {
		t.Fatalf("failed to open test db: %v", err)
	}
	_ = database.Close()

	rootCmd := newRootCmd()
	rootCmd.SetArgs([]string{"info", "nonexistent", "--db", testDBPath})
	err = rootCmd.Execute()
	if err == nil {
		t.Fatal("expected error for non-existent package, got nil")
	}
	if !strings.Contains(err.Error(), "is not installed") {
		t.Errorf("unexpected error message: %v", err)
	}
}
