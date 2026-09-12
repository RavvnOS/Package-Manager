package main

import (
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"runtime"
	"text/tabwriter"
	"time"

	"github.com/spf13/cobra"

	"ravpkg/internal/db"
)

var (
	dbPathFlag string
)

func getDefaultDBPath() string {
	if env := os.Getenv("RAVPKG_DB"); env != "" {
		return env
	}
	if runtime.GOOS == "windows" {
		return filepath.Join(".", "ravpkg.db")
	}
	return "/var/db/ravpkg/pkg.db"
}

func openDB() (*db.DB, error) {
	path := dbPathFlag
	if path == "" {
		path = getDefaultDBPath()
	}
	return db.Open(path)
}

func newRootCmd() *cobra.Command {
	rootCmd := &cobra.Command{
		Use:   "ravpkg",
		Short: "Minimal-viable package manager for ravynOS",
		Long: `ravpkg is the native package manager for ravynOS, managing package
installations, removals, queries, and system manifests.

Phase 1-2 Scaffolding:
- list: functional (reads local SQLite package DB)
- info: functional (reads package metadata and file list)
- install: stub (deferred to Phase 2)
- remove: stub (deferred to Phase 2)
- search: stub (deferred to Phase 4)`,
		SilenceUsage: true,
	}

	rootCmd.PersistentFlags().StringVarP(&dbPathFlag, "db", "d", "", "Path to SQLite database (default: /var/db/ravpkg/pkg.db or ./ravpkg.db)")

	rootCmd.AddCommand(newInstallCmd())
	rootCmd.AddCommand(newRemoveCmd())
	rootCmd.AddCommand(newListCmd())
	rootCmd.AddCommand(newInfoCmd())
	rootCmd.AddCommand(newSearchCmd())

	return rootCmd
}

// install <package-file> [STUB]
func newInstallCmd() *cobra.Command {
	return &cobra.Command{
		Use:   "install <package-file>",
		Short: "Install a package archive onto the system [STUB]",
		Long:  "Unpacks and installs package payload files according to its manifest. (Implementation deferred to Phase 2)",
		Args:  cobra.ExactArgs(1),
		Run: func(cmd *cobra.Command, args []string) {
			pkgFile := args[0]
			fmt.Printf("[STUB] Not yet implemented: filesystem installation logic for %q is deferred to Phase 2.\n", pkgFile)
		},
	}
}

// remove <package-name> [STUB]
func newRemoveCmd() *cobra.Command {
	return &cobra.Command{
		Use:   "remove <package-name>",
		Short: "Remove an installed package from the system [STUB]",
		Long:  "Removes installed package files and deregisters from local database. (Implementation deferred to Phase 2)",
		Args:  cobra.ExactArgs(1),
		Run: func(cmd *cobra.Command, args []string) {
			pkgName := args[0]
			fmt.Printf("[STUB] Not yet implemented: filesystem removal logic for %q is deferred to Phase 2.\n", pkgName)
		},
	}
}

// list [FUNCTIONAL]
func newListCmd() *cobra.Command {
	return &cobra.Command{
		Use:   "list",
		Short: "List all installed packages [FUNCTIONAL]",
		Long:  "Queries the local SQLite database and prints all currently installed packages.",
		Args:  cobra.NoArgs,
		RunE: func(cmd *cobra.Command, args []string) error {
			database, err := openDB()
			if err != nil {
				return fmt.Errorf("database error: %w", err)
			}
			defer database.Close()

			packages, err := database.ListPackages()
			if err != nil {
				return fmt.Errorf("failed to query packages: %w", err)
			}

			if len(packages) == 0 {
				fmt.Println("No packages currently installed.")
				return nil
			}

			w := tabwriter.NewWriter(os.Stdout, 0, 0, 3, ' ', 0)
			fmt.Fprintln(w, "NAME\tVERSION\tINSTALLED\tFILES")
			for _, p := range packages {
				dateStr := p.InstallDate.Format("2006-01-02 15:04:05")
				if p.InstallDate.IsZero() {
					dateStr = "-"
				}
				fmt.Fprintf(w, "%s\t%s\t%s\t%d\n", p.Name, p.Version, dateStr, len(p.InstalledFiles))
			}
			return w.Flush()
		},
	}
}

// info <package-name> [FUNCTIONAL]
func newInfoCmd() *cobra.Command {
	return &cobra.Command{
		Use:   "info <package-name>",
		Short: "Display details and installed files for a package [FUNCTIONAL]",
		Long:  "Displays detailed package metadata and installed file paths from the local SQLite database.",
		Args:  cobra.ExactArgs(1),
		RunE: func(cmd *cobra.Command, args []string) error {
			pkgName := args[0]
			database, err := openDB()
			if err != nil {
				return fmt.Errorf("database error: %w", err)
			}
			defer database.Close()

			pkg, err := database.GetPackage(pkgName)
			if err != nil {
				if errors.Is(err, db.ErrNotFound) {
					return fmt.Errorf("package %q is not installed", pkgName)
				}
				return fmt.Errorf("failed to get package info: %w", err)
			}

			dateStr := pkg.InstallDate.UTC().Format(time.RFC3339)
			if pkg.InstallDate.IsZero() {
				dateStr = "unknown"
			}

			fmt.Printf("Package:      %s\n", pkg.Name)
			fmt.Printf("Version:      %s\n", pkg.Version)
			fmt.Printf("Install Date: %s\n", dateStr)
			fmt.Printf("Manifest:     %s\n", pkg.ManifestPath)
			fmt.Printf("Files (%d):\n", len(pkg.InstalledFiles))
			for _, f := range pkg.InstalledFiles {
				fmt.Printf("  - %s\n", f)
			}

			return nil
		},
	}
}

// search <query> [STUB]
func newSearchCmd() *cobra.Command {
	return &cobra.Command{
		Use:   "search <query>",
		Short: "Search for packages in the remote repository [STUB]",
		Long:  "Searches package indices in the remote repository. (Implementation deferred to Phase 4)",
		Args:  cobra.ExactArgs(1),
		Run: func(cmd *cobra.Command, args []string) {
			query := args[0]
			fmt.Printf("[STUB] Not yet implemented: repository search for %q depends on Phase 4 repo tooling.\n", query)
		},
	}
}

func main() {
	rootCmd := newRootCmd()
	if err := rootCmd.Execute(); err != nil {
		os.Exit(1)
	}
}
