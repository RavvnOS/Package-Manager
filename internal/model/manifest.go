package model

import "time"

// InstallPath maps a package archive relative path to its target system destination.
type InstallPath struct {
	Source      string `json:"source"`
	Destination string `json:"destination"`
}

// Dependency represents a package dependency and optional version constraint.
// In Phase 1-2, this is schema-only (no resolution logic).
type Dependency struct {
	Name       string `json:"name"`
	Constraint string `json:"constraint,omitempty"`
}

// Manifest represents the parsed package manifest (manifest.json).
type Manifest struct {
	Name         string        `json:"name"`
	Version      string        `json:"version"`
	Description  string        `json:"description"`
	Checksum     string        `json:"checksum"`
	InstallPaths []InstallPath `json:"install_paths"`
	Dependencies []Dependency  `json:"dependencies,omitempty"`
}

// InstalledPackage represents an installed package entry tracked in the local SQLite database.
type InstalledPackage struct {
	Name           string    `json:"name"`
	Version        string    `json:"version"`
	InstallDate    time.Time `json:"install_date"`
	ManifestPath   string    `json:"manifest_path"`
	InstalledFiles []string  `json:"installed_files"`
}
