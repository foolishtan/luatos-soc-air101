"""Map file parser for CSKY linker .map files.

Parses the CSKY linker map file in a single streaming pass, extracting:
- Cross-reference call edges (caller -> callee)
- Per-function flash sizes from Memory Map
- Per-object RAM data/bss sizes from Memory Map

Handles the naming mismatch between cross-references (which use symbol names
from the "for <symbol>" field) and anonymous .text sections in the memory map
(which only have object file paths). Uses a mapping built during cross-ref
parsing to attribute anonymous object sizes to their known symbol names.
"""

import re
from collections import defaultdict
from dataclasses import dataclass, field
from enum import Enum, auto
from typing import Dict, List, Optional, Set, Tuple


class ParseState(Enum):
    HEADER = auto()
    CROSS_REFS = auto()
    REMOVED_SECTIONS = auto()
    SYMBOL_TABLE = auto()
    MEMORY_MAP = auto()
    COMPONENT_SIZES = auto()
    DONE = auto()


@dataclass
class CallEdge:
    """A call edge from caller to callee."""
    caller_func: str       # resolved caller function name
    callee_func: str       # resolved callee function name (from "for" symbol)
    caller_obj: str        # normalized caller object path
    callee_obj: str        # normalized callee object path
    caller_section: str    # raw caller section (e.g. ".text.UserMain")
    callee_section: str    # raw callee section
    symbol: str            # the "for" symbol


@dataclass
class FunctionInfo:
    """Per-function flash/RAM information from Memory Map."""
    name: str
    object_file: str = ""
    source_file: str = ""
    base_address: int = 0
    flash_size: int = 0          # bytes in flash (.text)
    is_named: bool = True        # True if has `.text.funcname` section
    is_anonymous_caller: bool = False  # True if caller had bare `.text` section
    is_anon_object: bool = False  # True if from anonymous .text (prebuilt lib)


@dataclass
class ObjectRamInfo:
    """Per-object RAM usage from Memory Map."""
    data_size: int = 0  # .data section bytes
    bss_size: int = 0   # .bss section bytes


@dataclass
class ParseResult:
    """Complete parsed map file data."""
    edges: List[CallEdge] = field(default_factory=list)
    functions: Dict[str, FunctionInfo] = field(default_factory=dict)
    object_ram: Dict[str, ObjectRamInfo] = field(default_factory=dict)
    grand_totals: Dict[str, int] = field(default_factory=dict)
    target_name: str = ""


# Regex patterns
CROSS_REF_RE = re.compile(
    r'^\s*(.+?)\((.+?)\)\s+refers\s+to\s+(.+?)\((.+?)\)\s+for\s+(.+)$'
)

MEMORY_MAP_RE = re.compile(
    r'^\s*(0x[0-9a-fA-F]+)\s+(0x[0-9a-fA-F]+)\s+(\S+)\s+(\S+)\s+(\d+)\s+(\S+)\s+(.+)$'
)

COMPONENT_SIZE_RE = re.compile(
    r'^\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(.+)$'
)

TOTAL_RE = re.compile(
    r'^\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(.+)$'
)


def normalize_object_path(path: str) -> str:
    """Normalize object file path: strip backslashes and whitespace."""
    return path.strip().replace('\\', '/')


def extract_source_file(obj_path: str) -> str:
    """Derive source file name from object path."""
    path = obj_path
    if path.endswith('.o'):
        path = path[:-2]

    parts = path.split('/')
    markers = ['release', 'cross']
    for marker in markers:
        if marker in parts:
            idx = parts.index(marker)
            if idx + 3 < len(parts):
                return '/'.join(parts[idx + 3:]) + '.c'

    return parts[-1] + '.c'


def resolve_caller_name(obj_path: str, section_name: str) -> Tuple[str, bool]:
    """Resolve caller function name from object path and section.

    Returns (function_name, is_anonymous).
    """
    if section_name.startswith('.text.') and section_name != '.text':
        func_name = section_name[len('.text.'):]
        return func_name, False
    else:
        # Anonymous section - use object filename as synthetic identifier
        obj_base = obj_path.rsplit('/', 1)[-1] if '/' in obj_path else obj_path
        if obj_base.endswith('.o'):
            obj_base = obj_base[:-2]
        return f"<{obj_base}>", True


def parse_map_file(filepath: str) -> ParseResult:
    """Parse a CSKY linker map file.

    Uses a state-machine streaming parser. Cross-references are parsed first,
    building a mapping from object files to their known symbol names. Then the
    memory map is parsed, attributing sizes to named functions directly and
    distributing anonymous object sizes among their known symbols.

    Args:
        filepath: Path to the .map file.

    Returns:
        ParseResult containing edges, functions, object RAM info, and totals.
    """
    import os

    result = ParseResult()

    basename = os.path.basename(filepath)
    result.target_name = basename[:-4] if basename.endswith('.map') else basename

    # ---- Tracking maps built during cross-ref parsing ----
    # For anonymous callee objects, maps object_path -> set of symbol names
    obj_to_symbols: Dict[str, Set[str]] = defaultdict(set)
    # For anonymous caller objects too
    obj_to_callers: Dict[str, Set[str]] = defaultdict(set)
    # Accumulated code sizes for anonymous objects (filled during memory map)
    anon_obj_sizes: Dict[str, int] = defaultdict(int)

    state = ParseState.HEADER

    with open(filepath, 'r', encoding='utf-8', errors='replace') as f:
        for line in f:
            raw_line = line.rstrip('\n\r')

            if raw_line.startswith('======='):
                if state == ParseState.HEADER:
                    state = ParseState.CROSS_REFS
                elif state == ParseState.CROSS_REFS:
                    state = ParseState.REMOVED_SECTIONS
                elif state == ParseState.REMOVED_SECTIONS:
                    state = ParseState.SYMBOL_TABLE
                elif state == ParseState.SYMBOL_TABLE:
                    state = ParseState.MEMORY_MAP
                elif state == ParseState.MEMORY_MAP:
                    state = ParseState.COMPONENT_SIZES
                elif state == ParseState.COMPONENT_SIZES:
                    state = ParseState.DONE
                continue

            if state == ParseState.CROSS_REFS:
                _parse_cross_ref(raw_line, result, obj_to_symbols, obj_to_callers)
            elif state == ParseState.MEMORY_MAP:
                _parse_memory_map(raw_line, result, obj_to_symbols,
                                  obj_to_callers, anon_obj_sizes)
            elif state == ParseState.DONE:
                _parse_totals(raw_line, result)

    # ---- Post-process: distribute anonymous object sizes ----
    _distribute_anon_sizes(result, obj_to_symbols, obj_to_callers, anon_obj_sizes)

    return result


def _parse_cross_ref(line: str, result: ParseResult,
                     obj_to_symbols: Dict[str, Set[str]],
                     obj_to_callers: Dict[str, Set[str]]) -> None:
    """Parse a cross-reference line, building symbol mapping for anonymous sections."""
    m = CROSS_REF_RE.match(line)
    if not m:
        return

    caller_obj = normalize_object_path(m.group(1))
    caller_section = m.group(2).strip()
    callee_obj = normalize_object_path(m.group(3))
    callee_section = m.group(4).strip()
    symbol = m.group(5).strip()

    # Resolve caller function name
    caller_func, is_caller_anon = resolve_caller_name(caller_obj, caller_section)

    # Callee function name is always from the "for" symbol
    callee_func = symbol

    edge = CallEdge(
        caller_func=caller_func,
        callee_func=callee_func,
        caller_obj=caller_obj,
        callee_obj=callee_obj,
        caller_section=caller_section,
        callee_section=callee_section,
        symbol=symbol,
    )
    result.edges.append(edge)

    # Track symbol mapping for anonymous callee objects
    if callee_section == '.text' or not callee_section.startswith('.text.'):
        # Callee is from anonymous .text or non-.text. section
        obj_to_symbols[callee_obj].add(callee_func)

    # Track anonymous caller objects too
    if is_caller_anon:
        obj_to_callers[caller_obj].add(caller_func)

    # Register anonymous callers as functions
    if is_caller_anon and caller_func not in result.functions:
        result.functions[caller_func] = FunctionInfo(
            name=caller_func,
            object_file=caller_obj,
            source_file=extract_source_file(caller_obj),
            is_named=False,
            is_anonymous_caller=True,
        )


def _parse_memory_map(line: str, result: ParseResult,
                      obj_to_symbols: Dict[str, Set[str]],
                      obj_to_callers: Dict[str, Set[str]],
                      anon_obj_sizes: Dict[str, int]) -> None:
    """Parse a memory map entry, attributing sizes."""
    m = MEMORY_MAP_RE.match(line)
    if not m:
        return

    base_addr = int(m.group(1), 16)
    size = int(m.group(2), 16)
    entry_type = m.group(3).strip()
    attr = m.group(4).strip()
    section_name = m.group(6).strip()
    obj_path = normalize_object_path(m.group(7))

    if entry_type == 'PAD':
        return

    # Ensure object RAM tracker exists
    if obj_path not in result.object_ram:
        result.object_ram[obj_path] = ObjectRamInfo()

    if entry_type == 'Code':
        if section_name.startswith('.text.') and section_name != '.text':
            # Named function section: .text.UserMain -> function "UserMain"
            func_name = section_name[len('.text.'):]
            _add_or_update_func(result, func_name, obj_path, size, is_named=True)
        elif section_name == '.text':
            # Anonymous .text section (prebuilt libs, assembly)
            # Accumulate size; post-processing will distribute to known symbols
            anon_obj_sizes[obj_path] += size
        elif section_name.startswith('.text.'):
            # Other .text.* variants (could be .text.startup.main, etc.)
            func_name = section_name[len('.text.'):]
            _add_or_update_func(result, func_name, obj_path, size, is_named=True)
    elif entry_type == 'Data':
        result.object_ram[obj_path].data_size += size
    elif entry_type == 'Zero':
        result.object_ram[obj_path].bss_size += size


def _add_or_update_func(result: ParseResult, name: str, obj_path: str,
                         size: int, is_named: bool = True) -> None:
    """Add or update a function entry."""
    if name in result.functions:
        func = result.functions[name]
        func.flash_size += size
        if not func.object_file:
            func.object_file = obj_path
            func.source_file = extract_source_file(obj_path)
        func.is_named = is_named
    else:
        result.functions[name] = FunctionInfo(
            name=name,
            object_file=obj_path,
            source_file=extract_source_file(obj_path),
            flash_size=size,
            is_named=is_named,
        )


def _distribute_anon_sizes(result: ParseResult,
                            obj_to_symbols: Dict[str, Set[str]],
                            obj_to_callers: Dict[str, Set[str]],
                            anon_obj_sizes: Dict[str, int]) -> None:
    """Distribute accumulated anonymous object sizes to their known symbol names."""
    for obj_path, total_size in anon_obj_sizes.items():
        # Get all known symbols for this object (from both callee and caller maps)
        symbols = set()
        if obj_path in obj_to_symbols:
            symbols.update(obj_to_symbols[obj_path])
        if obj_path in obj_to_callers:
            symbols.update(obj_to_callers[obj_path])

        if not symbols:
            # No known symbols - create a single synthetic entry
            obj_key = obj_path.rsplit('/', 1)[-1] if '/' in obj_path else obj_path
            if obj_key.endswith('.o'):
                obj_key = obj_key[:-2]
            synth_name = f"<{obj_key}>"
            if synth_name not in result.functions:
                result.functions[synth_name] = FunctionInfo(
                    name=synth_name,
                    object_file=obj_path,
                    source_file=extract_source_file(obj_path),
                    flash_size=total_size,
                    is_named=False,
                    is_anon_object=True,
                )
            continue

        # Filter out synthetic names (those starting with <)
        real_symbols = {s for s in symbols if not s.startswith('<')}
        if not real_symbols:
            real_symbols = symbols

        count = len(real_symbols)

        # Distribute size proportionally
        # Simple approach: split evenly. A better approach would require
        # disassembling the object file, which is out of scope.
        per_func_size = total_size // count
        remainder = total_size - (per_func_size * count)

        sorted_symbols = sorted(real_symbols)
        for i, sym in enumerate(sorted_symbols):
            allocated = per_func_size + (1 if i < remainder else 0)
            # Don't overwrite if already set from a named section
            if sym in result.functions and result.functions[sym].is_named:
                continue
            if sym in result.functions:
                result.functions[sym].flash_size += allocated
            else:
                result.functions[sym] = FunctionInfo(
                    name=sym,
                    object_file=obj_path,
                    source_file=extract_source_file(obj_path),
                    flash_size=allocated,
                    is_named=False,
                    is_anon_object=True,
                )


def _parse_totals(line: str, result: ParseResult) -> None:
    """Parse grand totals."""
    m = TOTAL_RE.match(line)
    if m:
        label = m.group(6).strip()
        code = int(m.group(1))
        ro_data = int(m.group(2))
        rw_data = int(m.group(3))
        zi_data = int(m.group(4))

        if label == 'Grand Totals':
            result.grand_totals['code'] = code
            result.grand_totals['ro_data'] = ro_data
            result.grand_totals['rw_data'] = rw_data
            result.grand_totals['zi_data'] = zi_data
            result.grand_totals['total_flash'] = code + ro_data + rw_data
            result.grand_totals['total_ram'] = rw_data + zi_data
