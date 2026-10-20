# Advanced Argument Parsing

Complex CLI argument parsing patterns for production scripts.

## Argument Parsing Strategies

| Strategy | Use When | Complexity |
|----------|----------|------------|
| Positional only | Simple scripts (1-3 args) | Low |
| `getopts` | Short flags (-v, -o file) | Medium |
| Manual parsing | Long options (--verbose) | Medium-High |
| Third-party parser | Complex CLIs, subcommands | High |

## Positional Arguments

### Basic Pattern

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

main() {
  # Validate argument count
  [[ $# -eq 2 ]] || usage
  
  INPUT="${1:?Input file required}"
  OUTPUT="${2:?Output file required}"
  
  # Validate input
  [[ -f "$INPUT" ]] || die "Input file not found: $INPUT"
  
  # Process...
}

main "$@"
```

### Optional Positional Args

```bash
# With defaults
INPUT="${1:-input.txt}"
OUTPUT="${2:-output.txt}"
VERBOSE="${3:-false}"

# Or explicit check
if [[ $# -ge 1 ]]; then
  INPUT="$1"
else
  INPUT="input.txt"
fi
```

## getopts — Short Flags Only

POSIX-compliant, works everywhere, but only handles short flags (`-v`, `-o file`).

### Basic getopts

```bash
#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<EOF
Usage: $0 [-h] [-v] [-o output-file] input-file

Options:
  -h          Show this help
  -v          Verbose output
  -o FILE     Output file (default: output.txt)
EOF
  exit 1
}

# Defaults
VERBOSE=false
OUTPUT="output.txt"

# Parse flags
while getopts "hvo:" opt; do
  case $opt in
    h)
      usage
      ;;
    v)
      VERBOSE=true
      ;;
    o)
      OUTPUT="$OPTARG"
      ;;
    \?)
      echo "Invalid option: -$OPTARG" >&2
      usage
      ;;
    :)
      echo "Option -$OPTARG requires an argument" >&2
      usage
      ;;
  esac
done

# Shift past processed options
shift $((OPTIND - 1))

# Remaining positional arguments
INPUT="${1:-}"
[[ -n "$INPUT" ]] || usage
```

### getopts with Required Arguments

```bash
# Colon after letter means "requires argument"
# -o file → o:
# -v (no arg) → v
while getopts "vo:p:" opt; do
  case $opt in
    v) VERBOSE=true ;;
    o) OUTPUT="$OPTARG" ;;
    p) PORT="$OPTARG" ;;
  esac
done
```

## Long Options — Manual Parsing

For `--verbose`, `--output=file`, etc.

### Long Options Pattern

```bash
#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<EOF
Usage: $0 [OPTIONS] input-file

Options:
  -h, --help              Show this help
  -v, --verbose           Verbose output
  -o, --output FILE       Output file
  -n, --dry-run           Dry run mode
      --config FILE       Config file
EOF
  exit 1
}

# Defaults
VERBOSE=false
OUTPUT=""
DRY_RUN=false
CONFIG="/etc/myapp/config"

# Parse arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      usage
      ;;
    -v|--verbose)
      VERBOSE=true
      shift
      ;;
    -o|--output)
      OUTPUT="$2"
      shift 2
      ;;
    --output=*)
      OUTPUT="${1#*=}"
      shift
      ;;
    -n|--dry-run)
      DRY_RUN=true
      shift
      ;;
    --config)
      CONFIG="$2"
      shift 2
      ;;
    --config=*)
      CONFIG="${1#*=}"
      shift
      ;;
    --)
      shift
      break
      ;;
    -*)
      die "Unknown option: $1"
      ;;
    *)
      break
      ;;
  esac
done

# Remaining positional args
INPUT="${1:-}"
[[ -n "$INPUT" ]] || usage
```

### Handling --option=value

```bash
case "$1" in
  --output=*)
    OUTPUT="${1#*=}"  # Strip prefix up to =
    shift
    ;;
  --output)
    OUTPUT="$2"
    shift 2
    ;;
esac
```

## Subcommands

Like `git commit`, `docker run`, etc.

### Subcommand Pattern

```bash
#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<EOF
Usage: $0 <command> [options]

Commands:
  start       Start the server
  stop        Stop the server
  restart     Restart the server
  status      Show server status
EOF
  exit 1
}

cmd_start() {
  echo "Starting server..."
  # Parse start-specific options
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -p|--port)
        PORT="$2"
        shift 2
        ;;
      *)
        die "Unknown option: $1"
        ;;
    esac
  done
  # Start logic...
}

cmd_stop() {
  echo "Stopping server..."
  # Stop logic...
}

cmd_status() {
  echo "Server status:"
  # Status logic...
}

main() {
  [[ $# -ge 1 ]] || usage
  
  command="$1"
  shift
  
  case "$command" in
    start)
      cmd_start "$@"
      ;;
    stop)
      cmd_stop "$@"
      ;;
    restart)
      cmd_stop
      cmd_start "$@"
      ;;
    status)
      cmd_status "$@"
      ;;
    -h|--help)
      usage
      ;;
    *)
      echo "Unknown command: $command" >&2
      usage
      ;;
  esac
}

main "$@"
```

## Complex Example — All Patterns Combined

```bash
#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# Global config
# ============================================================================
readonly SCRIPT_NAME="$(basename "$0")"
readonly VERSION="1.0.0"

# ============================================================================
# Defaults
# ============================================================================
VERBOSE=false
DRY_RUN=false
CONFIG_FILE=""
OUTPUT_DIR="./output"
PORT=8080
WORKERS=4

# ============================================================================
# Helpers
# ============================================================================
die() {
  echo "ERROR: $*" >&2
  exit 1
}

log() {
  [[ "$VERBOSE" == "true" ]] && echo "[$(date -Iseconds)] $*" >&2
}

# ============================================================================
# Usage
# ============================================================================
usage() {
  cat <<EOF
$SCRIPT_NAME v$VERSION

Usage: $SCRIPT_NAME [OPTIONS] <command> [ARGS]

Global Options:
  -h, --help              Show this help
  -v, --verbose           Verbose logging
  -n, --dry-run           Dry run mode
  -c, --config FILE       Config file
      --version           Show version

Commands:
  serve [OPTIONS]         Start HTTP server
  process [OPTIONS] FILE  Process a file
  
Run '$SCRIPT_NAME <command> --help' for command-specific help.
EOF
  exit 0
}

usage_serve() {
  cat <<EOF
Usage: $SCRIPT_NAME serve [OPTIONS]

Options:
  -p, --port PORT         Port to listen on (default: 8080)
  -w, --workers N         Number of workers (default: 4)
  -d, --dir DIR           Serve directory (default: .)
EOF
  exit 0
}

usage_process() {
  cat <<EOF
Usage: $SCRIPT_NAME process [OPTIONS] <input-file>

Options:
  -o, --output DIR        Output directory (default: ./output)
  -f, --format FMT        Output format: json, yaml, xml
EOF
  exit 0
}

# ============================================================================
# Subcommands
# ============================================================================
cmd_serve() {
  local dir="."
  
  # Parse serve-specific options
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help)
        usage_serve
        ;;
      -p|--port)
        PORT="$2"
        shift 2
        ;;
      -w|--workers)
        WORKERS="$2"
        shift 2
        ;;
      -d|--dir)
        dir="$2"
        shift 2
        ;;
      *)
        die "Unknown option: $1"
        ;;
    esac
  done
  
  log "Starting server on port $PORT with $WORKERS workers"
  log "Serving directory: $dir"
  
  [[ "$DRY_RUN" == "true" ]] && {
    echo "[DRY-RUN] Would start server"
    return 0
  }
  
  # Actual serve logic...
  python3 -m http.server "$PORT"
}

cmd_process() {
  local format="json"
  local input=""
  
  # Parse process-specific options
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help)
        usage_process
        ;;
      -o|--output)
        OUTPUT_DIR="$2"
        shift 2
        ;;
      -f|--format)
        format="$2"
        shift 2
        ;;
      -*)
        die "Unknown option: $1"
        ;;
      *)
        input="$1"
        shift
        break
        ;;
    esac
  done
  
  # Validate
  [[ -n "$input" ]] || die "Input file required"
  [[ -f "$input" ]] || die "Input file not found: $input"
  
  log "Processing $input → $OUTPUT_DIR (format: $format)"
  
  [[ "$DRY_RUN" == "true" ]] && {
    echo "[DRY-RUN] Would process file"
    return 0
  }
  
  # Actual process logic...
  mkdir -p "$OUTPUT_DIR"
  cp "$input" "$OUTPUT_DIR/"
}

# ============================================================================
# Main
# ============================================================================
main() {
  [[ $# -eq 0 ]] && usage
  
  # Parse global options
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help)
        usage
        ;;
      --version)
        echo "$VERSION"
        exit 0
        ;;
      -v|--verbose)
        VERBOSE=true
        shift
        ;;
      -n|--dry-run)
        DRY_RUN=true
        shift
        ;;
      -c|--config)
        CONFIG_FILE="$2"
        shift 2
        ;;
      serve|process)
        # Subcommand — stop parsing global options
        break
        ;;
      -*)
        die "Unknown global option: $1"
        ;;
      *)
        die "Unknown command: $1"
        ;;
    esac
  done
  
  # Load config if provided
  if [[ -n "$CONFIG_FILE" ]]; then
    [[ -f "$CONFIG_FILE" ]] || die "Config file not found: $CONFIG_FILE"
    log "Loading config: $CONFIG_FILE"
    # shellcheck source=/dev/null
    . "$CONFIG_FILE"
  fi
  
  # Dispatch to subcommand
  [[ $# -ge 1 ]] || usage
  
  local command="$1"
  shift
  
  case "$command" in
    serve)
      cmd_serve "$@"
      ;;
    process)
      cmd_process "$@"
      ;;
    *)
      die "Unknown command: $command"
      ;;
  esac
}

main "$@"
```

## Third-Party Parsers

### Using argbash (generates parser code)

```bash
# Define args in comments, generate parser
# ARG_OPTIONAL_BOOLEAN([verbose], [v], [Verbose output])
# ARG_OPTIONAL_SINGLE([output], [o], [Output file])
# ARG_POSITIONAL_SINGLE([input], [Input file])
# ARG_HELP([My script])
# ARGBASH_GO()

# Generate:
# argbash script.sh -o script-parser.sh
```

### Using docopt (Python-based)

```bash
#!/usr/bin/env bash

# Parse with docopt
usage="
Usage:
  $0 [options] <input>
  $0 -h | --help

Options:
  -h --help       Show this help
  -v --verbose    Verbose output
  -o FILE         Output file
"

eval "$(docopts -h "$usage" : "$@")"

# Variables set by docopts:
# $input, $verbose, $output
```

## Best Practices

1. **Validate early** — Check all required args before doing work
2. **Provide --help** — Every script should have help text
3. **Support --** — To separate flags from args: `script.sh -- -file-with-dash`
4. **Meaningful defaults** — Sensible defaults reduce CLI verbosity
5. **Error messages** — Tell user exactly what's wrong and how to fix it
6. **Be consistent** — If you use `-v` for verbose, don't use `-v` for version elsewhere
7. **Document in usage()** — Usage text is your API documentation

## Resources

- Bash manual on parameter expansion: `man bash`
- getopts tutorial: https://wiki.bash-hackers.org/howto/getopts_tutorial
- argbash generator: https://argbash.io/
- docopt: http://docopt.org/
