--[[ 
  start_game.lua (working, minimal, well-commented)

  What it does:
    - Unpauses the emulator
    - Waits a bit (optional)
    - Presses "A" repeatedly with configurable hold/release timings
    - Waits a bit at the end and pauses again

  Notes:
    - Button names for GBA in BizHawk are: A, B, Start, Select, Up, Down, Left, Right, L, R
    - We use joypad.set({ A = true }) WITHOUT a controller index for reliability on GBA.
    - This script advances frames manually via emu.frameadvance().
--]]

---------------------------------------
-- TUNABLE SETTINGS (edit these)
---------------------------------------

local BUTTON_NAME = "A"              -- Which button to press (e.g., "A", "B", "Start", "Up", ...)
local FRAMES_PER_SECOND = 60         -- GBA runs ~60 FPS; used for time helpers

local INITIAL_WAIT_FRAMES = 5 * FRAMES_PER_SECOND
-- ^ How long to wait before starting to press A (lets intro/logo settle)

local HOLD_FRAMES = 2
-- ^ How many frames to HOLD the button down per press (2–3 frames works well)

local RELEASE_FRAMES = 30
-- ^ How many frames to RELEASE the button between presses (menu navigation needs a gap)

local PRESS_COUNT = 30
-- ^ How many times to press the button total

local FINAL_WAIT_FRAMES = 3 * FRAMES_PER_SECOND
-- ^ After finishing presses, wait this long (e.g., let intro/scene progress)

local LOG_VERBOSE = true
-- ^ If true, prints per-press logs to Output; set false to reduce spam


---------------------------------------
-- INTERNAL HELPERS (no need to edit)
---------------------------------------

local function log(fmt, ...)
  if LOG_VERBOSE then
    console.log(string.format(fmt, ...))
  end
end

-- For debugging: list available button keys once
local function log_available_buttons_once()
  local seen = {}
  for k, v in pairs(joypad.get(1)) do
    table.insert(seen, k .. "=" .. tostring(v))
  end
  console.log("[start_game] Available button keys on P1: " .. table.concat(seen, ", "))
end

-- Press BUTTON_NAME for HOLD_FRAMES, then release for RELEASE_FRAMES.
local function press_once()
  -- Hold phase
  for f = 1, HOLD_FRAMES do
    joypad.set({ [BUTTON_NAME] = true })   -- press the button THIS frame
    emu.frameadvance()                     -- advance one frame
  end
  -- Release phase
  for f = 1, RELEASE_FRAMES do
    joypad.set({ [BUTTON_NAME] = false })  -- ensure it's released THIS frame
    emu.frameadvance()
  end
end


---------------------------------------
-- MAIN SEQUENCE
---------------------------------------

console.log("[start_game] Script begin")

-- Make sure we are running before we start counting frames
if client.ispaused() then
  client.unpause()
end

-- Optional settling delay
log("[start_game] Initial wait: %d frames", INITIAL_WAIT_FRAMES)
for i = 1, INITIAL_WAIT_FRAMES do
  emu.frameadvance()
end

-- Show available buttons once (helps if nothing happens)
log_available_buttons_once()

-- Press loop
log("[start_game] Starting automated presses: %d times (hold=%d, release=%d)", PRESS_COUNT, HOLD_FRAMES, RELEASE_FRAMES)
for i = 1, PRESS_COUNT do
  log("[start_game] Press %d/%d at frame %d", i, PRESS_COUNT, emu.framecount())
  press_once()
end

-- Final wait
log("[start_game] Final wait: %d frames", FINAL_WAIT_FRAMES)
for i = 1, FINAL_WAIT_FRAMES do
  emu.frameadvance()
end

-- Pause again so you can inspect the result
client.pause()
console.log(string.format("[start_game] Done at frame %d (paused=%s)", emu.framecount(), tostring(client.ispaused())))
