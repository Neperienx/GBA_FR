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

-- Memory inspection configuration (GBA addresses live in the EWRAM domain)
local MEM_DOMAIN = "EWRAM"

-- Known FireRed addresses pulled from community documentation / reverse engineering
local ADDR_MAP_GROUP = 0x02036DFC
local ADDR_MAP_NUMBER = 0x02036DFE
local ADDR_PLAYER_X = 0x02036E38
local ADDR_PLAYER_Y = 0x02036E3A
local ADDR_PLAYER_FACING = 0x02036E32
local ADDR_PLAYER_TILE_BEHAVIOR = 0x02037079

local GRASS_BEHAVIORS = {
  [0x03] = "Tall grass",
  [0x04] = "Long grass",
  [0x52] = "Long grass (alt)",
  [0x5A] = "Very tall grass",
}


---------------------------------------
-- INTERNAL HELPERS (no need to edit)
---------------------------------------

local function log(fmt, ...)
  if LOG_VERBOSE then
    console.log(string.format(fmt, ...))
  end
end

local function read_u8(addr)
  memory.usememorydomain(MEM_DOMAIN)
  return memory.read_u8(addr)
end

local function read_u16(addr)
  memory.usememorydomain(MEM_DOMAIN)
  return memory.read_u16_le(addr)
end

local function decode_grass_behavior(behavior)
  return GRASS_BEHAVIORS[behavior]
end

local function capture_game_state()
  local map_group = read_u8(ADDR_MAP_GROUP)
  local map_number = read_u8(ADDR_MAP_NUMBER)
  local x = read_u16(ADDR_PLAYER_X)
  local y = read_u16(ADDR_PLAYER_Y)
  local facing = read_u8(ADDR_PLAYER_FACING)
  local tile_behavior = read_u8(ADDR_PLAYER_TILE_BEHAVIOR)

  local grass_descriptor = decode_grass_behavior(tile_behavior)
  local in_grass = grass_descriptor ~= nil

  return {
    map_group = map_group,
    map_number = map_number,
    x = x,
    y = y,
    facing = facing,
    tile_behavior = tile_behavior,
    grass_descriptor = grass_descriptor,
    in_grass = in_grass,
  }
end

local function log_game_state()
  local state = capture_game_state()

  console.log(string.format(
    "[start_game] Map group=%d, map number=%d, coords=(%d,%d), facing=0x%02X",
    state.map_group,
    state.map_number,
    state.x,
    state.y,
    state.facing
  ))

  if state.in_grass then
    console.log(string.format(
      "[start_game] Player is in grass: behavior=0x%02X (%s)",
      state.tile_behavior,
      state.grass_descriptor
    ))
  else
    console.log(string.format(
      "[start_game] Player is not in recognized grass (behavior=0x%02X)",
      state.tile_behavior
    ))
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

-- Inspect the overworld state after the intro skip completes
log_game_state()

-- Pause again so you can inspect the result
client.pause()
console.log(string.format("[start_game] Done at frame %d (paused=%s)", emu.framecount(), tostring(client.ispaused())))
