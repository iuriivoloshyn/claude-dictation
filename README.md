# claude-dictation

Hold **F5** anywhere on a Mac, speak, release, and the text is pasted at the cursor in any app. Speech-to-text is **Claude Code's own voice dictation**, so a Claude subscription is all it needs. There's no extra service or API key, and transcription doesn't use Claude usage.

> **This README is written for a coding agent (e.g. Claude Code) that installs, checks or repairs this on its user's Mac.**
> If you're a person, open Claude Code in this folder and say: *"Install this for me following the README."*
>
> Unofficial and not affiliated with Anthropic. It drives the regular, unmodified `claude` CLI under the user's own login.

## How it works (read this before debugging)

```
F5 down ─► Hammerspoon module ─► tmux send-keys Space ─► hidden `claude` starts recording   (/voice tap mode, tap 1)
F5 up   ─► Hammerspoon module ─► tmux send-keys Space ─► `claude` stops, transcribes, submits (tap 2)
                                     UserPromptSubmit hook capture.sh: writes out.txt, exits 2 → prompt BLOCKED
         Hammerspoon module  ◄── reads ~/.claude-dictation/out.txt ─► pasteboard + Cmd+V into the app that had focus
```

- **Hidden session**: `tmux -L claude-dictation`, session `dictation`, working folder `~/.claude-dictation`. It runs `claude --settings ~/.claude-dictation/settings.json --strict-mcp-config --setting-sources local`, so the user's global hooks, plugins and MCP servers are not loaded. Settings give tap-mode voice, the capture hook, Haiku, no Remote Control and ask-before-tools permissions.
- **Always warm**: Hammerspoon starts the session at load (login), restarts it within 60 s if it dies, and refreshes it daily at 05:00. A cold start takes about 1 s, and speech during it is lost. The session uses about 280 MB of RAM; tell the user.
- **Short transcripts**: Claude Code auto-submits only 3+ words. For shorter ones the module presses Enter once the screen settles.
- **Blocked prompt**: after the hook blocks it, Claude Code puts the text back into its input, so the module clears it with Ctrl+U. Recording can only start from an empty input.
- **First start** in `~/.claude-dictation` shows "Do you trust this folder?". The module answers Yes on its own, and presses Enter only when "Yes" is highlighted.
- **Status file** `~/.claude-dictation/status` is rewritten every minute: `accessibility`, `f5_listener`, `claude` and `tmux` paths, `session_running`.

## 1. Preflight

Run these and handle each result before installing:

| Check | Command | Needed | If not |
|---|---|---|---|
| macOS | `uname` | `Darwin` | Not supported. Stop. |
| Homebrew | `command -v brew` | a path | Ask the user to install it from https://brew.sh (needs their password). |
| Claude Code | `claude --version` | a version with `/voice` | Install it (https://code.claude.com/docs/en/setup), or `claude update`. |
| Subscription login | `claude auth status` | `"authMethod": "claude.ai"` | Voice dictation doesn't work with API-key, Bedrock, Vertex or Foundry auth. The **user** must run `claude`, then `/login`, and pick their Claude account. It's interactive, so don't do it for them. |
| Existing Hammerspoon config | `grep -nE 'f5\|F5\|176' ~/.hammerspoon/init.lua` | nothing | Another binding on F5 would clash. Show it to the user and ask which one should win. |

Ask the user only if it isn't obvious: **dictation language** (default English; see Configure) and whether **F5** is fine as the key.

## 2. Install

```bash
gh repo clone iuriivoloshyn/claude-dictation && cd claude-dictation   # or git clone https://github.com/iuriivoloshyn/claude-dictation.git
./install.sh
```

`install.sh` is idempotent and non-interactive. It does the following:
- installs `tmux`, `jq` and the Hammerspoon cask if they're missing
- warns if the login isn't `claude.ai`
- copies `src/capture.sh` and `src/settings.json` to `~/.claude-dictation/` (an existing `settings.json` is kept)
- copies `src/claude_dictation.lua` to `~/.hammerspoon/`
- appends one line to `~/.hammerspoon/init.lua`: `ClaudeDictation = require("claude_dictation")`
- kills an old hidden session and restarts Hammerspoon

The module also turns on Hammerspoon's "launch at login".

## 3. Permissions (only the user can grant these)

1. **Accessibility for Hammerspoon**, which lets it see F5 and paste. Tell the user: *System Settings → Privacy & Security → Accessibility → turn on Hammerspoon.* You can open that pane for them: `open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"`. Confirm with `grep accessibility ~/.claude-dictation/status`; it updates within a minute.
2. **Microphone for Hammerspoon.** macOS asks the first time something records. Run `./verify.sh` (below) to trigger it, ask the user to click **Allow**, then run `./verify.sh` again.

## 4. Verify

```bash
./verify.sh          # plays "one two three four five six" out loud; warn the user first
./verify.sh --speak  # if the user has headphones on: they speak for 6 s instead
```

It checks the install, permissions and the hidden session, then drives a real recording the same way F5 does and checks the transcript. It pastes nothing. A run ends with `PASS` (exit 0) or `FAIL: <reason and fix>` plus the last lines of the hidden session.

Finally, ask the user to try it themselves: cursor in any text field, **hold F5**, speak, **release**. A "🎙 Listening…" banner shows while recording, and the text appears about a second after release. It also stays on the clipboard. Then tell the user:
- Recording starts the moment F5 goes down; words said before that are lost.
- Claude Code stops a recording after 2 minutes, or after 15 s of silence.
- On MacBooks, F5 is the microphone key. Both F5 and fn+F5 work, and F5 no longer starts macOS's own dictation.

## Configure

- **Language**: add `"language": "<code>"` to `~/.claude-dictation/settings.json`, for example `"ru"` or `"uk"`. Supported: cs, da, de, el, en, es, fr, hi, id, it, ja, ko, nl, no, pl, pt, ru, sv, tr, uk. Then run `tmux -L claude-dictation kill-server`; it comes back within a minute or on the next F5.
- **Key**: edit `KEYS` at the top of `~/.hammerspoon/claude_dictation.lua` (macOS key codes: 96 = F5, 176 = the microphone key). Then reload Hammerspoon: quit and `open -a Hammerspoon`, or use its menu → Reload Config. Note that `install.sh` overwrites this file.

## Troubleshooting

Always look at the hidden session first: `tmux -L claude-dictation capture-pane -p -t dictation`. The user can also watch it live with `tmux -L claude-dictation attach -t dictation` (detach: Ctrl+B, then D).

| Symptom | Cause and fix |
|---|---|
| F5 does nothing, no banner | `accessibility=false` in the status file: the user must grant it (step 3). No status file: the module didn't load, so ask the user for errors from the Hammerspoon console. Hammerspoon not running: `open -a Hammerspoon`. |
| "Dictation didn't start" banner | The session shows why. `Microphone access is denied`: System Settings → Privacy & Security → Microphone → Hammerspoon. `Voice mode requires a Claude.ai account`: the user logs in with `/login`. |
| "Dictation: no text" | Nothing was recognised. Check the input device (System Settings → Sound → Input), then `./verify.sh --speak`. |
| First words cut off | The session was cold-starting (after a reboot or crash). It's warm again within a minute. |
| macOS's own dictation pops up too | System Settings → Keyboard → Dictation → Shortcut → another shortcut, or Off. |
| Text went to the wrong window | It pastes into the app that had focus when F5 went down. It's also on the clipboard. |
| Session stuck on a dialog | Read the pane. After a Claude Code update a one-off notice can appear: `tmux -L claude-dictation kill-server`, then wait a minute. |

## Update / Uninstall

```bash
git pull && ./install.sh   # update; keeps ~/.claude-dictation/settings.json
./uninstall.sh             # removes ~/.claude-dictation, the module and the require line; keeps tmux, jq, Hammerspoon, Claude Code
```

## Rules for agents

- Don't touch Claude Code credentials, the keychain or OAuth tokens. This tool works only because it uses the unmodified `claude` binary with the user's own login.
- Change the user's `~/.hammerspoon/init.lua` only through `install.sh` and `uninstall.sh`, which add or remove one line.
- `verify.sh` plays sound and uses the microphone. Say so before running it.
- Don't leave test tmux servers or processes behind. The only long-running pieces are Hammerspoon and the `claude-dictation` tmux session.

## Privacy and cost

- Audio is streamed to Anthropic by Claude Code for transcription, the same as using `/voice` directly. Only the last transcript touches the disk (`~/.claude-dictation/out.txt`), and it's deleted right after pasting.
- Transcription doesn't use Claude messages or tokens, and the hook blocks the prompt so the model never sees it. As a safety net the session uses Haiku and asks before any tool, so even if the hook failed, nothing would run unattended.
- There are no keys, tokens or passwords in this repo.

## Files

| Repo | Installed to | Purpose |
|---|---|---|
| `src/claude_dictation.lua` | `~/.hammerspoon/claude_dictation.lua` | F5 handling, hidden session lifecycle, paste, status file |
| `src/settings.json` | `~/.claude-dictation/settings.json` | Hidden Claude Code settings: tap-mode voice, hook, Haiku, no Remote Control |
| `src/capture.sh` | `~/.claude-dictation/capture.sh` | `UserPromptSubmit` hook: save transcript, block prompt |
| `install.sh`, `uninstall.sh`, `verify.sh` | | set up, remove, self-test |
| `CLAUDE.md` | | points agents to this README |
