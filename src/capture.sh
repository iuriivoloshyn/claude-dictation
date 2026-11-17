#!/bin/bash
# UserPromptSubmit hook of the hidden dictation session (see settings.json).
# Saves the dictated prompt for Hammerspoon to paste, then blocks it so nothing is sent to the model.
# Always exits 2: exit 2 blocks the prompt even if saving failed.
dir="$(cd "$(dirname "$0")" && pwd)"
jq -r '.prompt // empty' > "$dir/out.tmp" 2>/dev/null && mv -f "$dir/out.tmp" "$dir/out.txt"
echo "dictation captured" >&2
exit 2
