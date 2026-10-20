# POSIX sh — Portable Shell Scripting

Writing scripts that work everywhere: Alpine, BusyBox, Dash, minimal containers, and old systems.

## Why POSIX sh?

**Use POSIX sh when:**
- Writing for Alpine Linux / Docker containers (uses BusyBox ash)
- Maximum portability across all Unix-like systems
- Minimal environments without bash installed
- System scripts that must work during early boot

**Don't use POSIX sh when:**
- bash is guaranteed available (most Linux systems, macOS)
- You need bash features (arrays, `[[`, process substitution)
- Developer convenience trumps portability

## POSIX vs bash — What's Different?

### Features NOT in POSIX sh

| Feature | bash | POSIX sh Alternative |
|---------|------|---------------------|
| `[[` test | ✅ | Use `[` |
| Arrays | ✅ | Use positional params or IFS tricks |
| `{1..10}` brace expansion | ✅ | Use `seq` |
| `$((i++))` increment | ✅ | `i=$((i + 1))` |
| `${var^^}` uppercase | ✅ | `tr` or `awk` |
| `${var//old/new}` | ✅ | `sed` |
| `[[ $a =~ regex ]]` | ✅ | `echo "$a" \| grep -E` |
| `pipefail` | ✅ | Not available |
| `<<<` here-strings | ✅ | Use pipe or here-doc |
| `source` | ✅ | Use `.` |
| `function name() {}` | ✅ | Use `name() {}` |

### POSIX sh Safety Header

```sh
#!/bin/sh
set -eu

# Note: set -o pipefail is NOT POSIX
# Some shells support it, but don't rely on it
```

### Checking for POSIX Compliance

```bash
# Check if script is POSIX-compliant
shellcheck --shell=sh script.sh

# Test with dash (POSIX-compliant shell)
dash script.sh
```

## POSIX Alternatives

### Test Operators — [ not [[

```sh
# POSIX — use [ ]
if [ -f "$file" ]; then
  echo "File exists"
fi

# Multiple conditions
if [ -f "$file" ] && [ -r "$file" ]; then
  echo "File exists and is readable"
fi

# String comparison
if [ "$a" = "$b" ]; then  # Note: single =
  echo "Equal"
fi

if [ "$a" != "$b" ]; then
  echo "Not equal"
fi

# Numeric comparison
if [ "$num" -eq 5 ]; then
  echo "Equal to 5"
fi

# Greater than (for strings, lexicographic)
if [ "$a" \> "$b" ]; then  # Must escape > and <
  echo "a is greater than b"
fi
```

### String Manipulation

```sh
# bash: ${var#pattern}
# POSIX: use case
strip_prefix() {
  case "$1" in
    prefix*) echo "${1#prefix}" ;;
    *) echo "$1" ;;
  esac
}

# bash: ${var%pattern}
# POSIX: use case
strip_suffix() {
  case "$1" in
    *suffix) echo "${1%suffix}" ;;
    *) echo "$1" ;;
  esac
}

# bash: ${var^^}
# POSIX: use tr
uppercase() {
  echo "$1" | tr '[:lower:]' '[:upper:]'
}

# bash: ${var,,}
# POSIX: use tr
lowercase() {
  echo "$1" | tr '[:upper:]' '[:lower:]'
}

# bash: ${var//old/new}
# POSIX: use sed
replace_all() {
  echo "$1" | sed "s/$2/$3/g"
}
```

### Arrays — Use Positional Parameters

```sh
# bash: array=(a b c)
# POSIX: use set
set -- a b c

# Access
echo "$1"  # a
echo "$2"  # b

# All elements
for item in "$@"; do
  echo "$item"
done

# Count
echo "$#"

# Append
set -- "$@" d

# Clear
set --
```

### Loops

```sh
# Range loop
# bash: for i in {1..10}
# POSIX: use seq
for i in $(seq 1 10); do
  echo "$i"
done

# C-style loop not available
# bash: for ((i=0; i<10; i++))
# POSIX: use while
i=0
while [ $i -lt 10 ]; do
  echo "$i"
  i=$((i + 1))
done
```

### Function Syntax

```sh
# bash: function name() { ... }
# POSIX: name() { ... }
greet() {
  echo "Hello, $1"
}

# Local variables (POSIX, but not in oldest shells)
process_file() {
  local file="$1"  # Works in most POSIX shells
  # If local doesn't work, use unique names
  _process_file_var="$1"
}
```

### Command Substitution

```sh
# bash: $(command) or `command`
# POSIX: both work, but $(command) is preferred
result=$(date +%s)

# Nested
outer=$(echo "$(inner_command)")
```

### Source Files

```sh
# bash: source file.sh
# POSIX: . file.sh
. ./library.sh
```

## Portability Patterns

### Checking Shell Type

```sh
# Detect if running in bash
if [ -n "$BASH_VERSION" ]; then
  echo "Running in bash"
fi

# Check for specific feature
if (eval 'set -o pipefail' 2>/dev/null); then
  set -o pipefail
fi
```

### Command Existence

```sh
# Check if command exists
if command -v python3 >/dev/null 2>&1; then
  python3 script.py
else
  echo "python3 not found" >&2
  exit 1
fi
```

### printf vs echo

```sh
# echo is not fully portable (behavior varies)
# bash: echo -n "text"
# POSIX: printf is safer
printf '%s' "text"
printf '%s\n' "text with newline"

# Format strings
printf "Name: %s, Age: %d\n" "$name" "$age"
```

### Read Lines

```sh
# POSIX way to read file line by line
while IFS= read -r line; do
  echo "$line"
done < file.txt

# Read from command (no process substitution in POSIX)
command | while IFS= read -r line; do
  echo "$line"
done
```

### Arithmetic

```sh
# POSIX arithmetic
result=$((5 + 3))
result=$((result * 2))

# Increment
# bash: $((i++))
# POSIX:
i=$((i + 1))

# Decrement
i=$((i - 1))

# No +=, -=, etc. in POSIX arithmetic
```

### Pattern Matching

```sh
# case is your friend in POSIX sh
case "$file" in
  *.txt)
    echo "Text file"
    ;;
  *.jpg|*.png)
    echo "Image file"
    ;;
  *)
    echo "Unknown"
    ;;
esac

# Pattern matching in tests
case "$string" in
  prefix*)
    echo "Starts with prefix"
    ;;
esac
```

## Common Pitfalls

### 1. Forgetting to Quote

```sh
# WRONG
if [ -f $file ]; then

# RIGHT
if [ -f "$file" ]; then
```

### 2. Using == instead of =

```sh
# WRONG (bashism)
if [ "$a" == "$b" ]; then

# RIGHT (POSIX)
if [ "$a" = "$b" ]; then
```

### 3. Using [[ ]]

```sh
# WRONG (bashism)
if [[ -f "$file" ]]; then

# RIGHT (POSIX)
if [ -f "$file" ]; then
```

### 4. Using {1..10}

```sh
# WRONG (bashism)
for i in {1..10}; do

# RIGHT (POSIX)
for i in $(seq 1 10); do
```

### 5. Using local Without Check

```sh
# local is common but not guaranteed in POSIX
# If you need it, check:
if ! (eval 'local x=1' 2>/dev/null); then
  echo "This shell doesn't support local" >&2
  exit 1
fi
```

## Alpine / BusyBox Specifics

Alpine Linux uses BusyBox, which has limited utilities.

### BusyBox Differences

```sh
# Many GNU flags don't work
# GNU: ls --color=auto
# BusyBox: ls --color (or not available)

# find: limited options
# GNU: find -printf
# BusyBox: use -print and format with awk

# date: limited format options
# GNU: date --date="yesterday"
# BusyBox: date -d @$(($(date +%s) - 86400))

# readlink: no -f on BusyBox
# Use: realpath (if available)
```

### Testing on Alpine

```bash
# Run script in Alpine container
docker run --rm -v "$PWD:/work" -w /work alpine:latest sh script.sh

# Interactive Alpine shell
docker run --rm -it -v "$PWD:/work" -w /work alpine:latest sh
```

## POSIX Template

```sh
#!/bin/sh
set -eu

# Error handler
die() {
  echo "ERROR: $*" >&2
  exit 1
}

# Check dependencies
check_deps() {
  for cmd in curl jq; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      die "Required command not found: $cmd"
    fi
  done
}

# Parse arguments
parse_args() {
  while [ $# -gt 0 ]; do
    case "$1" in
      -h|--help)
        usage
        exit 0
        ;;
      -v|--verbose)
        VERBOSE=true
        shift
        ;;
      -o|--output)
        OUTPUT="$2"
        shift 2
        ;;
      *)
        die "Unknown option: $1"
        ;;
    esac
  done
}

# Usage message
usage() {
  cat <<EOF
Usage: $0 [OPTIONS]

Options:
  -h, --help       Show this help
  -v, --verbose    Verbose output
  -o, --output     Output file
EOF
}

# Main function
main() {
  check_deps
  parse_args "$@"
  
  # Your logic here
  echo "Running..."
}

# Run main
main "$@"
```

## Resources

- POSIX spec: https://pubs.opengroup.org/onlinepubs/9699919799/utilities/V3_chap02.html
- Dash (POSIX-compliant shell): http://gondor.apana.org.au/~herbert/dash/
- ShellCheck POSIX mode: `shellcheck --shell=sh`
- BusyBox documentation: https://busybox.net/
- Rich's sh (POSIX) tricks: http://www.etalabs.net/sh_tricks.html

## Quick Reference — POSIX Compliance Checklist

✅ Use `#!/bin/sh` or `#!/usr/bin/env sh`
✅ Use `[` not `[[`
✅ Use `=` not `==` in tests
✅ Quote all variable expansions
✅ Use `.` not `source`
✅ Use `command -v` not `which`
✅ Use `$(...)` not backticks
✅ Use `printf` not `echo -n`
✅ No arrays — use positional params
✅ No brace expansion — use `seq`
✅ No `pipefail` — check exit codes manually
✅ Test with `dash` or in Alpine container
✅ Run `shellcheck --shell=sh`
