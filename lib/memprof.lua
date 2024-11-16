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
        io.write("\27[32m")
        print("memprof: connected")
        io.write("\27[0m")
    else
        client = nil
        active = false
        io.write("\27[31m")
        print("memprof: Unable to connect to server, running without profiling")
        io.write("\27[0m")
    end
end

-- Pushes a new section onto the profiling stack
function memprof.push(section_name)
    if not active then return end
    if #stack == 0 then
        -- New frame if topmost section
        -- client:send("S\n")
    end
    
    local mem_usage = collectgarbage("count")
    table.insert(stack, section_name)
    client:send(string.format("U%s %.2f\n", section_name, mem_usage))
    -- client:send("PUSH ")
    -- client:send(section_name)
    -- client:send(" ")
    -- client:send(mem_usage)
    -- client:send("\n")
    collectgarbage("stop")
end

-- Pops the current section from the profiling stack
function memprof.pop()
    if not active or #stack == 0 then return end
    
    local mem_usage = collectgarbage("count")
    local section = table.remove(stack)
    client:send(string.format("O%s %.2f\n", section, mem_usage))
    -- client:send("POP ")
    -- client:send(section)
    -- client:send(" ")
    -- client:send(mem_usage)
    -- client:send("\n")
    
    if #stack == 0 then
        client:send("E\n")
    end
    collectgarbage("restart")
end

-- function memprof.push(section_name) end
-- function memprof.pop(section_name) end

return memprof