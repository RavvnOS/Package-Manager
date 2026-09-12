package repo

import "errors"

var (
	// ErrNotImplemented is returned when invoking Phase 4 repo operations.
	ErrNotImplemented = errors.New("repository tooling is not yet implemented (scheduled for Phase 4)")
)

// Index represents the remote repository package index.
type Index struct {
	URL      string
	Packages map[string]string
}

// Search queries the remote repository index. Stub implementation for Phase 4.
func Search(query string) ([]string, error) {
	return nil, ErrNotImplemented
}
