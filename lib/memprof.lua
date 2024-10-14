-- memprof.lua (UDP version): A simple memory profiler for Love2D games using UDP
local socket = require("socket")

local memprof = {}
local client = nil
local stack = {}
local active = false

-- Initializes connection to the server and clears previous data
function memprof.init()
    client = socket.udp()
    client:setpeername("127.0.0.1", 1337)
    client:settimeout(0)
    local success = client:send("CLEAR\n")
    if success then
        active = true
        print("memprof: connected ++++++++++++++++++++++++++++++++++++++++++++")
    else
        print("---------------------------------------------------------------")
        print("memprof: Unable to connect to server, running without profiling")
        print("---------------------------------------------------------------")
        client = nil
        active = false
    end
end

-- Pushes a new section onto the profiling stack
function memprof.push(section_name)
    if not active then return end
    if #stack == 0 then
        -- New frame if topmost section
        client:send("FRAME\n")
    end
    
    local mem_usage = collectgarbage("count")
    table.insert(stack, section_name)
    client:send(string.format("PUSH %s %.2f\n", section_name, mem_usage))
    collectgarbage("stop")
end

-- Pops the current section from the profiling stack
function memprof.pop()
    if not active or #stack == 0 then return end
    
    local mem_usage = collectgarbage("count")
    local section = table.remove(stack)
    client:send(string.format("POP %s %.2f\n", section, mem_usage))
    
    if #stack == 0 then
        client:send("FRAME END\n")
    end
    collectgarbage("restart")
end

return memprof