#!/usr/bin/env python3
"""
auto_fix_dts.py

Conservative DTS auto-fixer used by flash_and_apply_overlays.sh.
It implements a small set of safe fixes targeted at fixing common dtc
warnings/failures found in device-tree overlays produced by the
ClockworkPi patches. The script is intentionally conservative and
only performs changes that are very likely to be safe:

- Add a reg property to nodes that have a unit-address (node@0 or node@0x34)
  and are missing a 'reg' property. The reg value is derived from the unit
  address (and padded if the parent indicates multiple address-cells).
- Pad existing reg properties (e.g., <0x34>) with leading zeros so their
  length matches the expected address-cells for the parent if siblings or
  an explicit '#address-cells' are available. We always pad with zeros
  (prefix) to avoid changing the lower-order part of the address.

Usage: auto_fix_dts.py --file <path-to-dts> [--apply] [--backup] [--report <file>]

The script writes a lightweight, human-readable summary to stdout and
optionally to a report file. If --apply is provided, the changes are
applied in-place (a backup is written with .orig suffix when --backup
is enabled).
"""
import argparse
import re
import sys
from pathlib import Path
import subprocess
import shlex
import shutil


def parse_args():
    p = argparse.ArgumentParser()
    p.add_argument('--file', '-f', required=True, help='DTS overlay file to fix')
    p.add_argument('--apply', action='store_true', help='Apply fixes to file in-place')
    p.add_argument('--backup', action='store_true', default=True, help='Create a .orig backup when applying')
    p.add_argument('--report', '-r', default=None, help='Append human-readable report to this file')
    p.add_argument('--verbose', '-v', action='store_true', help='Verbose output')
    p.add_argument('--dtc-inc', help='Pass-through DTC -i include flags (as a single string)')
    return p.parse_args()


def find_nodes(lines):
    """Yield tuples (node_label, node_name, unit_str, start_idx, end_idx, indent)
    for nodes with explicit unit addresses (node@addr) found in the file.
    The end_idx is the line index where the corresponding closing brace '}' is.
    The algorithm is intentionally simple: it scans lines and tracks brace depth
    counting occurrences of '{' and '}'. This works well for the fairly small
    and typical overlay fragments we edit.
    """
    node_re = re.compile(r'^(?P<indent>\s*)(?:(?P<label>[A-Za-z0-9_,-]+):\s*)?(?P<name>[A-Za-z0-9_,-]+)@(?P<unit>[^\s{]+)\s*\{')
    depth = 0
    nodes = []
    for idx, line in enumerate(lines):
        # Update depth info for the current line - assume braces are not in strings/comments in normal overlays
        open_braces = line.count('{')
        close_braces = line.count('}')
        m = node_re.match(line)
        if m:
            # find the matching closing brace for this node using a simple depth walk
            cur_depth = depth + open_braces
            end_idx = idx
            for j in range(idx+1, len(lines)):
                cur_depth += lines[j].count('{')
                cur_depth -= lines[j].count('}')
                if cur_depth <= depth:
                    end_idx = j
                    break
            nodes.append((m.group('label') or '', m.group('name'), m.group('unit'), idx, end_idx, m.group('indent')))
        depth += open_braces - close_braces
    return nodes


def extract_parent_block(lines, node_start_idx):
    # find the nearest previous line that represents a parent start (has a '{')
    depth = 0
    # compute depth up to node_start_idx to find parent depth
    for i in range(0, node_start_idx+1):
        depth += lines[i].count('{') - lines[i].count('}')
    # Now go backwards to find where depth decreases (parent's starting line)
    parent_start = None
    parent_depth = depth - 1
    cur_depth = 0
    for i in range(0, node_start_idx):
        cur_depth += lines[i].count('{') - lines[i].count('}')
    for i in range(node_start_idx-1, -1, -1):
        cur_depth -= lines[i].count('{') - lines[i].count('}')
        if cur_depth == parent_depth:
            # search backward for the start of the parent block (line that has a '{')
            for j in range(i, -1, -1):
                if '{' in lines[j]:
                    parent_start = j
                    break
            break
    if parent_start is None:
        # parent is root; return full file range
        return 0, len(lines)-1
    # find end of parent block
    cur_depth = 0
    for j in range(parent_start, len(lines)):
        cur_depth += lines[j].count('{') - lines[j].count('}')
        if cur_depth == 0:
            return parent_start, j
    return parent_start, len(lines)-1


def find_reg_in_block(block_text):
    # allow whitespace and newlines inside <> using DOTALL
    m = re.search(r'reg\s*=\s*<([^>]*)>\s*;', block_text, flags=re.S)
    if not m:
        return None
    tokens = re.findall(r'(0x[0-9A-Fa-f]+|\d+)', m.group(1))
    # return the full match (string), token list and start/end positions
    return m.group(0), tokens, m.start(), m.end()


def find_address_cells_in_block(block_text):
    m = re.search(r"#address-cells\s*=\s*<\s*(\d+)\s*>\s*;", block_text)
    if m:
        try:
            return int(m.group(1))
        except Exception:
            return None
    return None


def tokenize_unit(unit_str):
    parts = unit_str.split(',')
    tokens = []
    for p in parts:
        p = p.strip()
        if not p:
            continue
        # preserve hex/decimal formatting
        if p.lower().startswith('0x'):
            tokens.append(p.lower())
        else:
            # ensure decimal tokens are converted to decimal string
            if p.isdigit():
                tokens.append(str(int(p)))
            else:
                # fallback: if it contains bad chars, keep raw
                tokens.append(p)
    return tokens


def pad_tokens(tokens, target_len):
    # Pad with '0' on the left to target length
    if len(tokens) >= target_len:
        return tokens
    return ['0'] * (target_len - len(tokens)) + tokens


def stringify_tokens(tokens):
    # Keep token formatting as-is, join with space
    return ' '.join(tokens)


def report_append(report_path, text):
    if not report_path:
        return
    p = Path(report_path)
    p.parent.mkdir(parents=True, exist_ok=True)
    with p.open('a') as fh:
        fh.write(text)


def process_file(file_path, apply=False, backup=True, report=None, verbose=False, dtc_inc=None):
    p = Path(file_path)
    if not p.exists():
        raise SystemExit(f"File not found: {file_path}")
    orig_text = p.read_text()
    lines = orig_text.splitlines()

    nodes = find_nodes(lines)
    if verbose:
        print(f"Found {len(nodes)} unit-address nodes")
        for nd in nodes:
            print(f"  node: label={nd[0]!r}, name={nd[1]!r}, unit={nd[2]!r}, start={nd[3]}, end={nd[4]}, indent={nd[5]!r}")
    if not nodes:
        return False, 'no-change'

    modified = False
    changes = []
    # We'll operate on a mutable list of lines so we can edit easily
    for (label, nodename, unit, start, end, indent) in nodes:
        # Skip overlay fragment guidance and other non-hardware pseudo-nodes
        if nodename == 'fragment':
            continue
        block_lines = lines[start:end+1]
        block_text = '\n'.join(block_lines)
        reg_search = find_reg_in_block(block_text)
        # Determine expected address-cells by looking in the parent block (siblings or explicit #address-cells)
        parent_start, parent_end = extract_parent_block(lines, start)
        parent_block_text = '\n'.join(lines[parent_start:parent_end+1])
        expected_cells = find_address_cells_in_block(parent_block_text)
        if expected_cells is None:
            # look for sibling reg properties and use the max tokens among them
            sibling_regs = re.findall(r'reg\s*=\s*<([^>]*)>\s*;', parent_block_text, flags=re.S)
            if sibling_regs:
                max_tokens = 0
                for s in sibling_regs:
                    s_tokens = re.findall(r'(0x[0-9A-Fa-f]+|\d+)', s)
                    max_tokens = max(max_tokens, len(s_tokens))
                if max_tokens > 0:
                    expected_cells = max_tokens
        if expected_cells is None:
            expected_cells = 1

        # When the node has a unit address and missing reg -> add reg. If reg present but shorter -> pad.
        if reg_search is None:
            # no reg present; create one from unit
            unit_tokens = tokenize_unit(unit)
            if not unit_tokens:
                # skip if we couldn't parse
                continue
            padded = pad_tokens(unit_tokens, expected_cells)
            new_reg = '<{}>'.format(stringify_tokens(padded))
            # insert after opening brace line
            # find position of the line containing the opening brace (node declaration)
            opener_line_idx = start
            # insert into the block at start+1 with same indentation + a tab
            insert_idx = opener_line_idx + 1
            m_indent = re.match(r'^(\s*)', lines[opener_line_idx])
            indent_str = m_indent.group(1) if m_indent else ''
            reg_line = f"{indent_str}\treg = {new_reg};"
            lines.insert(insert_idx, reg_line)
            modified = True
            changes.append((p.name, nodename, 'add-reg', new_reg))
        else:
            full_match, tokens, rstart, rend = reg_search
            if tokens:
                if len(tokens) < expected_cells:
                    # pad left
                    padded = pad_tokens(tokens, expected_cells)
                    new_reg = '<{}>'.format(stringify_tokens(padded))
                    # replace in the block_text
                    new_block_text = block_text[:rstart] + 'reg = ' + new_reg + ';' + block_text[rend:]
                    # write back to lines
                    new_block_lines = new_block_text.splitlines()
                    lines[start:end+1] = new_block_lines
                    modified = True
                    changes.append((p.name, nodename, 'pad-reg', full_match + ' -> reg = ' + new_reg))
            else:
                # reg present but tokens not recognized; skip
                pass

    if not modified:
        if report:
            report_append(report, f"{p.name}: no modifications needed\n")
        return False, 'no-change'

    # write temp file and optionally apply
    fixed_path = p.with_suffix('.fixed.dts')
    p_fixed = fixed_path
    p_fixed.write_text('\n'.join(lines) + '\n')
    # delegate to apply decision
    if apply:
        if backup:
            backup_path = p.with_suffix('.dts.orig')
            if not backup_path.exists():
                # move original to backup, then write the fixed content to original path
                p.rename(backup_path)
        # write the fixed content to the original path
        p.write_text('\n'.join(lines) + '\n')
    else:
        # do not overwrite original; leave .fixed.dts for inspection
        pass

    # If dtc is present and dtc_inc info was passed, try running dtc to parse any
    # reg_format warnings and try to auto-pad reg properties accordingly (multiple
    # passes if necessary). We only attempt these fixes when dtc is installed.
    if shutil.which('dtc') is not None:
        dts_file_for_check = p if apply else p_fixed
        # iterate a few times to converge on pad fixes
        iter_count = 0
        max_iters = 3
        any_iter_modified = False
        while iter_count < max_iters:
            iter_count += 1
            # recompute nodes because the previous iteration may have rewritten lines
            nodes = find_nodes(lines)
            results, dtc_out = run_dtc_and_get_reg_format_warnings(str(dts_file_for_check), dtc_inc)
            if not results:
                break
            if verbose:
                print(f"dtc reported {len(results)} reg_format warnings; attempting to auto-pad (iter {iter_count})")
            made_changes_this_iter = False
            for nodepath, expected_cells in results:
                # nodepath examples: /fragment@1/__overlay__/spidev@0
                parts = [p for p in nodepath.strip('/').split('/') if p]
                if not parts:
                    continue
                # the last part should be the node with unit, e.g., spidev@0
                target = parts[-1]
                if '@' not in target:
                    continue
                name, unit = target.split('@', 1)
                # find a fragment index if present in parts
                frag_name = None
                for part in parts[:-1]:
                    if part.startswith('fragment@'):
                        frag_name = part
                        break
                # find the candidate node in our nodes list
                candidate = None
                for (lbl, ndname, ndunit, start_idx, end_idx, ndindent) in nodes:
                    if ndname == name and ndunit == unit:
                        # if frag_name specified, ensure this node is inside that fragment block
                        if frag_name:
                            frag_unit = frag_name.split('@', 1)[1]
                            # find fragment node range
                            for (flbl, fname, funit, fstart, fend, findent) in nodes:
                                if fname == 'fragment' and funit == frag_unit:
                                    # ensure this node is in the fragment block range
                                    if start_idx >= fstart and start_idx <= fend:
                                        candidate = (lbl, ndname, ndunit, start_idx, end_idx, ndindent)
                                        break
                            if candidate:
                                break
                        else:
                            candidate = (lbl, ndname, ndunit, start_idx, end_idx, ndindent)
                            break
                if not candidate:
                    if verbose:
                        print(f"Unable to find node {name}@{unit} in file to pad reg")
                    continue
                # Extract block and reg property
                (lbl, ndname, ndunit, sidx, eidx, nbindent) = candidate
                block_text = '\n'.join(lines[sidx:eidx+1])
                reg_search = find_reg_in_block(block_text)
                if not reg_search:
                    # No reg found - e.g., unit exists but no reg property - skip
                    continue
                full_match, tokens, rstart, rend = reg_search
                if tokens and len(tokens) < expected_cells:
                    padded = pad_tokens(tokens, expected_cells)
                    new_reg = '<{}>'.format(stringify_tokens(padded))
                    new_block_text = block_text[:rstart] + 'reg = ' + new_reg + ';' + block_text[rend:]
                    new_block_lines = new_block_text.splitlines()
                    lines[sidx:eidx+1] = new_block_lines
                    made_changes_this_iter = True
                    any_iter_modified = True
                    changes.append((p.name, ndname, 'pad-reg-dtc', f"{full_match} -> reg = {new_reg}"))
            if not made_changes_this_iter:
                break
            # write intermediate changes to file so the next dtc run sees them
            (p if apply else p_fixed).write_text('\n'.join(lines) + '\n')
        if any_iter_modified and apply:
            # if dtc couldn't validate the final file, we'll surface the output via report
            results_after, dtc_out_after = run_dtc_and_get_reg_format_warnings(str(dts_file_for_check), dtc_inc)
            if results_after:
                report_append(report, f"{p.name}: dtc still reported reg_format warnings after auto-padding; see dtc output:\n{dtc_out_after}\n")
        # Final compile check to ensure the modified file is valid
        rc, dtc_final_out = run_dtc_compile(str(dts_file_for_check), dtc_inc)
        if rc != 0:
            # revert to original since the compile failed
            backup_path = p.with_suffix('.dts.orig')
            if backup and backup_path.exists():
                backup_path.replace(p)
                report_append(report, f"{p.name}: auto-fix reverted because dtc compile failed (rc={rc}). dtc output:\n{dtc_final_out}\n")
                return False, 'reverted due to dtc compile failure'
            else:
                report_append(report, f"{p.name}: auto-fix left in place, but dtc compile failed (rc={rc}). dtc output:\n{dtc_final_out}\n")

    # Write summary to report
    report_entries = [f"{p.name}: modified {len(changes)} nodes"]
    for c in changes:
        report_entries.append(f"  node {c[1]}: {c[2]} -> {c[3]}")
    report_text = '\n'.join(report_entries) + '\n'
    if report:
        report_append(report, report_text)
    if verbose:
        print(report_text)
    return True, report_text


def run_dtc_and_get_reg_format_warnings(dts_path, dtc_inc=None):
    """Run dtc on dts_path and return list of (nodepath, expected_cells) tuples
    extracted from 'Warning (reg_format)' messages. Returns (list, dtc_output).
    """
    if shutil.which('dtc') is None:
        return [], ''
    cmd = ['dtc', '-@', '-I', 'dts', '-O', 'dtb', '-o', '/dev/null']
    if dtc_inc:
        try:
            cmd += shlex.split(dtc_inc)
        except Exception:
            # fallback: pass as a single token
            cmd.append(dtc_inc)
    cmd.append(dts_path)
    try:
        p = subprocess.run(cmd, capture_output=True, text=True)
    except Exception as e:
        return [], str(e)
    out = (p.stdout or '') + '\n' + (p.stderr or '')
    # parse reg_format messages
    reg_fmt_re = re.compile(r"Warning \(reg_format\):\s+([^:]+):reg: property has invalid length .*?\(#address-cells == (\d+)", flags=re.S)
    matches = reg_fmt_re.findall(out)
    results = []
    for nodepath, addr_cells in matches:
        nodepath = nodepath.strip()
        try:
            expected = int(addr_cells)
        except Exception:
            expected = None
        if expected:
            results.append((nodepath, expected))
    return results, out


def run_dtc_compile(dts_path, dtc_inc=None):
    """Run dtc to compile dts_path and return (returncode, combined_output)"""
    if shutil.which('dtc') is None:
        return 127, 'dtc not found'
    cmd = ['dtc', '-@', '-I', 'dts', '-O', 'dtb', '-o', '/dev/null']
    if dtc_inc:
        try:
            cmd += shlex.split(dtc_inc)
        except Exception:
            cmd.append(dtc_inc)
    cmd.append(dts_path)
    try:
        p = subprocess.run(cmd, capture_output=True, text=True)
    except Exception as e:
        return 1, str(e)
    out = (p.stdout or '') + '\n' + (p.stderr or '')
    return p.returncode, out


def main():
    args = parse_args()
    changed, summary = process_file(args.file, apply=args.apply, backup=args.backup, report=args.report, verbose=args.verbose, dtc_inc=args.dtc_inc)
    if changed:
        if args.apply:
            print(f"Applied modifications to {args.file}")
        else:
            print(f"Proposed modifications for {args.file} written to {args.file}.fixed.dts (use --apply to commit)")
        sys.exit(0)
    else:
        print(f"No changes made to {args.file} ({summary})")
        sys.exit(0)


if __name__ == '__main__':
    main()
