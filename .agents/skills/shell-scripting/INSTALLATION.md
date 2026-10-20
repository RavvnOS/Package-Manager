# Installation Guide

Complete installation guide for the Shell Scripting Expert skill.

## Quick Start

```bash
npx skills add Abhijit-without-h/Shell-Scripting-skill
```

## Installation Methods

### 1. Skills CLI (Recommended)

The [Skills CLI](https://skills.sh/) is the package manager for the open agent skills ecosystem.

#### Basic Installation

```bash
# Install for Claude Code (auto-detected)
npx skills add Abhijit-without-h/Shell-Scripting-skill

# Preview what will be installed
npx skills add Abhijit-without-h/Shell-Scripting-skill --list

# Non-interactive mode (for CI/CD)
npx skills add Abhijit-without-h/Shell-Scripting-skill -y
```

#### Advanced Options

```bash
# Install to specific agents
npx skills add Abhijit-without-h/Shell-Scripting-skill -a claude-code -a cursor

# Install globally (user directory)
npx skills add Abhijit-without-h/Shell-Scripting-skill -g

# Copy files instead of symlinking
npx skills add Abhijit-without-h/Shell-Scripting-skill --copy

# Install to all detected agents
npx skills add Abhijit-without-h/Shell-Scripting-skill --agent '*'
```

#### Supported Agents

The Skills CLI supports:
- Claude Code
- Cursor
- Codex
- OpenCode
- Continue
- Windsurf
- Roo
- And [40+ more agents](https://skills.sh/)

### 2. Claude Code Plugin System

```bash
# Using claude command
claude plugin install Abhijit-without-h/Shell-Scripting-skill
```

### 3. Direct Git Clone

```bash
# For Claude Code
git clone https://github.com/Abhijit-without-h/Shell-Scripting-skill.git \
  ~/.claude/skills/shell-scripting

# For Cursor
git clone https://github.com/Abhijit-without-h/Shell-Scripting-skill.git \
  ~/.cursor/skills/shell-scripting
```

### 4. Download & Extract

1. Download the latest release from [GitHub Releases](https://github.com/Abhijit-without-h/Shell-Scripting-skill/releases)
2. Extract to your agent's skills directory:
   - Claude Code: `~/.claude/skills/shell-scripting/`
   - Cursor: `~/.cursor/skills/shell-scripting/`

## Verification

After installation, verify the skill is working:

```bash
# Validate structure
cd ~/.claude/skills/shell-scripting
npm run validate

# Check if skill is loaded (in Claude Code)
# The skill should appear in available skills list
```

Expected output:
```
✅ All validation checks passed!
```

## Updating

### Using Skills CLI

```bash
# Check for updates
npx skills check

# Update all skills
npx skills update

# Update specific skill
npx skills update Abhijit-without-h/Shell-Scripting-skill
```

### Manual Update

```bash
cd ~/.claude/skills/shell-scripting
git pull origin main
npm run validate
```

## Uninstallation

### Using Skills CLI

```bash
npx skills remove shell-scripting
```

### Manual Removal

```bash
rm -rf ~/.claude/skills/shell-scripting
```

## Troubleshooting

### Skill Not Appearing

1. **Restart your agent** — Most agents require a restart to load new skills
2. **Check installation path** — Ensure the skill is in the correct directory
3. **Validate structure** — Run `npm run validate` in the skill directory

### Validation Fails

```bash
cd ~/.claude/skills/shell-scripting
npm run validate
```

If validation fails, reinstall:
```bash
rm -rf ~/.claude/skills/shell-scripting
npx skills add Abhijit-without-h/Shell-Scripting-skill
```

### Permission Issues

If you get permission errors:

```bash
# Fix ownership
sudo chown -R $USER ~/.claude/skills/

# Or install globally
npx skills add Abhijit-without-h/Shell-Scripting-skill -g
```

## CI/CD Integration

For automated deployments:

```bash
# Non-interactive installation
npx skills add Abhijit-without-h/Shell-Scripting-skill -y -g

# In GitHub Actions
- name: Install Shell Scripting Skill
  run: |
    npx skills add Abhijit-without-h/Shell-Scripting-skill -y -a claude-code
```

## Platform-Specific Notes

### macOS

```bash
# Default Claude Code path
~/.claude/skills/shell-scripting
```

### Linux

```bash
# Default Claude Code path
~/.claude/skills/shell-scripting
```

### Windows

```powershell
# Default Claude Code path
%USERPROFILE%\.claude\skills\shell-scripting
```

## Getting Help

- **Issues**: https://github.com/Abhijit-without-h/Shell-Scripting-skill/issues
- **Skills CLI Docs**: https://skills.sh/
- **Claude Code Docs**: https://claude.ai/code

## Next Steps

After installation:
1. ✅ Restart your AI agent
2. ✅ Test the skill by asking about shell scripting
3. ✅ Read the [README](./README.md) for usage examples
4. ✅ Explore [reference guides](./references/) for advanced topics
