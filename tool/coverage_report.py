#!/usr/bin/env python3
"""Merge the two suites' LCOV reports and print a coverage summary.

`flutter_constraint_layout` and `constraint_engine` are separate packages with separate
test suites, but the Flutter suite also executes engine code (the engine is a
path dependency compiled from source). A line is covered if *either* suite
reached it, so the two reports are unioned rather than compared.

The Flutter side only records those engine lines when it is run with
`--coverage-package=constraint_engine`; see the repo README.

Usage:
    python3 tool/coverage_report.py [--scope lib|engine|all] [--missing FILE]

`--scope lib` means the flutter_constraint_layout package's own lib/, `--scope engine`
means constraint_engine's.
"""

import argparse
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

ADAPTER = "packages/flutter_constraint_layout"
ENGINE = "packages/constraint_engine"

# Package roots whose coverage/lcov.info is merged. Each suite writes its SF:
# paths relative to its own package (Flutter) or absolute (the engine's
# format_coverage), so both are resolved back to repo-root-relative below.
SOURCES = [ADAPTER, ENGINE]


def load(package, hits):
    """Merge one package's LCOV file into `hits`: {file: {line: total_hits}}."""
    package_dir = os.path.join(ROOT, package)
    full = os.path.join(package_dir, "coverage", "lcov.info")
    if not os.path.exists(full):
        print(f"warning: {package}/coverage/lcov.info not found, skipping",
              file=sys.stderr)
        return
    current = None
    for line in open(full):
        line = line.strip()
        if line.startswith("SF:"):
            path = line[3:]
            if not os.path.isabs(path):
                path = os.path.join(package_dir, path)
            name = os.path.relpath(path, ROOT)
            if name.startswith(".."):
                # Outside the repo (pub cache, SDK); not ours to report on.
                current = None
                continue
            current = hits.setdefault(name, {})
        elif line.startswith("DA:") and current is not None:
            num, count = line[3:].split(",")[:2]
            current[int(num)] = current.get(int(num), 0) + int(count)
        elif line == "end_of_record":
            current = None


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--scope", default="all", choices=["lib", "engine", "all"])
    parser.add_argument(
        "--missing",
        help="print the uncovered line numbers for files matching this substring",
    )
    args = parser.parse_args()

    hits = {}
    for package in SOURCES:
        load(package, hits)

    def in_scope(name):
        if args.scope == "lib":
            return name.startswith(f"{ADAPTER}/lib/")
        if args.scope == "engine":
            return name.startswith(f"{ENGINE}/lib/")
        return True

    rows = []
    total_found = total_hit = 0
    for name, lines in sorted(hits.items()):
        if not in_scope(name):
            continue
        found = len(lines)
        hit = sum(1 for c in lines.values() if c > 0)
        total_found += found
        total_hit += hit
        rows.append((hit / found if found else 1.0, hit, found, name))

    rows.sort()
    for pct, hit, found, name in rows:
        print(f"  {100 * pct:5.1f}%  {hit:4d}/{found:4d}  {name}")
    if total_found:
        print(f"\nTOTAL ({args.scope}): {total_hit}/{total_found} = "
              f"{100 * total_hit / total_found:.2f}%")

    if args.missing:
        for name, lines in sorted(hits.items()):
            if args.missing not in name:
                continue
            uncovered = sorted(n for n, c in lines.items() if c == 0)
            if uncovered:
                print(f"\n{name} uncovered lines ({len(uncovered)}):")
                print("  " + ", ".join(str(n) for n in uncovered))


if __name__ == "__main__":
    main()
