# zsh Deep Dive

Everything zsh — scripting differences, interactive configuration, prompts, completions, and plugins.

## zsh vs bash — Key Scripting Differences

### 1. Array Indexing

```bash
# bash: 0-indexed
array=(one two three)
echo "${array[0]}"  # one
echo "${array[1]}"  # two

# zsh: 1-indexed (by default)
array=(one two three)
echo "${array[1]}"  # one
echo "${array[2]}"  # two

# zsh: force 0-indexing (bash compatibility)
setopt KSH_ARRAYS
```

### 2. Word Splitting

```bash
# bash: word splitting by default
files="a.txt b.txt"
ls $files  # expands to: ls a.txt b.txt

# zsh: NO word splitting by default (safer!)
files="a.txt b.txt"
ls $files  # tries to ls "a.txt b.txt" (one file with space)
ls ${=files}  # force word splitting with ${=var}

# zsh: enable bash-like word splitting
setopt SH_WORD_SPLIT
```

### 3. Glob Behavior

```bash
# bash: unmatched globs stay literal
ls *.nonexistent  # passes "*.nonexistent" to ls, ls errors

# zsh: unmatched globs are an error
ls *.nonexistent  # zsh: no matches found

# zsh: make globs optional (bash-like)
setopt NULL_GLOB  # unmatched globs expand to nothing
setopt NO_NOMATCH  # unmatched globs stay literal (bash behavior)
```

### 4. Option Syntax

```bash
# bash
set -e
set +e
shopt -s nullglob
shopt -u nullglob

# zsh (bash compatibility)
set -e
set +e

# zsh (native)
setopt ERR_EXIT
unsetopt ERR_EXIT
setopt NULL_GLOB
unsetopt NULL_GLOB
```

### 5. Test Operators

```bash
# bash: [[ ]] is bashism
if [[ -f "$file" ]]; then

# zsh: [[ ]] works, but also has special glob matching
if [[ "$string" == pattern* ]]; then  # glob matching
if [[ "$string" =~ regex ]]; then     # regex matching
```

## Interactive zsh Configuration

### .zshrc vs .zprofile vs .zshenv vs .zlogin

| File | When Loaded | Use For |
|------|-------------|---------|
| `.zshenv` | **Always** (login, non-login, scripts) | `PATH`, `EDITOR`, env vars needed everywhere |
| `.zprofile` | Login shells only | Stuff that should run once at login (like `.bash_profile`) |
| `.zlogin` | Login shells, **after** `.zshrc` | Rare — use `.zprofile` instead |
| `.zshrc` | Interactive shells | Aliases, prompts, completions, keybindings, functions |
| `.zlogout` | On logout | Cleanup tasks |

**Common pattern:**
- `.zshenv` → Set `PATH` and core environment variables
- `.zshrc` → Everything else (aliases, prompt, completions)

### Example .zshenv

```zsh
# ~/.zshenv
# Loaded for ALL zsh instances (interactive, non-interactive, scripts)

# PATH construction
typeset -U path  # Keep only unique entries
path=(
  /usr/local/bin
  /usr/bin
  /bin
  $HOME/.local/bin
  $path
)

# Core environment variables
export EDITOR=vim
export VISUAL=vim
export PAGER=less
export LANG=en_US.UTF-8
```

### Example .zshrc

```zsh
# ~/.zshrc
# Loaded for interactive shells only

# Enable completions
autoload -Uz compinit
compinit

# History settings
HISTFILE=~/.zsh_history
HISTSIZE=10000
SAVEHIST=10000
setopt APPEND_HISTORY       # Append to history file
setopt SHARE_HISTORY        # Share history across sessions
setopt HIST_IGNORE_DUPS     # Don't record duplicates
setopt HIST_IGNORE_SPACE    # Ignore commands starting with space

# Directory navigation
setopt AUTO_CD              # Type directory name to cd
setopt AUTO_PUSHD           # cd pushes to directory stack
setopt PUSHD_IGNORE_DUPS    # Don't push duplicates
setopt PUSHD_SILENT         # Don't print directory stack

# Globbing
setopt EXTENDED_GLOB        # Enable advanced globbing (#, ~, ^)
setopt NULL_GLOB            # Unmatched globs expand to nothing

# Correction
setopt CORRECT              # Suggest corrections for commands
setopt CORRECT_ALL          # Suggest corrections for all arguments

# Aliases
alias ll='ls -lah'
alias la='ls -A'
alias l='ls -CF'
alias ..='cd ..'
alias ...='cd ../..'
alias grep='grep --color=auto'

# Git aliases
alias gs='git status'
alias ga='git add'
alias gc='git commit'
alias gp='git push'
alias gl='git log --oneline --graph --decorate'

# Functions
mkcd() {
  mkdir -p "$1" && cd "$1"
}

# Prompt (simple)
PROMPT='%F{cyan}%~%f %# '
RPROMPT='%F{yellow}%*%f'
```

## Advanced Prompts

### Color Codes

```zsh
# %F{color}...%f wraps colored text
%F{red}text%f
%F{green}text%f
%F{blue}text%f
%F{yellow}text%f
%F{magenta}text%f
%F{cyan}text%f

# Numeric colors (256-color)
%F{196}bright red%f
%F{82}bright green%f
```

### Prompt Sequences

```zsh
%~      # Current directory (with ~ for home)
%/      # Current directory (full path)
%c      # Current directory (basename only)
%n      # Username
%m      # Hostname (short)
%M      # Hostname (full)
%*      # Time (HH:MM:SS)
%T      # Time (HH:MM)
%D      # Date (YY-MM-DD)
%?      # Exit code of last command
%#      # # for root, % for normal user
%(!.#.%) # Same as %#
%(?.✓.✗) # ✓ if last command succeeded, ✗ if failed
```

### Git Branch in Prompt

```zsh
# Load vcs_info for git branch
autoload -Uz vcs_info
precmd() { vcs_info }
setopt PROMPT_SUBST

zstyle ':vcs_info:git:*' formats ' (%b)'
PROMPT='%F{cyan}%~%f%F{yellow}${vcs_info_msg_0_}%f %# '
```

### Two-Line Prompt

```zsh
PROMPT='%F{blue}┌─[%f%F{cyan}%~%f%F{blue}]%f
└─%# '
```

## Completions

### Enable Completions

```zsh
# Basic completion
autoload -Uz compinit
compinit

# Case-insensitive completion
zstyle ':completion:*' matcher-list 'm:{a-z}={A-Z}'

# Menu selection
zstyle ':completion:*' menu select

# Colorful completion
zstyle ':completion:*' list-colors ${(s.:.)LS_COLORS}
```

### Custom Completions

```zsh
# Define completion function
_mycommand() {
  local -a options
  options=(
    '--help:Show help'
    '--verbose:Verbose output'
    '--output:Output file'
  )
  _describe 'option' options
}

# Register completion
compdef _mycommand mycommand
```

### Built-in Completion Helpers

```zsh
_arguments  # Parse complex argument structures
_describe   # Describe options with descriptions
_files      # Complete file paths
_directories # Complete only directories
_values     # Complete from a list of values
```

## Oh My Zsh

Oh My Zsh is a popular zsh configuration framework.

### Install

```bash
sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
```

### .zshrc with Oh My Zsh

```zsh
# Path to oh-my-zsh installation
export ZSH="$HOME/.oh-my-zsh"

# Theme
ZSH_THEME="robbyrussell"

# Plugins
plugins=(
  git
  docker
  kubectl
  zsh-autosuggestions
  zsh-syntax-highlighting
)

source $ZSH/oh-my-zsh.sh

# Your customizations here
```

### Popular Plugins

- `git` — Git aliases and functions
- `docker` — Docker completions
- `kubectl` — Kubernetes completions
- `zsh-autosuggestions` — Fish-like autosuggestions
- `zsh-syntax-highlighting` — Syntax highlighting as you type
- `z` — Jump to frecent directories

## Keybindings

### Emacs-style (default)

```zsh
bindkey -e  # Enable emacs keybindings

# Common bindings
# Ctrl+A — beginning of line
# Ctrl+E — end of line
# Ctrl+K — kill to end of line
# Ctrl+U — kill to beginning of line
# Ctrl+R — reverse history search
# Ctrl+W — kill word backward
```

### Vi-style

```zsh
bindkey -v  # Enable vi keybindings

# ESC to enter normal mode
# i to enter insert mode
# h/j/k/l for navigation
# 0/$ for line start/end
```

### Custom Keybindings

```zsh
# Bind Ctrl+Space to accept autosuggestion
bindkey '^ ' autosuggest-accept

# Bind Up/Down to history substring search
bindkey '^[[A' history-substring-search-up
bindkey '^[[B' history-substring-search-down
```

## Advanced Features

### Parameter Expansion

```zsh
# Modifiers
${var:u}    # Uppercase
${var:l}    # Lowercase
${var:c}    # Capitalize first letter

# Substitution
${var/old/new}   # Replace first occurrence
${var//old/new}  # Replace all occurrences

# Slicing
${var[1,5]}  # Characters 1-5 (1-indexed)

# Length
${#var}  # Length of string
```

### Arithmetic

```zsh
# Integer arithmetic
typeset -i count=0
count+=1
((count++))

# Floating point
typeset -F result
result=$(( 3.14 * 2 ))
```

### Process Substitution

```zsh
# Compare output of two commands
diff <(ls dir1) <(ls dir2)

# Read from process output
while read line; do
  echo "$line"
done < <(some_command)
```

## Debugging zsh Scripts

```zsh
# Print each command before execution
set -x
setopt XTRACE

# Turn off debugging
set +x
unsetopt XTRACE

# Print function definitions
which function_name

# List all defined functions
print -l ${(k)functions}

# List all aliases
alias

# Show where a command comes from
whence -v command
```

## Migration from bash

### bash → zsh Script Compatibility

Add to top of script for maximum bash compatibility:

```zsh
#!/usr/bin/env zsh
emulate -L bash
# Or: emulate -LR zsh (restrict to zsh mode)
```

### bash → zsh Interactive Migration

Update your .zshrc to source .bashrc aliases/functions:

```zsh
# ~/.zshrc
[[ -f ~/.bashrc ]] && source ~/.bashrc
```

## Common zsh Patterns

### Check if Interactive

```zsh
if [[ -o interactive ]]; then
  # Interactive shell stuff
  echo "Welcome!"
fi
```

### Detect zsh vs bash

```zsh
if [[ -n "$ZSH_VERSION" ]]; then
  echo "Running zsh"
elif [[ -n "$BASH_VERSION" ]]; then
  echo "Running bash"
fi
```

### Loop Over Files Safely

```zsh
# zsh: null glob to handle no matches
setopt NULL_GLOB
for file in *.txt; do
  [[ -f "$file" ]] || continue
  echo "$file"
done
```

## Resources

- Official docs: https://zsh.sourceforge.io/Doc/
- Oh My Zsh: https://ohmyz.sh/
- zsh-users plugins: https://github.com/zsh-users/
- Comparison: https://hyperpolyglot.org/unix-shells

---

**Fish shell note:** fish has completely different syntax (no `$`, different `if` syntax, functions replace aliases). It's incompatible with bash/zsh scripts. Deserves its own skill.
