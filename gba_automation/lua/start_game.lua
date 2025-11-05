--[[
    Entry point script that advances the Pokémon Fire Red startup flow.
    The script repeatedly presses the "A" button with pauses to navigate
    the title screen and initial menus until the game begins.
--]]

local CONTROLLER_INDEX = 1
local BUTTON_A = "A"

local FRAMES_PER_SECOND = 60
local INITIAL_WAIT_FRAMES = 5 * FRAMES_PER_SECOND
local HOLD_FRAMES = 2
local RELEASE_FRAMES = 30
local FINAL_WAIT_FRAMES = 180
local PRESS_COUNT = 6

local function log_button_state(phase)
    local state = joypad.get(CONTROLLER_INDEX)[BUTTON_A]
    console.log(string.format(
        "[start_game] %s at frame %d (A=%s)",
        phase,
        emu.framecount(),
        tostring(state)
    ))
end

local function press_a()
    console.log("[start_game] Holding A down")
    for frame = 1, HOLD_FRAMES do
        joypad.set({[BUTTON_A] = true}, CONTROLLER_INDEX)
        emu.frameadvance()
        log_button_state(string.format("Hold frame %d/%d", frame, HOLD_FRAMES))
    end

    console.log("[start_game] Releasing A")
    for frame = 1, RELEASE_FRAMES do
        joypad.set({[BUTTON_A] = false}, CONTROLLER_INDEX)
        emu.frameadvance()
        log_button_state(string.format("Release frame %d/%d", frame, RELEASE_FRAMES))
    end
end

console.log("[start_game] Waiting for the game to finish initial loading")
for _ = 1, INITIAL_WAIT_FRAMES do
    emu.frameadvance()
end

console.log(string.format(
    "[start_game] Beginning automated start sequence (isPaused=%s, frame=%d)",
    tostring(client.ispaused()),
    emu.framecount()
))
client.unpause()
log_button_state("Post-unpause state")

for i = 1, PRESS_COUNT do
    console.log(string.format("[start_game] Pressing A (%d/%d)", i, PRESS_COUNT))
    press_a()
end

console.log("[start_game] Final wait for the game intro to finish")
for _ = 1, FINAL_WAIT_FRAMES do
    emu.frameadvance()
end

client.pause()
console.log(string.format(
    "[start_game] Startup sequence complete (isPaused=%s, frame=%d)",
    tostring(client.ispaused()),
    emu.framecount()
))
log_button_state("Final state")
