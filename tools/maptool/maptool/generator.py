"""Self-contained HTML generator for function dependency tree.

Generates a single HTML file with embedded JSON data and vanilla JavaScript
for an interactive collapsible tree view, search, and detail panel.
"""

import json
import os
from typing import Dict, List, Optional

from .callgraph import TreeResult
from .parser import ParseResult


# Color thresholds for size indicators
COLOR_GREEN_MAX = 100    # bytes: small
COLOR_YELLOW_MAX = 500   # bytes: medium
# > 500 = red (large)

# Size formatting: 1024 = "1.00 KB"
def format_size(bytes_val: int) -> str:
    """Format byte size to human-readable string."""
    if bytes_val >= 1024:
        kb = bytes_val / 1024.0
        if kb >= 1024:
            return f"{kb / 1024:.2f} MB"
        return f"{kb:.2f} KB"
    return f"{bytes_val} B"


def get_size_class(flash_size: int) -> str:
    """Get CSS class for size-based coloring."""
    if flash_size < COLOR_GREEN_MAX:
        return "size-small"
    elif flash_size < COLOR_YELLOW_MAX:
        return "size-medium"
    else:
        return "size-large"


def generate_html(tree_result: TreeResult,
                  parse_result: ParseResult,
                  output_path: str,
                  title: str = "Function Dependency Tree",
                  include_d3: bool = False) -> str:
    """Generate a self-contained HTML file and write it to output_path.

    Args:
        tree_result: Built call graph tree.
        parse_result: Parsed map file data (for grand totals).
        output_path: Path to write the HTML file.
        title: HTML page title.
        include_d3: If True, include D3.js force graph view.

    Returns:
        The path to the generated file.
    """
    # Prepare JSON data for embedding
    json_data = _build_json_data(tree_result, parse_result)

    html = _render_html(json_data, title, include_d3)

    # Ensure output directory exists
    os.makedirs(os.path.dirname(os.path.abspath(output_path)), exist_ok=True)

    with open(output_path, 'w', encoding='utf-8') as f:
        f.write(html)

    return output_path


def _build_json_data(tree_result: TreeResult,
                     parse_result: ParseResult) -> dict:
    """Build the JSON data structure for embedding."""
    nodes_data = {}
    for name, node in tree_result.nodes.items():
        nodes_data[name] = {
            'n': node.name,
            's': node.source_file,
            'f': node.flash_size,
            'rd': node.ram_data,
            'rb': node.ram_bss,
            'c': node.callees,
            'p': node.callers,
            'd': node.depth,
            'sf': node.subtree_flash,
            'nn': node.is_named,
        }

    return {
        'nodes': nodes_data,
        'roots': tree_result.roots,
        'all_funcs': tree_result.all_functions,
        'unreachable': tree_result.unreachable_functions,
        'stats': {
            'total_funcs': tree_result.total_functions,
            'total_edges': tree_result.total_edges,
            'total_flash': parse_result.grand_totals.get('total_flash', tree_result.total_flash_sum),
            'total_ram': parse_result.grand_totals.get('total_ram', tree_result.total_ram_sum),
            'total_code': parse_result.grand_totals.get('code', 0),
            'total_ro': parse_result.grand_totals.get('ro_data', 0),
            'total_rw': parse_result.grand_totals.get('rw_data', 0),
            'total_zi': parse_result.grand_totals.get('zi_data', 0),
            'max_depth': tree_result.max_depth,
            'target_name': parse_result.target_name,
            'tree_flash_sum': tree_result.total_flash_sum,
            'tree_ram_sum': tree_result.total_ram_sum,
        },
    }


def _render_html(json_data: dict, title: str, include_d3: bool) -> str:
    """Render the complete HTML document."""
    json_str = json.dumps(json_data, ensure_ascii=False, separators=(',', ':'))

    d3_script = ''
    d3_view_button = ''
    if include_d3:
        d3_script = '<script src="https://d3js.org/d3.v7.min.js"></script>'
        d3_view_button = '<button id="btn-d3-view" onclick="switchToD3()" class="view-btn">&#9671; Force Graph</button>'

    return f'''<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>{title}</title>
{d3_script}
<style>
* {{ margin: 0; padding: 0; box-sizing: border-box; }}

body {{
    font-family: 'Segoe UI', system-ui, -apple-system, sans-serif;
    background: #0d1117;
    color: #c9d1d9;
    height: 100vh;
    display: flex;
    flex-direction: column;
    overflow: hidden;
}}

/* Top Bar */
.top-bar {{
    background: #161b22;
    border-bottom: 1px solid #30363d;
    padding: 10px 20px;
    display: flex;
    align-items: center;
    gap: 16px;
    flex-shrink: 0;
}}
.top-bar h1 {{
    font-size: 16px;
    font-weight: 600;
    color: #f0f6fc;
    white-space: nowrap;
}}
.top-bar .stats {{
    display: flex;
    gap: 16px;
    font-size: 12px;
    color: #8b949e;
}}
.top-bar .stats span {{
    white-space: nowrap;
}}
.top-bar .stat-val {{
    color: #79c0ff;
    font-weight: 600;
}}
.search-box {{
    flex: 1;
    max-width: 400px;
    margin-left: auto;
}}
.search-box input {{
    width: 100%;
    padding: 6px 12px;
    background: #0d1117;
    border: 1px solid #30363d;
    border-radius: 6px;
    color: #c9d1d9;
    font-size: 13px;
    outline: none;
}}
.search-box input:focus {{
    border-color: #58a6ff;
}}
.search-results {{
    position: absolute;
    background: #161b22;
    border: 1px solid #30363d;
    border-radius: 6px;
    max-height: 300px;
    overflow-y: auto;
    z-index: 100;
    display: none;
    margin-top: 4px;
    box-shadow: 0 8px 24px rgba(0,0,0,0.4);
}}
.search-result-item {{
    padding: 6px 12px;
    cursor: pointer;
    font-size: 12px;
    display: flex;
    justify-content: space-between;
    gap: 16px;
}}
.search-result-item:hover {{
    background: #1f6feb33;
}}
.search-result-item .sr-name {{
    color: #79c0ff;
    font-family: 'Cascadia Code', 'Fira Code', 'Consolas', monospace;
}}
.search-result-item .sr-info {{
    color: #8b949e;
    font-size: 11px;
}}
.view-btn {{
    background: #21262d;
    border: 1px solid #30363d;
    color: #c9d1d9;
    padding: 6px 12px;
    border-radius: 6px;
    cursor: pointer;
    font-size: 12px;
}}
.view-btn:hover {{
    background: #30363d;
}}

/* Main Content */
.main-content {{
    display: flex;
    flex: 1;
    overflow: hidden;
}}

/* Tree Panel */
.tree-panel {{
    flex: 0 0 60%;
    overflow: auto;
    border-right: 1px solid #30363d;
    padding: 8px 0;
}}
.tree-panel.full-width {{
    flex: 1 1 100%;
}}

/* Detail Panel */
.detail-panel {{
    flex: 0 0 40%;
    overflow-y: auto;
    padding: 16px;
    background: #0d1117;
}}
.detail-panel.hidden {{
    display: none;
}}
.detail-card {{
    position: sticky;
    top: 16px;
}}
.detail-card h2 {{
    font-size: 18px;
    font-family: 'Cascadia Code', 'Fira Code', 'Consolas', monospace;
    color: #79c0ff;
    margin-bottom: 12px;
}}
.detail-card .detail-row {{
    display: flex;
    justify-content: space-between;
    padding: 6px 0;
    border-bottom: 1px solid #21262d;
    font-size: 13px;
}}
.detail-card .detail-label {{
    color: #8b949e;
}}
.detail-card .detail-val {{
    color: #c9d1d9;
    font-family: 'Cascadia Code', 'Fira Code', 'Consolas', monospace;
}}
.detail-card .detail-callees {{
    margin-top: 12px;
}}
.detail-card .detail-callees h3 {{
    font-size: 13px;
    color: #8b949e;
    margin-bottom: 8px;
}}
.callee-list {{
    max-height: 400px;
    overflow-y: auto;
}}
.callee-item {{
    display: flex;
    align-items: center;
    padding: 4px 8px;
    cursor: pointer;
    border-radius: 4px;
    font-size: 12px;
    gap: 8px;
}}
.callee-item:hover {{
    background: #1f6feb33;
}}
.callee-item .callee-name {{
    font-family: 'Cascadia Code', 'Fira Code', 'Consolas', monospace;
    color: #79c0ff;
    flex: 1;
}}
.callee-item .callee-size {{
    color: #8b949e;
    font-size: 11px;
}}
.size-bar-mini {{
    display: inline-block;
    height: 4px;
    border-radius: 2px;
    vertical-align: middle;
    margin-right: 4px;
}}
.size-small .size-bar-mini {{ background: #3fb950; }}
.size-medium .size-bar-mini {{ background: #d29922; }}
.size-large .size-bar-mini {{ background: #f85149; }}

/* Tree Node */
.tree-node {{
    white-space: nowrap;
    user-select: none;
}}
.tree-row {{
    display: flex;
    align-items: center;
    padding: 2px 8px;
    cursor: pointer;
    font-size: 13px;
    gap: 4px;
    border-left: 3px solid transparent;
}}
.tree-row:hover {{
    background: #1f6feb22;
}}
.tree-row.selected {{
    background: #1f6feb44;
    border-left-color: #58a6ff;
}}
.tree-row.highlight {{
    background: #d2992233;
    border-left-color: #d29922;
}}
.tree-arrow {{
    width: 16px;
    height: 16px;
    display: inline-flex;
    align-items: center;
    justify-content: center;
    font-size: 10px;
    color: #8b949e;
    flex-shrink: 0;
    transition: transform 0.15s;
}}
.tree-arrow.expanded {{
    transform: rotate(90deg);
}}
.tree-arrow.no-children {{
    visibility: hidden;
}}
.tree-icon {{
    width: 14px;
    height: 14px;
    display: inline-flex;
    align-items: center;
    justify-content: center;
    font-size: 11px;
    flex-shrink: 0;
}}
.tree-name {{
    font-family: 'Cascadia Code', 'Fira Code', 'Consolas', monospace;
    color: #c9d1d9;
    flex: 1;
    overflow: hidden;
    text-overflow: ellipsis;
}}
.tree-name.root-func {{
    color: #f0f6fc;
    font-weight: 600;
}}
.tree-name.anon-func {{
    color: #8b949e;
    font-style: italic;
}}
.tree-size {{
    font-size: 11px;
    color: #8b949e;
    min-width: 70px;
    text-align: right;
    flex-shrink: 0;
}}
.tree-subtree {{
    font-size: 10px;
    color: #484f58;
    min-width: 60px;
    text-align: right;
    flex-shrink: 0;
}}
.tree-size-bar {{
    display: inline-block;
    height: 6px;
    border-radius: 3px;
    min-width: 3px;
    flex-shrink: 0;
    margin: 0 4px;
}}
.size-small .tree-size-bar {{ background: #3fb950; }}
.size-medium .tree-size-bar {{ background: #d29922; }}
.size-large .tree-size-bar {{ background: #f85149; }}

.tree-children {{
    display: none;
}}
.tree-children.expanded {{
    display: block;
}}

/* Loading & Empty states */
.loading {{
    display: flex;
    align-items: center;
    justify-content: center;
    height: 200px;
    color: #8b949e;
    font-size: 14px;
}}
.empty-state {{
    text-align: center;
    padding: 40px;
    color: #8b949e;
}}
.empty-state h3 {{
    margin-bottom: 8px;
    color: #c9d1d9;
}}

/* D3 Graph */
#d3-view {{
    display: none;
    width: 100%;
    height: 100%;
}}
#d3-view.active {{
    display: block;
}}
.d3-tooltip {{
    position: absolute;
    background: #161b22;
    border: 1px solid #30363d;
    border-radius: 6px;
    padding: 8px 12px;
    font-size: 12px;
    pointer-events: none;
    z-index: 200;
}}

/* Legend */
.legend {{
    display: flex;
    gap: 12px;
    padding: 4px 12px;
    font-size: 11px;
    color: #8b949e;
    align-items: center;
}}
.legend-dot {{
    width: 8px;
    height: 8px;
    border-radius: 50%;
    display: inline-block;
}}
.legend-dot.green {{ background: #3fb950; }}
.legend-dot.yellow {{ background: #d29922; }}
.legend-dot.red {{ background: #f85149; }}

/* Scrollbar */
::-webkit-scrollbar {{ width: 8px; height: 8px; }}
::-webkit-scrollbar-track {{ background: #0d1117; }}
::-webkit-scrollbar-thumb {{ background: #30363d; border-radius: 4px; }}
::-webkit-scrollbar-thumb:hover {{ background: #484f58; }}
</style>
</head>
<body>

<!-- Top Bar -->
<div class="top-bar">
    <h1>{title}</h1>
    <div class="stats" id="stats-bar">
        <span>Funcs: <span class="stat-val" id="stat-funcs">-</span></span>
        <span>Edges: <span class="stat-val" id="stat-edges">-</span></span>
        <span>Flash: <span class="stat-val" id="stat-flash">-</span></span>
        <span>RAM: <span class="stat-val" id="stat-ram">-</span></span>
    </div>
    <div class="search-box" style="position:relative">
        <input type="text" id="search-input" placeholder="Search functions..."
               autocomplete="off">
        <div class="search-results" id="search-results"></div>
    </div>
    {d3_view_button}
</div>

<!-- Legend -->
<div class="legend">
    Size: <span class="legend-dot green"></span> &lt;100B
    <span class="legend-dot yellow"></span> 100-500B
    <span class="legend-dot red"></span> &gt;500B
    &nbsp;|&nbsp; Click function to see details &nbsp;|&nbsp; Arrow to expand/collapse
</div>

<!-- Main Content -->
<div class="main-content">
    <div class="tree-panel" id="tree-panel">
        <div class="loading" id="tree-loading">Building tree...</div>
    </div>
    <div class="detail-panel" id="detail-panel">
        <div class="empty-state">
            <h3>Function Details</h3>
            <p>Click a function in the tree to see details</p>
        </div>
    </div>
</div>

<!-- D3 View Container -->
<div id="d3-view">
    <div class="d3-tooltip" id="d3-tooltip" style="display:none"></div>
</div>

<script>
// ==================== Embedded Data ====================
const TREE_DATA = {json_str};

// ==================== Global State ====================
let selectedNode = null;
let expandedNodes = new Set();
const MAX_BAR_WIDTH = 120;

// ==================== Size Utilities ====================
function formatSize(bytes) {{
    if (bytes >= 1048576) return (bytes / 1048576).toFixed(2) + ' MB';
    if (bytes >= 1024) return (bytes / 1024).toFixed(2) + ' KB';
    return bytes + ' B';
}}

function getSizeClass(bytes) {{
    if (bytes < 100) return 'size-small';
    if (bytes < 500) return 'size-medium';
    return 'size-large';
}}

function getBarWidth(bytes, maxBytes) {{
    if (maxBytes === 0) return 0;
    return Math.max(3, Math.min(MAX_BAR_WIDTH, (bytes / maxBytes) * MAX_BAR_WIDTH));
}}

// ==================== Initialization ====================
document.addEventListener('DOMContentLoaded', function() {{
    const data = TREE_DATA;
    const maxFlash = Math.max(...Object.values(data.nodes).map(n => n.f || 0), 1);

    // Update stats bar
    document.getElementById('stat-funcs').textContent = data.stats.total_funcs;
    document.getElementById('stat-edges').textContent = data.stats.total_edges;
    document.getElementById('stat-flash').textContent = formatSize(data.stats.total_flash);
    document.getElementById('stat-ram').textContent = formatSize(data.stats.total_ram);

    // Build tree
    const treePanel = document.getElementById('tree-panel');
    document.getElementById('tree-loading').remove();

    // Primary entry points to auto-expand (well-known boot chain)
    const primaryEntries = new Set([
        'UserMain', 'luat_main', 'main', 'task_start',
        'Reset_Handler', 'xPortSysTickHandler'
    ]);

    data.roots.forEach(root => {{
        if (data.nodes[root]) {{
            const nodeEl = createTreeNode(root, data, maxFlash, 0);
            treePanel.appendChild(nodeEl);
            // Auto-expand only primary entry points (max 2 levels)
            if (primaryEntries.has(root)) {{
                autoExpand(root, data, 2);
            }}
        }}
    }});

    // If there are many roots, show a note
    if (data.roots.length > 100) {{
        const note = document.createElement('div');
        note.style.cssText = 'padding:8px 16px;font-size:12px;color:#8b949e;border-bottom:1px solid #21262d';
        note.innerHTML = `Showing ${{data.roots.length}} root functions. `
            + `Only primary entry points are pre-expanded. `
            + `Click <b style="color:#79c0ff">&#9654;</b> arrows to explore.`;
        treePanel.insertBefore(note, treePanel.firstChild);
    }}

    // Search setup
    setupSearch(data);

    // Keyboard navigation
    document.addEventListener('keydown', function(e) {{
        if (e.key === 'Escape') {{
            document.getElementById('search-input').value = '';
            document.getElementById('search-results').style.display = 'none';
        }}
    }});
}});

// ==================== Tree Rendering ====================
function createTreeNode(name, data, maxFlash, indent) {{
    const node = data.nodes[name];
    if (!node) return document.createTextNode('');

    const hasChildren = node.c && node.c.length > 0;
    const sizeClass = getSizeClass(node.f);
    const barWidth = getBarWidth(node.f, maxFlash);

    const container = document.createElement('div');
    container.className = 'tree-node';
    container.setAttribute('data-name', name);

    // Row
    const row = document.createElement('div');
    row.className = 'tree-row ' + sizeClass;
    row.style.paddingLeft = (8 + indent * 16) + 'px';
    row.setAttribute('data-name', name);
    row.onclick = function(e) {{ selectNode(name, data, row, e); }};

    // Arrow
    const arrow = document.createElement('span');
    arrow.className = 'tree-arrow' + (hasChildren ? '' : ' no-children');
    arrow.textContent = '▶';
    if (hasChildren) {{
        arrow.onclick = function(e) {{
            e.stopPropagation();
            toggleChildren(name, container, data, maxFlash, indent);
        }};
    }}
    row.appendChild(arrow);

    // Icon
    const icon = document.createElement('span');
    icon.className = 'tree-icon';
    icon.textContent = hasChildren ? '📁' : '📄';
    row.appendChild(icon);

    // Size bar
    const bar = document.createElement('span');
    bar.className = 'tree-size-bar';
    bar.style.width = barWidth + 'px';
    row.appendChild(bar);

    // Name
    const nameSpan = document.createElement('span');
    nameSpan.className = 'tree-name';
    if (data.roots.includes(name)) {{
        nameSpan.classList.add('root-func');
    }}
    if (!node.nn) {{
        nameSpan.classList.add('anon-func');
    }}
    nameSpan.textContent = name;
    row.appendChild(nameSpan);

    // Flash size
    const sizeSpan = document.createElement('span');
    sizeSpan.className = 'tree-size';
    sizeSpan.textContent = formatSize(node.f);
    row.appendChild(sizeSpan);

    // Subtree size (lighter)
    if (node.sf && node.sf > node.f) {{
        const subSpan = document.createElement('span');
        subSpan.className = 'tree-subtree';
        subSpan.textContent = '∑ ' + formatSize(node.sf);
        row.appendChild(subSpan);
    }}

    container.appendChild(row);

    // Children container
    if (hasChildren) {{
        const childrenDiv = document.createElement('div');
        childrenDiv.className = 'tree-children';
        childrenDiv.setAttribute('data-parent', name);
        container.appendChild(childrenDiv);
    }}

    return container;
}}

function toggleChildren(name, container, data, maxFlash, indent) {{
    const childrenDiv = container.querySelector('.tree-children');
    if (!childrenDiv) return;

    const arrow = container.querySelector('.tree-arrow');

    if (childrenDiv.classList.contains('expanded')) {{
        // Collapse
        childrenDiv.classList.remove('expanded');
        arrow.classList.remove('expanded');
        expandedNodes.delete(name);
    }} else {{
        // Expand - lazy create children
        if (childrenDiv.children.length === 0) {{
            const node = data.nodes[name];
            if (node.c) {{
                node.c.forEach(callee => {{
                    if (data.nodes[callee]) {{
                        const childEl = createTreeNode(callee, data, maxFlash, indent + 1);
                        childrenDiv.appendChild(childEl);
                    }}
                }});
            }}
        }}
        childrenDiv.classList.add('expanded');
        arrow.classList.add('expanded');
        expandedNodes.add(name);
    }}
}}

function autoExpand(name, data, maxDepth) {{
    const node = data.nodes[name];
    if (!node || node.d >= maxDepth) return;

    const container = document.querySelector(`.tree-node[data-name="${{CSS.escape(name)}}"]`);
    if (!container) return;

    const childrenDiv = container.querySelector('.tree-children');
    const arrow = container.querySelector('.tree-arrow');
    if (!childrenDiv || !arrow || childrenDiv.children.length > 0) return;

    // Expand this node
    if (node.c) {{
        const maxFlash = Math.max(...Object.values(data.nodes).map(n => n.f || 0), 1);
        node.c.forEach(callee => {{
            if (data.nodes[callee]) {{
                const childEl = createTreeNode(callee, data, maxFlash, node.d + 1);
                childrenDiv.appendChild(childEl);
            }}
        }});
    }}
    childrenDiv.classList.add('expanded');
    arrow.classList.add('expanded');
    expandedNodes.add(name);

    // Recurse for next level
    if (node.d < maxDepth - 1 && node.c) {{
        // Use setTimeout to allow DOM to render
        node.c.forEach(callee => {{
            if (data.nodes[callee] && data.nodes[callee].d < maxDepth) {{
                autoExpand(callee, data, maxDepth);
            }}
        }});
    }}
}}

// ==================== Selection & Detail Panel ====================
function selectNode(name, data, row, event) {{
    // Deselect previous
    if (selectedNode) {{
        const prevRow = document.querySelector(`.tree-row[data-name="${{CSS.escape(selectedNode)}}"]`);
        if (prevRow) prevRow.classList.remove('selected');
    }}

    selectedNode = name;
    row.classList.add('selected');

    // Show detail panel
    showDetail(name, data);

    // Scroll to make visible
    row.scrollIntoView({{ behavior: 'smooth', block: 'nearest' }});
}}

function showDetail(name, data) {{
    const node = data.nodes[name];
    if (!node) return;

    const panel = document.getElementById('detail-panel');
    panel.innerHTML = '';

    const card = document.createElement('div');
    card.className = 'detail-card';

    // Header
    const h2 = document.createElement('h2');
    h2.textContent = name;
    if (!node.nn) h2.style.color = '#8b949e';
    card.appendChild(h2);

    // Rows
    const rows = [
        ['Source', node.s || '(unknown)'],
        ['Flash Size', formatSize(node.f)],
        ['RAM (.data)', formatSize(node.rd)],
        ['RAM (.bss)', formatSize(node.rb)],
        ['Total RAM', formatSize(node.rd + node.rb)],
        ['Depth', node.d],
        ['Subtree Flash', formatSize(node.sf)],
        ['Callers', (node.p || []).length],
        ['Callees', (node.c || []).length],
    ];

    rows.forEach(([label, val]) => {{
        const row = document.createElement('div');
        row.className = 'detail-row';
        row.innerHTML = `<span class="detail-label">${{label}}</span><span class="detail-val">${{val}}</span>`;
        card.appendChild(row);
    }});

    // Callers quick list
    if (node.p && node.p.length > 0) {{
        const callersSection = document.createElement('div');
        callersSection.className = 'detail-callees';
        callersSection.innerHTML = '<h3>Called by (' + node.p.length + ')</h3>';
        const callerList = document.createElement('div');
        callerList.className = 'callee-list';
        node.p.slice(0, 50).forEach(caller => {{
            const item = createCalleeItem(caller, data);
            callerList.appendChild(item);
        }});
        if (node.p.length > 50) {{
            const more = document.createElement('div');
            more.className = 'callee-item';
            more.textContent = '... and ' + (node.p.length - 50) + ' more';
            callerList.appendChild(more);
        }}
        callersSection.appendChild(callerList);
        card.appendChild(callersSection);
    }}

    // Callees list
    if (node.c && node.c.length > 0) {{
        const calleesSection = document.createElement('div');
        calleesSection.className = 'detail-callees';
        calleesSection.innerHTML = '<h3>Calls (' + node.c.length + ')</h3>';
        const calleeList = document.createElement('div');
        calleeList.className = 'callee-list';

        // Sort callees by flash size descending
        const sortedCallees = [...node.c].sort((a, b) => {{
            const sa = (data.nodes[a] && data.nodes[a].f) || 0;
            const sb = (data.nodes[b] && data.nodes[b].f) || 0;
            return sb - sa;
        }});

        sortedCallees.forEach(callee => {{
            const item = createCalleeItem(callee, data);
            calleeList.appendChild(item);
        }});
        calleesSection.appendChild(calleeList);
        card.appendChild(calleesSection);
    }}

    panel.appendChild(card);
}}

function createCalleeItem(name, data) {{
    const node = data.nodes[name];
    const sizeClass = node ? getSizeClass(node.f) : 'size-small';

    const item = document.createElement('div');
    item.className = 'callee-item ' + sizeClass;
    item.onclick = function() {{ navigateTo(name, data); }};

    const bar = document.createElement('span');
    bar.className = 'size-bar-mini';
    const maxFlash = Math.max(...Object.values(data.nodes).map(n => n.f || 0), 1);
    bar.style.width = getBarWidth(node ? node.f : 0, maxFlash) + 'px';
    item.appendChild(bar);

    const nameSpan = document.createElement('span');
    nameSpan.className = 'callee-name';
    nameSpan.textContent = name;
    item.appendChild(nameSpan);

    const sizeSpan = document.createElement('span');
    sizeSpan.className = 'callee-size';
    sizeSpan.textContent = node ? formatSize(node.f) : '?';
    item.appendChild(sizeSpan);

    return item;
}}

function navigateTo(name, data) {{
    if (!data.nodes[name]) return;

    // Expand all ancestors
    expandAncestors(name, data);

    // Find and select the row
    setTimeout(() => {{
        const row = document.querySelector(`.tree-row[data-name="${{CSS.escape(name)}}"]`);
        if (row) {{
            // Clear previous highlight
            document.querySelectorAll('.tree-row.highlight').forEach(r => r.classList.remove('highlight'));
            row.classList.add('highlight');
            selectNode(name, data, row);
            row.scrollIntoView({{ behavior: 'smooth', block: 'center' }});
        }}
    }}, 100);
}}

function expandAncestors(name, data) {{
    const node = data.nodes[name];
    if (!node) return;

    // Find callers that lead back to roots
    function findPath(target, path, visited) {{
        if (visited.has(target)) return null;
        visited.add(target);

        const n = data.nodes[target];
        if (!n) return null;

        if (data.roots.includes(target)) {{
            return [target];
        }}

        for (const caller of (n.p || [])) {{
            if (data.nodes[caller] && data.nodes[caller].d < n.d) {{
                const subPath = findPath(caller, path, visited);
                if (subPath) {{
                    return [target, ...subPath];
                }}
            }}
        }}

        // Try any caller
        for (const caller of (n.p || [])) {{
            const subPath = findPath(caller, path, visited);
            if (subPath) {{
                return [target, ...subPath];
            }}
        }}

        return null;
    }}

    const path = findPath(name, [], new Set());
    if (path) {{
        const maxFlash = Math.max(...Object.values(data.nodes).map(n => n.f || 0), 1);
        // Expand each ancestor (from root to target, excluding target itself)
        path.slice(1).reverse().forEach(ancestor => {{
            const container = document.querySelector(`.tree-node[data-name="${{CSS.escape(ancestor)}}"]`);
            if (container) {{
                const childrenDiv = container.querySelector('.tree-children');
                const arrow = container.querySelector('.tree-arrow');
                if (childrenDiv && !childrenDiv.classList.contains('expanded')) {{
                    // Expand
                    if (childrenDiv.children.length === 0) {{
                        const an = data.nodes[ancestor];
                        if (an.c) {{
                            an.c.forEach(callee => {{
                                if (data.nodes[callee]) {{
                                    const childEl = createTreeNode(callee, data, maxFlash, an.d + 1);
                                    childrenDiv.appendChild(childEl);
                                }}
                            }});
                        }}
                    }}
                    childrenDiv.classList.add('expanded');
                    if (arrow) arrow.classList.add('expanded');
                    expandedNodes.add(ancestor);
                }}
            }}
        }});
    }}
}}

// ==================== Search ====================
function setupSearch(data) {{
    const input = document.getElementById('search-input');
    const resultsDiv = document.getElementById('search-results');

    // Build search index
    const searchIndex = Object.keys(data.nodes).map(name => ({{
        name: name,
        lower: name.toLowerCase(),
        source: data.nodes[name].s || '',
        flash: data.nodes[name].f || 0,
    }}));

    input.addEventListener('input', function() {{
        const query = this.value.trim().toLowerCase();
        if (query.length < 1) {{
            resultsDiv.style.display = 'none';
            return;
        }}

        const matches = searchIndex.filter(item =>
            item.lower.includes(query)
        ).slice(0, 50);

        if (matches.length === 0) {{
            resultsDiv.innerHTML = '<div class="search-result-item" style="color:#8b949e">No matches</div>';
            resultsDiv.style.display = 'block';
            return;
        }}

        resultsDiv.innerHTML = matches.map(m => `
            <div class="search-result-item" data-name="${{m.name.replace(/"/g, '&quot;')}}">
                <span class="sr-name">${{m.name}}</span>
                <span class="sr-info">${{formatSize(m.flash)}} &middot; ${{m.source}}</span>
            </div>
        `).join('');

        // Click handlers
        resultsDiv.querySelectorAll('.search-result-item').forEach(item => {{
            item.addEventListener('click', function() {{
                const name = this.getAttribute('data-name');
                resultsDiv.style.display = 'none';
                input.value = '';
                navigateTo(name, data);
            }});
        }});

        resultsDiv.style.display = 'block';
    }});

    // Hide results on click outside
    document.addEventListener('click', function(e) {{
        if (!resultsDiv.contains(e.target) && e.target !== input) {{
            resultsDiv.style.display = 'none';
        }}
    }});
}}

// ==================== D3 Force Graph (optional) ====================
function switchToD3() {{
    document.getElementById('tree-panel').style.display = 'none';
    document.getElementById('detail-panel').classList.add('hidden');
    document.getElementById('d3-view').classList.add('active');
    document.getElementById('search-input').disabled = true;

    if (window.d3GraphRendered) return;
    window.d3GraphRendered = true;

    renderD3Graph();
}}

var d3GraphRendered = false;

function renderD3Graph() {{
    if (typeof d3 === 'undefined') {{
        document.getElementById('d3-view').innerHTML =
            '<div class="empty-state"><h3>D3.js not loaded</h3><p>Use --d3 flag or include CDN script</p></div>';
        return;
    }}

    const data = TREE_DATA;
    const container = document.getElementById('d3-view');
    const width = container.clientWidth;
    const height = container.clientHeight;

    // Build nodes and links
    const nodes = [];
    const nodeMap = new Map();
    const links = [];

    // Only include reachable functions up to depth 3 (performance)
    Object.values(data.nodes).forEach(n => {{
        if (n.d <= 5) {{
            const id = n.n;
            if (!nodeMap.has(id)) {{
                nodeMap.set(id, {{
                    id: id,
                    name: n.n,
                    flash: n.f,
                    depth: n.d,
                    isRoot: data.roots.includes(n.n),
                }});
            }}
        }}
    }});

    // Build links
    Object.values(data.nodes).forEach(n => {{
        if (n.d <= 5 && n.c) {{
            n.c.forEach(callee => {{
                if (nodeMap.has(callee)) {{
                    links.push({{
                        source: n.n,
                        target: callee,
                    }});
                }}
            }});
        }}
    }});

    nodes.push(...nodeMap.values());

    const svg = d3.select('#d3-view').append('svg')
        .attr('width', width)
        .attr('height', height);

    const simulation = d3.forceSimulation(nodes)
        .force('link', d3.forceLink(links).id(d => d.id).distance(60))
        .force('charge', d3.forceManyBody().strength(-100))
        .force('center', d3.forceCenter(width / 2, height / 2))
        .force('collision', d3.forceCollide().radius(15));

    const link = svg.append('g')
        .selectAll('line')
        .data(links)
        .join('line')
        .attr('stroke', '#30363d')
        .attr('stroke-width', 0.5)
        .attr('stroke-opacity', 0.6);

    const node = svg.append('g')
        .selectAll('circle')
        .data(nodes)
        .join('circle')
        .attr('r', d => d.isRoot ? 6 : Math.max(2, Math.sqrt(d.flash) / 10))
        .attr('fill', d => {{
            if (d.flash < 100) return '#3fb950';
            if (d.flash < 500) return '#d29922';
            return '#f85149';
        }})
        .attr('stroke', d => d.isRoot ? '#f0f6fc' : 'none')
        .attr('stroke-width', d => d.isRoot ? 2 : 0)
        .call(d3.drag()
            .on('start', dragstarted)
            .on('drag', dragged)
            .on('end', dragended));

    const tooltip = document.getElementById('d3-tooltip');
    node.on('mouseover', function(event, d) {{
        tooltip.style.display = 'block';
        tooltip.innerHTML = `<strong>${{d.name}}</strong><br>Flash: ${{formatSize(d.flash)}}`;
        tooltip.style.left = (event.pageX + 10) + 'px';
        tooltip.style.top = (event.pageY - 10) + 'px';
    }})
    .on('mousemove', function(event) {{
        tooltip.style.left = (event.pageX + 10) + 'px';
        tooltip.style.top = (event.pageY - 10) + 'px';
    }})
    .on('mouseout', function() {{
        tooltip.style.display = 'none';
    }});

    simulation.on('tick', () => {{
        link
            .attr('x1', d => d.source.x)
            .attr('y1', d => d.source.y)
            .attr('x2', d => d.target.x)
            .attr('y2', d => d.target.y);
        node
            .attr('cx', d => d.x)
            .attr('cy', d => d.y);
    }});

    function dragstarted(event, d) {{
        if (!event.active) simulation.alphaTarget(0.3).restart();
        d.fx = d.x;
        d.fy = d.y;
    }}
    function dragged(event, d) {{
        d.fx = event.x;
        d.fy = event.y;
    }}
    function dragended(event, d) {{
        if (!event.active) simulation.alphaTarget(0);
        d.fx = null;
        d.fy = null;
    }}
}}
</script>
</body>
</html>'''


def generate_json_output(tree_result: TreeResult,
                         parse_result: ParseResult,
                         output_path: str) -> str:
    """Generate raw JSON data file.

    Args:
        tree_result: Built call graph tree.
        parse_result: Parsed map file data.
        output_path: Path to write JSON file.

    Returns:
        Path to the generated file.
    """
    json_data = _build_json_data(tree_result, parse_result)

    os.makedirs(os.path.dirname(os.path.abspath(output_path)), exist_ok=True)

    with open(output_path, 'w', encoding='utf-8') as f:
        json.dump(json_data, f, ensure_ascii=False, indent=2)

    return output_path
