local socket = require("socket")

local debugserver = {}
local server
local msgParser = function(msg)
    -- Default message parser function
end

function debugserver.startServer(portNumber, hookFn)
    server = assert(socket.tcp(), "Failed to create TCP socket")
    server:settimeout(0) -- Set the socket to non-blocking mode

    local success, err = server:bind("*", portNumber)
    if not success then
        print("Error: Debug server not started. server:bind() error: " .. err)
        return false
    end

    success, err = server:listen()
    if not success then
        print("Error: Debug server not started. server:listen() error: " .. err)
        return false
    end

    msgParser = hookFn or msgParser

    if not server then
        print("Error: Debug server not started.")
        return false
    end

    print("Debug server started on port " .. portNumber)
    return true
end

function debugserver.receive()
    if not server then
        print("Error: Debug server not started.")
        return ""
    end

    local client, err = server:accept()
    if err and err~="timeout" then
        print("Error:",err)
    end
    if client then
        local message, receive_err = client:receive("*l") -- Read a line from the client
        if not receive_err and message then
            msgParser(message)
        end
        client:close()
        return message or ""
    end

    return ""
end

return debugserver
