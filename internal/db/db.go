package db

import (
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"time"

	_ "modernc.org/sqlite"

	"ravpkg/internal/model"
)

var (
	ErrNotFound      = errors.New("package not found in local database")
	ErrAlreadyExists = errors.New("package already installed")
)

// DB wraps an active SQLite connection for ravpkg package tracking.
type DB struct {
	conn *sql.DB
}

// Open initializes or opens a SQLite database at the specified path.
// For in-memory testing, use ":memory:" or "file::memory:?cache=shared".
func Open(dbPath string) (*DB, error) {
	if dbPath != ":memory:" && !filepath.IsAbs(dbPath) && dbPath != "" {
		// Ensure parent directory exists for file-based databases
		dir := filepath.Dir(dbPath)
		if dir != "." && dir != "" {
			if err := os.MkdirAll(dir, 0755); err != nil {
				return nil, fmt.Errorf("failed to create database directory %q: %w", dir, err)
			}
		}
	} else if filepath.IsAbs(dbPath) {
		dir := filepath.Dir(dbPath)
		if err := os.MkdirAll(dir, 0755); err != nil {
			return nil, fmt.Errorf("failed to create database directory %q: %w", dir, err)
		}
	}

	conn, err := sql.Open("sqlite", dbPath)
	if err != nil {
		return nil, fmt.Errorf("failed to open database: %w", err)
	}

	db := &DB{conn: conn}
	if err := db.initSchema(); err != nil {
		_ = conn.Close()
		return nil, fmt.Errorf("failed to initialize database schema: %w", err)
	}

	return db, nil
}

// Close releases the underlying SQLite connection.
func (d *DB) Close() error {
	if d.conn != nil {
		return d.conn.Close()
	}
	return nil
}

// initSchema creates the required tables if they don't already exist.
func (d *DB) initSchema() error {
	schema := `
	CREATE TABLE IF NOT EXISTS installed_packages (
		name TEXT PRIMARY KEY,
		version TEXT NOT NULL,
		install_date TEXT NOT NULL,
		manifest_path TEXT NOT NULL,
		installed_files TEXT NOT NULL
	);
	`
	_, err := d.conn.Exec(schema)
	return err
}

// AddPackage records an installed package in the database.
func (d *DB) AddPackage(pkg *model.InstalledPackage) error {
	if pkg == nil {
		return errors.New("package cannot be nil")
	}
	if pkg.Name == "" {
		return errors.New("package name cannot be empty")
	}

	filesJSON, err := json.Marshal(pkg.InstalledFiles)
	if err != nil {
		return fmt.Errorf("failed to serialize installed_files: %w", err)
	}

	installDate := pkg.InstallDate
	if installDate.IsZero() {
		installDate = time.Now().UTC()
	}

	query := `
	INSERT INTO installed_packages (name, version, install_date, manifest_path, installed_files)
	VALUES (?, ?, ?, ?, ?)
	`
	_, err = d.conn.Exec(query,
		pkg.Name,
		pkg.Version,
		installDate.Format(time.RFC3339),
		pkg.ManifestPath,
		string(filesJSON),
	)
	if err != nil {
		// Detect unique constraint violation in SQLite
		if errors.Is(err, sql.ErrNoRows) {
			return err
		}
		return fmt.Errorf("failed to record package %q: %w", pkg.Name, err)
	}

	return nil
}

// RemovePackage deletes a package entry by name from the database.
func (d *DB) RemovePackage(name string) error {
	res, err := d.conn.Exec(`DELETE FROM installed_packages WHERE name = ?`, name)
	if err != nil {
		return fmt.Errorf("failed to remove package %q: %w", name, err)
	}

	rowsAffected, err := res.RowsAffected()
	if err != nil {
		return err
	}
	if rowsAffected == 0 {
		return ErrNotFound
	}

	return nil
}

// GetPackage queries a package by name and returns its metadata and file list.
func (d *DB) GetPackage(name string) (*model.InstalledPackage, error) {
	row := d.conn.QueryRow(`
		SELECT name, version, install_date, manifest_path, installed_files
		FROM installed_packages
		WHERE name = ?
	`, name)

	var pkg model.InstalledPackage
	var dateStr, filesJSON string

	err := row.Scan(&pkg.Name, &pkg.Version, &dateStr, &pkg.ManifestPath, &filesJSON)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return nil, ErrNotFound
		}
		return nil, fmt.Errorf("failed to query package %q: %w", name, err)
	}

	parsedDate, err := time.Parse(time.RFC3339, dateStr)
	if err == nil {
		pkg.InstallDate = parsedDate
	}

	if filesJSON != "" {
		if err := json.Unmarshal([]byte(filesJSON), &pkg.InstalledFiles); err != nil {
			return nil, fmt.Errorf("failed to parse installed_files JSON for %q: %w", name, err)
		}
	}

	return &pkg, nil
}

// ListPackages returns all currently installed packages in alphabetical order.
func (d *DB) ListPackages() ([]model.InstalledPackage, error) {
	rows, err := d.conn.Query(`
		SELECT name, version, install_date, manifest_path, installed_files
		FROM installed_packages
		ORDER BY name ASC
	`)
	if err != nil {
		return nil, fmt.Errorf("failed to list packages: %w", err)
	}
	defer rows.Close()

	var packages []model.InstalledPackage
	for rows.Next() {
		var pkg model.InstalledPackage
		var dateStr, filesJSON string

		if err := rows.Scan(&pkg.Name, &pkg.Version, &dateStr, &pkg.ManifestPath, &filesJSON); err != nil {
			return nil, fmt.Errorf("failed to scan package row: %w", err)
		}

		if parsedDate, err := time.Parse(time.RFC3339, dateStr); err == nil {
			pkg.InstallDate = parsedDate
		}

		if filesJSON != "" {
			_ = json.Unmarshal([]byte(filesJSON), &pkg.InstalledFiles)
		}

		packages = append(packages, pkg)
	}

	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("row iteration error: %w", err)
	}

	return packages, nil
}
