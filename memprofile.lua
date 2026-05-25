-- memprofile.lua
-- Per-line memory allocation profiler for LÖVE/LuaJIT.
-- Hook writes events into a preallocated FFI buffer (outside Lua GC heap),
-- so the profiler itself does not allocate per event. GC is stopped during
-- profiling so collectgarbage("count") deltas reflect true allocations.
--
-- Usage:
--   local mp = require("memprofile")
--   mp.start(128 * 1024 * 1024)  -- buffer size in bytes, default 128 MB
--   ... code under test ...
--   mp.stop()
--   print(mp.report())           -- text report; arg 1 = row limit (default 50)
--   love.filesystem.write("memprofile.html", mp.reportHTML())  -- HTML w/ vscode:// links

local ffi = require("ffi")

local M = {}

-- Event layout: 4 doubles per event (32 bytes).
--   [0] event code: 1=call, 2=return, 3=line
--   [1] stack depth
--   [2] line number in combined cart (or -1 for call/return)
--   [3] memory in KB at the moment of the event
local FIELDS         = 4
local BYTES_PER_EVT  = FIELDS * 8
local DEFAULT_BYTES  = 128 * 1024 * 1024

local buf            -- ffi cdata: double[?]
local cap            -- capacity in events
local idx            -- next event slot
local depth          -- current stack depth (maintained by hook)
local overflowed     -- buffer filled up while running
local state          = "idle"  -- "idle" | "started" | "stopped"

-- ---------------------------------------------------------------------------
-- Hook
-- ---------------------------------------------------------------------------
-- Note: the hook must avoid creating Lua values that escape its local scope.
-- Strings used in comparisons are interned by LuaJIT, so == on event names is
-- a pointer compare, not an alloc. Buffer writes are FFI cdata stores.
local function hook(event, line)
	if idx >= cap then
		if not overflowed then
			overflowed = true
			debug.sethook()
			print(string.format(
				"memprofile: buffer overflow at %d events (~%.1f MB); hook stopped. Call memprofile.stop() to finalize.",
				cap, cap * BYTES_PER_EVT / 1024 / 1024))
		end
		return
	end

	local ec
	if event == "line" then
		ec = 3
	elseif event == "call" or event == "tail call" then
		depth = depth + 1
		ec = 1
	elseif event == "return" or event == "tail return" then
		depth = depth - 1
		ec = 2
	else
		return
	end

	local base = idx * FIELDS
	buf[base]     = ec
	buf[base + 1] = depth
	buf[base + 2] = line or -1
	buf[base + 3] = collectgarbage("count")
	idx = idx + 1
end

function M.state()
	return state
end
-- ---------------------------------------------------------------------------
-- Lifecycle
-- ---------------------------------------------------------------------------
function M.start(sizeBytes)
	if state == "started" then
		error("memprofile.start(): already running; call stop() first", 2)
	end

	sizeBytes = sizeBytes or DEFAULT_BYTES
	cap = math.floor(sizeBytes / BYTES_PER_EVT)
	if cap < 1024 then
		error("memprofile.start(): buffer too small (min ~32 KB)", 2)
	end

	print("memprofile start()")
	buf        = ffi.new("double[?]", cap * FIELDS)
	idx        = 0
	depth      = 0
	overflowed = false

	if rawget(_G, "jit") then
		jit.off()
		jit.flush()
	end
	collectgarbage("stop")
	collectgarbage("collect")  -- start from clean slate
	M._bracketStartCount = collectgarbage("count")

	debug.sethook(hook, "crl")
	state = "started"
end

function M.stop()
	if state ~= "started" then
		error("memprofile.stop(): not running", 2)
	end
	local endCount = collectgarbage("count")
	debug.sethook()
	collectgarbage("restart")
	if rawget(_G, "jit") then
		jit.on()
	end
	M._bracketEndCount = endCount
	M._bracketDeltaKB  = endCount - (M._bracketStartCount or endCount)
	print(string.format(
		"memprofile stop() — bracket NET: %.2f KB  (start=%.2f, end=%.2f)",
		M._bracketDeltaKB, M._bracketStartCount or 0, endCount))
	state = "stopped"
end

function M.reset()
	if state == "started" then
		error("memprofile.reset(): stop the profiler first", 2)
	end
	buf, cap, idx, depth, overflowed = nil, 0, 0, 0, false
	state = "idle"
end

function M.status()
	return {
		state = state,
		events = idx or 0,
		capacity = cap or 0,
		overflowed = overflowed or false,
	}
end

-- ---------------------------------------------------------------------------
-- Combined .p8 -> source-file line mapping
-- ---------------------------------------------------------------------------
-- combinelua.py inserts markers around #included content:
--   -- <abs_path>{{{
--   ...included file content...
--   -- }}}<abs_path>
-- Each marker occupies one line in the combined file. The opening marker
-- replaces the original #include line; the closing marker is purely synthetic.
-- This function returns a table indexed by combined-line, each entry being
-- { src = path, line = source_line }, or nil for closing-marker lines.
-- Normalize a path to forward slashes (suitable for vscode://file/ URLs).
local function fwd(p)
	return (p:gsub("\\", "/"))
end

-- Return absolute base dir (with trailing "/") used to resolve relative marker
-- paths emitted by combinelua.py. combinelua resolves include paths against
-- the CWD it was launched from (typically the love folder), so we anchor to
-- love.filesystem.getSource() at runtime.
local function getBaseDir()
	if love and love.filesystem and love.filesystem.getSource then
		local src = love.filesystem.getSource()
		if src and #src > 0 then
			src = fwd(src)
			if src:sub(-1) ~= "/" then src = src .. "/" end
			return src
		end
	end
	return ""
end

-- Resolve a marker path (possibly relative) to an absolute, forward-slashed path.
local function resolvePath(p, baseDir)
	p = fwd(p)
	-- Already absolute?  Either a leading "/" or "<drive>:".
	if p:sub(1, 1) == "/" or p:match("^%a:") then
		return p
	end
	return baseDir .. p
end

local function buildLineMap(combined_path)
	local data
	if love and love.filesystem and love.filesystem.read then
		data = love.filesystem.read(combined_path)
	end
	if not data then
		local f = io.open(combined_path, "rb")
		if not f then return nil, "cannot open " .. tostring(combined_path) end
		data = f:read("*a")
		f:close()
	end

	local baseDir = getBaseDir()
	-- Root source = the combined cart itself (lines outside any include marker
	-- come straight from the cart and map 1:1 to its line numbers).
	local root_src = resolvePath(combined_path, baseDir)

	local map    = {}
	local stack  = { { src = root_src, line = 1 } }
	local lineno = 0

	-- Iterate over all lines (preserve empty trailing line if any).
	for line in (data .. "\n"):gmatch("([^\n]*)\n") do
		lineno = lineno + 1
		local top = stack[#stack]

		local open_path  = line:match("^%s*%-%-%s*(.-){{{%s*$")
		local close_path = line:match("^%s*%-%-%s*}}}(.-)%s*$")

		if open_path then
			-- The opening marker replaced the #include line in the parent file.
			map[lineno] = { src = top.src, line = top.line, text = line }
			top.line = top.line + 1
			stack[#stack + 1] = { src = resolvePath(open_path, baseDir), line = 1 }
		elseif close_path then
			-- Closing marker is synthetic; no source line.
			map[lineno] = nil
			stack[#stack] = nil
		else
			map[lineno] = { src = top.src, line = top.line, text = line }
			top.line = top.line + 1
		end
	end

	return map
end

-- ---------------------------------------------------------------------------
-- Aggregation
-- ---------------------------------------------------------------------------
-- For each line event, we compute two allocation metrics:
--   self     = delta to the immediately following event, ONLY when that event
--              stays at the same stack depth (i.e. the line did not descend
--              into a callee). Approximates "this line allocated X by itself".
--   inclusive = delta from this line event to the next event whose depth is
--              <= this line's depth (i.e. we returned to this scope or above).
--              Approximates "this line plus everything it called allocated X".
-- Negative deltas (which can only come from GC, but GC is stopped) are clamped
-- to zero defensively.
--
-- Diagnostic side-channels (assigned to M._diag at end of aggregate):
--   posSum = Σ max(0, count[i+1] - count[i])  over all event pairs
--            (depth-blind sanity check; should ≈ Σ flat_kb and ≈ bracket NET)
--   negSum = Σ max(0, count[i] - count[i+1])  (sweep work that ran despite stop)
local function aggregate()
	-- Pass 1: compute next_le[i] = smallest j > i with depth[j] <= depth[i]
	-- using a monotonic stack. O(N) total.
	-- Stored as FFI int32 arrays to keep the hot loop tight and JIT-friendly.
	local n = idx
	local next_le    = ffi.new("int32_t[?]", n)        -- 0 = "none"
	local st_idx     = ffi.new("int32_t[?]", n + 1)
	local st_depth   = ffi.new("int32_t[?]", n + 1)
	local sp = 0
	-- Diagnostic accumulators walked alongside Pass 1.
	local posSum, negSum = 0, 0
	for j = 0, n - 1 do
		local dj = buf[j * FIELDS + 1]
		if j + 1 < n then
			local dlt = buf[(j + 1) * FIELDS + 3] - buf[j * FIELDS + 3]
			if dlt > 0 then posSum = posSum + dlt
			elseif dlt < 0 then negSum = negSum - dlt end
		end
		while sp > 0 and st_depth[sp] >= dj do
			-- encode "j" with +1 offset so 0 can mean "unset"
			next_le[st_idx[sp]] = j + 1
			sp = sp - 1
		end
		sp = sp + 1
		st_idx[sp]   = j
		st_depth[sp] = dj
	end
	-- Remaining stack entries get next_le = 0 (unset, already zero-init).
	M._diag = { posSum = posSum, negSum = negSum }

	-- Pass 2: aggregate per combined-line. O(N).
	-- NOTE: self_kb and incl_kb are depth-based and UNRELIABLE in LuaJIT because
	-- tail calls fire CALL hooks but no matching "tail return" hooks, so the
	-- recorded depth drifts upward.
	-- flat_kb attributes every positive consecutive delta to the MOST RECENTLY
	-- SEEN line event, regardless of what kind of event immediately precedes the
	-- delta. This correctly charges allocations done inside C functions (which
	-- have CALL+RETURN events but no LINE events) to the Lua line that called
	-- them. Σ flat_kb across all rows ≈ consec(+) ≈ bracket NET.
	local stats = {}  -- combined_line -> { n, self_kb, incl_kb, flat_kb }
	local last_line_s = nil   -- stats entry for the most recent line event
	for i = 0, n - 1 do
		local base = i * FIELDS
		local ec   = buf[base]
		local nb   = (i + 1 < n) and ((i + 1) * FIELDS) or nil
		local dlt  = nb and (buf[nb + 3] - buf[base + 3]) or 0

		if ec == 3 then  -- line event
			local d  = buf[base + 1]
			local ln = buf[base + 2]
			local m  = buf[base + 3]

			local s = stats[ln]
			if not s then
				s = { n = 0, self_kb = 0, incl_kb = 0, flat_kb = 0 }
				stats[ln] = s
			end
			s.n = s.n + 1
			last_line_s = s

			-- self: delta to immediate next event, only if same depth (broken in LJ)
			if nb and buf[nb + 1] == d and dlt > 0 then s.self_kb = s.self_kb + dlt end

			-- inclusive: delta to next event at depth <= d (broken in LJ; see note)
			local jp1 = next_le[i]
			if jp1 ~= 0 then
				local d2 = buf[(jp1 - 1) * FIELDS + 3] - m
				if d2 > 0 then s.incl_kb = s.incl_kb + d2 end
			end
		end

		-- flat: attribute every positive delta to the most recent line event,
		-- regardless of whether the leading event is a line/call/return.
		if dlt > 0 and last_line_s then
			last_line_s.flat_kb = last_line_s.flat_kb + dlt
		end
	end

	return stats
end

-- ---------------------------------------------------------------------------
-- Report
-- ---------------------------------------------------------------------------
local function pad(s, w, right)
	s = tostring(s)
	local l = #s
	if l >= w then return s:sub(1, w) end
	local fill = (" "):rep(w - l)
	return right and (fill .. s) or (s .. fill)
end

local function trim(s)
	return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- Strip a long absolute path down to a useful tail (basename, but keep the
-- parent dir for context). E.g. "c:/.../pico8/actors/act.lua" -> "actors/act.lua".
local function shortenPath(p)
	local parent, file = p:match("([^/\\]+)[/\\]([^/\\]+)$")
	if file then return parent .. "/" .. file end
	return p:match("([^/\\]+)$") or p
end

-- Collect, map and sort rows. Shared by report() and reportHTML().
local function gatherRows(combined_path)
	combined_path = combined_path or (rawget(_G, "cartname") or "schifahren-game-combined.p8")

	local map, err = buildLineMap(combined_path)
	if not map then
		error("memprofile: " .. tostring(err), 3)
	end

	local stats = aggregate()

	local rows = {}
	for ln, s in pairs(stats) do
		local src = map[ln]
		rows[#rows + 1] = {
			combined_line = ln,
			src_file = src and src.src or "?",
			src_line = src and src.line or -1,
			code     = src and trim(src.text or "") or "",
			n        = s.n,
			self_kb  = s.self_kb,
			incl_kb  = s.incl_kb,
			flat_kb  = s.flat_kb,
		}
	end
	-- Sort by depth-blind flat_kb (reliable in LuaJIT) instead of broken incl_kb.
	table.sort(rows, function(a, b) return a.flat_kb > b.flat_kb end)
	return rows, combined_path
end

function M.report(limit, combined_path)
	if state ~= "stopped" then
		error("memprofile.report(): call stop() before report()", 2)
	end

	limit = limit or 50
	local rows, cart = gatherRows(combined_path)

	local out = {}
	out[#out + 1] = "memprofile report"
	out[#out + 1] = "================="
	out[#out + 1] = string.format(
		"events: %d / %d  (overflow: %s)",
		idx, cap, tostring(overflowed))
	out[#out + 1] = string.format("combined cart: %s", cart)
	out[#out + 1] = string.format("unique lines hit: %d (showing top %d by inclusive)",
		#rows, math.min(#rows, limit))
	out[#out + 1] = ""

	local hdr = string.format(
		"%s | %s | %s | %s | %s | %s | %s | %s | %s | %s",
		pad("#",        3),
		pad("source:line",       32),
		pad("comb:line",         9),
		pad("calls",             6, true),
		pad("flat KB",           7, true),
		pad("self KB",           7, true),
		pad("incl KB",           7, true),
		pad("self KB/call",      12, true),
		pad("incl KB/call",      12, true),
		"code")
	local sep = string.rep("-", math.min(#hdr, 220))
	out[#out + 1] = hdr
	out[#out + 1] = sep

	local shown = math.min(#rows, limit)
	for i = 1, shown do
		local r = rows[i]
		local src = string.format("%s:%d", shortenPath(r.src_file), r.src_line)
		local code = r.code or ""
		if #code > 80 then code = code:sub(1, 80) .. "…" end
		out[#out + 1] = string.format(
			"%s | %s | %s | %s | %s | %s | %s | %s | %s | %s",
			pad(i, 3),
			pad(src,                                          32),
			pad(string.format(":%d", r.combined_line),        9),
			pad(r.n,                                          6, true),
			pad(string.format("%.3f", r.flat_kb),             7, true),
			pad(string.format("%.3f", r.self_kb),             7, true),
			pad(string.format("%.3f", r.incl_kb),             7, true),
			pad(string.format("%.6f", r.self_kb / r.n),       12, true),
			pad(string.format("%.6f", r.incl_kb / r.n),       12, true),
			code)
	end

	local tot_self, tot_incl, tot_calls = 0, 0, 0
	for _, r in ipairs(rows) do
		tot_self  = tot_self  + r.self_kb
		tot_incl  = tot_incl  + r.incl_kb
		tot_calls = tot_calls + r.n
	end
	out[#out + 1] = sep
	out[#out + 1] = string.format(
		"totals: %d line-hits, self %.3f KB, incl %.3f KB",
		tot_calls, tot_self, tot_incl)

	return table.concat(out, "\n")
end

-- ---------------------------------------------------------------------------
-- HTML report (with vscode://file/ links)
-- ---------------------------------------------------------------------------
local function htmlEscape(s)
	return (s:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;")
		:gsub('"', "&quot;"):gsub("'", "&#39;"))
end

function M.reportHTML(limit, combined_path)
	if state ~= "stopped" then
		error("memprofile.reportHTML(): call stop() before reportHTML()", 2)
	end

	limit = limit or 200
	local rows, cart = gatherRows(combined_path)
	local shown = math.min(#rows, limit)

	-- For per-cell heat bars relative to the displayed top.
	local max_self, max_incl, max_flat = 0, 0, 0
	for i = 1, shown do
		if rows[i].self_kb > max_self then max_self = rows[i].self_kb end
		if rows[i].incl_kb > max_incl then max_incl = rows[i].incl_kb end
		if rows[i].flat_kb > max_flat then max_flat = rows[i].flat_kb end
	end
	if max_self == 0 then max_self = 1 end
	if max_incl == 0 then max_incl = 1 end
	if max_flat == 0 then max_flat = 1 end

	local tot_self, tot_incl, tot_flat, tot_calls = 0, 0, 0, 0
	for _, r in ipairs(rows) do
		tot_self  = tot_self  + r.self_kb
		tot_incl  = tot_incl  + r.incl_kb
		tot_flat  = tot_flat  + r.flat_kb
		tot_calls = tot_calls + r.n
	end

	local out = {}
	out[#out + 1] = [[<!doctype html><html><head><meta charset="utf-8"><title>memprofile</title>
<style>
body { font-family: ui-monospace, Consolas, monospace; background:#1e1e1e; color:#ddd; margin:1em; font-size:12px; }
h1 { font-size:14px; margin:0 0 .5em 0; }
.meta { color:#999; margin-bottom:.75em; }
table { border-collapse: collapse; width: 100%; }
th, td { padding:2px 6px; text-align:left; border-bottom:1px solid #333; vertical-align: top; }
th { background:#2b2b2b; position: sticky; top: 0; }
td.num { text-align:right; font-variant-numeric: tabular-nums; }
td.bar { position: relative; }
td.bar .fill { position:absolute; left:0; top:0; bottom:0; background:#3a4d6b; z-index:0; }
td.bar span { position:relative; z-index:1; padding: 0 4px; }
a { color:#79b8ff; text-decoration:none; }
a:hover { text-decoration:underline; }
.code { color:#cfa; white-space:pre; overflow:hidden; max-width:60ch; text-overflow:ellipsis; display:inline-block; vertical-align:bottom; }
tr:hover td { background:#252525; }
</style></head><body>]]
	out[#out + 1] = "<h1>memprofile report</h1>"
	local diag = M._diag or {}
	out[#out + 1] = string.format(
		'<div class="meta">events %d / %d  &middot; overflow: %s &middot; cart: %s &middot; unique lines: %d &middot; showing top %d &middot; totals: %d hits, <b>flat %.1f KB</b>, self %.1f KB, incl %.1f KB (depth-based, broken in LJ) &middot; bracket NET: %.1f KB &middot; consec(+): %.1f KB &middot; consec(-): %.1f KB</div>',
		idx, cap, tostring(overflowed), htmlEscape(cart), #rows, shown,
		tot_calls, tot_flat, tot_self, tot_incl, M._bracketDeltaKB or 0,
		diag.posSum or 0, diag.negSum or 0)

	out[#out + 1] = "<table><thead><tr>"
	out[#out + 1] = "<th>#</th><th>source:line</th><th>comb:line</th><th>calls</th><th>flat KB</th><th>self KB</th><th>incl KB</th><th>flat KB/call</th><th>code</th>"
	out[#out + 1] = "</tr></thead><tbody>"

	for i = 1, shown do
		local r = rows[i]
		local link = string.format("vscode://file/%s:%d", r.src_file, r.src_line)
		local label = htmlEscape(string.format("%s:%d", shortenPath(r.src_file), r.src_line))
		local flat_w = math.floor(100 * r.flat_kb / max_flat + 0.5)
		local self_w = math.floor(100 * r.self_kb / max_self + 0.5)
		local incl_w = math.floor(100 * r.incl_kb / max_incl + 0.5)
		out[#out + 1] = string.format(
			'<tr><td class="num">%d</td>'
			.. '<td><a href="%s" title="%s">%s</a></td>'
			.. '<td class="num">:%d</td>'
			.. '<td class="num">%d</td>'
			.. '<td class="num bar"><div class="fill" style="width:%d%%"></div><span>%.3f</span></td>'
			.. '<td class="num bar"><div class="fill" style="width:%d%%"></div><span>%.3f</span></td>'
			.. '<td class="num bar"><div class="fill" style="width:%d%%"></div><span>%.3f</span></td>'
			.. '<td class="num">%.6f</td>'
			.. '<td><span class="code">%s</span></td></tr>',
			i,
			htmlEscape(link), htmlEscape(r.src_file), label,
			r.combined_line,
			r.n,
			flat_w, r.flat_kb,
			self_w, r.self_kb,
			incl_w, r.incl_kb,
			r.flat_kb / r.n,
			htmlEscape(r.code or ""))
	end

	out[#out + 1] = "</tbody></table></body></html>"
	return table.concat(out)
end

return M
