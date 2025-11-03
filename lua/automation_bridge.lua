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

local function try_comm_socket_shim()
    local comm = rawget(_G, "comm")
    if not comm then
        return nil, "BizHawk comm API unavailable"
    end

    local function pick(...)
        for i = 1, select("#", ...) do
            local name = select(i, ...)
            local fn = comm[name]
            if fn then
                return fn
            end
        end
        return nil
    end

    local socketServerOpen = pick("socketServerOpen", "socketServerStart", "socketServerListen")
    local socketServerClose = pick("socketServerClose", "socketServerStop")
    local socketServerIsConnected = pick("socketServerIsConnected", "socketServerConnected")
    local socketServerSend = pick("socketServerSend", "socketServerSendLine", "socketServerSendText")
    local socketServerPeek = pick("socketServerPeek", "socketServerReceive", "socketServerRead")
    local socketServerReceive = pick("socketServerReceive", "socketServerRecv", "socketServerReadLine")

    if not (socketServerOpen and socketServerClose and socketServerIsConnected and socketServerSend and socketServerPeek) then
        return nil, "BizHawk comm API is missing socket server helpers"
    end

    local shim = {}

    function shim.bind(_, port)
        socketServerClose()
        socketServerOpen(port)

        local server = {
            _client = nil,
            _buffer = ""
        }

        function server:settimeout(_)
            -- Non-blocking behaviour is implemented by returning "timeout" when
            -- no data is available, matching LuaSocket semantics.
        end

        local function reopen()
            socketServerClose()
            socketServerOpen(port)
            server._client = nil
            server._buffer = ""
        end

        function server:accept()
            if not socketServerIsConnected() then
                if server._client then
                    -- Client disconnected without us noticing; reset state so we
                    -- can accept a new connection once it arrives.
                    reopen()
                end
                return nil
            end

            if server._client then
                return server._client
            end

            local client = {}

            function client:settimeout(_)
            end

            function client:close()
                reopen()
            end

            function client:send(payload)
                local result = socketServerSend(payload)
                if result == false then
                    reopen()
                    return nil, "closed"
                end
                return true
            end

            function client:receive(pattern)
                if pattern ~= "*l" then
                    error("BizHawk socket shim only supports receive pattern '*l'")
                end

                if not socketServerIsConnected() then
                    reopen()
                    return nil, "closed"
                end

                while true do
                    local newline = server._buffer:find("\n", 1, true)
                    if newline then
                        local line = server._buffer:sub(1, newline - 1)
                        server._buffer = server._buffer:sub(newline + 1)
                        return line
                    end

                    local chunk = socketServerPeek()
                    if socketServerReceive then
                        local received = socketServerReceive()
                        if received and #received > 0 then
                            chunk = received
                        end
                    end

                    if chunk and #chunk > 0 then
                        server._buffer = server._buffer .. chunk
                    else
                        return nil, "timeout"
                    end
                end
            end

            server._client = client
            return client
        end

        return server
    end

    return shim
end

local function try_luanet_socket_shim()
    local ok_luanet, luanet = pcall(require, "luanet")
    if not ok_luanet or not luanet then
        return nil, "luanet module unavailable"
    end

    local ok_load, load_err = pcall(luanet.load_assembly, "System")
    if not ok_load then
        return nil, load_err or "failed to load System assembly"
    end

    local IPAddress = luanet.import_type("System.Net.IPAddress")
    local TcpListener = luanet.import_type("System.Net.Sockets.TcpListener")
    local LingerOption = luanet.import_type("System.Net.Sockets.LingerOption")
    local Encoding = luanet.import_type("System.Text.Encoding")
    local Byte = luanet.import_type("System.Byte")

    if not (IPAddress and TcpListener and LingerOption and Encoding and Byte) then
        return nil, "required .NET networking types unavailable"
    end

    local encoding = Encoding.UTF8

    local function to_ip(host)
        if host == "*" or host == "0.0.0.0" then
            return IPAddress.Any
        end

        local ok_parse, parsed = pcall(IPAddress.Parse, host)
        if ok_parse and parsed then
            return parsed
        end

        return IPAddress.Loopback
    end

    local shim = {}

    function shim.bind(host, port)
        local listener = TcpListener(to_ip(host or "127.0.0.1"), port)
        listener:Start()
        listener.Server.Blocking = false

        local server = {
            _listener = listener,
            _client = nil,
            _stream = nil,
            _buffer = ""
        }

        local function reset_client()
            if server._stream then
                server._stream:Close()
                server._stream = nil
            end
            if server._client then
                server._client:Close()
                server._client = nil
            end
            server._client_wrapper = nil
            server._buffer = ""
        end

        function server:settimeout(_)
            -- Handled by returning "timeout" when no data is currently buffered.
        end

        function server:accept()
            if server._client and server._client.Connected then
                return server._client_wrapper
            elseif server._client then
                reset_client()
            end

            local pending = false
            local ok_pending, pending_result = pcall(server._listener.Pending, server._listener)
            if ok_pending then
                pending = pending_result
            end

            if not pending then
                return nil
            end

            local ok_accept, client = pcall(server._listener.AcceptTcpClient, server._listener)
            if not ok_accept or not client then
                return nil
            end

            client.NoDelay = true
            client.LingerState = LingerOption(false, 0)
            client.ReceiveTimeout = 0
            client.SendTimeout = 0

            local stream = client:GetStream()
            stream.ReadTimeout = 1
            stream.WriteTimeout = 1

            server._client = client
            server._stream = stream
            server._buffer = ""

            local wrapper = {}

            function wrapper:settimeout(_)
            end

            function wrapper:close()
                reset_client()
            end

            function wrapper:send(payload)
                if not server._client or not server._client.Connected then
                    reset_client()
                    return nil, "closed"
                end

                local bytes = encoding:GetBytes(payload)
                local ok_write = pcall(function()
                    stream:Write(bytes, 0, bytes.Length)
                    stream:Flush()
                end)

                if not ok_write then
                    reset_client()
                    return nil, "closed"
                end

                return true
            end

            function wrapper:receive(pattern)
                if pattern ~= "*l" then
                    error("BizHawk luanet socket shim only supports receive pattern '*l'")
                end

                while true do
                    if not server._client or not server._client.Connected then
                        reset_client()
                        return nil, "closed"
                    end

                    local newline = server._buffer:find("\n", 1, true)
                    if newline then
                        local line = server._buffer:sub(1, newline - 1)
                        server._buffer = server._buffer:sub(newline + 1)
                        return line
                    end

                    local available = server._client.Available
                    if available == 0 then
                        return nil, "timeout"
                    end

                    local buffer = luanet.make_array(Byte, available)
                    local read = stream:Read(buffer, 0, available)
                    if read == 0 then
                        reset_client()
                        return nil, "closed"
                    end

                    local chunk = encoding:GetString(buffer, 0, read)
                    server._buffer = server._buffer .. chunk
                end
            end

            server._client_wrapper = wrapper
            return wrapper
        end

        function server:close()
            reset_client()
            server._listener:Stop()
        end

        return server
    end

    return shim
end

local ok_socket, socket = pcall(require, "socket")
if not ok_socket or not socket then
    local comm_socket, comm_err = try_comm_socket_shim()
    if comm_socket then
        socket = comm_socket
    else
        local luanet_socket, luanet_err = try_luanet_socket_shim()
        if luanet_socket then
            socket = luanet_socket
        else
            error(luanet_err or comm_err or "LuaSocket module not found and BizHawk comm API unavailable. Please enable one of them.")
        end
    end
end
local event = event or require("event")
local joypad = joypad or joypad
local memory = memory
local emu = emu

-- BizHawk uses a different joypad API signature (controller index first).
-- We detect the signature at runtime so the script stays compatible with
-- both mGBA and BizHawk without any manual changes.
local JOYPAD_SET_NEEDS_PORT = false
if joypad and joypad.set then
    local ok = pcall(joypad.set, {})
    if not ok then
        JOYPAD_SET_NEEDS_PORT = true
    end
end

-- BizHawk exposes memory domains; default to "System Bus" when available so
-- absolute addresses can still be used.
local MEMORY_DOMAIN = nil
if memory and memory.getcurrentmemorydomain and memory.usememorydomain then
    local current = memory.getcurrentmemorydomain()
    if not current or current == "" then
        pcall(memory.usememorydomain, "System Bus")
        current = memory.getcurrentmemorydomain()
    end
    MEMORY_DOMAIN = current
end

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
    if watcher.size == 1 then
        return read_u8(watcher.address)
    elseif watcher.size == 2 then
        return read_u16(watcher.address)
    elseif watcher.size == 4 then
        return read_u32(watcher.address)
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
    if JOYPAD_SET_NEEDS_PORT then
        joypad.set(1, current_input)
    else
        joypad.set(current_input)
    end
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
