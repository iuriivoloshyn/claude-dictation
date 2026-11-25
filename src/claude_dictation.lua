-- claude_dictation.lua: hold F5 anywhere on the Mac, speak, release, and the text is pasted at the cursor.
--
-- Speech-to-text is Claude Code's own voice dictation, running in a hidden tmux session
-- (tmux socket "claude-dictation", working folder ~/.claude-dictation). F5 down = first tap of Claude Code's
-- tap-to-talk (start), F5 up = second tap (stop). Claude Code then submits the transcript; the session's
-- UserPromptSubmit hook (capture.sh) saves it to out.txt and blocks the prompt, so nothing reaches the model.
-- This module reads out.txt and pastes it into the app that was in front when F5 went down.
--
-- Installed by install.sh from the claude-dictation repo; see its README.

local M = {}

local HOME = os.getenv("HOME")
local DIR = HOME .. "/.claude-dictation"
local OUT = DIR .. "/out.txt"
local SOCKET = "claude-dictation"
local KEYS = { [96] = true, [176] = true }  -- 96 = F5 as a function key, 176 = F5's microphone (Dictation) key
local MAX_AGE = 24 * 3600                  -- an older session is restarted while idle, so memory does not creep

local evTypes = hs.eventtap.event.types
local function now() return hs.timer.secondsSinceEpoch() end
local function q(s) return "'" .. s:gsub("'", "'\\''") .. "'" end

local function firstExisting(paths)
  for _, p in ipairs(paths) do if hs.fs.attributes(p) then return p end end
end
local function fromLoginShell(cmd)  -- slow, only used when the usual locations have nothing
  local out = hs.execute("command -v " .. cmd, true) or ""
  out = out:gsub("%s+$", "")
  if out ~= "" then return out end
end

local CLAUDE = firstExisting({ "/opt/homebrew/bin/claude", "/usr/local/bin/claude", HOME .. "/.local/bin/claude",
  HOME .. "/.claude/local/claude" }) or fromLoginShell("claude")
local TMUX = firstExisting({ "/opt/homebrew/bin/tmux", "/usr/local/bin/tmux" }) or fromLoginShell("tmux")

M.state = "idle"  -- idle | starting | recording | finishing
local function setState(s) M.state, M.stateAt = s, now() end

local function tmux(args) return hs.execute(q(TMUX) .. " -L " .. SOCKET .. " " .. args) or "" end
local function pane() return tmux("capture-pane -p -t dictation 2>/dev/null") end
local function running() return tmux("has-session -t dictation 2>/dev/null && echo yes"):find("yes") ~= nil end
local function ready()
  local p = pane()
  return p:find("❯") ~= nil and not p:find("Accessing workspace")
end
-- Empties the input box. Claude Code's Ctrl-U deletes only one visual line, and a long transcript put back after the
-- hook blocks it wraps over several: the rest stayed there, the next tap typed a space into it instead of starting a
-- recording, and F5 showed "Dictation didn't start". Extra Ctrl-Us on an empty input do nothing.
local CLEAR = "send-keys -t dictation" .. string.rep(" C-u", 60)
local function clearInput() tmux(CLEAR) end

-- Reading Claude Code's screen. The footer is everything under the input box: "REC", "Transcribing…", notices.
local function footer(p)
  local pos = 1
  for s in p:gmatch("()\n─") do pos = s end
  return p:sub(pos)
end
local function isRecording(p) return footer(p):find("REC") ~= nil end
local function inputHasText(p)
  local line
  for l in p:gmatch("[^\n]+") do if l:find("^❯") then line = l end end
  if not line then return false end
  line = line:gsub("^❯", "")
  for _, g in ipairs({ "▁", "▂", "▃", "▄", "▅", "▆", "▇", "█" }) do line = line:gsub(g, "") end  -- level meter
  if line:find('^%s*Try "') then return false end  -- grey hint shown in an empty input
  return line:find("%S") ~= nil
end

local function inputName()
  local d = hs.audiodevice.defaultInputDevice()
  return d and d:name() or "none"
end
-- Claude Code's notices, turned into what the user should do.
local function problem(f)
  if f:find("No audio detected") then
    return "nomic", "🎙 The microphone sent no sound (input: " .. inputName() .. ").\n"
      .. "Dictation restarted: try again. If it repeats: System Settings → Sound → Input."
  elseif f:find("No speech detected") then
    return "nospeech", "Didn't hear any speech (input: " .. inputName() .. ")"
  elseif f:find("[Mm]icrophone access") then
    return "denied", "Microphone blocked: System Settings → Privacy & Security → Microphone → Hammerspoon"
  elseif f:find("Claude%.ai account") then
    return "login", "Dictation needs Claude Code logged in with a Claude account: run claude, then /login"
  end
end

local function alert(text, secs)
  if M.alertId then hs.alert.closeSpecific(M.alertId) end
  M.lastMessage = text
  M.alertId = hs.alert.show(text, { textSize = 18, radius = 10 }, hs.screen.mainScreen(), secs or 3)
end
local function alertClose()
  if M.alertId then hs.alert.closeSpecific(M.alertId); M.alertId = nil end
end

local function startCommand()
  local path = table.concat({ CLAUDE:match("^(.*)/"), "/opt/homebrew/bin", "/usr/local/bin",
    "/usr/bin", "/bin", "/usr/sbin", "/sbin" }, ":")
  local claude = q(CLAUDE) .. " --settings " .. q(DIR .. "/settings.json")
    .. " --strict-mcp-config --setting-sources local"  -- no MCP servers, plugins or global hooks: faster, lighter
  return "new-session -d -s dictation -x 110 -y 30 -c " .. q(DIR) .. " -e " .. q("PATH=" .. path)
    .. " " .. q("exec " .. claude)
end

-- Start the hidden Claude Code unless it is running.
local function ensure()
  if running() then return end
  tmux(startCommand())
  M.startedAt = now()
  -- The first start in ~/.claude-dictation asks "Do you trust this folder?". The folder is ours: answer Yes.
  -- Enter is pressed only once "Yes" is visibly selected; Enter on the default ("No, exit") would quit Claude Code.
  local t0 = now()
  if M.trustPoll then M.trustPoll:stop() end
  M.trustPoll = hs.timer.doEvery(0.4, function()
    local p = pane()
    if p:find("I trust this folder") then
      if p:find("❯ Yes, I trust this folder") then
        tmux("send-keys -t dictation Enter")
      else
        tmux("send-keys -t dictation Down")
      end
    elseif ready() or now() - t0 > 30 then
      M.trustPoll:stop()
    end
  end)
end

-- A long-running Claude Code can lose the microphone (after sleep or when headphones reconnect) and then records
-- only silence. A fresh session picks up the current one, so restart it, but never in the middle of a dictation.
local function restart()
  if M.state ~= "idle" then M.restartPending = true; return end
  M.restartPending = false
  tmux("kill-server")
  hs.timer.doAfter(0.5, function() if M.state == "idle" then ensure() end end)
end
local function restartSoon(delay)  -- debounced: a headset connecting changes the device list several times
  if M.restartTimer then M.restartTimer:stop() end
  M.restartTimer = hs.timer.doAfter(delay, restart)
end

local function toIdle(msg, secs)
  setState("idle")
  if msg then alert(msg, secs or 3) else alertClose() end
  if M.restartPending then restart() end
end

-- Last resort: stop everything and go back to idle, so a bug can never leave a banner up or F5 dead.
local function reset(msg)
  for _, k in ipairs({ "poll", "recWatch", "startPoll" }) do if M[k] then pcall(M[k].stop, M[k]) end end
  pcall(function()
    if isRecording(pane()) then tmux("send-keys -t dictation Escape") end  -- cancel a recording still running
    clearInput()
  end)
  toIdle(msg, 4)
end
-- Runs fn; on an error, logs it to the Hammerspoon console and resets.
local function safe(fn)
  return function(...)
    local ok, err = pcall(fn, ...)
    if not ok then
      print("claude_dictation: " .. tostring(err))
      reset("Dictation hit an error and was reset: try again")
    end
  end
end
local STUCK_AFTER = { starting = 35, recording = 135, finishing = 50 }  -- seconds; Claude Code's own limit is 2 min

local function paste(text)
  hs.pasteboard.setContents(text)  -- the text also stays on the clipboard
  local app = M.target
  if app and app:isRunning() and hs.application.frontmostApplication() ~= app then app:activate() end
  hs.timer.doAfter(0.1, function() hs.eventtap.keyStroke({ "cmd" }, "v", 0) end)
end

-- Stop (when sendSpace) and collect the result: the transcript from out.txt, or the reason there is none.
local function finish(sendSpace)
  if M.recWatch then M.recWatch:stop() end
  setState("finishing")
  alert("✍️ Transcribing…", STUCK_AFTER.finishing)
  -- Second tap stops. Skip it if Claude Code has already stopped: a tap on an empty input starts a new recording.
  if sendSpace and isRecording(pane()) then tmux("send-keys -t dictation Space") end
  local t0, last, stable, enterAt, retapped = now(), nil, 0, nil, false
  M.poll = hs.timer.doEvery(0.15, safe(function()
    local f = io.open(OUT, "r")
    if f then
      local text = f:read("a"); f:close(); os.remove(OUT)
      M.poll:stop()
      -- the blocked prompt is put back into the input box: clear it
      hs.timer.doAfter(0.3, clearInput)
      text = text:gsub("^%s+", ""):gsub("%s+$", "")
      toIdle()
      if text ~= "" then paste(text) end
      return
    end
    local p = pane()
    local foot, elapsed = footer(p), now() - t0
    local kind, msg = problem(foot)
    if kind and kind ~= M.staleNotice then
      M.poll:stop(); clearInput()
      if kind == "nomic" then M.restartPending = true end
      return toIdle(msg, 6)
    end
    if p == last then stable = stable + 1 else stable, last = 0, p end
    local recording = isRecording(p)
    if recording and elapsed > 2 and not retapped then  -- the stop tap was lost: tap again
      tmux("send-keys -t dictation Space"); retapped = true
    end
    local busy = recording or foot:find("Transcribing")
    if not busy and stable >= 5 and elapsed > 1 then
      if inputHasText(p) then
        -- Transcripts under 3 words are only inserted, not submitted: submit them.
        if not enterAt then tmux("send-keys -t dictation Enter"); enterAt = now() end
      elseif not enterAt or now() - enterAt > 2 then
        M.poll:stop()
        return toIdle("Dictation: nothing recognised (input: " .. inputName() .. ")", 3)
      end
    end
    if elapsed > (busy and 45 or 15) then
      M.poll:stop(); clearInput()
      toIdle("Dictation: no text. See: tmux -L " .. SOCKET .. " attach -t dictation", 5)
    end
  end))
end

local function record()
  os.remove(OUT)
  M.staleNotice = problem(footer(pane()))  -- a notice left over from the previous try is not about this one
  clearInput()  -- recording starts only from an empty input
  tmux("send-keys -t dictation Space")  -- tap mode: first tap starts recording
  setState("recording")
  alert("🎙 Listening… release F5 to paste", STUCK_AFTER.recording)
  local t0, seen, gone = now(), false, 0
  if M.recWatch then M.recWatch:stop() end
  M.recWatch = hs.timer.doEvery(0.25, safe(function()
    if M.state ~= "recording" then return M.recWatch:stop() end
    local p = pane()
    if isRecording(p) then
      seen, gone = true, 0
      if not problem(footer(p)) then M.staleNotice = nil end
      return
    end
    if seen then
      -- Claude Code stopped on its own (15 s of silence, the 2-minute limit, a dead microphone): collect it now,
      -- so that releasing F5 does not start a new recording.
      gone = gone + 1
      if gone >= 2 then finish(false) end
    elseif now() - t0 > 1.5 then
      M.recWatch:stop()
      local _, msg = problem(footer(p))
      toIdle(msg or ("Dictation didn't start. See: tmux -L " .. SOCKET .. " attach -t dictation"), 6)
    end
  end))
end

function M.down()
  if M.state ~= "idle" then return end
  M.target, M.held, M.lastUse = hs.application.frontmostApplication(), true, now()
  if ready() then return record() end
  setState("starting")  -- normally it is already running; this is the rare cold start
  alert("Starting dictation…", STUCK_AFTER.starting)
  ensure()
  local t0 = now()
  M.startPoll = hs.timer.doEvery(0.1, safe(function()
    if ready() then
      M.startPoll:stop()
      if M.held then record() else toIdle("Dictation ready: hold F5 and speak", 1.5) end
    elseif now() - t0 > 30 then
      M.startPoll:stop(); toIdle("Dictation failed to start. See README → Troubleshooting", 4)
    end
  end))
end

function M.up()
  M.held = false
  if M.state == "recording" then finish(true) end
end

-- ~/.claude-dictation/status: plain key=value lines for verify.sh and agents (rewritten on load and every minute).
local function writeStatus()
  local f = io.open(DIR .. "/status", "w")
  if not f then return end
  f:write("updated=", os.date("!%Y-%m-%dT%H:%M:%SZ"), "\n",
    "accessibility=", tostring(hs.accessibilityState()), "\n",
    "f5_listener=", tostring(M.tap ~= nil and M.tap:isEnabled()), "\n",
    "claude=", tostring(CLAUDE), "\n",
    "tmux=", tostring(TMUX), "\n",
    "session_running=", tostring(TMUX ~= nil and running()), "\n",
    "input=", inputName(), "\n")
  f:close()
end

-- Microphones present and the default one; a change means the session should start afresh.
local function audioInputs()
  local ids = {}
  for _, d in ipairs(hs.audiodevice.allInputDevices()) do ids[#ids + 1] = d:uid() or d:name() end
  table.sort(ids)
  local def = hs.audiodevice.defaultInputDevice()
  return (def and (def:uid() or def:name()) or "-") .. "|" .. table.concat(ids, ",")
end

function M.start()
  if not CLAUDE or not TMUX then
    writeStatus()
    hs.alert.show("Claude dictation: " .. (CLAUDE and "tmux" or "claude") .. " not found. Run install.sh again.", 6)
    return M
  end
  if not hs.accessibilityState() then hs.accessibilityState(true) end  -- shows macOS's Accessibility prompt
  M.tap = hs.eventtap.new({ evTypes.keyDown, evTypes.keyUp }, function(e)
    if not KEYS[e:getKeyCode()] then return false end
    if e:getType() == evTypes.keyDown then
      if e:getProperty(hs.eventtap.event.properties.keyboardEventAutorepeat) == 0 then safe(M.down)() end
    else
      safe(M.up)()
    end
    return true  -- swallow F5 so macOS's own dictation does not start too
  end)
  M.tap:start()

  -- Keep it warm: a cold start takes ~1 s and words spoken during it are lost.
  ensure()
  M.startedAt = M.startedAt or now()
  M.keepAlive = hs.timer.doEvery(60, function()
    if M.state == "idle" then
      if now() - (M.startedAt or now()) > MAX_AGE and now() - (M.lastUse or 0) > 300 then restart() else ensure() end
    end
    -- macOS can disable a tap under load; a tap made before Accessibility was granted also starts working here
    if not M.tap:isEnabled() then M.tap:start() end
    writeStatus()
  end)
  -- Fresh session after the Mac wakes and when microphones come or go (AirPods connecting, a USB mic).
  M.wake = hs.caffeinate.watcher.new(function(ev)
    if ev == hs.caffeinate.watcher.systemDidWake then restartSoon(3) end
  end):start()
  M.audio = audioInputs()
  M.audioPoll = hs.timer.doEvery(3, function()
    local a = audioInputs()
    if a ~= M.audio then M.audio = a; restartSoon(3) end
    -- watchdog: no state may last longer than its limit
    if M.state ~= "idle" and now() - (M.stateAt or 0) > (STUCK_AFTER[M.state] or 60) then
      reset("Dictation was stuck and has been reset")
    end
  end)
  if not hs.autoLaunch() then hs.autoLaunch(true) end  -- Hammerspoon must start at login for this to work
  writeStatus()
  return M
end

return M.start()
