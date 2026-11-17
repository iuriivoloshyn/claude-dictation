#!/bin/bash
# Installs claude-dictation: hold F5 anywhere on the Mac, speak, release, and the text is pasted at the cursor.
# Safe to run again (updates the files, keeps your ~/.claude-dictation/settings.json).
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
dest="$HOME/.claude-dictation"
hsdir="$HOME/.hammerspoon"
line='ClaudeDictation = require("claude_dictation")  -- hold F5 to dictate (claude-dictation)'

info() { printf '\033[1m==> %s\033[0m\n' "$*"; }
warn() { printf '\033[33mWarning:\033[0m %s\n' "$*"; }
die()  { printf '\033[31mError:\033[0m %s\n' "$*" >&2; exit 1; }

[[ "$(uname)" == Darwin ]] || die "macOS only."
command -v brew >/dev/null || die "Homebrew is required. Install it from https://brew.sh and run this again."
command -v claude >/dev/null || die "Claude Code is not installed. Install it (https://code.claude.com/docs/en/setup), run 'claude' once, log in with your Claude account, then run this again."

for tool in tmux jq; do
  command -v "$tool" >/dev/null || { info "Installing $tool"; brew install "$tool"; }
done
if [[ ! -d /Applications/Hammerspoon.app && ! -d "$HOME/Applications/Hammerspoon.app" ]]; then
  info "Installing Hammerspoon"; brew install --cask hammerspoon
fi

# Voice dictation only works with a Claude subscription login (not an API key).
auth="$(claude auth status 2>/dev/null | jq -r '.authMethod // empty' 2>/dev/null || true)"
[[ "$auth" == "claude.ai" ]] || warn "Claude Code is not logged in with a Claude subscription (got: '${auth:-none}'). Run 'claude', then /login, and choose your Claude account. Dictation will not work until then."

info "Installing files to $dest and $hsdir"
mkdir -p "$dest" "$hsdir"
install -m 755 "$here/src/capture.sh" "$dest/capture.sh"
if [[ -f "$dest/settings.json" ]]; then
  info "Keeping your existing $dest/settings.json"
else
  install -m 644 "$here/src/settings.json" "$dest/settings.json"
fi
install -m 644 "$here/src/claude_dictation.lua" "$hsdir/claude_dictation.lua"
touch "$hsdir/init.lua"
grep -q 'require("claude_dictation")' "$hsdir/init.lua" || printf '\n%s\n' "$line" >> "$hsdir/init.lua"

# Stop an old hidden session so the new files are used, then (re)start Hammerspoon.
tmux -L claude-dictation kill-server 2>/dev/null || true
if pgrep -x Hammerspoon >/dev/null; then
  osascript -e 'quit app "Hammerspoon"' >/dev/null 2>&1 || true
  sleep 1.5
fi
open -g -a Hammerspoon

cat <<'EOF'

Installed. Two one-time permissions, then it is ready:
  1. Accessibility: System Settings > Privacy & Security > Accessibility > turn on Hammerspoon.
     Then click the Hammerspoon menu-bar icon > Reload Config.
  2. Microphone: the first time you hold F5, macOS asks to let Hammerspoon use the microphone. Click Allow,
     then try again.

Use: put the cursor anywhere, hold F5, speak, release. See README.md for settings and troubleshooting.
EOF
