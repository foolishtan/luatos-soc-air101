#!/usr/bin/env python3
"""Convenience script: Parse a CSKY linker map file and generate a function
dependency tree HTML page.

Usage:
    python scripts/generate_deps.py --map build/out/AIR6208.map
    python scripts/generate_deps.py --map build/out/AIR6208.map --entry UserMain --d3

This is a thin wrapper around `maptool.cli.main()`.
"""

import sys
from pathlib import Path

# Add parent directory to path so we can import maptool
sys.path.insert(0, str(Path(__file__).parent.parent))

from maptool.cli import main

if __name__ == '__main__':
    main()
