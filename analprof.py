#!/usr/bin/env python3
"""analprof.py - analyze LuaJIT jit.p folded-stack output and render flame graph HTML.

Usage:
    python analprof.py [prof.txt] [out.html] [schifahren-game-combined.p8]

Defaults to prof.txt -> prof.html, looks up schifahren-game-combined.p8 for [string]:N resolution.
"""

import sys
import os
import re
import json
import html as html_lib


def parse_prof(path):
    """Parse LuaJIT G-format profile output.

    Returns (samples, fmt_info).
    samples: list of (frames_list, count).
    fmt_info: dict with 'split_mode_3', 'lines_in', 'unsupported_format'.
    """
    with open(path, 'r', encoding='utf-8', errors='replace') as f:
        raw = [ln.rstrip('\n') for ln in f if ln.strip()]

    info = {'lines_in': len(raw), 'split_mode_3': False, 'unsupported_format': False}

    # G-mode lines end with ' <integer>'. If any non-blank line lacks that pattern
    # or starts with whitespace + %, the file is not in G format.
    line_re = re.compile(r'^(.+?)\s+(\d+)$')
    if raw and not any(line_re.match(ln) for ln in raw[:5]):
        info['unsupported_format'] = True
        return [], info
    if any('%' in ln for ln in raw[:20]):
        # text report (default jit.p output), not folded stacks
        info['unsupported_format'] = True
        return [], info

    samples = []
    i = 0
    dup_skipped = 0
    while i < len(raw):
        m = line_re.match(raw[i])
        if not m:
            i += 1
            continue
        stack_str, count_str = m.group(1), m.group(2)
        count = int(count_str)
        frames = stack_str.split(';')

        # detect split mode 3: next line is "<last_frame> <same_count>"
        if i + 1 < len(raw):
            mn = line_re.match(raw[i + 1])
            if mn and mn.group(2) == count_str:
                nfr = mn.group(1).split(';')
                if len(nfr) == 1 and nfr[0] == frames[-1]:
                    samples.append((frames, count))
                    i += 2
                    dup_skipped += 1
                    continue
        samples.append((frames, count))
        i += 1

    info['split_mode_3'] = dup_skipped > 0
    info['dup_skipped'] = dup_skipped
    return samples, info


def build_tree(samples):
    root = {'name': 'all', 'total': 0, 'self': 0, 'children': {}}
    for frames, count in samples:
        root['total'] += count
        n = root
        for f in frames:
            ch = n['children'].get(f)
            if ch is None:
                ch = {'name': f, 'total': 0, 'self': 0, 'children': {}}
                n['children'][f] = ch
            n = ch
            n['total'] += count
        n['self'] += count
    return root


def load_p8(path):
    if not path or not os.path.exists(path):
        return None
    with open(path, 'r', encoding='utf-8', errors='replace') as f:
        return [ln.rstrip('\n') for ln in f.readlines()]


# combinelua.py emits these wrapper comments around each #include'd file.
# Start: "<lead>-- <resolved_path>{{{"  End: "<lead>-- }}}<resolved_path>"
INCLUDE_START_RE = re.compile(r'^\s*--\s+(.+?)\{\{\{\s*$')
INCLUDE_END_RE   = re.compile(r'^\s*--\s+\}\}\}(.+?)\s*$')

STRING_RE = re.compile(r'^\[string\]:(\d+)$')
# Frames like "api.lua:4201", "main.lua:1583", "pico8\\foo.lua:42".
FILE_LINE_RE = re.compile(r'^([\w./\\\-]+\.lua):(\d+)$')
FUNC_DEF_RE  = re.compile(r'^\s*(?:local\s+)?function\s+([\w.:]+)\s*\(')
FUNC_ASSIGN_RE = re.compile(r'^\s*([\w.:]+)\s*=\s*function\s*\(')


def find_enclosing_function(lines, line_no, look_back=400):
    """Best-effort: walk backward to find the most recent 'function NAME(' or 'NAME = function('."""
    if not lines or line_no < 1:
        return None
    start = min(line_no, len(lines)) - 1
    stop  = max(start - look_back, -1)
    for i in range(start, stop, -1):
        m = FUNC_DEF_RE.match(lines[i])
        if m:
            return m.group(1)
        m = FUNC_ASSIGN_RE.match(lines[i])
        if m:
            return m.group(1)
    return None


def build_line_origin(p8_lines, root_name='schifahren-game.p8'):
    """Map each combined-file line (1-based) -> (original_file, original_line, depth).

    Walks the {{{/}}} markers combinelua.py left in the combined p8 file and
    keeps a stack of (file, next_orig_line). Marker lines themselves get None.
    """
    if not p8_lines:
        return None
    out = [None] * len(p8_lines)
    # Stack entries: [file, next_orig_line]
    stack = [[root_name, 1]]
    for i, ln in enumerate(p8_lines):
        ms = INCLUDE_START_RE.match(ln)
        me = INCLUDE_END_RE.match(ln)
        if ms:
            # The outer file's #include directive line is replaced by this block;
            # consume one outer line so resumption after the matching }}} continues correctly.
            if stack:
                stack[-1][1] += 1
            stack.append([ms.group(1).strip(), 1])
            out[i] = None
        elif me:
            if len(stack) > 1:
                stack.pop()
            out[i] = None
        else:
            if stack:
                top = stack[-1]
                out[i] = (top[0], top[1], len(stack) - 1)
                top[1] += 1
    return out


def collect_sources(tree, p8_lines, line_origin, base_dir):
    """Walk tree, return dict {frame_name: {'line', 'file'?, 'orig'?, 'func'?}}.

    Handles two frame shapes:
      - [string]:N        -> looked up in the combined p8 (with combinelua attribution)
      - file.lua:N        -> looked up by reading file.lua relative to base_dir
    """
    out = {}
    file_cache = {}  # path -> list[str] | None

    def read_file(rel_path):
        if rel_path in file_cache:
            return file_cache[rel_path]
        # accept both '/' and '\\' separators as written in the trace
        norm = rel_path.replace('\\', os.sep).replace('/', os.sep)
        cand = os.path.join(base_dir, norm)
        if os.path.exists(cand):
            try:
                with open(cand, 'r', encoding='utf-8', errors='replace') as f:
                    file_cache[rel_path] = [ln.rstrip('\n') for ln in f.readlines()]
            except OSError:
                file_cache[rel_path] = None
        else:
            file_cache[rel_path] = None
        return file_cache[rel_path]

    def visit(n):
        name = n['name']
        if name in out:
            for c in n['children'].values():
                visit(c)
            return

        ms = STRING_RE.match(name)
        if ms and p8_lines:
            ln = int(ms.group(1))
            if 1 <= ln <= len(p8_lines):
                rec = {'line': p8_lines[ln - 1]}
                origin_file_lines = None
                if line_origin is not None:
                    orig = line_origin[ln - 1]
                    if orig is not None:
                        rec['file'] = orig[0]
                        rec['orig'] = orig[1]
                        origin_file_lines = read_file(orig[0])
                # enclosing function: prefer the original source file if accessible,
                # else fall back to the combined p8 (line numbers are still valid there).
                func = None
                if origin_file_lines:
                    func = find_enclosing_function(origin_file_lines, rec['orig'])
                if func is None:
                    func = find_enclosing_function(p8_lines, ln)
                if func:
                    rec['func'] = func
                out[name] = rec
        else:
            mf = FILE_LINE_RE.match(name)
            if mf:
                path = mf.group(1)
                ln   = int(mf.group(2))
                lines = read_file(path)
                if lines and 1 <= ln <= len(lines):
                    rec = {'line': lines[ln - 1], 'file': path, 'orig': ln}
                    func = find_enclosing_function(lines, ln)
                    if func:
                        rec['func'] = func
                    out[name] = rec

        for c in n['children'].values():
            visit(c)

    visit(tree)
    return out


def to_jsonable(node):
    """Convert tree (dict of children) to JSON form with children as a sorted list."""
    children = [to_jsonable(c) for c in node['children'].values()]
    children.sort(key=lambda x: -x['t'])
    return {
        'n': node['name'],
        't': node['total'],
        's': node['self'],
        'c': children,
    }


def aggregate_frames(samples, sources, n=100):
    """For each unique frame, sum inclusive samples (deduped per stack).

    Returned list is sorted by total samples desc, limited to top n.
    pct is over total samples (so it won't sum to 100% — frames overlap on stacks).
    """
    inc = {}
    sites = {}  # how many distinct stacks contain this frame
    for frames, c in samples:
        for k in set(frames):
            inc[k] = inc.get(k, 0) + c
            sites[k] = sites.get(k, 0) + 1
    total = sum(c for _, c in samples) or 1
    items = sorted(inc.items(), key=lambda kv: -kv[1])[:n]
    out = []
    for name, count in items:
        rec = sources.get(name, {})
        origin = ''
        if 'file' in rec and 'orig' in rec:
            origin = f"{rec['file']}:{rec['orig']}"
        src = (rec.get('line') or '').strip()
        out.append({
            'name':   name,
            'count':  count,
            'pct':    100.0 * count / total,
            'sites':  sites[name],
            'src':    src,
            'origin': origin,
            'func':   rec.get('func', ''),
        })
    return out


def top_lines(samples, sources, n=20):
    """Aggregate sample counts by leaf frame; use pre-resolved sources for source/origin/func."""
    leaf_counts = {}
    for frames, c in samples:
        leaf_counts[frames[-1]] = leaf_counts.get(frames[-1], 0) + c
    items = sorted(leaf_counts.items(), key=lambda kv: -kv[1])[:n]
    total = sum(leaf_counts.values())
    out = []
    for name, c in items:
        rec = sources.get(name, {})
        origin = ''
        if 'file' in rec and 'orig' in rec:
            origin = f"{rec['file']}:{rec['orig']}"
        src = (rec.get('line') or '').strip()
        out.append({'name': name, 'count': c, 'pct': 100.0 * c / total,
                    'src': src, 'origin': origin, 'func': rec.get('func', '')})
    return out


HTML_TEMPLATE = r"""<!doctype html>
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

const flame    = document.getElementById('flame');
const tooltip  = document.getElementById('tooltip');
const statusEl = document.getElementById('status');
const crumbEl  = document.getElementById('breadcrumb');
const ROW_H    = 19;

// attach parent refs so we can walk up for the breadcrumb
(function attachParents(n, p) { n._parent = p; for (const c of n.c) attachParents(c, n); })(tree, null);

let rootView  = tree;
let searchTxt = '';
let labelMode = 'frame'; // 'frame' or 'source'

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
      ? `<span style="color:#fff">${lbl}</span>`
      : `<a href="#" data-idx="${i}" style="color:#9cf; text-decoration:none">${lbl}</a>`;
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
  // warm "flame" palette
  return `hsl(${hue}, 75%, 60%)`;
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
  let h = `<b>${escapeHtml(node.n)}</b><br>`;
  h += `samples (inclusive): <b>${node.t}</b> (${pct}%)<br>`;
  h += `samples (self):      <b>${node.s}</b> (${selfPct}%)<br>`;
  const info = srcInfoFor(node.n);
  if (info !== null) {
    if (info.file) {
      h += `<br>from: <b>${escapeHtml(info.file)}</b>:${info.orig}<br>`;
    }
    if (info.func) {
      h += `function: <b>${escapeHtml(info.func)}</b><br>`;
    }
    if (info.line !== undefined) {
      h += `source line:<br><span style="color:#048">${escapeHtml(info.line)}</span><br>`;
    }
  }
  h += `<br>stack:<br><span style="color:#444">${escapeHtml(stackPath)}</span>`;
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
  statusEl.textContent =
    ` | ${rootView.t} samples (${(100*rootView.t/tree.t).toFixed(1)}% of total)`;
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
  let html = '<table class="top"><tr><th>#</th><th>samples</th><th>%</th>'
           + (includeSites ? '<th>stacks</th>' : '')
           + '<th>frame</th><th>origin</th><th>function</th><th>source line</th></tr>';
  rows.forEach((r, i) => {
    const w = Math.round(100 * r.count / max);
    html += `<tr>
      <td>${i+1}</td>
      <td>${r.count}</td>
      <td>${r.pct.toFixed(2)}%<div class="bar1"><div style="width:${w}%"></div></div></td>
      ${includeSites ? `<td>${r.sites}</td>` : ''}
      <td>${escapeHtml(r.name)}</td>
      <td>${escapeHtml(r.origin || '')}</td>
      <td>${escapeHtml(r.func || '')}</td>
      <td class="src">${escapeHtml(r.src || '')}</td>
    </tr>`;
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

// tabs
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
"""


def main():
    args = sys.argv[1:]
    prof_path = args[0] if len(args) >= 1 else 'prof.txt'
    out_path  = args[1] if len(args) >= 2 else 'prof.html'
    p8_path   = args[2] if len(args) >= 3 else 'schifahren-game-combined.p8'

    if not os.path.exists(prof_path):
        print(f'ERROR: {prof_path} not found', file=sys.stderr)
        sys.exit(1)

    print(f'reading {prof_path}')
    samples, info = parse_prof(prof_path)
    if info.get('unsupported_format'):
        print('ERROR: prof.txt does not look like LuaJIT G-format folded stacks.',
              file=sys.stderr)
        print('  re-run with mode containing "G", e.g. jit.p.start("Gl,prof.txt")',
              file=sys.stderr)
        sys.exit(2)
    total = sum(c for _, c in samples)
    info['total_samples'] = total
    info['sample_groups'] = len(samples)
    print(f'parsed {len(samples)} sample groups, {total} samples total'
          + (f', split-mode-3 dedupe applied ({info["dup_skipped"]} dup lines skipped)'
             if info['split_mode_3'] else ''))

    p8_lines = load_p8(p8_path)
    if p8_lines:
        print(f'loaded {p8_path} ({len(p8_lines)} lines)')
        info['p8_file'] = p8_path
        info['p8_lines'] = len(p8_lines)
    else:
        print(f'note: {p8_path} not found - [string]:N source lookup disabled')

    print('building tree...')
    tree = build_tree(samples)
    line_origin = build_line_origin(p8_lines) if p8_lines else None
    if line_origin is not None:
        attributed = sum(1 for x in line_origin if x is not None)
        print(f'  built line-origin map: {attributed}/{len(line_origin)} lines attributed to source files')
    base_dir = os.path.dirname(os.path.abspath(prof_path)) or '.'
    sources = collect_sources(tree, p8_lines, line_origin, base_dir)
    n_string = sum(1 for k in sources if k.startswith('[string]:'))
    n_file   = len(sources) - n_string
    n_func   = sum(1 for v in sources.values() if 'func' in v)
    print(f'  resolved frames: [string]:N={n_string}, file.lua:N={n_file} '
          f'({n_func} with enclosing-function name)')

    payload = to_jsonable(tree)
    top = top_lines(samples, sources, n=30)
    all_frames_list = aggregate_frames(samples, sources, n=100)

    def emb(obj):
        # protect against literal </script> inside JSON-escaped source text
        return json.dumps(obj, ensure_ascii=False).replace('</', '<\\/')

    html = HTML_TEMPLATE
    html = html.replace('%%TOTAL%%',   str(total))
    html = html.replace('%%FILE%%',    html_lib.escape(os.path.basename(prof_path)))
    html = html.replace('%%DATA%%',    emb(payload))
    html = html.replace('%%SOURCES%%', emb(sources))
    html = html.replace('%%TOP%%',     emb(top))
    html = html.replace('%%ALL%%',     emb(all_frames_list))
    html = html.replace('%%INFO%%',    emb(info))

    with open(out_path, 'w', encoding='utf-8') as f:
        f.write(html)
    print(f'wrote {out_path}  ({os.path.getsize(out_path)} bytes)')


if __name__ == '__main__':
    main()
