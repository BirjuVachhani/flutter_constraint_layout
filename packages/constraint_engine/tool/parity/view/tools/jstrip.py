"""Strip comments and blank lines from Java sources so a diff shows code only.

Usage: python3 -I jstrip.py <src_root> <out_root>
Writes every .java file under src_root, comments removed and whitespace runs
collapsed, to the same relative path under out_root.
"""
import os
import re
import sys


def strip(text):
    out = []
    i, n = 0, len(text)
    while i < n:
        c = text[i]
        if c == '/' and i + 1 < n and text[i + 1] == '/':
            j = text.find('\n', i)
            i = n if j < 0 else j
        elif c == '/' and i + 1 < n and text[i + 1] == '*':
            j = text.find('*/', i + 2)
            # keep line count stable enough for reading: drop the comment
            i = n if j < 0 else j + 2
        elif c in '"\'':
            j = i + 1
            while j < n and text[j] != c:
                j += 2 if text[j] == '\\' else 1
            out.append(text[i:j + 1])
            i = j + 1
        else:
            out.append(c)
            i += 1
    lines = []
    for line in ''.join(out).split('\n'):
        line = re.sub(r'\s+', ' ', line).strip()
        if line:
            lines.append(line)
    return '\n'.join(lines) + '\n'


def main():
    src, dst = sys.argv[1], sys.argv[2]
    for root, _, files in os.walk(src):
        for f in files:
            if not f.endswith('.java'):
                continue
            p = os.path.join(root, f)
            rel = os.path.relpath(p, src)
            q = os.path.join(dst, rel)
            os.makedirs(os.path.dirname(q), exist_ok=True)
            with open(p, encoding='utf-8') as fh:
                t = fh.read()
            with open(q, 'w', encoding='utf-8') as fh:
                fh.write(strip(t))


main()
