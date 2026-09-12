package db_test

import (
	"errors"
	"testing"
	"time"

	"ravpkg/internal/db"
	"ravpkg/internal/model"
)

func setupTestDB(t *testing.T) *db.DB {
	t.Helper()
	database, err := db.Open(":memory:")
	if err != nil {
		t.Fatalf("failed to open in-memory db: %v", err)
	}
	t.Cleanup(func() {
		_ = database.Close()
	})
	return database
}

func TestDB_AddAndGetPackage(t *testing.T) {
	d := setupTestDB(t)

	now := time.Date(2026, 9, 10, 12, 0, 0, 0, time.UTC)
	pkg := &model.InstalledPackage{
		Name:         "ravterm",
		Version:      "1.0.0",
		InstallDate:  now,
		ManifestPath: "/var/db/ravpkg/manifests/ravterm-1.0.0.json",
		InstalledFiles: []string{
			"/usr/local/bin/ravterm",
			"/usr/local/share/man/man1/ravterm.1",
		},
	}

	if err := d.AddPackage(pkg); err != nil {
		t.Fatalf("AddPackage failed: %v", err)
	}

	retrieved, err := d.GetPackage("ravterm")
	if err != nil {
		t.Fatalf("GetPackage failed: %v", err)
	}

	if retrieved.Name != pkg.Name {
		t.Errorf("expected name %q, got %q", pkg.Name, retrieved.Name)
	}
	if retrieved.Version != pkg.Version {
		t.Errorf("expected version %q, got %q", pkg.Version, retrieved.Version)
	}
	if retrieved.ManifestPath != pkg.ManifestPath {
		t.Errorf("expected manifest path %q, got %q", pkg.ManifestPath, retrieved.ManifestPath)
	}
	if len(retrieved.InstalledFiles) != 2 {
		t.Fatalf("expected 2 installed files, got %d", len(retrieved.InstalledFiles))
	}
	if retrieved.InstalledFiles[0] != "/usr/local/bin/ravterm" {
		t.Errorf("expected installed file %q, got %q", "/usr/local/bin/ravterm", retrieved.InstalledFiles[0])
	}
}

func TestDB_GetPackage_NotFound(t *testing.T) {
	d := setupTestDB(t)

	_, err := d.GetPackage("non-existent-package")
	if err == nil {
		t.Fatal("expected error for non-existent package, got nil")
	}
	if !errors.Is(err, db.ErrNotFound) {
		t.Errorf("expected ErrNotFound, got: %v", err)
	}
}

func TestDB_ListPackages(t *testing.T) {
	d := setupTestDB(t)

	// List when empty
	list, err := d.ListPackages()
	if err != nil {
		t.Fatalf("ListPackages failed on empty db: %v", err)
	}
	if len(list) != 0 {
		t.Fatalf("expected 0 packages, got %d", len(list))
	}

	// Insert multiple packages
	pkgs := []*model.InstalledPackage{
		{
			Name:           "pkg-b",
			Version:        "2.0.0",
			ManifestPath:   "/path/b.json",
			InstalledFiles: []string{"/bin/b"},
		},
		{
			Name:           "pkg-a",
			Version:        "1.0.0",
			ManifestPath:   "/path/a.json",
			InstalledFiles: []string{"/bin/a"},
		},
	}

	for _, p := range pkgs {
		if err := d.AddPackage(p); err != nil {
			t.Fatalf("failed to add package %q: %v", p.Name, err)
		}
	}

	list, err = d.ListPackages()
	if err != nil {
		t.Fatalf("ListPackages failed: %v", err)
	}
	if len(list) != 2 {
		t.Fatalf("expected 2 packages, got %d", len(list))
	}

	// Expect alphabetical ordering: pkg-a then pkg-b
	if list[0].Name != "pkg-a" || list[1].Name != "pkg-b" {
		t.Errorf("expected alphabetical order [pkg-a, pkg-b], got [%s, %s]", list[0].Name, list[1].Name)
	}
}

func TestDB_RemovePackage(t *testing.T) {
	d := setupTestDB(t)

	pkg := &model.InstalledPackage{
		Name:           "ravfetch",
		Version:        "0.9.0",
		ManifestPath:   "/path/ravfetch.json",
		InstalledFiles: []string{"/bin/ravfetch"},
	}

	if err := d.AddPackage(pkg); err != nil {
		t.Fatalf("failed to add package: %v", err)
	}

	// Successful remove
	if err := d.RemovePackage("ravfetch"); err != nil {
		t.Fatalf("RemovePackage failed: %v", err)
	}

	// Verify package is gone
	_, err := d.GetPackage("ravfetch")
	if !errors.Is(err, db.ErrNotFound) {
		t.Fatalf("expected ErrNotFound after removal, got: %v", err)
	}

	// Remove non-existent package returns ErrNotFound
	err = d.RemovePackage("ravfetch")
	if !errors.Is(err, db.ErrNotFound) {
		t.Errorf("expected ErrNotFound for removing non-existent package, got: %v", err)
	}
}
