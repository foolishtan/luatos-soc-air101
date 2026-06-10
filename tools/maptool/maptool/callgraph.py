"""Call graph builder.

Builds a function dependency tree from parsed map file data using BFS
from configurable entry points.
"""

from collections import deque
from dataclasses import dataclass, field
from typing import Dict, List, Optional, Set, Tuple

from .parser import CallEdge, FunctionInfo, ObjectRamInfo, ParseResult


@dataclass
class TreeNode:
    """A node in the function dependency tree."""
    name: str
    source_file: str
    flash_size: int          # own flash bytes
    ram_data: int            # RAM .data bytes (from object file)
    ram_bss: int             # RAM .bss bytes (from object file)
    depth: int               # depth from root
    callees: List[str] = field(default_factory=list)     # direct callee function names
    callers: List[str] = field(default_factory=list)     # direct caller function names
    subtree_flash: int = 0   # cumulative flash of self + all descendants
    is_named: bool = True
    is_anon_caller: bool = False


@dataclass
class TreeResult:
    """Complete call graph and tree result."""
    nodes: Dict[str, TreeNode] = field(default_factory=dict)
    roots: List[str] = field(default_factory=list)       # root function names
    all_functions: List[str] = field(default_factory=list)  # all reachable function names
    edge_count: int = 0
    total_flash_sum: int = 0
    total_ram_sum: int = 0
    # Stats
    total_functions: int = 0
    total_edges: int = 0
    max_depth: int = 0
    unreachable_functions: List[str] = field(default_factory=list)


def build_call_graph(parse_result: ParseResult,
                     entry_points: Optional[List[str]] = None,
                     max_depth: int = 20) -> TreeResult:
    """Build the function dependency tree from parsed map data.

    Args:
        parse_result: Parsed map file data.
        entry_points: List of entry function names. If None, auto-detect roots
                      (functions that are never called by anyone, or default entries).
        max_depth: Maximum tree depth to expand.

    Returns:
        TreeResult with nodes, roots, and statistics.
    """
    result = TreeResult()
    result.total_edges = len(parse_result.edges)

    # Build forward adjacency (caller -> set of callees) and reverse (callee -> set of callers)
    forward: Dict[str, Set[str]] = {}   # caller -> {callee, ...}
    reverse: Dict[str, Set[str]] = {}   # callee -> {caller, ...}

    for edge in parse_result.edges:
        caller = edge.caller_func
        callee = edge.callee_func

        if caller == callee:
            continue  # Skip self-references (shouldn't exist, but be safe)

        if caller not in forward:
            forward[caller] = set()
        forward[caller].add(callee)

        if callee not in reverse:
            reverse[callee] = set()
        reverse[callee].add(caller)

    # Determine entry points
    if entry_points:
        roots = entry_points
    else:
        # Auto-detect: functions that have no callers, or default entries
        auto_roots = []
        # Default entry points known in the system
        default_entries = ['UserMain', 'luat_main', 'main', 'task_start',
                          'Reset_Handler', 'xPortSysTickHandler']

        for entry in default_entries:
            if entry in parse_result.functions:
                auto_roots.append(entry)

        # Also include functions that have no callers (true roots)
        called_set = set(reverse.keys())
        for fname in parse_result.functions:
            if fname not in called_set and fname not in auto_roots:
                if not fname.startswith('<'):  # Skip anonymous callers
                    auto_roots.append(fname)

        roots = auto_roots  # Include all auto-detected roots

    result.roots = roots

    # BFS from each root
    visited: Set[str] = set()
    queue = deque()

    for root in roots:
        if root not in visited:
            visited.add(root)
            node = _make_tree_node(root, parse_result, reverse, depth=0)
            result.nodes[root] = node
            queue.append(root)

    while queue:
        current = queue.popleft()
        current_node = result.nodes[current]

        if current_node.depth >= max_depth:
            continue

        # Get callees
        callees = forward.get(current, set())
        current_node.callees = sorted(callees)

        for callee in callees:
            if callee not in visited:
                visited.add(callee)
                depth = current_node.depth + 1
                node = _make_tree_node(callee, parse_result, reverse, depth=depth)
                result.nodes[callee] = node
                queue.append(callee)

            # Record caller relationship (even for back-edges)
            if callee in result.nodes:
                if current not in result.nodes[callee].callers:
                    result.nodes[callee].callers.append(current)

    # Compute subtree cumulative sizes (post-order DFS)
    _compute_subtree_sizes(result.nodes, roots)

    # Collect all reachable functions
    result.all_functions = sorted(visited)
    result.total_functions = len(visited)

    # Find max depth
    if result.nodes:
        result.max_depth = max(n.depth for n in result.nodes.values())

    # Find unreachable functions (in parse_result but not visited)
    all_parse_funcs = set(parse_result.functions.keys())
    result.unreachable_functions = sorted(all_parse_funcs - visited)

    # Compute totals
    result.total_flash_sum = sum(n.flash_size for n in result.nodes.values())
    result.total_ram_sum = sum(n.ram_data + n.ram_bss for n in result.nodes.values())

    return result


def _make_tree_node(name: str, parse_result: ParseResult,
                    reverse: Dict[str, Set[str]], depth: int) -> TreeNode:
    """Create a TreeNode from parsed data."""
    func_info = parse_result.functions.get(name)
    if func_info:
        obj_file = func_info.object_file
        source_file = func_info.source_file
        flash_size = func_info.flash_size
        is_named = func_info.is_named
        is_anon = func_info.is_anonymous_caller
    else:
        obj_file = ""
        source_file = ""
        flash_size = 0
        is_named = True
        is_anon = False

    # Get RAM info from object file
    ram_info = parse_result.object_ram.get(obj_file, ObjectRamInfo())

    return TreeNode(
        name=name,
        source_file=source_file,
        flash_size=flash_size,
        ram_data=ram_info.data_size,
        ram_bss=ram_info.bss_size,
        depth=depth,
        is_named=is_named,
        is_anon_caller=is_anon,
    )


def _compute_subtree_sizes(nodes: Dict[str, TreeNode],
                            roots: List[str]) -> None:
    """Compute cumulative subtree flash sizes using post-order traversal.

    Since the call graph can have cycles (back-edges for shared functions),
    we compute on the DAG formed by the BFS tree structure. A function
    appears in multiple subtrees if called from multiple parents, but
    its subtree_flash is computed once based on its BFS-tree descendants.
    """
    # Build tree adjacency from the BFS structure
    # A node's subtree includes all nodes reachable from it in the BFS tree
    # (not through back-edges - back-edges go to already-visited nodes at
    # shallower or equal depth)

    visited = set()
    order = []  # post-order

    def dfs(name: str):
        if name in visited or name not in nodes:
            return
        visited.add(name)
        for callee in nodes[name].callees:
            if callee in nodes:
                # Only follow tree edges (callee is deeper)
                if nodes[callee].depth > nodes[name].depth:
                    dfs(callee)
        order.append(name)

    for root in roots:
        dfs(root)

    # Compute cumulative sizes in post-order
    computed = set()
    for name in order:
        if name not in nodes:
            continue
        node = nodes[name]
        total = node.flash_size
        for callee in node.callees:
            if callee in nodes and nodes[callee].depth > node.depth:
                # Only count unique subtree contributions
                callee_node = nodes[callee]
                total += callee_node.subtree_flash
        node.subtree_flash = total
        computed.add(name)
