"""CLI entry point for MapTool - function dependency tree generator.

Usage:
    python -m maptool.cli --map build/out/AIR6208.map
    python -m maptool.cli --map build/out/AIR6208.map --entry UserMain,luat_main
    python -m maptool.cli --map build/out/AIR6208.map --output output/tree.html --d3
"""

import os
import sys

import click

from . import __version__
from .parser import parse_map_file
from .callgraph import build_call_graph
from .generator import generate_html, generate_json_output


@click.command()
@click.option('--map', 'map_file', required=True,
              type=click.Path(exists=True, dir_okay=False),
              help='Path to the .map file (required)')
@click.option('--output', '-o', 'output_file',
              type=click.Path(dir_okay=False),
              default=None,
              help='Output HTML file path (default: output/<target>_tree.html)')
@click.option('--entry', '-e', 'entry_points',
              default='UserMain,luat_main',
              help='Entry function(s), comma-separated (default: UserMain,luat_main)')
@click.option('--max-depth', '-d', 'max_depth',
              type=int, default=20,
              help='Maximum tree depth (default: 20)')
@click.option('--title', '-t',
              default=None,
              help='HTML page title (default: auto-generated)')
@click.option('--d3/--no-d3', 'include_d3',
              default=False,
              help='Include D3.js force graph view (default: off)')
@click.option('--all-roots/--no-all-roots', 'use_all_roots',
              default=False,
              help='Use ALL uncalled functions as roots (ignores --entry)')
@click.option('--json', 'json_output',
              type=click.Path(dir_okay=False),
              default=None,
              help='Also output raw JSON data file')
@click.version_option(version=__version__)
def main(map_file, output_file, entry_points, max_depth, title, include_d3,
         use_all_roots, json_output):
    """Parse a CSKY linker .map file and generate an interactive HTML
    function dependency tree with flash/RAM size annotations.

    Example usage:

        python -m maptool.cli --map build/out/AIR6208.map

        python -m maptool.cli --map build/out/AIR6208.map --entry UserMain

        python -m maptool.cli --map build/out/AIR6208.map --d3 --json output/tree.json
    """
    # Default output path
    if output_file is None:
        base = os.path.splitext(os.path.basename(map_file))[0]
        output_dir = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                                  '..', 'output')
        output_file = os.path.join(output_dir, f'{base}_tree.html')

    # Default title
    if title is None:
        base = os.path.splitext(os.path.basename(map_file))[0]
        title = f'{base} Function Dependency Tree'

    # Parse entry points
    if use_all_roots:
        entries = None  # Will auto-detect all roots
        entry_display = 'auto-detect (all roots)'
    else:
        entries = [e.strip() for e in entry_points.split(',') if e.strip()]
        entry_display = ", ".join(entries)

    click.echo(f'MapTool v{__version__}')
    click.echo(f'  Map file: {map_file}')
    click.echo(f'  Output:   {output_file}')
    click.echo(f'  Entries:  {entry_display}')
    click.echo(f'  Max depth: {max_depth}')
    click.echo()

    # Phase 1: Parse map file
    click.echo('Phase 1: Parsing map file...')
    try:
        parse_result = parse_map_file(map_file)
    except Exception as e:
        click.echo(f'ERROR: Failed to parse map file: {e}', err=True)
        sys.exit(1)

    click.echo(f'  Extracted {len(parse_result.edges)} call edges')
    click.echo(f'  Found {len(parse_result.functions)} functions')
    click.echo(f'  Tracked RAM for {len(parse_result.object_ram)} objects')

    if parse_result.grand_totals:
        gt = parse_result.grand_totals
        click.echo(f'  Grand totals: {gt.get("code",0)} code + '
                    f'{gt.get("ro_data",0)} RO + '
                    f'{gt.get("rw_data",0)} RW + '
                    f'{gt.get("zi_data",0)} ZI')

    # Phase 2: Build call graph
    click.echo('Phase 2: Building call graph...')
    try:
        tree_result = build_call_graph(parse_result, entries, max_depth)
    except Exception as e:
        click.echo(f'ERROR: Failed to build call graph: {e}', err=True)
        import traceback
        traceback.print_exc()
        sys.exit(1)

    click.echo(f'  Reachable functions: {tree_result.total_functions}')
    click.echo(f'  Unreachable: {len(tree_result.unreachable_functions)}')
    click.echo(f'  Max depth: {tree_result.max_depth}')
    click.echo(f'  Tree flash sum: {tree_result.total_flash_sum:,} bytes')
    click.echo(f'  Tree RAM sum: {tree_result.total_ram_sum:,} bytes')

    # Phase 3: Generate HTML
    click.echo('Phase 3: Generating HTML...')
    try:
        actual_output = generate_html(
            tree_result, parse_result, output_file,
            title=title, include_d3=include_d3
        )
    except Exception as e:
        click.echo(f'ERROR: Failed to generate HTML: {e}', err=True)
        import traceback
        traceback.print_exc()
        sys.exit(1)

    click.echo(f'  HTML written to: {actual_output}')
    click.echo(f'  File size: {os.path.getsize(actual_output):,} bytes')

    # Optional JSON output
    if json_output:
        click.echo('Phase 4: Generating JSON...')
        try:
            json_path = generate_json_output(tree_result, parse_result, json_output)
            click.echo(f'  JSON written to: {json_path}')
        except Exception as e:
            click.echo(f'ERROR: Failed to generate JSON: {e}', err=True)

    click.echo()
    click.echo(f'Done! Open {actual_output} in your browser to explore the tree.')


if __name__ == '__main__':
    main()
