# bash Deep Dive

Advanced bash features, arrays, string manipulation, and patterns.

## bash-Specific Features

These features work in bash but NOT in POSIX sh.

### Arrays

```bash
# Declare array
declare -a files
files=(a.txt b.txt c.txt)

# Another way
files=("file 1.txt" "file 2.txt")

# Access elements (0-indexed)
echo "${files[0]}"  # a.txt
echo "${files[1]}"  # b.txt

# All elements
echo "${files[@]}"   # a.txt b.txt c.txt
echo "${files[*]}"   # Same, but joins with IFS

# Array length
echo "${#files[@]}"  # 3

# Iterate
for file in "${files[@]}"; do
  echo "$file"
done

# Append
files+=(d.txt)

# Slice (start:length)
echo "${files[@]:1:2}"  # Elements 1-2
```

### Associative Arrays (Hash Maps)

```bash
# Declare (bash 4+)
declare -A config
config[host]="localhost"
config[port]="3306"
config[user]="admin"

# Access
echo "${config[host]}"  # localhost

# All keys
echo "${!config[@]}"    # host port user

# All values
echo "${config[@]}"     # localhost 3306 admin

# Iterate
for key in "${!config[@]}"; do
  echo "$key = ${config[$key]}"
done

# Check if key exists
if [[ -v config[host] ]]; then
  echo "host is set"
fi
```

### String Manipulation

```bash
string="Hello, World!"

# Length
echo "${#string}"  # 13

# Substring (offset:length)
echo "${string:0:5}"   # Hello
echo "${string:7}"     # World!

# Remove prefix (shortest match)
file="path/to/file.txt"
echo "${file#*/}"      # to/file.txt

# Remove prefix (longest match)
echo "${file##*/}"     # file.txt (basename)

# Remove suffix (shortest match)
echo "${file%.*}"      # path/to/file

# Remove suffix (longest match)
echo "${file%%/*}"     # path

# Replace first occurrence
echo "${string/World/Universe}"  # Hello, Universe!

# Replace all occurrences
string="foo bar foo"
echo "${string//foo/baz}"  # baz bar baz

# Uppercase/lowercase (bash 4+)
echo "${string^^}"  # HELLO, WORLD!
echo "${string,,}"  # hello, world!

# Capitalize first letter (bash 4+)
echo "${string^}"   # Hello, world!
```

### Pattern Matching

```bash
# Case statement with patterns
case "$filename" in
  *.txt)
    echo "Text file"
    ;;
  *.jpg|*.png|*.gif)
    echo "Image file"
    ;;
  *)
    echo "Unknown type"
    ;;
esac

# Pattern matching in conditionals
if [[ "$string" == Hello* ]]; then
  echo "Starts with Hello"
fi

if [[ "$string" =~ ^[0-9]+$ ]]; then
  echo "Is a number"
fi
```

### Default Values

```bash
# ${var:-default} — Use default if unset or empty
echo "${USER:-anonymous}"

# ${var:=default} — Assign default if unset or empty
: "${CONFIG_DIR:=/etc/myapp}"

# ${var:?error message} — Exit with error if unset or empty
rm -rf "${DIR:?DIR must be set}"

# ${var:+value} — Use value if var is set
echo "User is ${USER:+logged in}"
```

### Command Substitution

```bash
# Modern syntax (preferred)
now=$(date +%s)
files=$(ls *.txt)

# Old syntax (avoid)
now=`date +%s`
```

### Process Substitution

```bash
# Compare output of two commands
diff <(ls dir1) <(ls dir2)

# Multiple inputs
paste <(seq 1 5) <(seq 6 10)

# Output to process
tar czf >(ssh user@host 'cat > backup.tar.gz') directory/
```

### Here Documents

```bash
# Basic heredoc
cat <<EOF
This is a multi-line
string with $variables expanded
EOF

# Quoted heredoc (no expansion)
cat <<'EOF'
This is literal $variable text
EOF

# Indented heredoc (bash 4+)
cat <<-EOF
	This text can be indented
	with tabs for readability
EOF

# Here string
grep pattern <<<"$variable"
```

### Arithmetic

```bash
# Arithmetic expansion
result=$((5 + 3))
result=$((result * 2))

# Operators
$((a + b))   # Addition
$((a - b))   # Subtraction
$((a * b))   # Multiplication
$((a / b))   # Division (integer)
$((a % b))   # Modulo
$((a ** b))  # Exponentiation

# Comparison (returns 0 or 1)
$((a == b))
$((a != b))
$((a < b))
$((a <= b))
$((a > b))
$((a >= b))

# Logical
$((a && b))  # AND
$((a || b))  # OR
$((! a))     # NOT

# Bitwise
$((a & b))   # AND
$((a | b))   # OR
$((a ^ b))   # XOR
$((a << 2))  # Left shift
$((a >> 2))  # Right shift

# Increment/decrement
$((i++))     # Post-increment
$((++i))     # Pre-increment
$((i--))     # Post-decrement
$((--i))     # Pre-decrement

# Assignment operators
$((a += 5))
$((a -= 5))
$((a *= 5))
$((a /= 5))
```

### Conditional Expressions [[ ]]

```bash
# [[ ]] is more powerful than [ ]
# No word splitting, no pathname expansion

# String comparisons
[[ "$a" == "$b" ]]     # Equal
[[ "$a" != "$b" ]]     # Not equal
[[ "$a" < "$b" ]]      # Less than (lexicographic)
[[ "$a" > "$b" ]]      # Greater than
[[ -z "$a" ]]          # Empty string
[[ -n "$a" ]]          # Non-empty string

# Pattern matching
[[ "$string" == Hello* ]]        # Glob
[[ "$string" =~ ^[0-9]+$ ]]      # Regex

# File tests
[[ -e "$file" ]]       # Exists
[[ -f "$file" ]]       # Regular file
[[ -d "$dir" ]]        # Directory
[[ -L "$link" ]]       # Symbolic link
[[ -r "$file" ]]       # Readable
[[ -w "$file" ]]       # Writable
[[ -x "$file" ]]       # Executable
[[ -s "$file" ]]       # Non-empty
[[ "$f1" -nt "$f2" ]]  # f1 newer than f2
[[ "$f1" -ot "$f2" ]]  # f1 older than f2

# Logical
[[ cond1 && cond2 ]]   # AND
[[ cond1 || cond2 ]]   # OR
[[ ! cond ]]           # NOT
```

## Advanced Patterns

### Check Command Success

```bash
# Best: use command directly in if
if command; then
  echo "Success"
else
  echo "Failed"
fi

# Negate
if ! command; then
  echo "Command failed"
fi

# Chain commands
if cmd1 && cmd2 && cmd3; then
  echo "All succeeded"
fi

# Short-circuit operators
command && echo "Success" || echo "Failed"
```

### Read Files Line by Line

```bash
# Read file
while IFS= read -r line; do
  echo "$line"
done < file.txt

# Read command output
while IFS= read -r line; do
  echo "$line"
done < <(command)

# Read with delimiter
while IFS=: read -r user pass uid gid gecos home shell; do
  echo "User: $user, Home: $home"
done < /etc/passwd
```

### Iterate Over Command Output

```bash
# BAD — word splitting breaks on spaces
for file in $(ls); do
  echo "$file"
done

# GOOD — use glob
for file in *; do
  [[ -f "$file" ]] || continue
  echo "$file"
done

# GOOD — use find with -print0
while IFS= read -r -d '' file; do
  echo "$file"
done < <(find . -name "*.txt" -print0)

# GOOD — use array
mapfile -t files < <(find . -name "*.txt")
for file in "${files[@]}"; do
  echo "$file"
done
```

### Parallel Execution

```bash
# Background jobs
command1 &
command2 &
command3 &
wait  # Wait for all background jobs

# Capture PIDs
command1 &
pid1=$!
command2 &
pid2=$!

# Wait for specific job
wait $pid1

# Limit concurrent jobs
MAX_JOBS=4
for file in *.txt; do
  process_file "$file" &
  
  # Limit parallelism
  while [[ $(jobs -r | wc -l) -ge $MAX_JOBS ]]; do
    sleep 0.1
  done
done
wait
```

### Debugging

```bash
# Print each command before execution
set -x

# Turn off debugging
set +x

# Debug specific section
set -x
complex_function
set +x

# Trace to file
exec 5> debug.log
BASH_XTRACEFD=5
set -x
```

### Strict Mode

```bash
#!/usr/bin/env bash

# Unofficial bash strict mode
set -euo pipefail
IFS=$'\n\t'

# Explanation:
# set -e  → Exit on error
# set -u  → Exit on undefined variable
# set -o pipefail → Exit on pipe failure
# IFS=$'\n\t' → Only split on newline and tab (not space)
```

### Subshells vs Current Shell

```bash
# Subshell (changes don't affect parent)
(cd /tmp; echo "In /tmp: $(pwd)")
echo "Still in: $(pwd)"

# Current shell (changes persist)
cd /tmp
echo "Now in: $(pwd)"

# Variables in subshells
VAR=1
(VAR=2; echo "$VAR")  # 2
echo "$VAR"           # 1

# Source vs execute
source script.sh  # Runs in current shell
./script.sh       # Runs in subshell
```

## Performance Tips

### Avoid External Commands

```bash
# BAD — spawns external process
length=$(echo -n "$string" | wc -c)

# GOOD — pure bash
length=${#string}

# BAD
basename=$(basename "$path")
dirname=$(dirname "$path")

# GOOD
basename="${path##*/}"
dirname="${path%/*}"
```

### Use Built-in Tests

```bash
# [ ] spawns external test command (on some systems)
if [ -f "$file" ]; then

# [[ ]] is bash built-in (faster)
if [[ -f "$file" ]]; then
```

### Avoid Subshells in Loops

```bash
# BAD — creates subshell every iteration
cat file.txt | while read line; do
  sum=$((sum + 1))  # Won't work — subshell
done
echo $sum  # Still 0

# GOOD — no subshell
while read line; do
  sum=$((sum + 1))
done < file.txt
echo $sum  # Works
```

## bash Version Detection

```bash
# Check bash version
if [[ ${BASH_VERSINFO[0]} -lt 4 ]]; then
  echo "bash 4+ required"
  exit 1
fi

# Feature detection
if [[ -v BASH_VERSINFO ]]; then
  echo "Running bash"
fi
```

## Resources

- Bash manual: `man bash`
- Advanced Bash-Scripting Guide: https://tldp.org/LDP/abs/html/
- Bash Guide: https://mywiki.wooledge.org/BashGuide
- Bash Pitfalls: https://mywiki.wooledge.org/BashPitfalls
- ShellCheck: https://www.shellcheck.net/
