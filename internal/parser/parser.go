package parser

import (
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"regexp"
	"strings"

	"ravpkg/internal/model"
)

var (
	// sha256Regex matches 64 hexadecimal characters.
	sha256Regex = regexp.MustCompile(`^[a-fA-F0-9]{64}$`)

	ErrEmptyManifest   = errors.New("manifest data is empty")
	ErrMissingField    = errors.New("manifest missing required field")
	ErrInvalidChecksum = errors.New("invalid checksum: must be a 64-character hexadecimal SHA-256 string")
	ErrInvalidPath     = errors.New("invalid install_path")
)

// ParseManifest parses raw JSON manifest bytes and validates its structure and fields.
func ParseManifest(data []byte) (*model.Manifest, error) {
	if len(strings.TrimSpace(string(data))) == 0 {
		return nil, ErrEmptyManifest
	}

	var m model.Manifest
	if err := json.Unmarshal(data, &m); err != nil {
		return nil, fmt.Errorf("malformed manifest JSON: %w", err)
	}

	if err := ValidateManifest(&m); err != nil {
		return nil, err
	}

	return &m, nil
}

// ParseManifestFile reads a manifest JSON file from the filesystem and parses it.
func ParseManifestFile(path string) (*model.Manifest, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, fmt.Errorf("unable to read manifest file at %q: %w", path, err)
	}
	return ParseManifest(data)
}

// ValidateManifest performs structural and semantic checks on the manifest fields.
func ValidateManifest(m *model.Manifest) error {
	if strings.TrimSpace(m.Name) == "" {
		return fmt.Errorf("%w: 'name'", ErrMissingField)
	}

	if strings.TrimSpace(m.Version) == "" {
		return fmt.Errorf("%w: 'version'", ErrMissingField)
	}

	if strings.TrimSpace(m.Description) == "" {
		return fmt.Errorf("%w: 'description'", ErrMissingField)
	}

	if strings.TrimSpace(m.Checksum) == "" {
		return fmt.Errorf("%w: 'checksum'", ErrMissingField)
	}

	if !sha256Regex.MatchString(m.Checksum) {
		return fmt.Errorf("%w (got %q)", ErrInvalidChecksum, m.Checksum)
	}

	if len(m.InstallPaths) == 0 {
		return fmt.Errorf("%w: 'install_paths' cannot be empty", ErrMissingField)
	}

	for i, ip := range m.InstallPaths {
		if strings.TrimSpace(ip.Source) == "" {
			return fmt.Errorf("%w: install_paths[%d] 'source' cannot be empty", ErrInvalidPath, i)
		}
		if strings.TrimSpace(ip.Destination) == "" {
			return fmt.Errorf("%w: install_paths[%d] 'destination' cannot be empty", ErrInvalidPath, i)
		}
	}

	for i, dep := range m.Dependencies {
		if strings.TrimSpace(dep.Name) == "" {
			return fmt.Errorf("%w: dependencies[%d] 'name' cannot be empty", ErrMissingField, i)
		}
	}

	return nil
}
