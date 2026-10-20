# Testing Shell Scripts

Testing, debugging, and linting for production-grade shell scripts.

## ShellCheck — The Linter

ShellCheck is **mandatory** for all shell scripts. It catches common bugs and pitfalls.

### Installation

```bash
# macOS
brew install shellcheck

# Ubuntu/Debian
apt install shellcheck

# Arch
pacman -S shellcheck

# Or use Docker
docker run --rm -v "$PWD:/mnt" koalaman/shellcheck script.sh
```

### Basic Usage

```bash
# Check a single script
shellcheck script.sh

# Check all scripts
find . -name "*.sh" -exec shellcheck {} +

# Check with specific shell
shellcheck --shell=bash script.sh
shellcheck --shell=sh script.sh  # POSIX

# Output formats
shellcheck --format=gcc script.sh   # gcc-style
shellcheck --format=json script.sh  # JSON
```

### Inline Directives

```bash
#!/usr/bin/env bash

# Disable specific warning
# shellcheck disable=SC2034
UNUSED_VAR="value"

# Disable for one command
echo "$var"  # shellcheck disable=SC2086

# Multiple codes
# shellcheck disable=SC2034,SC2154
MY_VAR="$EXTERNAL_VAR"

# Source external files (helps ShellCheck find definitions)
# shellcheck source=/path/to/library.sh
source library.sh
```

### Common ShellCheck Warnings

| Code | Issue | Fix |
|------|-------|-----|
| SC2086 | Unquoted variable | `echo "$var"` not `echo $var` |
| SC2046 | Quote command substitution | `for f in $(ls)` → use glob |
| SC2006 | Use `$(...)` not backticks | `` `cmd` `` → `$(cmd)` |
| SC2181 | Check exit code directly | `if command; then` not `if [ $? -eq 0 ]` |
| SC2164 | Use `cd ... \|\| exit` | Catch cd failures |
| SC2155 | Declare and assign separately | `local var; var=$(cmd)` |

### CI Integration

```bash
# .github/workflows/shellcheck.yml
name: ShellCheck
on: [push, pull_request]
jobs:
  shellcheck:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2
      - name: Run ShellCheck
        run: |
          find . -name "*.sh" -print0 | xargs -0 shellcheck
```

## bats — Bash Automated Testing System

bats is a TAP-compliant testing framework for bash.

### Installation

```bash
# macOS
brew install bats-core

# From source
git clone https://github.com/bats-core/bats-core.git
cd bats-core
./install.sh /usr/local

# Or use npm
npm install -g bats
```

### Basic Test Structure

```bash
#!/usr/bin/env bats

# test/backup.bats

# Setup runs before each test
setup() {
  export TEST_DIR="$(mktemp -d)"
}

# Teardown runs after each test
teardown() {
  rm -rf "$TEST_DIR"
}

@test "script exits 0 on success" {
  run ./backup.sh --help
  [ "$status" -eq 0 ]
}

@test "script requires config file" {
  run ./backup.sh
  [ "$status" -ne 0 ]
  [[ "$output" =~ "Config file not found" ]]
}

@test "creates backup directory" {
  run ./backup.sh --output "$TEST_DIR/backup"
  [ "$status" -eq 0 ]
  [ -d "$TEST_DIR/backup" ]
}
```

### Running Tests

```bash
# Run all tests
bats test/

# Run specific test file
bats test/backup.bats

# Verbose output
bats -t test/

# Parallel execution
bats -j 4 test/
```

### bats Assertions

```bash
# Exit code
[ "$status" -eq 0 ]
[ "$status" -ne 0 ]

# Output matching
[[ "$output" =~ "expected string" ]]
[[ "$output" == "exact match" ]]

# Line count
[ "${#lines[@]}" -eq 3 ]

# Specific line
[ "${lines[0]}" = "First line" ]

# File tests
[ -f "$file" ]
[ -d "$dir" ]
[ -x "$script" ]
```

### Helper Libraries

```bash
# test_helper.bash
load_helpers() {
  load '/usr/local/lib/bats-support/load'
  load '/usr/local/lib/bats-assert/load'
}

# test/backup.bats
#!/usr/bin/env bats

load test_helper

@test "example with helpers" {
  run command
  assert_success
  assert_output "expected"
  refute_output "not this"
}
```

### Mocking Commands

```bash
# Create mock in PATH
setup() {
  export PATH="$BATS_TEST_DIRNAME/mocks:$PATH"
}

# mocks/aws
#!/usr/bin/env bash
echo "mock aws output"
exit 0
```

### Testing Private Functions

```bash
# script.sh
backup_database() {
  mysqldump mydb > backup.sql
}

main() {
  backup_database
}

# Only run main if not sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi

# test/script.bats
@test "backup_database creates file" {
  source ./script.sh
  backup_database
  [ -f backup.sql ]
}
```

## Debugging Techniques

### set -x (Xtrace)

```bash
#!/usr/bin/env bash
set -euo pipefail

# Debug entire script
set -x

# Debug specific section
set -x
complex_function
set +x

# Conditional debugging
[[ -n "${DEBUG:-}" ]] && set -x
```

### Custom Trace Output

```bash
# Redirect trace to stderr with prefix
export PS4='+ ${BASH_SOURCE}:${LINENO}: '
set -x

# Redirect trace to file
exec 5> debug.log
BASH_XTRACEFD=5
set -x
```

### Debug Functions

```bash
# Print variable values
debug_vars() {
  echo "DEBUG: var1=$var1, var2=$var2, var3=$var3" >&2
}

# Stack trace
print_stack_trace() {
  local frame=0
  echo "Stack trace:" >&2
  while caller $frame >&2; do
    ((frame++))
  done
}

# Call on error
trap print_stack_trace ERR
```

### Interactive Debugging

```bash
# Add breakpoint
debug_break() {
  echo "=== Breakpoint ===" >&2
  echo "Variables:" >&2
  declare -p >&2
  read -p "Press enter to continue..."
}

# Use in script
complex_calculation
debug_break
more_code
```

## Test-Driven Development

### Example TDD Workflow

```bash
# 1. Write test first
# test/calculator.bats
@test "add function returns sum" {
  source ./calculator.sh
  result=$(add 2 3)
  [ "$result" -eq 5 ]
}

# 2. Run test (fails)
bats test/calculator.bats

# 3. Implement function
# calculator.sh
add() {
  echo $(( $1 + $2 ))
}

# 4. Run test (passes)
bats test/calculator.bats
```

## Integration Testing

### Testing Scripts That Call External Services

```bash
# Use test doubles
setup() {
  # Mock API endpoint
  export API_URL="http://localhost:8080"
  
  # Start mock server in background
  mock_server &
  MOCK_PID=$!
  
  # Wait for server to be ready
  wait_for_server "$API_URL"
}

teardown() {
  kill $MOCK_PID 2>/dev/null || true
}

mock_server() {
  while true; do
    echo -e "HTTP/1.1 200 OK\r\n\r\n{\"status\":\"ok\"}" | nc -l 8080
  done
}

wait_for_server() {
  local url="$1"
  local attempts=0
  while ! curl -sf "$url" >/dev/null; do
    sleep 0.1
    attempts=$((attempts + 1))
    if [[ $attempts -gt 30 ]]; then
      return 1
    fi
  done
}
```

## Coverage Analysis

### Manual Coverage Tracking

```bash
# Track which functions are called
declare -A COVERAGE

trace_function() {
  local func="${FUNCNAME[1]}"
  COVERAGE[$func]=1
}

# Add to functions
backup_database() {
  trace_function
  # ... function body
}

# Report
report_coverage() {
  echo "Functions called:"
  for func in "${!COVERAGE[@]}"; do
    echo "  - $func"
  done
}

trap report_coverage EXIT
```

## Performance Testing

### Timing Scripts

```bash
# Measure script execution time
time ./script.sh

# Detailed timing
/usr/bin/time -v ./script.sh

# In script
start_time=$(date +%s)
do_work
end_time=$(date +%s)
duration=$((end_time - start_time))
echo "Took ${duration}s"
```

### Profiling

```bash
# Profile with bash built-in
set -x
PS4='+ $(date "+%s.%N") ${BASH_SOURCE}:${LINENO}: '
./script.sh 2>&1 | tee profile.log

# Analyze slowest lines
awk '{print $2, $3}' profile.log | sort -n | tail -20
```

## Best Practices

1. **Every script should pass ShellCheck** — No exceptions
2. **Write tests for critical logic** — Especially for data transformations
3. **Test edge cases** — Empty input, missing files, permission errors
4. **Use mocks for external dependencies** — Don't hit real APIs in tests
5. **Test error handling** — Ensure script fails correctly
6. **CI/CD integration** — Run tests on every commit
7. **Measure coverage** — Know what's tested and what's not

## Example Test Suite Structure

```
project/
├── backup.sh
├── lib/
│   ├── database.sh
│   └── storage.sh
├── test/
│   ├── backup.bats
│   ├── database.bats
│   ├── storage.bats
│   └── test_helper.bash
└── .github/
    └── workflows/
        └── test.yml
```

## Resources

- ShellCheck wiki: https://github.com/koalaman/shellcheck/wiki
- bats documentation: https://bats-core.readthedocs.io/
- bats-assert: https://github.com/bats-core/bats-assert
- bats-support: https://github.com/bats-core/bats-support
