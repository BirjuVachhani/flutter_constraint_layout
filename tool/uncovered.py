#!/usr/bin/env python3
"""Print uncovered lines with their source text, grouped into contiguous runs.

Usage: python3 tool/uncovered.py <path-substring> [...]
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from coverage_report import ROOT, SOURCES, load  # noqa: E402


def main():
    hits = {}
    for package in SOURCES:
        load(package, hits)

    for needle in sys.argv[1:]:
        for name, lines in sorted(hits.items()):
            if needle not in name:
                continue
            uncovered = sorted(n for n, c in lines.items() if c == 0)
            if not uncovered:
                continue
            src = open(os.path.join(ROOT, name)).read().split("\n")
            print(f"\n===== {name}: {len(uncovered)} uncovered =====")
            runs = []
            for n in uncovered:
                if runs and n - runs[-1][-1] <= 2:
                    runs[-1].append(n)
                else:
                    runs.append([n])
            for run in runs:
                lo, hi = run[0], run[-1]
                print(f"--- {lo}-{hi}")
                for n in range(lo, hi + 1):
                    mark = "!" if n in lines and lines[n] == 0 else " "
                    print(f"{mark}{n:5d}| {src[n - 1]}")


if __name__ == "__main__":
    main()
