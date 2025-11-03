--[[
Automation bridge between the emulator runtime (Lua) and an external
Python process.  The bridge exposes a very small JSON based protocol that
allows Python to drive inputs while receiving high level game state
updates extracted from the Fire Red memory map.

The script is designed for mGBA (or compatible emulators with Lua 5.3 +
socket support).  It opens a TCP server on localhost and streams game
state once per frame.  Python sends back commands describing either
frame-long button presses or macros (a list of button presses with a
fixed duration for each step).
]]

local socket = require("socket")
local event = event or require("event")
local joypad = joypad or joypad
local memory = memory
local emu = emu

local HOST = "127.0.0.1"
local PORT = 8765

local function dbg(msg)
    if not msg then
        return
    end
    print("[bridge] " .. msg)
end

-----------------------------------------------------------------------
-- Minimal JSON implementation ---------------------------------------
-----------------------------------------------------------------------

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

local function parse_literal(str, idx, literal, value)
    if str:sub(idx, idx + #literal - 1) == literal then
        return value, idx + #literal
    end
    return nil, idx, json_error("Invalid literal", idx)
end

local function parse_number(str, idx)
    local num_pattern = "^-?%d+%.?%d*[eE]?[+-]?%d*"
    local s, e = str:find(num_pattern, idx)
    if not s then
        return nil, idx, json_error("Invalid number", idx)
    end
    local num = tonumber(str:sub(s, e))
    return num, e + 1
end

local function parse_string(str, idx)
    idx = idx + 1
    local start = idx
    local escaped = {}
    local out = {}
    while idx <= #str do
        local c = str:sub(idx, idx)
        if c == '"' then
            out[#out + 1] = table.concat(escaped)
            return table.concat(out), idx + 1
        elseif c == '\\' then
            out[#out + 1] = table.concat(escaped)
            escaped = {}
            idx = idx + 1
            local esc = str:sub(idx, idx)
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
                local hex = str:sub(idx + 1, idx + 4)
                out[#out + 1] = string.char(tonumber(hex, 16))
                idx = idx + 4
            else
                return nil, idx, json_error("Invalid escape", idx)
            end
            idx = idx + 1
            escaped = {}
            start = idx
        else
            escaped[#escaped + 1] = c
            idx = idx + 1
        end
    end
    return nil, idx, json_error("Unterminated string", idx)
end

local function parse_array(str, idx)
    local arr = {}
    idx = idx + 1
    idx = skip_ws(str, idx)
    if str:sub(idx, idx) == ']' then
        return arr, idx + 1
    end
    while idx <= #str do
        local value
        value, idx, err = parse_value(str, idx)
        if err then
            return nil, idx, err
        end
        arr[#arr + 1] = value
        idx = skip_ws(str, idx)
        local c = str:sub(idx, idx)
        if c == ',' then
            idx = idx + 1
            idx = skip_ws(str, idx)
        elseif c == ']' then
            return arr, idx + 1
        else
            return nil, idx, json_error("Expected ',' or ']'", idx)
        end
    end
    return nil, idx, json_error("Unterminated array", idx)
end

function parse_object(str, idx)
    local obj = {}
    idx = idx + 1
    idx = skip_ws(str, idx)
    if str:sub(idx, idx) == '}' then
        return obj, idx + 1
    end
    while idx <= #str do
        if str:sub(idx, idx) ~= '"' then
            return nil, idx, json_error("Expected string key", idx)
        end
        local key
        key, idx, err = parse_string(str, idx)
        if err then
            return nil, idx, err
        end
        idx = skip_ws(str, idx)
        if str:sub(idx, idx) ~= ':' then
            return nil, idx, json_error("Expected ':'", idx)
        end
        idx = skip_ws(str, idx + 1)
        local value
        value, idx, err = parse_value(str, idx)
        if err then
            return nil, idx, err
        end
        obj[key] = value
        idx = skip_ws(str, idx)
        local c = str:sub(idx, idx)
        if c == ',' then
            idx = idx + 1
            idx = skip_ws(str, idx)
        elseif c == '}' then
            return obj, idx + 1
        else
            return nil, idx, json_error("Expected ',' or '}'", idx)
        end
    end
    return nil, idx, json_error("Unterminated object", idx)
end

function parse_value(str, idx)
    idx = skip_ws(str, idx)
    local c = str:sub(idx, idx)
    if c == '"' then
        return parse_string(str, idx)
    elseif c == '{' then
        return parse_object(str, idx)
    elseif c == '[' then
        return parse_array(str, idx)
    elseif c == 't' then
        return parse_literal(str, idx, "true", true)
    elseif c == 'f' then
        return parse_literal(str, idx, "false", false)
    elseif c == 'n' then
        return parse_literal(str, idx, "null", nil)
    else
        return parse_number(str, idx)
    end
end

local function json_decode(str)
    local value, idx, err = parse_value(str, 1)
    if err then
        error("JSON decode error: " .. err.message .. " at index " .. err.index)
    end
    return value
end

-----------------------------------------------------------------------
-- Fire Red specific memory addresses --------------------------------
-----------------------------------------------------------------------

local WATCHERS = {
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
    { name = "enemy_species", address = 0x020240A8, size = 2, type = "u16" },
}

local function read_value(watcher)
    if watcher.size == 1 then
        return memory.readbyte(watcher.address)
    elseif watcher.size == 2 then
        return memory.readword(watcher.address)
    elseif watcher.size == 4 then
        return memory.readdword(watcher.address)
    else
        error("Unsupported watcher size: " .. tostring(watcher.size))
    end
end

local function gather_state()
    local snapshot = {}
    for _, watcher in ipairs(WATCHERS) do
        snapshot[watcher.name] = read_value(watcher)
    end
    snapshot.frame = emu.framecount()
    return snapshot
end

-----------------------------------------------------------------------
-- Networking ---------------------------------------------------------
-----------------------------------------------------------------------

local server = assert(socket.bind(HOST, PORT))
server:settimeout(0)

local client = nil
local pending_macro = nil
local macro_step_index = 1
local macro_step_timer = 0
local current_input = {}

local function accept_client()
    if client then
        return
    end
    local new_client = server:accept()
    if new_client then
        dbg("Client connected")
        new_client:settimeout(0)
        client = new_client
        pending_macro = nil
        macro_step_index = 1
        macro_step_timer = 0
        current_input = {}
    end
end

local function clear_client()
    if client then
        dbg("Client disconnected")
        client:close()
    end
    client = nil
    pending_macro = nil
    macro_step_index = 1
    macro_step_timer = 0
    current_input = {}
end

local function set_input(buttons)
    current_input = {}
    if buttons then
        for _, button in ipairs(buttons) do
            current_input[button] = true
        end
    end
end

local function apply_input()
    joypad.set(current_input)
end

local function start_macro(macro)
    if not macro then
        return
    end
    pending_macro = macro
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
        if pending_macro then
            pending_macro = nil
        end
        set_input(cmd.buttons)
    elseif cmd.type == "macro" then
        start_macro(cmd.steps)
    elseif cmd.type == "reset" then
        pending_macro = nil
        set_input(nil)
    end
end

local function pump_commands()
    if not client then
        return
    end
    while true do
        local line, err = client:receive("*l")
        if not line then
            if err == "timeout" then
                break
            else
                clear_client()
                break
            end
        end
        if line and #line > 0 then
            local ok, decoded = pcall(json_decode, line)
            if ok then
                process_command(decoded)
            else
                dbg("Failed to decode command: " .. tostring(decoded))
            end
        end
    end
end

local function send_state(state)
    if not client then
        return
    end
    local payload = json_encode({ type = "state", data = state }) .. "\n"
    local ok, err = client:send(payload)
    if not ok then
        clear_client()
    end
end

local function on_frame()
    accept_client()
    pump_commands()
    step_macro()
    apply_input()
    if client then
        local state = gather_state()
        send_state(state)
    end
end

event.onframestart(on_frame)

dbg(string.format("Listening on %s:%d", HOST, PORT))
