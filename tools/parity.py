#!/usr/bin/env python3
"""
parity.py web.json native.json

Puts the web app's reading of each workbook beside the native reader's and
names every difference: in the layout it detected, in which sessions exist,
and field by field inside each session. Ends with `differences: none` or a
count, the way the web app's own tests end with `errors: none`.

Numbers are compared to a millionth, since the two languages print the same
double in different ways; everything else must match exactly.
"""
import json
import sys


def same(a, b):
    if isinstance(a, bool) or isinstance(b, bool):
        return a == b
    if isinstance(a, (int, float)) and isinstance(b, (int, float)):
        return abs(a - b) <= 1e-6 * max(1.0, abs(a), abs(b))
    return a == b


def compare(path, a, b, out):
    if isinstance(a, dict) and isinstance(b, dict):
        for k in sorted(set(a) | set(b)):
            if k not in a:
                out.append(f"{path}.{k}: only native has it = {json.dumps(b[k], ensure_ascii=False)[:120]}")
            elif k not in b:
                out.append(f"{path}.{k}: only web has it = {json.dumps(a[k], ensure_ascii=False)[:120]}")
            else:
                compare(f"{path}.{k}", a[k], b[k], out)
    elif isinstance(a, list) and isinstance(b, list):
        if len(a) != len(b):
            out.append(f"{path}: web has {len(a)}, native has {len(b)}")
        for i, (x, y) in enumerate(zip(a, b)):
            compare(f"{path}[{i}]", x, y, out)
    elif not same(a, b):
        out.append(f"{path}: web {json.dumps(a, ensure_ascii=False)[:120]} / native {json.dumps(b, ensure_ascii=False)[:120]}")


def main():
    web = json.load(open(sys.argv[1]))
    native = json.load(open(sys.argv[2]))
    total = 0
    for name in sorted(set(web) | set(native)):
        diffs = []
        w, n = web.get(name), native.get(name)
        if w is None or n is None:
            diffs.append("missing on one side")
        else:
            w = dict(w)
            w.pop("pageErrors", None)
            compare("mapping", w.get("mapping"), n.get("mapping"), diffs)
            wk = {x["key"]: x for x in w.get("workouts", [])}
            nk = {x["key"]: x for x in n.get("workouts", [])}
            order_w = [x["key"] for x in w.get("workouts", [])]
            order_n = [x["key"] for x in n.get("workouts", [])]
            for key in order_w:
                if key not in nk:
                    diffs.append(f"session {key}: web only")
            for key in order_n:
                if key not in wk:
                    diffs.append(f"session {key}: native only")
            for key in order_w:
                if key in nk:
                    compare(f"session {key}", wk[key], nk[key], diffs)
            if set(order_w) == set(order_n) and order_w != order_n:
                diffs.append("sessions are in a different order")
        count = len(w.get("workouts", [])) if isinstance(w, dict) else 0
        print(f"{name}: {count} sessions, {len(diffs)} difference{'s' if len(diffs) != 1 else ''}")
        for d in diffs[:25]:
            print("   " + d)
        if len(diffs) > 25:
            print(f"   ... and {len(diffs) - 25} more")
        total += len(diffs)
    print()
    print("differences:", "none" if total == 0 else total)
    sys.exit(0 if total == 0 else 1)


if __name__ == "__main__":
    main()
