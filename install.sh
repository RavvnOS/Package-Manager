#!/usr/bin/env bash
# install.sh - Installer for ravpkg on ravynOS / POSIX systems
set -euo pipefail

PREFIX="${PREFIX:-/usr/local}"
BIN_DIR="$PREFIX/bin"
LIB_DIR="$PREFIX/lib/ravpkg"

echo "Installing ravpkg to $PREFIX..."

# Check prerequisites
for tool in sqlite3 jq; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "Error: required dependency '$tool' not found." >&2
        echo "Please install $tool before installing ravpkg." >&2
        exit 1
    fi
done

# Create destination directories
mkdir -p "$BIN_DIR"
mkdir -p "$LIB_DIR"

# Copy library scripts and schema
cp lib/db.sh "$LIB_DIR/db.sh"
cp lib/parser.sh "$LIB_DIR/parser.sh"
cp schema/schema.sql "$LIB_DIR/schema.sql"
chmod 644 "$LIB_DIR/db.sh" "$LIB_DIR/parser.sh" "$LIB_DIR/schema.sql"

# Copy main binary executable
cp bin/ravpkg "$BIN_DIR/ravpkg"
chmod 755 "$BIN_DIR/ravpkg"

echo "ravpkg successfully installed to $BIN_DIR/ravpkg"
echo "Libraries installed to $LIB_DIR"
echo "Run 'ravpkg --help' to verify installation."
