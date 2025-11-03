-- bizhawk_client_bridge.lua
-- BizHawk acts as the TCP CLIENT (you run a Python server that listens).
-- Start BizHawk like this so it connects automatically:
--   EmuHawk.exe --gdi --socket_ip=127.0.0.1 --socket_port=8765

console.clear()
console.log("[bridge] BizHawk client bridge starting…")

----------------------------------------------------------------------
-- Config
----------------------------------------------------------------------
local DOMAIN = "System Bus"  -- GBA memory domain in BizHawk

-- 🔧 Fill these for your game build (these are FRLG USA v1.0 placeholders).
-- For French FireRed, you will RAM-scan and update them later.
local ADDR = {
  in_battle   = 0x02022F2C, -- u8  (0/1)
  enemy_pid   = 0x020240A4, -- u32 (wild/enemy PID)
  enemy_species = 0x020240A8, -- u16 (species ID)
  -- add more when needed (HP, PP, map, etc.)
}

----------------------------------------------------------------------
-- Helpers: inputs, holds, state reads
----------------------------------------------------------------------
local current_input = {}
local hold_timer = 0

local function clear_input()
  current_input = {}
  hold_timer = 0
end

local function press_once(buttons)
  local m = {}
  for _,b in ipairs(buttons or {}) do m[b] = true end
  joypad.set(m) -- pressed for this frame only
end

local function start_hold(buttons, frames)
  current_input = {}
  for _,b in ipairs(buttons or {}) do current_input[b] = true end
  hold_timer = math.max(tonumber(frames or 1) or 1, 1)
end

local function step_hold()
  if hold_timer > 0 then
    joypad.set(current_input)
    hold_timer = hold_timer - 1
    if hold_timer <= 0 then
      current_input = {}
    end
  end
end

local function rd_u8(a)  return memory.read_u8(a,  DOMAIN) end
local function rd_u16(a) return memory.read_u16_le(a, DOMAIN) end
local function rd_u32(a) return memory.read_u32_le(a, DOMAIN) end

local function make_state_json()
  -- Build a tiny JSON line without external libs
  local frame   = emu.framecount()
  local ib      = rd_u8(ADDR.in_battle)
  local species = rd_u16(ADDR.enemy_species)
  local pid     = rd_u32(ADDR.enemy_pid)
  -- NOTE: if addresses are wrong for your ROM, these will just be 0/garbage until you update them.
  return string.format('{"type":"state","frame":%d,"in_battle":%d,"species":%d,"pid":%u}\n',
                       frame, ib or 0, species or 0, pid or 0)
end

----------------------------------------------------------------------
-- Command protocol (line-based, very simple):
--   PING
--   PRESS <Button>[,<Button2>...]
--   HOLD <frames> <Button>[,<Button2>...]
--   RESET
--   SAY <text...>      (prints to BizHawk console)
--
-- Examples from Python:
--   b"PING\n"
--   b"PRESS A\n"
--   b"HOLD 60 Up\n"
--   b"PRESS Left,Start\n"
--   b"RESET\n"
----------------------------------------------------------------------
local function split_csv(s)
  local t = {}
  for token in string.gmatch(s, "([^,]+)") do
    token = token:gsub("^%s+", ""):gsub("%s+$", "")
    if #token > 0 then table.insert(t, token) end
  end
  return t
end

local function handle_command(line)
  -- strip CR/LF
  line = line:gsub("[\r\n]+$", "")
  if #line == 0 then return end

  if line:match("^PING") then
    comm.socketServerSend("PONG\n")
    return
  end

  if line:match("^RESET$") then
    clear_input()
    comm.socketServerSend('{"ok":true,"cmd":"RESET"}\n')
    return
  end

  local frames, btns

  -- HOLD <frames> <btns>
  frames, btns = line:match("^HOLD%s+(%d+)%s+(.+)$")
  if frames and btns then
    local buttons = split_csv(btns)
    start_hold(buttons, tonumber(frames))
    comm.socketServerSend('{"ok":true,"cmd":"HOLD"}\n')
    return
  end

  -- PRESS <btns>
  btns = line:match("^PRESS%s+(.+)$")
  if btns then
    local buttons = split_csv(btns)
    press_once(buttons)
    comm.socketServerSend('{"ok":true,"cmd":"PRESS"}\n')
    return
  end

  -- SAY <text>
  local text = line:match("^SAY%s+(.+)$")
  if text then
    console.log("[python] "..text)
    comm.socketServerSend('{"ok":true,"cmd":"SAY"}\n')
    return
  end

  -- Unknown
  comm.socketServerSend('{"ok":false,"error":"unknown_cmd"}\n')
end

----------------------------------------------------------------------
-- Main loop
-- IMPORTANT: we must yield once per frame with emu.frameadvance()
----------------------------------------------------------------------
console.log("[bridge] running; BizHawk should have been launched with --socket_ip/--socket_port")
while true do
  -- 1) Read one line from Python (nil if none this frame)
  local msg = comm.socketServerResponse()
  if msg and #msg > 0 then
    -- There might be multiple lines buffered; process each '\n'-terminated line
    -- BizHawk usually delivers one line, but we guard anyway.
    for line in string.gmatch(msg, "([^\n]*)\n?") do
      if line and #line > 0 then handle_command(line) end
    end
  end

  -- 2) Apply any active hold
  step_hold()

  -- 3) Stream state (one JSON line per frame)
  comm.socketServerSend(make_state_json())

  -- 4) Yield for one frame
  emu.frameadvance()
end
