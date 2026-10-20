# shell-scripting Skill

Expert shell scripting guidance for bash, zsh, and POSIX sh.

## What This Skill Covers

- **Safety patterns** — `set -euo pipefail`, quoting, error handling, traps
- **Argument parsing** — getopts, long options, subcommands
- **zsh specifics** — Scripting differences, .zshrc configuration, prompts, completions
- **Testing** — ShellCheck, bats, debugging techniques
- **Operational patterns** — Cron, daemons, systemd, logging, monitoring
- **POSIX portability** — Writing scripts that work on Alpine, BusyBox, minimal containers

## Skill Structure

```
shell-scripting/
├── SKILL.md                          # Main entry point — core patterns, quick start
├── README.md                         # This file
└── references/
    ├── bash.md                       # Bash-specific features (arrays, string manipulation)
    ├── zsh.md                        # zsh deep-dive (scripting + interactive)
    ├── posix-sh.md                   # POSIX portable scripting
    ├── safety-patterns.md            # Advanced error handling, security
    ├── argument-parsing.md           # Complex CLI argument patterns
    ├── testing.md                    # ShellCheck, bats, debugging
    └── operational.md                # Cron, daemons, systemd, monitoring
```

## When This Skill Triggers

The skill is automatically used when:
- Writing `.sh` files
- User asks about bash/zsh/shell scripting
- User mentions shell safety, quoting, or error handling
- User asks about .zshrc configuration
- User mentions cron, systemd, or daemon scripts

## Philosophy

**Scripts should fail loudly and early.** This skill teaches Claude to write scripts that:
- Exit immediately on errors (`set -e`)
- Quote religiously to handle spaces
- Validate inputs before destructive operations
- Clean up with traps even when interrupted
- Pass ShellCheck without warnings

## Installation

### Via Skills CLI (Recommended)

The easiest way to install using the [open agent skills ecosystem](https://skills.sh/):

```bash
# Install to Claude Code
npx skills add Abhijit-without-h/Shell-Scripting-skill

# Install to specific agents
npx skills add Abhijit-without-h/Shell-Scripting-skill -a claude-code

# List what would be installed first
npx skills add Abhijit-without-h/Shell-Scripting-skill --list

# Non-interactive installation
npx skills add Abhijit-without-h/Shell-Scripting-skill -y
```

### Via Claude Code Plugin System

```bash
# Using Claude Code CLI
claude plugin install Abhijit-without-h/Shell-Scripting-skill
```

### Manual Installation

```bash
# Clone directly to skills directory
git clone https://github.com/Abhijit-without-h/Shell-Scripting-skill.git \
  ~/.claude/skills/shell-scripting
```

### Validation

After installation, validate the skill structure:

```bash
cd ~/.claude/skills/shell-scripting
npm run validate
```

## Usage Examples

### Quick Safety Header
```bash
#!/usr/bin/env bash
set -euo pipefail

die() { echo "ERROR: $*" >&2; exit 1; }
```

### Cron-Safe Script
```bash
#!/usr/bin/env bash
set -euo pipefail
PATH=/usr/local/bin:/usr/bin:/bin
exec >> /var/log/script.log 2>&1
echo "[$(date -Iseconds)] Starting..."
```

### Complex Argument Parsing
See `references/argument-parsing.md` for full patterns.

### zsh Configuration
See `references/zsh.md` for .zshrc patterns, prompts, completions.

## Key Patterns

| Pattern | Code |
|---------|------|
| Safety header | `set -euo pipefail` |
| Die function | `die() { echo "ERROR: $*" >&2; exit 1; }` |
| Always quote | `"$var"` not `$var` |
| Check command exists | `command -v python` |
| Cleanup trap | `trap 'rm -f "$TMP"' EXIT` |
| Safe deletion | `rm -rf "${DIR:?}"` |
| Temp file | `TMP=$(mktemp)` |
| Lock file | `flock -n 200 \|\| die "locked"` |

## Testing

All scripts should:
1. Pass ShellCheck: `shellcheck script.sh`
2. Have tests for critical logic (bats)
3. Be tested in target environment (Alpine for POSIX sh)

## Resources

- Main guide: `SKILL.md`
- Reference files: `references/*.md`
- ShellCheck: https://www.shellcheck.net/
- bats: https://bats-core.readthedocs.io/

## Contributing

To improve this skill:
1. Test patterns in real scripts
2. Update reference files with new patterns
3. Keep examples practical and production-focused
4. Maintain strong opinions on safety
