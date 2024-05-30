-- debugserver.lua
local socket = require("socket")

local debugserver = {}
local server
local msgParser = function(msg)
  -- print("[debugserver] got "..msg)
end

function debugserver.startServer(portNumber, hookFn)
  server = assert(socket.tcp())
  server:settimeout(0) -- Set the socket to non-blocking mode
  server:bind("*", portNumber)
  server:listen()
  msgParser = hookFn or msgParser
  print("Debug server started on port " .. portNumber)
end

function debugserver.receive()
  if not server then
    print("Error: Debug server not started.")
    return ""
  end

  local client = server:accept()

  if client then
    local message = client:receive("*l") -- Read a line from the client
    if message then msgParser(message) end
    client:close()

    return message
  end

  return ""
end

return debugserver
