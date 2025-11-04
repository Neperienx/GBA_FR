--[[
BizHawk-specific automation bridge that mirrors the JSON protocol used by
lua/automation_bridge.lua without relying on LuaSocket or luanet bindings.

BizHawk exposes its own networking helpers through the global `comm` table.
This script wraps those helpers so the Python bot can connect exactly the
same way it does with the mGBA bridge (Python acts as the TCP client).

The launcher (`main.py`) copies this file to the BizHawk Lua folder before
starting EmuHawk, so you normally do not need to load it manually.
]]

local console = console or { log = print }
local comm = rawget(_G, "comm")
if not comm then
    error("BizHawk comm API is unavailable; please enable Lua sockets in EmuHawk.")
end

local socket_start = comm.socketServerStart or comm.socketServerListen or comm.socketServerOpen
local socket_stop = comm.socketServerStop or comm.socketServerClose
local socket_connected = comm.socketServerIsConnected or comm.socketServerConnected
local socket_response = comm.socketServerResponse or comm.socketServerPeek
local socket_send = comm.socketServerSend or comm.socketServerSendText or comm.socketServerSendLine

if not (socket_start and socket_stop and socket_connected and socket_response and socket_send) then
    error("BizHawk comm API is missing socket server helpers required by the bridge.")
end

local function getenv(name)
    if not os or not os.getenv then
        return nil
    end
    local ok, value = pcall(os.getenv, name)
    if ok and value and #value > 0 then
        return value
    end
    return nil
end

local HOST = getenv("GBA_BRIDGE_HOST") or "127.0.0.1"
local PORT = tonumber(getenv("GBA_BRIDGE_PORT") or "8765", 10) or 8765

console.clear()
console.log(string.format("[bridge] BizHawk automation bridge listening on %s:%d", HOST, PORT))

local event = event or require("event")
local joypad = joypad or joypad
local memory = memory
local emu = emu

local JOYPAD_SET_NEEDS_PORT = false
if joypad and joypad.set then
    local ok = pcall(joypad.set, {})
    if not ok then
        JOYPAD_SET_NEEDS_PORT = true
    end
end

local MEMORY_DOMAIN = nil
if memory and memory.getcurrentmemorydomain and memory.usememorydomain then
    local current = memory.getcurrentmemorydomain()
    if not current or current == "" then
        pcall(memory.usememorydomain, "System Bus")
        current = memory.getcurrentmemorydomain()
    end
    MEMORY_DOMAIN = current
end

local WATCHERS = {
    { name = "frame", address = nil, size = 0 },
    { name = "in_battle_flag", address = 0x02022F2C, size = 1, type = "u8" },
    { name = "battle_mode", address = 0x02022F2D, size = 1, type = "u8" },
    { name = "player_hp", address = 0x02024284, size = 2, type = "u16" },
    { name = "player_max_hp", address = 0x02024286, size = 2, type = "u16" },
    { name = "battle_pp_1", address = 0x0202405A, size = 1, type = "u8" },
    { name = "battle_pp_2", address = 0x0202405B, size = 1, type = "u8" },
    { name = "battle_pp_3", address = 0x0202405C, size = 1, type = "u8" },
    { name = "battle_pp_4", address = 0x0202405D, size = 1, type = "u8" },
    { name = "enemy_personality", address = 0x020240A4, size = 4, type = "u32" },
    { name = "enemy_tid", address = 0x020240A0, size = 2, type = "u16" },
    { name = "enemy_sid", address = 0x020240A2, size = 2, type = "u16" },
}

local function read_u8(address)
    if memory.readbyte then
        return memory.readbyte(address)
    elseif memory.read_u8 then
        if MEMORY_DOMAIN then
            return memory.read_u8(address, MEMORY_DOMAIN)
        end
        return memory.read_u8(address)
    end
    error("Memory read (u8) not supported in this environment")
end

local function read_u16(address)
    if memory.readword then
        return memory.readword(address)
    elseif memory.read_u16_le then
        if MEMORY_DOMAIN then
            return memory.read_u16_le(address, MEMORY_DOMAIN)
        end
        return memory.read_u16_le(address)
    end
    error("Memory read (u16) not supported in this environment")
end

local function read_u32(address)
    if memory.readdword then
        return memory.readdword(address)
    elseif memory.read_u32_le then
        if MEMORY_DOMAIN then
            return memory.read_u32_le(address, MEMORY_DOMAIN)
        end
        return memory.read_u32_le(address)
    end
    error("Memory read (u32) not supported in this environment")
end

local function read_value(watcher)
    if watcher.address == nil then
        return emu.framecount()
    elseif watcher.size == 1 then
        return read_u8(watcher.address)
    elseif watcher.size == 2 then
        return read_u16(watcher.address)
    elseif watcher.size == 4 then
        return read_u32(watcher.address)
    else
        error("Unsupported watcher size: " .. tostring(watcher.size))
    end
end

local function escape_str(str)
    return (str:gsub('[\"%c]', function(c)
        if c == '"' then
            return '\\"'
        elseif c == '\\' then
            return '\\\\'
        elseif c == '\n' then
            return '\\n'
        elseif c == '\r' then
            return '\\r'
        elseif c == '\t' then
            return '\\t'
        else
            return string.format("\\u%04X", string.byte(c))
        end
    end))
end

local function json_encode(value)
    local t = type(value)
    if t == "nil" then
        return "null"
    elseif t == "boolean" then
        return value and "true" or "false"
    elseif t == "number" then
        return string.format("%s", value)
    elseif t == "string" then
        return '"' .. escape_str(value) .. '"'
    elseif t == "table" then
        local is_array = (#value > 0)
        local out = {}
        if is_array then
            for i = 1, #value do
                out[#out + 1] = json_encode(value[i])
            end
            return "[" .. table.concat(out, ",") .. "]"
        else
            for k, v in pairs(value) do
                out[#out + 1] = json_encode(tostring(k)) .. ":" .. json_encode(v)
            end
            return "{" .. table.concat(out, ",") .. "}"
        end
    else
        error("Unsupported JSON type: " .. t)
    end
end

local function json_error(message, index)
    return { message = message, index = index }
end

local function skip_ws(str, idx)
    local len = #str
    while idx <= len do
        local c = str:sub(idx, idx)
        if c ~= ' ' and c ~= '\n' and c ~= '\t' and c ~= '\r' then
            break
        end
        idx = idx + 1
    end
    return idx
end

local function parse_value(str, idx)
    idx = skip_ws(str, idx)
    local c = str:sub(idx, idx)
    if c == '"' then
        local i = idx + 1
        local out = {}
        while i <= #str do
            local ch = str:sub(i, i)
            if ch == '"' then
                return table.concat(out), i + 1
            elseif ch == '\\' then
                local esc = str:sub(i + 1, i + 1)
                if esc == '"' or esc == '\\' or esc == '/' then
                    out[#out + 1] = esc
                elseif esc == 'b' then
                    out[#out + 1] = '\b'
                elseif esc == 'f' then
                    out[#out + 1] = '\f'
                elseif esc == 'n' then
                    out[#out + 1] = '\n'
                elseif esc == 'r' then
                    out[#out + 1] = '\r'
                elseif esc == 't' then
                    out[#out + 1] = '\t'
                elseif esc == 'u' then
                    local hex = str:sub(i + 2, i + 5)
                    out[#out + 1] = string.char(tonumber(hex, 16) or 0)
                    i = i + 4
                end
                i = i + 2
            else
                out[#out + 1] = ch
                i = i + 1
            end
        end
        return nil, json_error("unterminated string", idx)
    elseif c == '{' then
        local obj = {}
        local i = idx + 1
        i = skip_ws(str, i)
        if str:sub(i, i) == '}' then
            return obj, i + 1
        end
        while i <= #str do
            local key
            key, i = parse_value(str, i)
            if not key then
                return nil, i
            end
            i = skip_ws(str, i)
            if str:sub(i, i) ~= ':' then
                return nil, json_error("expected ':'", i)
            end
            local value
            value, i = parse_value(str, i + 1)
            if value == nil and type(i) == "table" then
                return nil, i
            end
            obj[key] = value
            i = skip_ws(str, i)
            local sep = str:sub(i, i)
            if sep == '}' then
                return obj, i + 1
            elseif sep ~= ',' then
                return nil, json_error("expected ',' or '}'", i)
            end
            i = i + 1
        end
        return nil, json_error("unterminated object", idx)
    elseif c == '[' then
        local arr = {}
        local i = idx + 1
        i = skip_ws(str, i)
        if str:sub(i, i) == ']' then
            return arr, i + 1
        end
        while i <= #str do
            local value
            value, i = parse_value(str, i)
            if value == nil and type(i) == "table" then
                return nil, i
            end
            arr[#arr + 1] = value
            i = skip_ws(str, i)
            local sep = str:sub(i, i)
            if sep == ']' then
                return arr, i + 1
            elseif sep ~= ',' then
                return nil, json_error("expected ',' or ']'", i)
            end
            i = i + 1
        end
        return nil, json_error("unterminated array", idx)
    elseif c == '-' or (c >= '0' and c <= '9') then
        local start_idx = idx
        while idx <= #str do
            c = str:sub(idx, idx)
            if c ~= '+' and c ~= '-' and c ~= '.' and c ~= 'e' and c ~= 'E' and (c < '0' or c > '9') then
                break
            end
            idx = idx + 1
        end
        local num = tonumber(str:sub(start_idx, idx - 1))
        return num, idx
    elseif str:sub(idx, idx + 3) == "true" then
        return true, idx + 4
    elseif str:sub(idx, idx + 4) == "false" then
        return false, idx + 5
    elseif str:sub(idx, idx + 3) == "null" then
        return nil, idx + 4
    end
    return nil, json_error("unexpected character", idx)
end

local function json_decode(str)
    local value, idx = parse_value(str, 1)
    if type(idx) == "table" then
        return nil, idx
    end
    idx = skip_ws(str, idx)
    if idx <= #str then
        return nil, json_error("trailing characters", idx)
    end
    return value
end

local function gather_state()
    local snapshot = {}
    for _, watcher in ipairs(WATCHERS) do
        snapshot[watcher.name] = read_value(watcher)
    end
    return snapshot
end

local current_input = {}
local pending_macro = nil
local macro_step_index = 1
local macro_step_timer = 0
local last_connection_state = false
local receive_buffer = ""

local function set_input(buttons)
    current_input = {}
    if buttons then
        for _, button in ipairs(buttons) do
            current_input[button] = true
        end
    end
end

local function apply_input()
    if JOYPAD_SET_NEEDS_PORT then
        joypad.set(1, current_input)
    else
        joypad.set(current_input)
    end
end

local function start_macro(steps)
    if not steps then
        return
    end
    pending_macro = steps
    macro_step_index = 1
    macro_step_timer = 0
end

local function step_macro()
    if not pending_macro then
        return
    end
    local step = pending_macro[macro_step_index]
    if not step then
        pending_macro = nil
        set_input(nil)
        return
    end
    if macro_step_timer == 0 then
        set_input(step.buttons)
        macro_step_timer = step.duration or 1
    end
    macro_step_timer = macro_step_timer - 1
    if macro_step_timer <= 0 then
        macro_step_index = macro_step_index + 1
        macro_step_timer = 0
    end
end

local function process_command(cmd)
    if cmd.type == "input" then
        pending_macro = nil
        set_input(cmd.buttons)
    elseif cmd.type == "macro" then
        start_macro(cmd.steps)
    elseif cmd.type == "reset" then
        pending_macro = nil
        set_input(nil)
    end
end

local function reset_server()
    if socket_stop then
        pcall(socket_stop)
    end
    receive_buffer = ""
    pending_macro = nil
    set_input(nil)
    macro_step_index = 1
    macro_step_timer = 0
    local ok, err = pcall(socket_start, PORT)
    if not ok then
        console.log("[bridge] failed to (re)start socket server: " .. tostring(err))
    end
end

reset_server()

local function pump_commands()
    if not socket_connected() then
        if last_connection_state then
            console.log("[bridge] client disconnected; waiting for reconnection")
            last_connection_state = false
            receive_buffer = ""
            pending_macro = nil
            set_input(nil)
        end
        return
    end

    if not last_connection_state then
        console.log("[bridge] client connected")
        last_connection_state = true
    end

    while true do
        local chunk = socket_response()
        if not chunk or #chunk == 0 then
            break
        end
        receive_buffer = receive_buffer .. chunk
        while true do
            local newline = receive_buffer:find("\n", 1, true)
            if not newline then
                break
            end
            local line = receive_buffer:sub(1, newline - 1)
            receive_buffer = receive_buffer:sub(newline + 1)
            if #line > 0 then
                local ok, message = pcall(json_decode, line)
                if ok and message then
                    process_command(message)
                else
                    console.log("[bridge] failed to decode command: " .. tostring(message))
                end
            end
        end
    end
end

local function send_state()
    if not socket_connected() then
        return
    end
    local payload = json_encode({ type = "state", data = gather_state() }) .. "\n"
    local ok = socket_send(payload)
    if ok == false then
        console.log("[bridge] send failed; restarting server")
        reset_server()
        last_connection_state = false
    end
end

local function on_frame()
    pump_commands()
    step_macro()
    apply_input()
    send_state()
    emu.frameadvance()
end

while true do
    on_frame()
end
