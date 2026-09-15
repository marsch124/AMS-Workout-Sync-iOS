#!/usr/bin/env python3
"""
stats-parity.py web.json native.json

The Progress figures — kept, streaks, by sport, missed-or-moved, trends,
twelve weeks of load — as the web app's AmsSync.stats() derives them against
the native Stats. Numbers to a millionth; everything else exact. Ends with
`differences: none`.
"""
import json, sys

def same(a, b):
    if isinstance(a, bool) or isinstance(b, bool): return a == b
    if isinstance(a, (int, float)) and isinstance(b, (int, float)):
        return abs(a - b) <= 1e-6 * max(1.0, abs(a), abs(b))
    return a == b

def compare(path, a, b, out):
    if isinstance(a, dict) and isinstance(b, dict):
        for k in sorted(set(a) | set(b)):
            if k not in a: out.append(f"{path}.{k}: only native = {json.dumps(b[k])[:80]}")
            elif k not in b: out.append(f"{path}.{k}: only web = {json.dumps(a[k])[:80]}")
            else: compare(f"{path}.{k}", a[k], b[k], out)
    elif isinstance(a, list) and isinstance(b, list):
        if len(a) != len(b): out.append(f"{path}: web {len(a)} / native {len(b)}")
        for i, (x, y) in enumerate(zip(a, b)): compare(f"{path}[{i}]", x, y, out)
    elif not same(a, b):
        out.append(f"{path}: web {json.dumps(a)[:80]} / native {json.dumps(b)[:80]}")

web = json.load(open(sys.argv[1])); native = json.load(open(sys.argv[2]))
total = 0
for name in sorted(set(web) | set(native)):
    diffs = []
    w = (web.get(name) or {}).get("stats"); n = native.get(name)
    if w is None or n is None or "error" in n:
        diffs.append("missing on one side: " + json.dumps(n)[:80])
    else:
        n = dict(n); n.pop("road", None)
        compare("stats", w, n, diffs)
    print(f"{name}: {len(diffs)} difference{'s' if len(diffs) != 1 else ''}")
    for d in diffs[:12]: print("   " + d)
    total += len(diffs)
print("\ndifferences:", "none" if total == 0 else total)
sys.exit(0 if total == 0 else 1)
