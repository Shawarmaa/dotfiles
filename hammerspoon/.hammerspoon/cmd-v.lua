-- Cmd+V pastes images into terminal coding agents on macOS.
-- https://github.com/Shawarmaa/cmd-v

-- Terminals where Cmd+V does not deliver images, by bundle ID.
local TERMINALS = {
  ["com.mitchellh.ghostty"] = true,
  ["com.apple.Terminal"] = true,
  ["com.googlecode.iterm2"] = true,
  ["org.alacritty"] = true,
  ["net.kovidgoyal.kitty"] = true,
  ["com.github.wez.wezterm"] = true,
}

local function terminalInFront()
  local app = hs.application.frontmostApplication()
  if app and TERMINALS[app:bundleID()] then return app end
  return nil
end

local IMAGE_TYPES = {
  ["public.png"] = true,
  ["public.tiff"] = true,
  ["public.jpeg"] = true,
  ["com.compuserve.gif"] = true,
}

local function pasteboardHasImage()
  for _, uti in ipairs(hs.pasteboard.contentTypes() or {}) do
    if IMAGE_TYPES[uti] then return true end
  end
  return false
end

-- Hammerspoon collects taps and timers held only in a local, and they then stop
-- firing with no error anywhere. These hang off the module table instead, which
-- package.loaded keeps alive for as long as Hammerspoon runs.
local M = {}

-- Returning false leaves the keystroke untouched, which is every case but an
-- image in a listed terminal. That is also why this cannot loop: the injected
-- event carries ctrl, and the guard below requires cmd alone.
M.tap = hs.eventtap.new({ hs.eventtap.event.types.keyDown }, function(event)
  if event:getKeyCode() ~= hs.keycodes.map.v then return false end

  local flags = event:getFlags()
  if not flags.cmd or flags.ctrl or flags.alt or flags.shift then return false end

  if not terminalInFront() then return false end
  if not pasteboardHasImage() then return false end

  return true, {
    hs.eventtap.event.newKeyEvent({ "ctrl" }, "v", true),
    hs.eventtap.event.newKeyEvent({ "ctrl" }, "v", false),
  }
end)

M.tap:start()

-- Without Accessibility permission the tap starts without error and then never
-- sees a keystroke, so say so rather than look broken.
if not hs.accessibilityState() then
  hs.alert.show("cmd-v needs Accessibility permission for Hammerspoon")
end

-- Raycast pastes without a keystroke any event tap can see, so the tap above
-- never fires for it. It does write to the pasteboard, marked transient, and a
-- screenshot carries public.png alone. That difference is the gate: without it
-- this would fire on every screenshot taken with the terminal focused.
local TRANSIENT = "org.nspasteboard.TransientType"

local function transientImageArrived()
  local types = hs.pasteboard.contentTypes() or {}
  local image, transient = false, false
  for _, uti in ipairs(types) do
    if IMAGE_TYPES[uti] then image = true end
    if uti == TRANSIENT then transient = true end
  end
  return image and transient
end

local lastSeenChange = hs.pasteboard.changeCount()

M.timer = hs.timer.doEvery(0.15, function()
  local count = hs.pasteboard.changeCount()
  if count == lastSeenChange then return end
  lastSeenChange = count

  local app = terminalInFront()
  if not app then return end
  if not transientImageArrived() then return end

  hs.eventtap.event.newKeyEvent({ "ctrl" }, "v", true):post(app)
  hs.eventtap.event.newKeyEvent({ "ctrl" }, "v", false):post(app)
end)

return M
