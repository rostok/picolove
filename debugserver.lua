-- debugserver.lua
local socket = require("socket")

local debugserver = {}
local server

function debugserver.startServer(portNumber)
  server = assert(socket.tcp())
  server:settimeout(0) -- Set the socket to non-blocking mode
  server:bind("*", portNumber)
  server:listen()

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
    client:close()

    return message
  end

  return ""
end

return debugserver
