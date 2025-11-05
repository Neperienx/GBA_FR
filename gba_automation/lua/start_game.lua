--[[
    Entry point script that advances the Pokémon Fire Red startup flow.
    The script repeatedly presses the "A" button with pauses to navigate
    the title screen and initial menus until the game begins.
--]]

local BUTTON_A = "P1 A"

local FRAMES_PER_SECOND = 60
local INITIAL_WAIT_FRAMES = 5 * FRAMES_PER_SECOND
local HOLD_FRAMES = 2
local RELEASE_FRAMES = 30
local FINAL_WAIT_FRAMES = 180
local PRESS_COUNT = 6

local function press_a()
    joypad.set({[BUTTON_A] = true})
    for _ = 1, HOLD_FRAMES do
        emu.frameadvance()
    end

    joypad.set({[BUTTON_A] = false})
    for _ = 1, RELEASE_FRAMES do
        emu.frameadvance()
    end
end

console.log("[start_game] Waiting for the game to finish initial loading")
for _ = 1, INITIAL_WAIT_FRAMES do
    emu.frameadvance()
end

console.log("[start_game] Beginning automated start sequence")
client.unpause()

for i = 1, PRESS_COUNT do
    console.log(string.format("[start_game] Pressing A (%d/%d)", i, PRESS_COUNT))
    press_a()
end

console.log("[start_game] Final wait for the game intro to finish")
for _ = 1, FINAL_WAIT_FRAMES do
    emu.frameadvance()
end

console.log("[start_game] Startup sequence complete")
client.pause()
