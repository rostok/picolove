-- memprof_server.lua (UDP version): A simple server for memprof using UDP
local socket = require("socket")

local server = socket.udp()
server:setsockname("127.0.0.1", 1337)
server:settimeout(0)

local frames = {}
local current_frame = nil
local frame_count = 0

io.write("\27[2J\27c\27[H")

local function cls()
    io.write("\27[2J\27c\27[H")
end

-- Function to clear terminal lines
local function clear_terminal_lines(num_lines)
    io.write("\27[u")  -- Restore cursor position
--    for i = 1, num_lines do io.write("\r\27[2K\n") end
--    io.write("\27[u")  -- Restore cursor position
    io.write("\27[s")  -- Save cursor position
end

-- Function to display frame data
local function print_stats()
    local frame = frames[#frames]
    local terminator = string.rep(" ", 20)
--    print(string.format("Memory allocated, Frame %d", frame_count))
    for _, section in ipairs(frame.sections) do
--        print(string.format("%8.2f KB %s", section.memory, string.rep(" ", section.level * 4) .. section.name .. terminator))
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
    for _, section in ipairs(frame.sections) do
        local data = avg_data[section.name]
        if data then
            print(string.format("%8.2f KB %s", data.total / data.count, string.rep(" ", section.level * 4) .. section.name .. terminator))
        end
    end
    print(string.rep("-", 40))

    -- Calculate and display max values over all frames
    local max_data = {}
    for _, past_frame in ipairs(frames) do
        for _, past_section in ipairs(past_frame.sections) do
            max_data[past_section.name] = math.max(max_data[past_section.name] or 0, past_section.memory)
        end
    end

    print("Max values over all frames:")
    for _, section in ipairs(frame.sections) do
        local max_value = max_data[section.name]
        if max_value then
            print(string.format("%8.2f KB %s", max_value, string.rep(" ", section.level * 4) .. section.name .. terminator))
        end
    end
    print(string.rep("-", 40))
end

-- Function to retain only the latest number of frames
local function frame_retention(number)
    while #frames > number do
        table.remove(frames, 1)
    end
end

cls()
while true do
    local data, ip, port = server:receivefrom()
    if data then
        if data == "CLEAR" then
            frames = {}
            current_frame = nil
            frame_count = 0
            cls()
        elseif data:match("^PUSH") then
            if not current_frame then
                frame_count = frame_count + 1
                current_frame = {sections = {}, level_stack = {}}  -- Added level_stack to manage nesting
                table.insert(frames, current_frame)
            end
            local section_name, memory = data:match("PUSH ([^%s]+) ([%d%.]+)")
            memory = tonumber(memory)
            local current_level = #current_frame.level_stack
            local existing_section = nil
            for _, section in ipairs(current_frame.sections) do
                if section.name == section_name and section.level == current_level then
                    existing_section = section
                    break
                end
            end
            if existing_section then
                existing_section.memory = existing_section.memory + (memory - existing_section.start_mem)
                existing_section.start_mem = memory
            else
                table.insert(current_frame.sections, {name = section_name, start_mem = memory, level = current_level, memory = 0})
            end
            table.insert(current_frame.level_stack, section_name)  -- Keep track of current nesting level
        elseif data:match("^POP") then
            if current_frame then
                local section_name, memory = data:match("POP ([^%s]+) ([%d%.]+)")
                memory = tonumber(memory)
                for _, section in ipairs(current_frame.sections) do
                    if section.name == section_name then
                        section.memory = section.memory + (memory - section.start_mem)
                        break
                    end
                end
                table.remove(current_frame.level_stack)  -- Remove the section from the level stack
                if #current_frame.level_stack == 0 then
                    clear_terminal_lines(#current_frame.sections + 4)
                    print_stats()
                    current_frame = nil
                end
            end
        elseif data:match("^FRAME END") then
            if current_frame then
                clear_terminal_lines(#current_frame.sections + 4)
                print_stats()
                current_frame = nil
            end
            -- Display summary after frame ends
            local avg_data = {}
            for _, past_frame in ipairs(frames) do
                for _, past_section in ipairs(past_frame.sections) do
                    avg_data[past_section.name] = avg_data[past_section.name] or {total = 0, count = 0}
                    avg_data[past_section.name].total = avg_data[past_section.name].total + past_section.memory
                    avg_data[past_section.name].count = avg_data[past_section.name].count + 1
                end
            end
            -- Retain only the latest number of frames
            frame_retention(30)  -- Example retention of the latest 30 frames
        end
    end

    socket.sleep(0.0001)
end