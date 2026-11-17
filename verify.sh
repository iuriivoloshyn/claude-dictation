#!/bin/bash
# Self-test of claude-dictation. Checks the install, then dictates a test phrase through the hidden Claude Code
# exactly the way F5 does (but pastes nothing).
#   ./verify.sh          plays a short spoken phrase on the speakers (audible!) and checks the transcript
#   ./verify.sh --speak  records 6 s of whatever the user says instead (headphones on, or speakers muted)
# Exit 0 = PASS. On FAIL it says why and prints the last lines of the hidden session.
set -uo pipefail

D="$HOME/.claude-dictation"
mode="${1:-}"
t()    { tmux -L claude-dictation "$@"; }
pane() { t capture-pane -p -t dictation 2>/dev/null; }
ok()   { echo "ok:   $*"; }
fail() {
  echo "FAIL: $*"
  echo "--- hidden session, last lines:"; pane | grep -v '^[[:space:]]*$' | tail -12
  exit 1
}

command -v tmux >/dev/null || fail "tmux is not installed. Run ./install.sh"
[[ -f "$D/settings.json" && -x "$D/capture.sh" ]] || fail "files missing in $D. Run ./install.sh"
grep -q 'require("claude_dictation")' "$HOME/.hammerspoon/init.lua" 2>/dev/null \
  || fail "~/.hammerspoon/init.lua does not load claude_dictation. Run ./install.sh"
pgrep -x Hammerspoon >/dev/null || fail "Hammerspoon is not running. Start it: open -a Hammerspoon"
ok "files installed, Hammerspoon running"

[[ -f "$D/status" ]] || fail "no $D/status, so the Hammerspoon module did not load. Ask the user to open the Hammerspoon console (menu-bar icon > Console) and read you the errors."
grep -q '^accessibility=true' "$D/status" || fail "Hammerspoon has no Accessibility permission, so it cannot see F5 or paste. The user must turn it on: System Settings > Privacy & Security > Accessibility > Hammerspoon. Then wait a minute (or Hammerspoon menu > Reload Config) and run this again."
ok "Accessibility granted ($(grep -E '^(updated|f5_listener)=' "$D/status" | tr '\n' ' '))"

for _ in $(seq 1 60); do
  p="$(pane)"; grep -q '^❯' <<<"$p" && ! grep -q 'Accessing workspace' <<<"$p" && break; sleep 0.5
done
grep -q '^❯' <<<"$p" || fail "the hidden Claude Code is not ready. Hammerspoon starts it within a minute; run this again. If it persists, look at the session text below."
ok "hidden Claude Code is ready"

rm -f "$D/out.txt"
t send-keys -t dictation C-u; sleep 0.4
t send-keys -t dictation Space   # = F5 down
for _ in $(seq 1 20); do pane | grep -q 'REC' && break; sleep 0.1; done
pane | grep -q 'REC' || fail "recording did not start. See the session text below: 'Microphone access is denied' means the user must allow the microphone for Hammerspoon (System Settings > Privacy & Security > Microphone); 'requires a Claude.ai account' means the user must log in to Claude Code with a subscription account."
ok "recording started"

if [[ "$mode" == "--speak" ]]; then
  echo ">>> Speak now, 6 seconds…"; sleep 6
else
  tmp="$(mktemp -d)"
  say -r 190 -o "$tmp/phrase.aiff" "one two three four five six" && afplay "$tmp/phrase.aiff"
  rm -rf "$tmp"; sleep 0.6
fi
t send-keys -t dictation Space   # = F5 up

for _ in $(seq 1 30); do [[ -f "$D/out.txt" ]] && break; sleep 0.3; done
if [[ ! -f "$D/out.txt" ]]; then   # under 3 words is inserted but not submitted; F5's code presses Enter too
  t send-keys -t dictation Enter
  for _ in $(seq 1 15); do [[ -f "$D/out.txt" ]] && break; sleep 0.3; done
fi
if [[ ! -f "$D/out.txt" ]]; then
  t send-keys -t dictation Escape
  fail "no transcript. The microphone heard nothing: speakers muted or headphones on? Try ./verify.sh --speak"
fi
text="$(cat "$D/out.txt")"; rm -f "$D/out.txt"
sleep 0.3; t send-keys -t dictation C-u   # the blocked prompt is put back in the input; clear it
echo "transcript: $text"

if [[ "$mode" != "--speak" ]]; then
  n="$(tr -c '[:alnum:]' '\n' <<<"$text" | grep -ciE '^(1|2|3|4|5|6|one|two|three|four|five|six)$')"
  (( n >= 5 )) || fail "transcript is incomplete, expected 'one … six'. Is the volume very low?"
fi
echo "PASS: dictation works. Last check needs the user: put the cursor in any text field, hold F5, speak, release."
