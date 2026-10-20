# Safety Patterns & Error Handling

Advanced patterns for writing bulletproof shell scripts.

## Error Philosophy

**Scripts should fail loudly and early.** Silent failures are the enemy of reliability.

### Core Principles

1. **Exit on error** — `set -e` or explicit checks
2. **Validate early** — Check preconditions before doing work
3. **Meaningful messages** — Tell the user what went wrong and why
4. **Clean up** — Use traps to clean up temp files even on failure
5. **Exit codes** — Use standard exit codes to communicate failure types

## Error Handling Patterns

### The die() Function

```bash
#!/usr/bin/env bash
set -euo pipefail

die() {
  echo "ERROR: $*" >&2
  exit 1
}

# Usage
[[ -f "$CONFIG" ]] || die "Config file not found: $CONFIG"
[[ -n "${API_KEY:-}" ]] || die "API_KEY environment variable not set"

if ! command -v jq >/dev/null 2>&1; then
  die "jq is required but not installed"
fi
```

### Contextual Error Messages

```bash
# BAD — generic, unhelpful
[[ -f "$file" ]] || die "File not found"

# GOOD — specific, actionable
[[ -f "$file" ]] || die "Input file not found: $file. Check path and permissions."

# BETTER — includes remedy
[[ -f "$file" ]] || die "Input file not found: $file. Run '$0 --help' for usage."
```

### Function Error Handling

```bash
# Pattern 1: Return error code
backup_database() {
  if ! mysqldump mydb > backup.sql; then
    return 1
  fi
  return 0
}

if ! backup_database; then
  die "Database backup failed"
fi

# Pattern 2: Use || die inside function (with set -e)
backup_database() {
  mysqldump mydb > backup.sql || die "mysqldump failed"
  gzip backup.sql || die "gzip failed"
}

backup_database  # Propagates error via die()
```

### Exit Codes

Use meaningful exit codes:

```bash
# Standard exit codes
readonly EX_OK=0           # Success
readonly EX_GENERAL=1      # General error
readonly EX_MISUSE=2       # Misuse (bad arguments)
readonly EX_NOINPUT=66     # Input file missing
readonly EX_UNAVAILABLE=69 # Service unavailable
readonly EX_IOERR=74       # I/O error
readonly EX_TEMPFAIL=75    # Temporary failure
readonly EX_CONFIG=78      # Configuration error

# Usage
[[ $# -ge 1 ]] || {
  usage
  exit $EX_MISUSE
}

[[ -f "$INPUT" ]] || {
  echo "Input file not found: $INPUT" >&2
  exit $EX_NOINPUT
}
```

### Traps — Always Clean Up

```bash
#!/usr/bin/env bash
set -euo pipefail

# Create temp directory
TMP_DIR=$(mktemp -d)

# Cleanup function
cleanup() {
  local exit_code=$?
  echo "Cleaning up..."
  rm -rf "$TMP_DIR"
  if [[ $exit_code -ne 0 ]]; then
    echo "Script failed with exit code: $exit_code" >&2
  fi
  exit $exit_code
}

# Register trap for EXIT, INT (Ctrl+C), TERM (kill)
trap cleanup EXIT INT TERM

# Script continues...
# Cleanup runs automatically on any exit
```

### Multiple Traps

```bash
# Separate cleanup and error handling
cleanup_files() {
  rm -f "$TMP_FILE"
}

cleanup_processes() {
  # Kill background jobs
  jobs -p | xargs -r kill 2>/dev/null
}

cleanup() {
  cleanup_files
  cleanup_processes
}

trap cleanup EXIT
trap 'echo "Interrupted"; exit 130' INT  # 128 + SIGINT (2)
trap 'echo "Terminated"; exit 143' TERM  # 128 + SIGTERM (15)
```

## Input Validation

### Command-Line Arguments

```bash
# Validate required args
validate_args() {
  [[ $# -ge 1 ]] || die "Missing required argument: input-file"
  
  local input="$1"
  
  # File exists
  [[ -f "$input" ]] || die "Input file not found: $input"
  
  # File is readable
  [[ -r "$input" ]] || die "Input file not readable: $input"
  
  # File is non-empty
  [[ -s "$input" ]] || die "Input file is empty: $input"
}
```

### Environment Variables

```bash
# Required env vars
validate_env() {
  local required_vars=(
    DATABASE_URL
    API_KEY
    CONFIG_DIR
  )
  
  for var in "${required_vars[@]}"; do
    if [[ -z "${!var:-}" ]]; then
      die "Required environment variable not set: $var"
    fi
  done
}

# Call early
validate_env
```

### Numeric Validation

```bash
# Check if string is a number
is_number() {
  [[ "$1" =~ ^[0-9]+$ ]]
}

# Usage
if ! is_number "$PORT"; then
  die "PORT must be a number: $PORT"
fi

if [[ $PORT -lt 1 || $PORT -gt 65535 ]]; then
  die "PORT must be between 1 and 65535: $PORT"
fi
```

## Safe File Operations

### Variable Guards

```bash
# BAD — if DIR is unset, deletes current directory!
rm -rf $DIR

# GOOD — fails if DIR is unset or empty
rm -rf "${DIR:?DIR variable must be set}"

# BETTER — validate before delete
[[ -n "${DIR:-}" ]] || die "DIR not set"
[[ -d "$DIR" ]] || die "DIR is not a directory: $DIR"
rm -rf "$DIR"
```

### Atomic Writes

```bash
# Write to temp file, then move atomically
write_config() {
  local config_file="$1"
  local tmp_file="${config_file}.tmp.$$"
  
  # Write to temp
  cat > "$tmp_file" <<EOF
key1=value1
key2=value2
EOF
  
  # Atomic move (on same filesystem)
  mv "$tmp_file" "$config_file"
}
```

### Safe Temp Files

```bash
# BAD — predictable, race condition
TMP_FILE="/tmp/myapp-$$.tmp"

# GOOD — unpredictable, secure
TMP_FILE=$(mktemp)

# BETTER — in secure temp directory
TMP_DIR=$(mktemp -d)
TMP_FILE="$TMP_DIR/output.txt"

# Cleanup
trap 'rm -rf "$TMP_DIR"' EXIT
```

### File Locking

```bash
# Prevent concurrent runs
LOCK_FILE="/var/lock/myapp.lock"

acquire_lock() {
  exec 200>"$LOCK_FILE"
  if ! flock -n 200; then
    die "Another instance is already running"
  fi
}

# Alternative: timeout after N seconds
acquire_lock_with_timeout() {
  exec 200>"$LOCK_FILE"
  if ! flock -w 60 200; then
    die "Could not acquire lock within 60 seconds"
  fi
}

acquire_lock
# Lock released automatically when script exits
```

## Process Management

### Check Dependencies

```bash
#!/usr/bin/env bash
set -euo pipefail

# Check required commands
check_dependencies() {
  local deps=(
    jq
    curl
    git
  )
  
  local missing=()
  for cmd in "${deps[@]}"; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      missing+=("$cmd")
    fi
  done
  
  if [[ ${#missing[@]} -gt 0 ]]; then
    die "Missing required commands: ${missing[*]}"
  fi
}

check_dependencies
```

### Background Jobs

```bash
# Start background job with error checking
start_server() {
  local log_file="$1"
  
  server_command > "$log_file" 2>&1 &
  local pid=$!
  
  # Give it a moment to fail
  sleep 1
  
  # Check if still running
  if ! kill -0 $pid 2>/dev/null; then
    die "Server failed to start. Check $log_file"
  fi
  
  echo $pid
}

# Cleanup background jobs on exit
cleanup() {
  if [[ -n "${SERVER_PID:-}" ]]; then
    echo "Stopping server (PID $SERVER_PID)..."
    kill $SERVER_PID 2>/dev/null || true
    wait $SERVER_PID 2>/dev/null || true
  fi
}
trap cleanup EXIT

SERVER_PID=$(start_server "server.log")
```

## Defensive Coding

### Always Quote Variables

```bash
# These all break on spaces or special characters
rm -rf $DIR
echo $USER_INPUT > file
for file in $FILES; do

# These are safe
rm -rf "$DIR"
echo "$USER_INPUT" > file
for file in "${FILES[@]}"; do
```

### IFS (Internal Field Separator)

```bash
# Default IFS splits on space, tab, newline
# This can cause issues

# Set IFS for parsing
while IFS=: read -r user pass uid gid gecos home shell; do
  echo "User: $user"
done < /etc/passwd

# Safe default IFS for scripts
IFS=$'\n\t'  # Only split on newline and tab, not space
```

### Glob Safety

```bash
# Disable globbing when iterating
set -f  # or: set -o noglob
for pattern in $PATTERNS; do
  echo "$pattern"
done
set +f

# Or quote
for pattern in "$PATTERNS"; do
  echo "$pattern"
done
```

## Security Considerations

### Command Injection

```bash
# BAD — command injection vulnerability
user_input="file.txt; rm -rf /"
eval "cat $user_input"  # NEVER USE EVAL WITH USER INPUT

# GOOD — properly quoted
cat "$user_input"

# BAD — vulnerable to injection
find . -name "$user_pattern" -exec rm {} \;

# BETTER — validate input first
if [[ "$user_pattern" =~ ^[a-zA-Z0-9._-]+$ ]]; then
  find . -name "$user_pattern" -exec rm {} \;
else
  die "Invalid pattern"
fi
```

### Sensitive Data

```bash
# Don't log sensitive data
# BAD
echo "Connecting with password: $PASSWORD"

# GOOD
echo "Connecting to database..."

# Avoid secrets in command line (visible in ps)
# BAD
mysql -u root -p"$PASSWORD"

# BETTER — use config file or stdin
mysql --defaults-file=<(cat <<EOF
[client]
user=root
password=$PASSWORD
EOF
) mydb
```

### File Permissions

```bash
# Create files with restricted permissions
(umask 077 && touch "$SECRET_FILE")
# Or explicit
touch "$SECRET_FILE"
chmod 600 "$SECRET_FILE"

# Check file permissions before reading secrets
if [[ $(stat -f %A "$CONFIG") != "600" ]]; then
  die "Config file has unsafe permissions: $CONFIG"
fi
```

## Logging

### Log Levels

```bash
# Log functions
readonly LOG_LEVEL="${LOG_LEVEL:-INFO}"

log() {
  local level="$1"
  shift
  echo "[$(date -Iseconds)] [$level] $*" >&2
}

debug() { [[ "$LOG_LEVEL" == "DEBUG" ]] && log DEBUG "$@"; }
info() { log INFO "$@"; }
warn() { log WARN "$@"; }
error() { log ERROR "$@"; }

# Usage
debug "Starting function foo with arg: $1"
info "Processing file: $file"
warn "Retrying connection..."
error "Failed to connect to database"
```

### Structured Logging

```bash
# JSON logging for parsing
log_json() {
  local level="$1"
  shift
  printf '{"timestamp":"%s","level":"%s","message":"%s"}\n' \
    "$(date -Iseconds)" "$level" "$*" >&2
}
```

## Retry Logic

```bash
# Retry with exponential backoff
retry() {
  local max_attempts="$1"
  shift
  local cmd=("$@")
  
  local attempt=1
  local delay=1
  
  while [[ $attempt -le $max_attempts ]]; do
    if "${cmd[@]}"; then
      return 0
    fi
    
    if [[ $attempt -eq $max_attempts ]]; then
      log ERROR "Command failed after $max_attempts attempts: ${cmd[*]}"
      return 1
    fi
    
    log WARN "Attempt $attempt failed, retrying in ${delay}s..."
    sleep $delay
    
    attempt=$((attempt + 1))
    delay=$((delay * 2))  # Exponential backoff
  done
}

# Usage
retry 3 curl -f https://api.example.com/health
```

## Testing Patterns

### Dry-Run Mode

```bash
#!/usr/bin/env bash
set -euo pipefail

DRY_RUN="${DRY_RUN:-false}"

run() {
  if [[ "$DRY_RUN" == "true" ]]; then
    echo "[DRY-RUN] $*" >&2
  else
    "$@"
  fi
}

# Usage
run rm -rf "$DIR"
run git push origin main

# Invoke with: DRY_RUN=true ./script.sh
```

### Assertions

```bash
# Assert function
assert() {
  if ! "$@"; then
    die "Assertion failed: $*"
  fi
}

# Usage
assert [[ -f "$CONFIG" ]]
assert command -v jq >/dev/null
assert [[ $PORT -gt 0 ]]
```

## Resources

- POSIX exit codes: `/usr/include/sysexits.h`
- Signal numbers: `kill -l`
- Bash manual: `man bash`
- ShellCheck: https://www.shellcheck.net/
