---
name: shell-scripting
description: >
  Expert shell scripting for bash, zsh, and POSIX sh. Covers safety patterns (set -euo pipefail,
  quoting, error handling), argument parsing, functions, file operations, process management,
  testing with bats/ShellCheck, and operational patterns (cron, locks, signals). Also covers
  zsh-specific features including .zshrc configuration, prompts, completions, and scripting differences.
  Use when writing bash/zsh scripts, configuring shells, or when user mentions .sh files, shell safety,
  or asks about zsh/bash differences.
---

# Shell Scripting Guide

Safe, production-grade shell scripts for bash, zsh, and POSIX sh.

## Philosophy

Shell scripts fail silently and unpredictably by default. This skill teaches you to write scripts that:
- **Fail fast and loudly** when something goes wrong
- **Quote religiously** to handle spaces and special characters
- **Validate inputs** before destructive operations
- **Clean up after themselves** even when interrupted
- **Run reliably** in cron, CI/CD, and other non-interactive environments

## Quick Start — The Safety Header

**Every bash script must start with this:**

```bash
#!/usr/bin/env bash
set -euo pipefail

# Optional but recommended:
# set -x  # Debug mode — prints each command before execution
```

**What each flag does:**
- `set -e` — Exit immediately if any command fails (exit code ≠ 0)
- `set -u` — Exit if you reference an undefined variable
- `set -o pipefail` — Exit if any command in a pipeline fails (not just the last one)

**For POSIX sh** (Alpine, minimal containers):
```sh
#!/bin/sh
set -eu
# Note: pipefail is not POSIX, omit or check for bash
```

**For zsh scripts:**
```zsh
#!/usr/bin/env zsh
setopt ERR_EXIT NO_UNSET PIPE_FAIL
# Or use: set -euo pipefail (bash compatibility)
```

## Core Safety Patterns

### 1. Always Quote Variables

```bash
# BAD — breaks on spaces, globs, fails silently
rm -rf $DIR
echo $USER_INPUT > file.txt
for file in $FILES; do echo $file; done

# GOOD — safe quoting
rm -rf "${DIR:?}"              # :? fails if DIR is empty/unset
echo "$USER_INPUT" > file.txt
for file in "${FILES[@]}"; do  # array-safe iteration
  echo "$file"
done
```

### 2. Use `command -v`, Never `which`

```bash
# BAD — which is not POSIX, may not exist
if which python >/dev/null; then

# GOOD — POSIX-compliant
if command -v python >/dev/null 2>&1; then
  python script.py
fi
```

### 3. Cleanup Traps

```bash
#!/usr/bin/env bash
set -euo pipefail

# Create temp file
TMP=$(mktemp)

# Always cleanup on exit (success, failure, or interrupt)
cleanup() {
  rm -f "$TMP"
}
trap cleanup EXIT INT TERM

# Script continues...
```

### 4. Error Handling

```bash
# die() helper function
die() {
  echo "ERROR: $*" >&2
  exit 1
}

# Validate preconditions
[[ -f "$CONFIG_FILE" ]] || die "Config file not found: $CONFIG_FILE"
[[ -n "${API_KEY:-}" ]] || die "API_KEY environment variable not set"

# Check command success
if ! curl -f "$URL" -o output.json; then
  die "Failed to fetch $URL"
fi
```

## Argument Parsing

### Positional Arguments with Validation

```bash
#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<EOF
Usage: $0 <input-file> <output-file>

Converts input file to output format.
EOF
  exit 1
}

# Validate argument count
[[ $# -eq 2 ]] || usage

INPUT="${1:?Input file required}"
OUTPUT="${2:?Output file required}"

# Validate input exists
[[ -f "$INPUT" ]] || die "Input file not found: $INPUT"
```

### getopts for Flags (POSIX)

```bash
#!/usr/bin/env bash
set -euo pipefail

VERBOSE=false
OUTPUT=""

usage() {
  echo "Usage: $0 [-v] [-o output-file] input-file"
  exit 1
}

while getopts "vo:h" opt; do
  case $opt in
    v) VERBOSE=true ;;
    o) OUTPUT="$OPTARG" ;;
    h) usage ;;
    *) usage ;;
  esac
done
shift $((OPTIND - 1))

# Remaining positional args
INPUT="${1:-}"
[[ -n "$INPUT" ]] || usage
```

## Functions & Structure

### The main() Pattern

```bash
#!/usr/bin/env bash
set -euo pipefail

# Helper functions
log() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" >&2
}

die() {
  log "ERROR: $*"
  exit 1
}

# Main logic
main() {
  log "Starting backup..."
  
  # Do work
  if ! backup_database; then
    die "Database backup failed"
  fi
  
  log "Backup complete"
}

backup_database() {
  # Function implementation
  mysqldump mydb > backup.sql
}

# Call main with all script arguments
main "$@"
```

### Function Best Practices

```bash
# Use local variables
process_file() {
  local file="$1"
  local temp_file
  temp_file=$(mktemp)
  
  # Process...
  
  rm -f "$temp_file"
}

# Return values: use exit codes, not echo
file_exists() {
  [[ -f "$1" ]]
  # Returns 0 (success) if file exists, 1 otherwise
}

# Capture output when needed
result=$(get_timestamp)

# Readonly constants
readonly CONFIG_DIR="/etc/myapp"
readonly MAX_RETRIES=3
```

## File & Path Operations

### Safe File Operations

```bash
# Script-relative paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/config.ini"

# Test file types
[[ -f "$FILE" ]]  # regular file
[[ -d "$DIR" ]]   # directory
[[ -r "$FILE" ]]  # readable
[[ -w "$FILE" ]]  # writable
[[ -x "$FILE" ]]  # executable
[[ -L "$LINK" ]]  # symbolic link
[[ -s "$FILE" ]]  # non-empty file

# Safe deletion — guard with variable check
[[ -n "${DIR:-}" ]] || die "DIR not set"
rm -rf "${DIR:?DIR must be set}"

# Atomic file writes
echo "data" > "$FILE.tmp"
mv "$FILE.tmp" "$FILE"  # atomic on same filesystem
```

### Directory Navigation

```bash
# BAD — loses error context
cd /tmp
do_work

# GOOD — fails if cd fails (with set -e)
cd /tmp || die "Failed to cd to /tmp"
do_work

# BETTER — automatic cleanup with subshell
(
  cd /tmp || exit 1
  do_work
)  # automatically returns to original directory

# BEST — pushd/popd for explicit state
pushd /tmp > /dev/null || die "Failed to cd to /tmp"
do_work
popd > /dev/null
```

## Common Pitfalls to Avoid

| Bad Pattern | Why It's Bad | Safe Pattern |
|-------------|--------------|--------------|
| `rm -rf $DIR` | If `$DIR` is empty, deletes current directory | `rm -rf "${DIR:?}"` |
| `if [ $? -eq 0 ]` | `$?` changes with every command | `if command; then` |
| `ls \| grep foo` | Breaks on spaces, parses ls output | `find . -name "*foo*"` or glob |
| `for f in $(ls)` | Word splitting breaks on spaces | `for f in ./*; do` |
| `which python` | Not POSIX, may not exist | `command -v python` |
| `cat file \| grep pattern` | Useless use of cat (UUOC) | `grep pattern file` |
| `#!/bin/sh` with `[[` | `[[` is not POSIX | Use `[` or change shebang to bash |
| `echo $VAR` | Breaks on spaces and globs | `echo "$VAR"` |
| Hardcoded `/tmp/myfile` | Race conditions, permissions issues | `mktemp` |
| `exit 0` on error | Misleading exit code | `exit 1` or higher |

## Testing & Linting

### ShellCheck — Mandatory

Every script should pass ShellCheck:

```bash
# Install: brew install shellcheck (macOS) or apt install shellcheck (Linux)
shellcheck script.sh

# In CI/CD
find . -name "*.sh" -exec shellcheck {} +
```

### bats — Bash Automated Testing

See `references/testing.md` for full bats coverage.

```bash
# test.bats
#!/usr/bin/env bats

@test "script exits 0 on success" {
  run ./backup.sh --dry-run
  [ "$status" -eq 0 ]
}

@test "script fails without config file" {
  run ./backup.sh
  [ "$status" -ne 0 ]
  [[ "$output" =~ "Config file not found" ]]
}
```

## Operational Patterns

### Cron-Safe Scripts

```bash
#!/usr/bin/env bash
set -euo pipefail

# Use absolute paths (cron has minimal PATH)
PATH=/usr/local/bin:/usr/bin:/bin

# Log to file with rotation
LOG_FILE="/var/log/backup.log"
exec >> "$LOG_FILE" 2>&1

# Always log timestamp
echo "[$(date -Iseconds)] Starting backup"

# Rest of script...
```

### Lock Files (Prevent Concurrent Runs)

```bash
#!/usr/bin/env bash
set -euo pipefail

LOCK_FILE="/var/lock/backup.lock"

# Acquire lock
exec 200>"$LOCK_FILE"
flock -n 200 || {
  echo "Another instance is running"
  exit 1
}

# Script continues... lock released on exit
```

### Signal Handling

```bash
#!/usr/bin/env bash
set -euo pipefail

cleanup() {
  echo "Caught signal, cleaning up..."
  # Kill child processes
  jobs -p | xargs -r kill
  # Remove temp files
  rm -f "$TMP_FILE"
  exit 130  # 128 + SIGINT
}

trap cleanup INT TERM

# Long-running work...
```

## Shell Selection Guide

| Shell | Use When | Notes |
|-------|----------|-------|
| `#!/usr/bin/env bash` | Default choice | Portable across Linux/macOS, rich features |
| `#!/bin/bash` | System scripts only | Hardcoded path, may not exist on all systems |
| `#!/bin/sh` | Maximum portability | Alpine, minimal containers. POSIX only. |
| `#!/usr/bin/env zsh` | zsh-specific features | Mostly for interactive config, not scripts |

## Variable Naming

```bash
# UPPERCASE for environment variables and exported vars
export DATABASE_URL="postgresql://..."
export PATH="/usr/local/bin:$PATH"

# lowercase for local/internal variables
input_file="data.csv"
user_name="admin"

# Readonly for constants
readonly MAX_RETRIES=3
readonly CONFIG_DIR="/etc/myapp"
```

## zsh-Specific Content

For zsh scripting differences, interactive configuration (.zshrc), prompts, and completions, see:
- **`references/zsh.md`** — Comprehensive zsh guide

## Advanced Topics

See reference files for deep dives:
- **`references/bash.md`** — Bash-specific features (arrays, string manipulation, advanced patterns)
- **`references/posix-sh.md`** — POSIX portable scripting constraints and patterns
- **`references/safety-patterns.md`** — Advanced error handling, input validation, security
- **`references/argument-parsing.md`** — Complex CLI argument parsers, long options
- **`references/testing.md`** — bats, ShellCheck integration, debugging techniques
- **`references/operational.md`** — Systemd units, log rotation, daemon patterns

## Quick Reference Card

```bash
# Safety header (bash)
#!/usr/bin/env bash
set -euo pipefail

# Die helper
die() { echo "ERROR: $*" >&2; exit 1; }

# Temp file
TMP=$(mktemp)
trap 'rm -f "$TMP"' EXIT

# Validate args
[[ $# -ge 1 ]] || die "Usage: $0 <file>"
[[ -f "$1" ]] || die "File not found: $1"

# Check command exists
command -v jq >/dev/null || die "jq not installed"

# Safe variable reference
rm -rf "${DIR:?DIR must be set}"

# Array iteration
for item in "${array[@]}"; do
  echo "$item"
done

# Function with local vars
process() {
  local input="$1"
  # ...
}

# Conditional execution
if command; then
  # Success path
else
  # Failure path
fi
```

## When to Use Each Skill Section

- **Getting started with a script?** → Safety header + core patterns
- **Need argument parsing?** → Argument parsing section
- **Writing for production?** → Operational patterns + testing
- **Debugging failures?** → Error handling + ShellCheck
- **Configuring zsh?** → `references/zsh.md`
- **Need POSIX portability?** → `references/posix-sh.md`
- **Building a complex CLI?** → `references/argument-parsing.md`

---

**Remember:** The goal is safe, maintainable scripts that fail loudly and clean up after themselves. When in doubt, quote more, validate more, and test with ShellCheck.
