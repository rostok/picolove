local socket = require("socket")

local debugserver = {}
local server
local clients = {}

function debugserver.startServer(portNumber)
    -- always IPv4: with tcp() + "*" one instance may get [::] and another 0.0.0.0, both on the same port
    server = assert(socket.tcp4(), "Failed to create TCP socket")
    server:settimeout(0)
    -- luasocket turns reuseaddr on: a second instance would bind and listen on a busy port without an error
    server:setoption("reuseaddr", false)

    local ok, err = server:bind("0.0.0.0", portNumber)
    if not ok then
        print("Debug server port " .. portNumber .. " not available: " .. err)
        server:close()
        server = nil
        return false
    end

    ok, err = server:listen()
    if not ok then
        print("Error: Debug server not started. server:listen() error: " .. err)
        server = nil
        return false
    end

    print("Debug server started on port " .. portNumber)
    return true
end

function debugserver.stopServer()
    for _, c in ipairs(clients) do c:close() end
    clients = {}
    if server then server:close() server = nil end
end

-- non-blocking: accept any pending clients, then read any pending lines from
-- existing clients. returns a list of received messages (may be empty).
-- drops clients on closed/reset; keeps them on "timeout" (no data yet).
function debugserver.update()
    local messages = {}
    if not server then return messages end

    while true do
        local client = server:accept()
        if not client then break end
        client:settimeout(0)
        clients[#clients+1] = client
    end

    local i = 1
    while i <= #clients do
        local c = clients[i]
        local drop = false
        while true do
            local line, err = c:receive("*l")
            if line then
                messages[#messages+1] = line
            else
                if err ~= "timeout" then drop = true end
                break
            end
        end
        if drop then
            c:close()
            table.remove(clients, i)
        else
            i = i + 1
        end
    end

    return messages
end

-- send a single line to every connected client. drops clients on any
-- non-timeout error; drops on partial/timeout writes too (no per-client queue).
function debugserver.broadcast(line)
    if not server or #clients == 0 then return end
    local data = line .. "\n"
    local i = 1
    while i <= #clients do
        local c = clients[i]
        local _, err = c:send(data)
        if err then
            c:close()
            table.remove(clients, i)
        else
            i = i + 1
        end
    end
end

-- log wrapper
function debugserver.logbroadcast(...)
    local n = select("#", ...)
    local parts = {}
    for i = 1, n do parts[i] = tostring(select(i, ...)) end
    debugserver.broadcast(table.concat(parts, "\t"))
end


return debugserver