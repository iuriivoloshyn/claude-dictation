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
local DAILY_RESTART = "05:00"              -- fresh start once a day, so memory does not creep

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

local function tmux(args) return hs.execute(q(TMUX) .. " -L " .. SOCKET .. " " .. args) or "" end
local function pane() return tmux("capture-pane -p -t dictation 2>/dev/null") end
local function running() return tmux("has-session -t dictation 2>/dev/null && echo yes"):find("yes") ~= nil end
local function ready()
  local p = pane()
  return p:find("❯") ~= nil and not p:find("Accessing workspace")
end

local function alert(text, secs)
  if M.alertId then hs.alert.closeSpecific(M.alertId) end
  M.alertId = hs.alert.show(text, { textSize = 18, radius = 10 }, hs.screen.mainScreen(), secs or true)
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

local function paste(text)
  hs.pasteboard.setContents(text)  -- the text also stays on the clipboard
  local app = M.target
  if app and app:isRunning() and hs.application.frontmostApplication() ~= app then app:activate() end
  hs.timer.doAfter(0.1, function() hs.eventtap.keyStroke({ "cmd" }, "v", 0) end)
end

local function record()
  os.remove(OUT)
  tmux("send-keys -t dictation C-u")    -- recording starts only from an empty input
  tmux("send-keys -t dictation Space")  -- tap mode: first tap starts recording
  M.state = "recording"
  alert("🎙 Listening… release F5 to paste")
  hs.timer.doAfter(1.0, function()      -- recording never started: say where to look
    if M.state == "recording" and not pane():find("REC") then
      M.state = "idle"
      alert("Dictation didn't start. See: tmux -L " .. SOCKET .. " attach", 5)
    end
  end)
end

local function finish()
  M.state = "finishing"
  alert("✍️ Transcribing…")
  tmux("send-keys -t dictation Space")  -- second tap stops; 3+ words are submitted and caught by the hook
  local t0, last, stable, enterSent = now(), nil, 0, false
  M.poll = hs.timer.doEvery(0.15, function()
    local f = io.open(OUT, "r")
    if f then
      local text = f:read("a"); f:close(); os.remove(OUT)
      M.poll:stop(); alertClose(); M.state = "idle"
      -- the blocked prompt is put back into the input box: clear it
      hs.timer.doAfter(0.3, function() tmux("send-keys -t dictation C-u") end)
      text = text:gsub("^%s+", ""):gsub("%s+$", "")
      if text ~= "" then paste(text) end
      return
    end
    local p = pane()
    if p == last then stable = stable + 1 else stable, last = 0, p end
    -- Transcripts under 3 words are only inserted, not submitted: press Enter once the screen settles.
    if not enterSent and now() - t0 > 2 and stable >= 5 and not p:find("REC") then
      tmux("send-keys -t dictation Enter"); enterSent = true
    end
    if now() - t0 > 12 then
      M.poll:stop(); M.state = "idle"
      alert("Dictation: no text", 2)
    end
  end)
end

function M.down()
  if M.state ~= "idle" then return end
  M.target, M.held = hs.application.frontmostApplication(), true
  if ready() then return record() end
  M.state = "starting"  -- normally it is already running; this is the rare cold start
  alert("Starting dictation…")
  ensure()
  local t0 = now()
  M.startPoll = hs.timer.doEvery(0.1, function()
    if ready() then
      M.startPoll:stop()
      if M.held then record() else M.state = "idle"; alert("Dictation ready: hold F5 and speak", 1.5) end
    elseif now() - t0 > 30 then
      M.startPoll:stop(); M.state = "idle"; alert("Dictation failed to start. See README → Troubleshooting", 4)
    end
  end)
end

function M.up()
  M.held = false
  if M.state == "recording" then finish() end
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
    "session_running=", tostring(TMUX ~= nil and running()), "\n")
  f:close()
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
      if e:getProperty(hs.eventtap.event.properties.keyboardEventAutorepeat) == 0 then M.down() end
    else
      M.up()
    end
    return true  -- swallow F5 so macOS's own dictation does not start too
  end)
  M.tap:start()

  -- Keep it warm: a cold start takes ~1 s and words spoken during it are lost.
  ensure()
  M.keepAlive = hs.timer.doEvery(60, function()
    if M.state == "idle" then ensure() end
    -- macOS can disable a tap under load; a tap made before Accessibility was granted also starts working here
    if not M.tap:isEnabled() then M.tap:start() end
    writeStatus()
  end)
  M.daily = hs.timer.doAt(DAILY_RESTART, "1d", function()
    if M.state == "idle" then tmux("kill-server"); hs.timer.doAfter(2, ensure) end
  end)
  if not hs.autoLaunch() then hs.autoLaunch(true) end  -- Hammerspoon must start at login for this to work
  writeStatus()
  return M
end

return M.start()
