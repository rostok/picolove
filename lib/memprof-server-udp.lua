-- memprof_server.lua: A simple server for memory profiling
local socket = require("socket")

local server = assert(socket.bind("127.0.0.1", 1337))
server:settimeout(nil)

local clients = {}
local frames = {}
local current_frame = nil

local function display_frame_data(frame)
    print(string.rep("-", 40))
    print(string.format("Frame %s", frame.number or "(No Number)"))
    for _, section in ipairs(frame.sections) do
        print(string.format("Memory allocated: %s %.2f KB", string.rep(" ", section.level * 4) .. section.name, section.memory))
    end
    print(string.rep("-", 40))

    -- Calculate and display averages over all frames
    local avg_data = {}
    for _, past_frame in ipairs(frames) do
        for _, past_section in ipairs(past_frame.sections) do
            avg_data[past_section.name] = avg_data[past_section.name] or {total = 0, count = 0}
            avg_data[past_section.name].total = avg_data[past_section.name].total + past_section.memory
            avg_data[past_section.name].count = avg_data[past_section.name].count + 1
        end
    end

    print("Averages over all frames:")
    for section_name, data in pairs(avg_data) do
        print(string.format("Memory allocated: %s %.2f KB", section_name, data.total / data.count))
    end
    print(string.rep("-", 40))
end

while true do
    -- Accept new client connections
    local client = server:accept()
    if client then
        client:settimeout(0)
        table.insert(clients, client)
    end

    -- Handle existing clients
    for i = #clients, 1, -1 do
        local c = clients[i]
        local line, err = c:receive()
        if not err then
            print(line);
            if line == "CLEAR" then
                frames = {}
                current_frame = nil
            elseif line:match("^FRAME") then
                local frame_number = line:match("FRAME (%d+)")
                current_frame = {number = frame_number, sections = {}}
                table.insert(frames, current_frame)
            elseif line:match("^PUSH") then
                local section_name, memory = line:match("PUSH ([^%s]+) ([%d%.]+)")
                memory = tonumber(memory)
                local level = #current_frame.sections
                table.insert(current_frame.sections, {name = section_name, memory = memory, level = level})
            elseif line:match("^POP") then
                local section_name, memory = line:match("POP ([^%s]+) ([%d%.]+)")
                memory = tonumber(memory)
                for _, section in ipairs(current_frame.sections) do
                    if section.name == section_name then
                        section.memory = memory - section.memory
                        break
                    end
                end
                if #current_frame.sections == 0 then
                    display_frame_data(current_frame)
                end
            elseif line == "FRAME END" then
                if current_frame then
                    display_frame_data(current_frame)
                end
                current_frame = nil
            end
        elseif err == "closed" then
            table.remove(clients, i)
        else
            print(err)
        end
    end

    socket.sleep(0.01)
end