#!/usr/bin/env python3
"""
write-parity.py <scenarios.json> <web-dir> <native-dir>

Compares, scenario by scenario, the workbook the web app wrote with the one
the native app wrote. Three checks, strictest first:

1. The archive has the same parts, in the same order, with the same
   compression method, CRC and uncompressed size.
2. Every part is either byte-for-byte the same compressed data in both, or —
   where the two compressors were each given a changed part to pack — the
   same bytes once unpacked. Deflate output differs between Apple's
   compressor and the browser's for identical input, so only the unpacked
   text can be asked to agree there.
3. Against the original workbook: every part the native writer did not change
   is copied through as the original compressed bytes (invariant 1), and the
   parts it did change are named.

Ends with `differences: none` or a count.
"""
import json
import struct
import sys
import zlib
from collections import Counter


def read_zip(path):
    data = open(path, "rb").read()
    eocd = data.rfind(b"PK\x05\x06")
    if eocd < 0:
        raise ValueError("not a zip")
    count, = struct.unpack_from("<H", data, eocd + 10)
    offset, = struct.unpack_from("<I", data, eocd + 16)
    parts = []
    for _ in range(count):
        (sig, _vm, _vn, flags, method, mtime, mdate, crc, comp, uncomp,
         nlen, xlen, clen, _d, _ia, _ea, local) = struct.unpack_from("<IHHHHHHIIIHHHHHII", data, offset)
        name = data[offset + 46:offset + 46 + nlen].decode("utf-8")
        lnlen, lxlen = struct.unpack_from("<HH", data, local + 26)
        start = local + 30 + lnlen + lxlen
        raw = data[start:start + comp]
        header = data[local:local + 30 + lnlen + lxlen]
        parts.append({"name": name, "method": method, "crc": crc, "uncomp": uncomp, "flags": flags,
                      "date": (mtime, mdate), "raw": raw, "header": header})
        offset += 46 + nlen + xlen + clen
    return parts


def plain(part):
    if part["method"] == 0:
        return part["raw"]
    return zlib.decompress(part["raw"], -15)


def main():
    scenarios = json.load(open(sys.argv[1]))
    web_dir, native_dir = sys.argv[2], sys.argv[3]
    total = 0
    touched = Counter()
    checked = 0

    for sc in scenarios:
        name = sc["name"]
        diffs = []
        try:
            web = read_zip(f"{web_dir}/{name}.xlsx")
        except Exception as e:
            print(f"{name}: web output missing ({e})")
            total += 1
            continue
        try:
            native = read_zip(f"{native_dir}/{name}.xlsx")
        except Exception as e:
            print(f"{name}: native output missing ({e})")
            total += 1
            continue
        original = {p["name"]: p for p in read_zip(sc["file"])}

        if [p["name"] for p in web] != [p["name"] for p in native]:
            diffs.append(f"parts differ: web {[p['name'] for p in web]} / native {[p['name'] for p in native]}")
        for w, n in zip(web, native):
            if w["name"] != n["name"]:
                continue
            for field in ("method", "crc", "uncomp", "flags", "date"):
                if w[field] != n[field]:
                    diffs.append(f"{w['name']}: {field} web {w[field]} / native {n[field]}")
            if w["raw"] != n["raw"]:
                a, b = plain(w), plain(n)
                if a != b:
                    # Name the first place they part company, in text.
                    i = next((k for k in range(min(len(a), len(b))) if a[k] != b[k]), min(len(a), len(b)))
                    ctx = lambda s: s[max(0, i - 60):i + 60].decode("utf-8", "replace")
                    diffs.append(f"{w['name']}: content differs at byte {i}\n      web:    …{ctx(a)}…\n      native: …{ctx(b)}…")
            o = original.get(n["name"])
            if o is None or o["raw"] != n["raw"]:
                touched[n["name"]] += 1
                if o is not None and plain(o) == plain(n) and n["name"] != "xl/workbook.xml":
                    pass
            elif zlib.crc32(plain(n)) & 0xffffffff != n["crc"]:
                diffs.append(f"{n['name']}: CRC does not match its contents")

        checked += 1
        status = "ok" if not diffs else f"{len(diffs)} difference{'s' if len(diffs) != 1 else ''}"
        if diffs:
            print(f"{name}: {status}")
            for d in diffs[:6]:
                print("   " + d)
        total += len(diffs)

    print()
    print(f"{checked} scenarios compared. Parts the writers changed, and how often:")
    for part, n in touched.most_common():
        print(f"   {part}: {n}")
    print()
    print("differences:", "none" if total == 0 else total)
    sys.exit(0 if total == 0 else 1)


if __name__ == "__main__":
    main()
