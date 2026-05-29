-- analprof.lua — Lua port of analprof.py.
-- Parses LuaJIT G-format folded-stack profile output (produced by jit.p with
-- the "G" mode flag) and renders a self-contained flame-graph HTML report.
-- Designed to be callable from inside the picolove cart sandbox so that
-- jitpgprofile can stop the profiler and emit prof.html in one shot.
--
-- API:
--   analprof.generate(prof_path, html_path, opts) -> ok, info
--     opts = { combined_p8 = "schifahren-game-combined.p8",
--              interval_ms = <override>,                 -- else parsed from filename
--              base_dir    = <love source dir override> }
--   analprof.parseIntervalFromFilename(path)            -- nil if not "prof_<mode>.txt"

local M = {}

local function fwd(p) return (p:gsub("\\", "/")) end
local function trim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end

-- Plain-string replace (no Lua-pattern semantics for needle or repl).
local function plainReplace(s, needle, repl)
	local out, i = {}, 1
	while true do
		local a, b = s:find(needle, i, true)
		if not a then
			out[#out + 1] = s:sub(i)
			break
		end
		out[#out + 1] = s:sub(i, a - 1)
		out[#out + 1] = repl
		i = b + 1
	end
	return table.concat(out)
end

-- ---------------------------------------------------------------------------
-- Minimal JSON encoder. Sufficient for our tree/sources/info structures.
-- ---------------------------------------------------------------------------
local function encodeString(s)
	s = s:gsub('\\', '\\\\')
	     :gsub('"',  '\\"')
	     :gsub('\b', '\\b')
	     :gsub('\f', '\\f')
	     :gsub('\n', '\\n')
	     :gsub('\r', '\\r')
	     :gsub('\t', '\\t')
	s = s:gsub('[%z\1-\31]', function(c)
		return string.format("\\u%04x", string.byte(c))
	end)
	-- defang "</script" sequences inside embedded JSON
	s = plainReplace(s, "</", "<\\/")
	return '"' .. s .. '"'
end

local function jsonEncode(v)
	local tv = type(v)
	if v == nil then return "null"
	elseif tv == "boolean" then return v and "true" or "false"
	elseif tv == "number" then
		if v ~= v or v == math.huge or v == -math.huge then return "null" end
		if v % 1 == 0 then return string.format("%d", v) end
		return string.format("%.6f", v):gsub("0+$", ""):gsub("%.$", ".0")
	elseif tv == "string" then return encodeString(v)
	elseif tv == "table" then
		-- array iff keys are 1..#t and there are no extras
		local n, isarr = 0, true
		for k, _ in pairs(v) do
			n = n + 1
			if type(k) ~= "number" then isarr = false; break end
		end
		if isarr and n == #v then
			local parts = {}
			for i = 1, n do parts[i] = jsonEncode(v[i]) end
			return "[" .. table.concat(parts, ",") .. "]"
		else
			local parts = {}
			for k, val in pairs(v) do
				parts[#parts + 1] = encodeString(tostring(k)) .. ":" .. jsonEncode(val)
			end
			return "{" .. table.concat(parts, ",") .. "}"
		end
	end
	error("analprof: cannot encode type " .. tv)
end

-- ---------------------------------------------------------------------------
-- File IO helpers.
-- ---------------------------------------------------------------------------
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

local function resolvePath(p, baseDir)
	p = fwd(p)
	if p:sub(1, 1) == "/" or p:match("^%a:") then return p end
	return (baseDir or "") .. p
end

local function readFileLines(path)
	local f = io.open(path, "rb")
	if not f then return nil end
	local data = f:read("*a")
	f:close()
	local lines = {}
	for line in (data .. "\n"):gmatch("([^\n]*)\n") do
		if line:sub(-1) == "\r" then line = line:sub(1, -2) end
		lines[#lines + 1] = line
	end
	if #lines > 0 and lines[#lines] == "" then
		lines[#lines] = nil
	end
	return lines
end

local function htmlEscape(s)
	s = tostring(s or "")
	return (s:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;")
		:gsub('"', "&quot;"):gsub("'", "&#39;"))
end

-- ---------------------------------------------------------------------------
-- Parse G-format folded stacks: "frame1;frame2;... <count>" per line.
-- Optional split-mode-3 dedupe: a trailing "<leaf> <same_count>" alone is
-- skipped (jit.p emits it when split=3).
-- ---------------------------------------------------------------------------
function M.parse(path)
	local lines = readFileLines(path)
	local info = {
		lines_in = lines and #lines or 0,
		split_mode_3 = false,
		dup_skipped = 0,
		unsupported_format = false,
	}
	if not lines then return nil, info end

	local raw = {}
	for _, ln in ipairs(lines) do
		if not ln:match("^%s*$") then raw[#raw + 1] = ln end
	end

	local function parseLine(ln)
		return ln:match("^(.+)%s+(%d+)$")
	end

	if #raw > 0 then
		local any = false
		for i = 1, math.min(5, #raw) do
			if parseLine(raw[i]) then any = true; break end
		end
		if not any then info.unsupported_format = true; return {}, info end
	end
	for i = 1, math.min(20, #raw) do
		if raw[i]:find("%", 1, true) then
			info.unsupported_format = true
			return {}, info
		end
	end

	local samples = {}
	local i = 1
	while i <= #raw do
		local stack, countStr = parseLine(raw[i])
		if not stack then i = i + 1
		else
			local count = tonumber(countStr)
			local frames = {}
			for f in (stack .. ";"):gmatch("([^;]*);") do frames[#frames + 1] = f end

			if i + 1 <= #raw then
				local s2, c2 = parseLine(raw[i + 1])
				if s2 and c2 == countStr and not s2:find(";", 1, true)
					and s2 == frames[#frames] then
					samples[#samples + 1] = { frames = frames, count = count }
					i = i + 2
					info.dup_skipped = info.dup_skipped + 1
				else
					samples[#samples + 1] = { frames = frames, count = count }
					i = i + 1
				end
			else
				samples[#samples + 1] = { frames = frames, count = count }
				i = i + 1
			end
		end
	end

	info.split_mode_3 = info.dup_skipped > 0
	return samples, info
end

-- ---------------------------------------------------------------------------
-- Build call tree from samples.
-- ---------------------------------------------------------------------------
function M.buildTree(samples)
	local root = { name = "all", total = 0, self_ = 0, children = {} }
	for _, sm in ipairs(samples) do
		root.total = root.total + sm.count
		local n = root
		for _, f in ipairs(sm.frames) do
			local ch = n.children[f]
			if not ch then
				ch = { name = f, total = 0, self_ = 0, children = {} }
				n.children[f] = ch
			end
			n = ch
			n.total = n.total + sm.count
		end
		n.self_ = n.self_ + sm.count
	end
	return root
end

-- ---------------------------------------------------------------------------
-- Walk combined p8 (built by combinelua.py) and map each line index to its
-- origin (source file + line within that file). Marker lines map to nil.
-- Mirrors analprof.py.build_line_origin and matches memprofile's logic.
-- ---------------------------------------------------------------------------
local INCLUDE_START_RE = "^%s*%-%-%s+(.-){{{%s*$"
local INCLUDE_END_RE   = "^%s*%-%-%s+}}}(.-)%s*$"

function M.buildLineOrigin(p8_lines, root_name)
	if not p8_lines or #p8_lines == 0 then return nil end
	local out = {}
	local stack = { { file = root_name or "schifahren-game.p8", line = 1 } }
	for i, ln in ipairs(p8_lines) do
		local op = ln:match(INCLUDE_START_RE)
		local cp = ln:match(INCLUDE_END_RE)
		if op then
			if #stack > 0 then stack[#stack].line = stack[#stack].line + 1 end
			stack[#stack + 1] = { file = trim(op), line = 1 }
			out[i] = false
		elseif cp then
			if #stack > 1 then stack[#stack] = nil end
			out[i] = false
		else
			local top = stack[#stack]
			out[i] = { file = top.file, line = top.line, depth = #stack - 1 }
			top.line = top.line + 1
		end
	end
	return out
end

-- ---------------------------------------------------------------------------
-- Walk backward from `line_no` looking for the most recent function decl.
-- ---------------------------------------------------------------------------
local FUNC_DEF_PAT    = "^%s*function%s+([%w_.:]+)%s*%("
local FUNC_LOCAL_PAT  = "^%s*local%s+function%s+([%w_.:]+)%s*%("
local FUNC_ASSIGN_PAT = "^%s*([%w_.:]+)%s*=%s*function%s*%("

local function findEnclosingFunction(lines, line_no, look_back)
	if not lines or line_no < 1 then return nil end
	look_back = look_back or 400
	local startIdx = math.min(line_no, #lines)
	local stopIdx  = math.max(startIdx - look_back, 1)
	for i = startIdx, stopIdx, -1 do
		local ln = lines[i] or ""
		local m = ln:match(FUNC_LOCAL_PAT) or ln:match(FUNC_DEF_PAT)
		if m then return m end
		m = ln:match(FUNC_ASSIGN_PAT)
		if m then return m end
	end
	return nil
end

-- ---------------------------------------------------------------------------
-- Resolve frame names to source records: { line, file?, orig?, func? }.
-- Handles "[string]:N" via combined-cart line-origin map and "file.lua:N" by
-- reading file.lua relative to base_dir.
-- ---------------------------------------------------------------------------
local STRING_RE    = "^%[string%]:(%d+)$"
local FILE_LINE_RE = "^([%w_./\\%-]+%.lua):(%d+)$"

function M.collectSources(tree, p8_lines, line_origin, base_dir)
	local out = {}
	local fileCache = {}

	local function readFile(relPath)
		if fileCache[relPath] ~= nil then
			return fileCache[relPath] or nil
		end
		local cand = resolvePath(relPath, base_dir)
		local lines = readFileLines(cand)
		fileCache[relPath] = lines or false
		return lines
	end

	local function visit(n)
		local name = n.name
		if out[name] == nil then
			local sl = name:match(STRING_RE)
			local handled = false
			if sl and p8_lines then
				local ln = tonumber(sl)
				if ln >= 1 and ln <= #p8_lines then
					local rec = { line = p8_lines[ln] }
					local originLines
					if line_origin then
						local orig = line_origin[ln]
						if orig then
							rec.file = orig.file
							rec.orig = orig.line
							originLines = readFile(orig.file)
						end
					end
					local fn
					if originLines and rec.orig then
						fn = findEnclosingFunction(originLines, rec.orig)
					end
					if not fn then fn = findEnclosingFunction(p8_lines, ln) end
					if fn then rec.func = fn end
					out[name] = rec
					handled = true
				end
			end
			if not handled then
				local fp, lp = name:match(FILE_LINE_RE)
				if fp then
					local ln = tonumber(lp)
					local lines = readFile(fp)
					if lines and ln >= 1 and ln <= #lines then
						local rec = { line = lines[ln], file = fp, orig = ln }
						local fn = findEnclosingFunction(lines, ln)
						if fn then rec.func = fn end
						out[name] = rec
					end
				end
			end
		end
		for _, c in pairs(n.children) do visit(c) end
	end

	visit(tree)
	return out
end

-- Tree -> JSON-friendly form (children as array sorted by total desc).
local function toJsonable(node)
	local children = {}
	for _, c in pairs(node.children) do children[#children + 1] = toJsonable(c) end
	table.sort(children, function(a, b) return a.t > b.t end)
	return { n = node.name, t = node.total, s = node.self_, c = children }
end

-- ---------------------------------------------------------------------------
-- Inclusive samples per unique frame (deduped within each stack).
-- ---------------------------------------------------------------------------
function M.aggregateFrames(samples, sources, n, interval_ms)
	n = n or 100
	local inc, sites, total = {}, {}, 0
	for _, sm in ipairs(samples) do
		total = total + sm.count
		local seen = {}
		for _, k in ipairs(sm.frames) do
			if not seen[k] then
				seen[k] = true
				inc[k]   = (inc[k]   or 0) + sm.count
				sites[k] = (sites[k] or 0) + 1
			end
		end
	end
	if total == 0 then total = 1 end
	local items = {}
	for k, c in pairs(inc) do items[#items + 1] = { k, c } end
	table.sort(items, function(a, b) return a[2] > b[2] end)
	local out = {}
	for i = 1, math.min(#items, n) do
		local name, count = items[i][1], items[i][2]
		local rec = sources[name] or {}
		local origin = ""
		if rec.file and rec.orig then origin = rec.file .. ":" .. rec.orig end
		out[i] = {
			name   = name,
			count  = count,
			pct    = 100 * count / total,
			ms     = interval_ms and (count * interval_ms) or nil,
			sites  = sites[name],
			src    = trim(rec.line or ""),
			origin = origin,
			func   = rec.func or "",
		}
	end
	return out
end

-- ---------------------------------------------------------------------------
-- Self-time per leaf: samples grouped by the leaf frame of each stack.
-- ---------------------------------------------------------------------------
function M.topLines(samples, sources, n, interval_ms)
	n = n or 20
	local leaf, total = {}, 0
	for _, sm in ipairs(samples) do
		local f = sm.frames[#sm.frames]
		leaf[f] = (leaf[f] or 0) + sm.count
		total = total + sm.count
	end
	if total == 0 then total = 1 end
	local items = {}
	for k, c in pairs(leaf) do items[#items + 1] = { k, c } end
	table.sort(items, function(a, b) return a[2] > b[2] end)
	local out = {}
	for i = 1, math.min(#items, n) do
		local name, count = items[i][1], items[i][2]
		local rec = sources[name] or {}
		local origin = ""
		if rec.file and rec.orig then origin = rec.file .. ":" .. rec.orig end
		out[i] = {
			name   = name,
			count  = count,
			pct    = 100 * count / total,
			ms     = interval_ms and (count * interval_ms) or nil,
			src    = trim(rec.line or ""),
			origin = origin,
			func   = rec.func or "",
		}
	end
	return out
end

-- ---------------------------------------------------------------------------
-- Pull the sampling interval (ms) out of a "prof_<mode>.txt" filename. The
-- mode segment mirrors jit.p's syntax — we just look for "iN".
-- ---------------------------------------------------------------------------
function M.parseIntervalFromFilename(path)
	if not path then return nil end
	local base = path:match("([^/\\]+)$") or path
	local mode = base:match("^prof_(.-)%.txt$")
	if not mode then return nil end
	local n = mode:match("i(%d+)")
	return n and tonumber(n) or nil
end

-- ---------------------------------------------------------------------------
-- HTML template — visually identical to analprof.py's output. ms column is
-- only rendered when info.interval_ms is set; the tooltip also adds ms.
-- ---------------------------------------------------------------------------
local HTML_TEMPLATE = [==[<!doctype html>
<html><head><meta charset="utf-8"><title>LuaJIT prof flamegraph - %%FILE%%</title>
<style>
html, body { margin:0; padding:0; background:#1c1c1c; color:#eee;
  font-family: -apple-system, 'Segoe UI', Arial, sans-serif; }
#header { padding:8px 12px; background:#0d0d0d; position:sticky; top:0; z-index:5;
  border-bottom:1px solid #333; }
#header input[type=text] { width:240px; }
#header b { color:#fff; }
#status { color:#bbb; margin-left:8px; font-size:12px; }
#tabs button { background:#2a2a2a; color:#eee; border:1px solid #444; padding:4px 10px;
  cursor:pointer; }
#tabs button.active { background:#3a3a3a; border-color:#fff; }
.pane { display:none; padding:8px; }
.pane.active { display:block; }
#flame { position:relative; }
.bar {
  position:absolute; height:18px; line-height:18px; font-size:11px;
  white-space:nowrap; overflow:hidden;
  border:0.5px solid rgba(0,0,0,0.4); box-sizing:border-box;
  cursor:pointer; padding:0 4px; color:#111;
  text-shadow: 0 0 2px rgba(255,255,255,0.4);
}
.bar:hover { outline:2px solid #fff; z-index:3; }
.bar.match { outline:2px solid #ffd54f; }
.bar.dim { opacity:0.35; }
#tooltip {
  position:fixed; display:none; pointer-events:none;
  background:#fff; color:#111; padding:8px 10px; border:1px solid #555;
  font-family: monospace; font-size:11px; line-height:1.35;
  z-index:1000; max-width:780px;
  box-shadow: 2px 2px 8px rgba(0,0,0,0.5);
}
#tooltip b { color:#000; }
table.top { border-collapse:collapse; }
table.top td, table.top th { padding:3px 8px; border-bottom:1px solid #333; font-family:monospace;
  font-size:12px; vertical-align:top; }
table.top th { text-align:left; color:#bbb; }
table.top tr:hover { background:#2a2a2a; }
.src { color:#9cd; }
.bar1 { background:#444; height:4px; position:relative; min-width:120px; }
.bar1>div { position:absolute; left:0; top:0; bottom:0; background:#e57; }
</style></head>
<body>
<div id="header">
  <span id="tabs">
    <button data-tab="flame" class="active">flame</button>
    <button data-tab="top">top (leaf)</button>
    <button data-tab="all">all (inclusive)</button>
    <button data-tab="info">info</button>
  </span>
  &nbsp;total samples: <b>%%TOTAL%%</b>
  &nbsp;file: <b>%%FILE%%</b>
  &nbsp;<button id="labelmode" title="toggle bar labels between frame name and source-line text">labels: frame</button>
  &nbsp;search: <input id="search" type="text" placeholder="filter visible labels">
  &nbsp;<button id="reset">reset zoom</button>
  <span id="status"></span>
  <div id="breadcrumb" style="font-size:11px; margin-top:4px; color:#9cf;"></div>
  <div style="font-size:11px; color:#888;">tip: click any bar to zoom in (rescales to full width); click a breadcrumb crumb above to zoom out; search filters whatever is currently shown on bars.</div>
</div>

<div id="pane-flame" class="pane active"><div id="flame"></div></div>
<div id="pane-top" class="pane"><div id="topbody"></div></div>
<div id="pane-all" class="pane"><div id="allbody"></div></div>
<div id="pane-info" class="pane"><pre id="infobody"></pre></div>

<div id="tooltip"></div>

<script id="profdata" type="application/json">%%DATA%%</script>
<script id="profsrc" type="application/json">%%SOURCES%%</script>
<script id="proftop" type="application/json">%%TOP%%</script>
<script id="profall" type="application/json">%%ALL%%</script>
<script id="profinfo" type="application/json">%%INFO%%</script>

<script>
const tree    = JSON.parse(document.getElementById('profdata').textContent);
const sources = JSON.parse(document.getElementById('profsrc').textContent);
const topList = JSON.parse(document.getElementById('proftop').textContent);
const allList = JSON.parse(document.getElementById('profall').textContent);
const info    = JSON.parse(document.getElementById('profinfo').textContent);
const intervalMs = (typeof info.interval_ms === 'number') ? info.interval_ms : null;

const flame    = document.getElementById('flame');
const tooltip  = document.getElementById('tooltip');
const statusEl = document.getElementById('status');
const crumbEl  = document.getElementById('breadcrumb');
const ROW_H    = 19;

(function attachParents(n, p) { n._parent = p; for (const c of n.c) attachParents(c, n); })(tree, null);

let rootView  = tree;
let searchTxt = '';
let labelMode = 'frame';

function fmtMs(samples) {
  if (intervalMs === null) return '';
  const ms = samples * intervalMs;
  if (ms >= 1000) return (ms/1000).toFixed(3) + ' s';
  if (ms >= 10)   return ms.toFixed(1) + ' ms';
  return ms.toFixed(2) + ' ms';
}

function displayName(node) {
  if (labelMode === 'source') {
    const info = sources[node.n];
    if (info && info.line) return info.line.trim();
  }
  return node.n;
}

function renderBreadcrumb() {
  const path = [];
  for (let n = rootView; n; n = n._parent) path.unshift(n);
  crumbEl.innerHTML = path.map((p, i) => {
    const last = i === path.length - 1;
    const dn = displayName(p);
    const short = dn.length > 60 ? dn.slice(0, 57) + '...' : dn;
    const lbl = escapeHtml(short);
    return last
      ? '<span style="color:#fff">' + lbl + '</span>'
      : '<a href="#" data-idx="' + i + '" style="color:#9cf; text-decoration:none">' + lbl + '</a>';
  }).join(' &raquo; ');
  crumbEl.querySelectorAll('a').forEach(a => {
    a.onclick = e => {
      e.preventDefault();
      rootView = path[parseInt(a.dataset.idx, 10)];
      drawFlame();
    };
  });
}

function colorFor(name) {
  let h = 0;
  for (let i = 0; i < name.length; i++) h = (h * 33 + name.charCodeAt(i)) | 0;
  const hue = Math.abs(h) % 50;
  return 'hsl(' + hue + ', 75%, 60%)';
}

function srcInfoFor(name) {
  return sources[name] || null;
}

function escapeHtml(s) {
  return String(s).replace(/[&<>"']/g, c =>
    ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
}

function showTip(e, node, stackPath) {
  const pct = (100 * node.t / tree.t).toFixed(2);
  const selfPct = (100 * node.s / tree.t).toFixed(2);
  let h = '<b>' + escapeHtml(node.n) + '</b><br>';
  h += 'samples (inclusive): <b>' + node.t + '</b> (' + pct + '%)';
  if (intervalMs !== null) h += ' &mdash; <b>' + fmtMs(node.t) + '</b>';
  h += '<br>';
  h += 'samples (self):      <b>' + node.s + '</b> (' + selfPct + '%)';
  if (intervalMs !== null) h += ' &mdash; <b>' + fmtMs(node.s) + '</b>';
  h += '<br>';
  const sinfo = srcInfoFor(node.n);
  if (sinfo !== null) {
    if (sinfo.file) h += '<br>from: <b>' + escapeHtml(sinfo.file) + '</b>:' + sinfo.orig + '<br>';
    if (sinfo.func) h += 'function: <b>' + escapeHtml(sinfo.func) + '</b><br>';
    if (sinfo.line !== undefined) h += 'source line:<br><span style="color:#048">' + escapeHtml(sinfo.line) + '</span><br>';
  }
  h += '<br>stack:<br><span style="color:#444">' + escapeHtml(stackPath) + '</span>';
  tooltip.innerHTML = h;
  tooltip.style.display = 'block';
  moveTip(e);
}
function moveTip(e) {
  let x = e.clientX + 12, y = e.clientY + 12;
  if (x + 500 > window.innerWidth) x = e.clientX - 510;
  if (y + 200 > window.innerHeight) y = e.clientY - 210;
  tooltip.style.left = x + 'px';
  tooltip.style.top  = y + 'px';
}
function hideTip() { tooltip.style.display = 'none'; }

function drawFlame() {
  flame.innerHTML = '';
  const W = flame.clientWidth;
  const total = rootView.t || 1;
  const pxPerSample = W / total;
  let maxDepth = 0;

  function render(node, x, depth, stackPath) {
    const w = node.t * pxPerSample;
    if (w < 0.4) return;
    if (depth > maxDepth) maxDepth = depth;

    const el = document.createElement('div');
    el.className = 'bar';
    el.style.left = x + 'px';
    el.style.top  = (depth * ROW_H) + 'px';
    el.style.width = Math.max(1, w) + 'px';
    el.style.background = colorFor(node.n);
    el.textContent = displayName(node);

    const isMatch = searchTxt && displayName(node).toLowerCase().includes(searchTxt);
    if (searchTxt) {
      if (isMatch) el.classList.add('match');
      else el.classList.add('dim');
    }

    el.addEventListener('click', () => { rootView = node; drawFlame(); });
    el.addEventListener('mouseenter', e => showTip(e, node, stackPath));
    el.addEventListener('mousemove',  moveTip);
    el.addEventListener('mouseleave', hideTip);
    flame.appendChild(el);

    let cx = x;
    for (const c of node.c) {
      render(c, cx, depth + 1, stackPath ? stackPath + ';' + c.n : c.n);
      cx += c.t * pxPerSample;
    }
  }
  render(rootView, 0, 0, rootView.n);
  flame.style.height = ((maxDepth + 2) * ROW_H) + 'px';
  let statusTxt = ' | ' + rootView.t + ' samples (' + (100*rootView.t/tree.t).toFixed(1) + '% of total)';
  if (intervalMs !== null) statusTxt += ' | ' + fmtMs(rootView.t) + ' (interval ' + intervalMs + ' ms)';
  statusEl.textContent = statusTxt;
  renderBreadcrumb();
}

function drawTop() {
  document.getElementById('topbody').innerHTML =
    '<div style="color:#bbb; font-size:11px; padding:4px 0;">'
    + 'self-time per leaf: samples grouped by the leaf frame of each stack.'
    + '</div>'
    + renderTable(topList, false);
}

function renderTable(rows, includeSites) {
  const max = rows.length ? rows[0].count : 1;
  const showMs = intervalMs !== null;
  let html = '<table class="top"><tr><th>#</th><th>samples</th><th>%</th>'
           + (showMs ? '<th>time</th>' : '')
           + (includeSites ? '<th>stacks</th>' : '')
           + '<th>frame</th><th>origin</th><th>function</th><th>source line</th></tr>';
  rows.forEach((r, i) => {
    const w = Math.round(100 * r.count / max);
    html += '<tr>'
      + '<td>' + (i+1) + '</td>'
      + '<td>' + r.count + '</td>'
      + '<td>' + r.pct.toFixed(2) + '%<div class="bar1"><div style="width:' + w + '%"></div></div></td>'
      + (showMs ? '<td>' + fmtMs(r.count) + '</td>' : '')
      + (includeSites ? '<td>' + r.sites + '</td>' : '')
      + '<td>' + escapeHtml(r.name) + '</td>'
      + '<td>' + escapeHtml(r.origin || '') + '</td>'
      + '<td>' + escapeHtml(r.func || '') + '</td>'
      + '<td class="src">' + escapeHtml(r.src || '') + '</td>'
      + '</tr>';
  });
  html += '</table>';
  return html;
}

function drawAll() {
  document.getElementById('allbody').innerHTML =
    '<div style="color:#bbb; font-size:11px; padding:4px 0;">'
    + 'inclusive samples per unique frame (sample counted once per stack containing it). '
    + 'percentages can sum to more than 100% because caller frames overlap callees.'
    + '</div>'
    + renderTable(allList, true);
}

function drawInfo() {
  document.getElementById('infobody').textContent = JSON.stringify(info, null, 2);
}

document.querySelectorAll('#tabs button').forEach(b => {
  b.addEventListener('click', () => {
    document.querySelectorAll('#tabs button').forEach(x => x.classList.remove('active'));
    document.querySelectorAll('.pane').forEach(x => x.classList.remove('active'));
    b.classList.add('active');
    document.getElementById('pane-' + b.dataset.tab).classList.add('active');
    if (b.dataset.tab === 'flame') drawFlame();
  });
});

document.getElementById('reset').onclick = () => { rootView = tree; drawFlame(); };
document.getElementById('search').oninput = e => {
  searchTxt = e.target.value.trim().toLowerCase();
  drawFlame();
};
document.getElementById('labelmode').onclick = e => {
  labelMode = (labelMode === 'frame') ? 'source' : 'frame';
  e.target.textContent = 'labels: ' + labelMode;
  drawFlame();
};
window.addEventListener('resize', () => { if (document.getElementById('pane-flame').classList.contains('active')) drawFlame(); });

drawFlame();
drawTop();
drawAll();
drawInfo();
</script>
</body></html>
]==]

-- ---------------------------------------------------------------------------
-- Top-level driver: parse prof_path, write rendered HTML to html_path.
-- Returns ok (bool), info (table with totals/diagnostics).
-- ---------------------------------------------------------------------------
function M.generate(prof_path, html_path, opts)
	opts = opts or {}
	local base_dir = opts.base_dir or getBaseDir()
	local combined = opts.combined_p8 or "schifahren-game-combined.p8"
	local interval_ms = opts.interval_ms or M.parseIntervalFromFilename(prof_path)

	local samples, info = M.parse(prof_path)
	if not samples then
		return false, { error = "cannot read " .. tostring(prof_path) }
	end
	if info.unsupported_format then
		info.error = "not a LuaJIT G-format folded-stack file"
		return false, info
	end

	local total = 0
	for _, sm in ipairs(samples) do total = total + sm.count end
	info.total_samples = total
	info.sample_groups = #samples
	info.interval_ms = interval_ms
	info.total_ms = interval_ms and (total * interval_ms) or nil
	info.prof_path = prof_path
	info.html_path = html_path

	-- combined cart is read from love source dir (it lives next to main.lua)
	local p8_lines = readFileLines(resolvePath(combined, base_dir))
	if p8_lines then
		info.p8_file = combined
		info.p8_lines = #p8_lines
	end

	local tree = M.buildTree(samples)
	local line_origin = p8_lines and M.buildLineOrigin(p8_lines) or nil
	local sources = M.collectSources(tree, p8_lines, line_origin, base_dir)

	local payload = toJsonable(tree)
	local top = M.topLines(samples, sources, 30, interval_ms)
	local all = M.aggregateFrames(samples, sources, 100, interval_ms)

	local html = HTML_TEMPLATE
	local fileBase = prof_path:match("([^/\\]+)$") or prof_path
	html = plainReplace(html, "%%TOTAL%%",   tostring(total))
	html = plainReplace(html, "%%FILE%%",    htmlEscape(fileBase))
	html = plainReplace(html, "%%DATA%%",    jsonEncode(payload))
	html = plainReplace(html, "%%SOURCES%%", jsonEncode(sources))
	html = plainReplace(html, "%%TOP%%",     jsonEncode(top))
	html = plainReplace(html, "%%ALL%%",     jsonEncode(all))
	html = plainReplace(html, "%%INFO%%",    jsonEncode(info))

	local f, err = io.open(html_path, "wb")
	if not f then return false, { error = "cannot write " .. tostring(html_path) .. ": " .. tostring(err) } end
	f:write(html)
	f:close()
	info.html_bytes = #html
	return true, info
end

return M
