# claude-dictation

Hold **F5** anywhere on your Mac, speak, release, and the text appears where your cursor is. It works in any app: browser, Slack, Notes, a terminal.

Speech-to-text is **Claude Code's own voice dictation**, so it costs nothing extra if you already have a Claude subscription. Transcription doesn't count toward your Claude usage, and nothing is sent to the model.

## How it works

```
 F5 down ──► Hammerspoon ──► hidden Claude Code (tmux) starts recording   ("tap" #1 of /voice tap mode)
 F5 up   ──► Hammerspoon ──► Claude Code stops, transcribes, submits      ("tap" #2)
                              └─► hook capture.sh saves the text and BLOCKS the prompt (never reaches the model)
             Hammerspoon ◄── reads the text, pastes it with Cmd+V into the app you were in
```

- An ordinary, unmodified `claude` runs in a hidden tmux session (`tmux -L claude-dictation`), working folder `~/.claude-dictation`. It uses your normal login; no tokens are copied or touched.
- That session's `UserPromptSubmit` hook (`capture.sh`) writes the transcript to `~/.claude-dictation/out.txt` and exits with code 2, which blocks the prompt.
- The Hammerspoon module catches F5, drives the hidden session, and pastes the result. The text also stays on your clipboard.
- The hidden session is kept running (about 280 MB of RAM) so recording starts instantly. A cold start takes about a second, and words spoken during it would be lost. It starts with Hammerspoon at login, restarts within a minute if it dies, and is refreshed daily at 05:00.

## Requirements

- macOS (built and tested on macOS 27, Apple Silicon MacBook Pro)
- [Homebrew](https://brew.sh)
- [Claude Code](https://code.claude.com/docs/en/setup), **logged in with a Claude subscription account** (Pro / Max / Team / Enterprise). Voice dictation does not work with an API key, Bedrock, Vertex or Foundry login.
- A Claude Code version that has voice dictation (`/voice`). Update with `claude update` if `/voice` is unknown.

The installer adds **tmux**, **jq** and **[Hammerspoon](https://www.hammerspoon.org)** via Homebrew if they are missing.

## Install

```bash
gh repo clone iuriivoloshyn/claude-dictation   # or: git clone git@github.com:iuriivoloshyn/claude-dictation.git
cd claude-dictation
./install.sh
```

Then two one-time permissions:

1. **Accessibility**: System Settings → Privacy & Security → Accessibility → turn on **Hammerspoon**, then click the Hammerspoon menu-bar icon → **Reload Config**. Hammerspoon needs this to see F5 and to paste.
2. **Microphone**: the first time you hold F5, macOS asks to let **Hammerspoon** use the microphone. Click **Allow** and try again.

If you already use Hammerspoon, your `~/.hammerspoon/init.lua` is kept; the installer only adds one line at the end:

```lua
ClaudeDictation = require("claude_dictation")  -- hold F5 to dictate (claude-dictation)
```

## Use

1. Put the cursor where the text should go.
2. **Hold F5** and speak. A "🎙 Listening…" banner shows while it records.
3. **Release F5**. After about a second the text is pasted.

Notes:
- Recording starts the moment you press F5. Words spoken before the press are not captured.
- Claude Code stops a recording after **2 minutes**, or after **15 seconds of silence**.
- On MacBooks F5 is the microphone (Dictation) key. Both the plain key and **fn+F5** work. F5 is consumed, so macOS's own dictation won't start from it.

## Settings

Edit `~/.claude-dictation/settings.json`, then restart the hidden session with `tmux -L claude-dictation kill-server` (it comes back within a minute, or on the next F5 press).

- **Language**: add `"language": "russian"` (or `"ru"`, `"uk"`, `"de"`, `"es"`, …). The default is English. Supported: cs, da, de, el, en, es, fr, hi, id, it, ja, ko, nl, no, pl, pt, ru, sv, tr, uk.
- **Another key**: change `KEYS` near the top of `~/.hammerspoon/claude_dictation.lua` (macOS key codes; 96 = F5, 176 = microphone key), then Reload Config.

## Update

```bash
cd claude-dictation && git pull && ./install.sh
```

Re-running the installer is safe. It keeps your `settings.json`.

## Uninstall

```bash
./uninstall.sh
```

This removes `~/.claude-dictation`, `~/.hammerspoon/claude_dictation.lua` and the `require` line. tmux, jq, Hammerspoon and Claude Code stay installed.

## Troubleshooting

Look at the hidden session first. It shows exactly what Claude Code is doing:

```bash
tmux -L claude-dictation attach -t dictation     # detach again with Ctrl+B, then D
```

| Symptom | Fix |
|---|---|
| Nothing happens on F5 | Hammerspoon isn't running or has no Accessibility permission. Grant it, then Reload Config. Check the Hammerspoon console for errors. |
| "Dictation didn't start" | Attach to the session (above). `Microphone access is denied` → System Settings → Privacy & Security → Microphone → Hammerspoon on. `Voice mode requires a Claude.ai account` → in a normal terminal run `claude`, then `/login` with your subscription account. |
| "Dictation: no text" | Nothing was recognised. Check the input device in System Settings → Sound → Input, and speak after pressing F5. |
| macOS's own dictation pops up too | System Settings → Keyboard → Dictation → Shortcut → choose another shortcut or Off. |
| The first words are cut off | The hidden session was starting (after a reboot or crash). Wait until "🎙 Listening…" shows. |
| Text goes to the wrong window | The text is pasted into the app that was in front when you pressed F5. Don't switch apps while holding it. It's also on the clipboard, so Cmd+V works. |

## Privacy and cost

- Audio is streamed to Anthropic for transcription by Claude Code, exactly as when you use `/voice` yourself. Nothing is saved to disk except the last transcript in `~/.claude-dictation/out.txt`, which is deleted right after pasting.
- Transcription doesn't use Claude messages or tokens. The prompt is blocked by the hook, so the model never sees it. As a safety net the hidden session uses Haiku and asks before any tool use, so even if the hook ever failed, nothing would run on its own.
- No keys, tokens or passwords are stored in this repo or by the installer.

## Files

| Repo | Installed to | What |
|---|---|---|
| `src/claude_dictation.lua` | `~/.hammerspoon/claude_dictation.lua` | Hammerspoon module: F5 handling, hidden session, paste |
| `src/settings.json` | `~/.claude-dictation/settings.json` | Settings of the hidden Claude Code: tap mode, hook, Haiku, no Remote Control |
| `src/capture.sh` | `~/.claude-dictation/capture.sh` | Hook: saves the transcript and blocks the prompt |
| `install.sh` / `uninstall.sh` | | Set up / remove |
