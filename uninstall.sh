#!/bin/bash
# Removes claude-dictation. Leaves tmux, jq, Hammerspoon and Claude Code installed.
set -uo pipefail

hsdir="$HOME/.hammerspoon"

tmux -L claude-dictation kill-server 2>/dev/null
[[ -f "$hsdir/init.lua" ]] && sed -i '' '/require("claude_dictation")/d' "$hsdir/init.lua"
rm -f "$hsdir/claude_dictation.lua"
rm -rf "$HOME/.claude-dictation"

if pgrep -x Hammerspoon >/dev/null; then
  osascript -e 'quit app "Hammerspoon"' >/dev/null 2>&1
  sleep 1.5
  open -g -a Hammerspoon
fi
echo "claude-dictation removed. tmux, jq, Hammerspoon and Claude Code were left installed."
