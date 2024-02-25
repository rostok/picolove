local clock = os.clock

--- Simple profiler written in Lua.
-- @module profile
-- @alias profile
local profile = {}

-- function labels
local _labeled = {}
-- function definitions
local _defined = {}
-- time of last call
local _tcalled = {}
-- total execution time
local _telapsed = {}
-- number of calls
local _ncalls = {}
-- list of internal profiler functions
local _internal = {}


-- table where keys are stack functions separated by '/' and value is total time spent in that function
local _stacktime = {}

local function GetStack(depth,...)
  -- depth = depth or 3
  local output, sep, info = "", ""
  while true do
      info = debug.getinfo(3 + depth)
      if not info then break end
      output =  (info.name or "?") .. sep .. output
      sep = "/"
      depth = depth + 1
      local shoudBreak = false
      for _,v in pairs(arg) do
        if info.name==v then shoudBreak=true end
      end
      if shoudBreak then break end
  end
  return output, depth
end

function profile.flamebuilder(event, line, info)
  -- Generate the stack key
  local stack_key, depth = GetStack(1, "_update", "_draw")

  local cur = _stacktime[stack_key]
  local val = cur or {}
  -- Handle call and return events differently
  if event == 'call' then
      -- Record the time the function was called
        val.call = clock()
        -- val.info = info
        val.info = {linedefined=info.linedefined,lastlinedefined=info.lastlinedefined,name=info.name,source=info.source,short_src=info.short_src}
        val.depth = depth-1
        val.stack = stack_key
        val.n = (val.n or 0)+1
        _stacktime[stack_key] = val
  elseif event == 'return' then
      -- Check if there's a recorded call time for this stack
      local call_time = val and val.call or nil
      if call_time then
          -- Calculate the time spent in the function
          local elapsed_time = clock() - call_time
          -- Update the total time spent in this stack
          val.time = (val.time or 0) + elapsed_time
          -- Clear the recorded call time for this stack
          val.call = nil
          _stacktime[stack_key] = val
      end
  end
end

local function getFunctionDeclaration(info)
  local declaration = ""

  if info.source and info.linedefined and info.lastlinedefined then
      if info.source:sub(1, 1) == "@" then
          -- Source is a file
          declaration = string.format("%s:%d-%d", info.source:sub(2), info.linedefined, info.lastlinedefined)
      else
          -- Source is a string
          local lines = {}
          for line in string.gmatch(info.source, "[^\n]+") do
              table.insert(lines, line)
          end
          local startLine = info.linedefined
          local endLine = info.lastlinedefined
          if startLine >= 1 and endLine <= #lines then
              for i = startLine, endLine do
                  declaration = declaration .. lines[i] .. "\n"
              end
          end
      end
  end
  if info.name then
      declaration = string.format("%s (%s)", declaration, info.name)
  end
  return declaration
end

function profile.parse(depth, parent, startTime)
  local o = ""
  for stack, val in pairs(_stacktime) do
      local time = val.time or 0
      local functions = {}
      for func in string.gmatch(stack, "[^/]+") do
          table.insert(functions, func)
      end
      if #functions == depth and (parent == "" or string.sub(stack, 1, #parent) == parent) then
          local currentFunction = functions[depth]
          local currentFunctionStack = parent .. (parent == "" and "" or "/") .. currentFunction
          o = o .. string.format(
              '{"name": "%s", "cat": "function", "ph": "B", "ts": %d, "pid": 0, "tid": 0},',
              currentFunction, startTime
          )
          -- local innerOutput, newStartTime = profile.parse(depth + 1, currentFunctionStack, startTime)
          local innerOutput, newStartTime = profile.parse(depth + 1, stack, startTime)
          o = o .. innerOutput
          startTime = startTime + (time * 1000)  -- Assuming time is in seconds, convert to milliseconds
          o = o .. string.format(
              '{"name": "%s", "cat": "function", "ph": "E", "ts": %d, "pid": 0, "tid": 0, "args":{"declaration":"%s","defined":"%s","source":"%s","stack":"%s","num_calls":"%s"}},',
              currentFunction, startTime, val.declaration, val.defined, val.source, val.stack, val.n
          )
      end
  end
  return o, startTime
end

local function sanitize(str)
  local sanitized = str or ""
  sanitized = sanitized:gsub("\\", "\\\\")  -- Escape backslashes
  sanitized = sanitized:gsub("''", "\\'")  -- Escape double quotes
  sanitized = sanitized:gsub("\"", "\\\"")  -- Escape double quotes
  sanitized = sanitized:gsub("\n", "\\n")   -- Escape newlines
  sanitized = sanitized:gsub("\r", "\\r")   -- Escape carriage returns
  sanitized = sanitized:gsub("\t", "\\t")   -- Escape tabs
  return sanitized
end

function profile.tracingJSON()
  -- sanitize
  local minimalStackDepth = 999999999
  for stack, val in pairs(_stacktime) do
    -- val.source = info.source
    val.defined = sanitize(val.info.short_src..":"..val.info.linedefined)
    val.declaration = sanitize(getFunctionDeclaration(val.info))
    val.source = sanitize(val.info.source)
    val.stack = sanitize(val.stack)
    minimalStackDepth = math.min( minimalStackDepth, val.depth )
  end
  local output, totaltime = profile.parse(minimalStackDepth, "", 0)
  if output ~= "" then
      -- Remove trailing comma and wrap in brackets to form a valid JSON array
      output = "[" .. string.sub(output, 1, -2) .. "]"
  else
      output = "[]"
  end
  return output
end

function profile.flameHTML(dataFile,extraContent)
  extraContent = extraContent or ""
  local dataScript = dataFile and "<script src="..dataFile.."></script>" or "<script>"..profile.flameJS().."</script>"
  local o = [[<html>
  <style>
  a, body {
      color: white;
      background-color:gray;
      font-family: 'Arial Narrow', Arial, sans-serif;
      font-stretch: condensed;
      overflow-x:scroll;
  }
  .bar {
      font-size: 12px;
      position: absolute;
      background-color: #3498db;
      height: 24px;
      line-height: 24px;
      text-align: center;
      border: 1px solid #8af;
      overflow: hidden;  
  }
  .bar:hover {
      background-color: yellow; 
      color:black;
      display: block; 
  }
  .tooltip {
      font-size: 12px;
      line-height: 12px;
      display: none; 
      position: absolute;
      border: 1px solid #333;
      background-color: #fff;
      color: #333;
      padding: 10px;
      white-space: nowrap; 
      z-index: 10; 
      text-align: left;
  }
  #scd {
	position: absolute;
    bottom: 10px;
	left: 10px;
  }
  </style>
  <body>
  <div id=scd><pre>]]..extraContent..[[</pre><input id=scale value=0 size=1></input>
  <a href=# onclick='scale=width/maxtime;go();'>0</a>
  <a href=# onclick='scale=100;go();'>100</a>
  <a href=# onclick='scale=250;go();'>250</a>
  <a href=# onclick='scale=500;go();'>500</a>
  <a href=# onclick='scale=1000;go();'>1000</a>
  <a href=# onclick='scale=2000;go();'>2000</a>
  </div>
  ]]..dataScript..[[
  <script>
  let width = document.documentElement.clientWidth-8;
  var maxtime = Math.max(...data.map(obj => obj.time));
  var scale = width/maxtime;
  var minstack = Math.min(...data.map(obj => obj.depth = obj.stack.split('/').length));
  var names = [...new Set(data.map(obj => obj.name))].sort().reduce((acc, name, idx) => ({ ...acc, [name]: idx }), {});
  var totalCalls = {};
  data.forEach(d => totalCalls[d.name] = (totalCalls[d.name] || 0) + d.n);
  data.forEach(d => d.totalCalls = totalCalls[d.name]);
  var totalTime = {};
  data.forEach(d => totalTime[d.name] = (totalTime[d.name] || 0) + d.time);
  data.forEach(d => d.totalTime = totalTime[d.name]);

  function stringToColor(str) { return `hsl(${(360 * names[str]) / Object.keys(names).length},50%,50%)`;  }
  
  function bar(x, y, w, t, d) {
      var bar = document.createElement('div');
      bar.className = 'bar';
      bar.style.left = 4+x + 'px';
      bar.style.top = 4+y + 'px';
      bar.style.width = w + 'px';
      bar.innerHTML = t;
      bar.style.backgroundColor = stringToColor(t);
      var tooltip = document.createElement('div');
      tooltip.className = 'tooltip';
      tooltip.innerHTML = 'name,source,defined,declaration,n,time,totalCalls,totalTime'.split(',').map(s=>`${s}:${d[s]}`).join('<br>');
  
      bar.addEventListener('mousemove', function(e) {
          tooltip.style.left = (e.clientX + 10) + 'px';
          tooltip.style.top  = (e.clientY + 10) + 'px';
      });
      bar.addEventListener('mouseout', function() { tooltip.style.display = 'none'; });
      bar.addEventListener('mouseover', function() { tooltip.style.display = 'block'; });
  
      document.body.appendChild(tooltip);
      document.body.appendChild(bar);
      console.log(tooltip.width);
  }
  function rec(depth,parent='',startTime=0) {
    data.filter(d=>d.depth==depth && (parent=='' || d.stack.startsWith(parent)) ).sort((a, b) => a.name.localeCompare(b.name)).forEach(d=>{
      var x = startTime*scale;
      var y = (depth-minstack)*25;
      var w = d.time*scale;
      bar(x,y,w,d.name,d);
      rec(depth+1,d.stack,startTime);
      startTime += d.time;
    });
  }
  function go() {
    document.querySelectorAll('div.bar,div.toolbar').forEach(d=>d.remove())
    rec(minstack)
  }
  go()
  document.getElementById('scale').addEventListener('change', function(event) {
  	var v = parseFloat(event.target.value)||0;
  	scale = v==0 ? width/maxtime : v;
  	go()
  });
  </script>
  </body>    
  </html>]]
  return o;
end

function profile.flameJS()
  local o = "data = [\n";
  for stack, v in pairs(_stacktime) do
    o = o..string.format("{time:%s,name:'%s',stack:'%s',source:'%s',defined:'%s',declaration:'%s',n:%s},\n",
    v.time or 0,sanitize(v.info.name),sanitize(v.stack),sanitize(v.source),sanitize(v.defined),sanitize(v.declaration),v.n)
  end
  o = o.."\n];"
  return o;
end

--- This is an internal function.
-- @tparam string event Event type
-- @tparam number line Line number
-- @tparam[opt] table info Debug info table
function profile.hooker(event, line, info)
  info = info or debug.getinfo(2, 'fnS')
  local f = info.func
  -- ignore the profiler itself
  if _internal[f] or info.what ~= "Lua" then
    return
  end

  profile.flamebuilder(event,line,info)
  -- get the function name if available
  if info.name then
    _labeled[f] = info.name
  end
  -- find the line definition
  if not _defined[f] then
    _defined[f] = info.short_src..":"..info.linedefined
    _ncalls[f] = 0
    _telapsed[f] = 0
  end
  if _tcalled[f] then
    local dt = clock() - _tcalled[f]
    _telapsed[f] = _telapsed[f] + dt
    _tcalled[f] = nil
  end
  if event == "tail call" then
    local prev = debug.getinfo(3, 'fnS')
    profile.hooker("return", line, prev)
    profile.hooker("call", line, info)
  elseif event == 'call' then
    _tcalled[f] = clock()
  else
    _ncalls[f] = _ncalls[f] + 1
  end
end

--- Sets a clock function to be used by the profiler.
-- @tparam function func Clock function that returns a number
function profile.setclock(f)
  assert(type(f) == "function", "clock must be a function")
  clock = f
end

--- Starts collecting data.
function profile.start()
  if rawget(_G, 'jit') then
    jit.off()
    jit.flush()
  end
  debug.sethook(profile.hooker, "cr")
end

--- Stops collecting data.
function profile.stop()
  debug.sethook()
  for f in pairs(_tcalled) do
    local dt = clock() - _tcalled[f]
    _telapsed[f] = _telapsed[f] + dt
    _tcalled[f] = nil
  end
  -- merge closures
  local lookup = {}
  for f, d in pairs(_defined) do
    local id = (_labeled[f] or '?')..d
    local f2 = lookup[id]
    if f2 then
      _ncalls[f2] = _ncalls[f2] + (_ncalls[f] or 0)
      _telapsed[f2] = _telapsed[f2] + (_telapsed[f] or 0)
      _defined[f], _labeled[f] = nil, nil
      _ncalls[f], _telapsed[f] = nil, nil
    else
      lookup[id] = f
    end
  end
  collectgarbage('collect')
  -- enable JIT if avaialbe
  if rawget(_G, 'jit') then
    jit.on()
  end
end

--- Resets all collected data.
function profile.reset()
  _stacktime = {}

  for f in pairs(_ncalls) do
    _ncalls[f] = 0
  end
  for f in pairs(_telapsed) do
    _telapsed[f] = 0
  end
  for f in pairs(_tcalled) do
    _tcalled[f] = nil
  end
  collectgarbage('collect')
end

--- This is an internal function.
-- @tparam function a First function
-- @tparam function b Second function
function profile.comp(a, b)
  local dt = _telapsed[b] - _telapsed[a]
  if dt == 0 then
    return _ncalls[b] < _ncalls[a]
  end
  return dt < 0
end

--- Iterates all functions that have been called since the profile was started.
-- @tparam[opt] number limit Maximum number of rows
function profile.query(limit)
  local t = {}
  for f, n in pairs(_ncalls) do
    if n > 0 then
      t[#t + 1] = f
    end
  end
  table.sort(t, profile.comp)
  if limit then
    while #t > limit do
      table.remove(t)
    end
  end
  for i, f in ipairs(t) do
    local dt = 0
    if _tcalled[f] then
      dt = clock() - _tcalled[f]
    end
    t[i] = { i, _labeled[f] or '?', _ncalls[f], _telapsed[f] + dt, (_telapsed[f] + dt)*1000/_ncalls[f], _defined[f] }
  end
  return t
end

local cols = { 3, 29, 8, 10, 13, 52 }
local rightalign = { true, false, true, true, true, false }

--- Generates a text report.
-- @tparam[opt] number limit Maximum number of rows
function profile.report(n)
  local out = {}
  local report = profile.query(n)
  for i, row in ipairs(report) do
    for j = 1, 6 do
      local s = row[j]
      local l2 = cols[j]
      local ra = rightalign[j]
      if j==4 or j==5 then s = string.format("%.6f", s) end
      s = tostring(s)
      local l1 = s:len() or 0
      if l1 < l2 then
        if ra then 
          s = (' '):rep(l2-l1)..s
        else
          s = s..(' '):rep(l2-l1)
        end
      elseif l1 > l2 then
        s = s:sub(l1 - l2 + 1, l1)
      end
      row[j] = s
    end
    out[i] = table.concat(row, ' | ')
  end

  local row = " +-----+-------------------------------+----------+------------+---------------+------------------------------------------------------+ \n"
  local col = " | #   | Function                      | Calls    | Time (s)   | Per Call (ms) |Code                                                  | \n"
  local sz = row..col..row
  if #out > 0 then
    sz = sz..' | '..table.concat(out, ' | \n | ')..' | \n'
  end
  return sz..row
end

-- store all internal profiler functions
for _, v in pairs(profile) do
  if type(v) == "function" then
    _internal[v] = true
  end
end

return profile