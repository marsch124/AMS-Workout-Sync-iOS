#!/usr/bin/env python3
"""Puts the course together: src/ (page, kit, engine, one file pair per chapter) -> index.html. The page shows the real pictures
from shots/ beside it (published together with it). Run:  python3 docs/intro/build.py
Based on AMS Triathlon Training 2.8 (84). Update the course in the release that changes a taught screen."""
import pathlib

root = pathlib.Path(__file__).resolve().parent
src = root / "src"
read = lambda p: p.read_text(encoding="utf-8")
chapters = sorted((src / "chapters").glob("*.js"))
css = read(src / "page.css") + read(src / "kit.css") + "".join(
    f"\n/* ===== {p.name} ===== */\n" + read(p) for p in sorted((src / "chapters").glob("*.css")))
js = "'use strict';\n" + read(src / "icons.js").replace("'use strict';", "", 1) + read(src / "core.js") + "".join(
    f"\n/* ===== {p.name} ===== */\n" + read(p) for p in chapters)
if (src / "finale.js").exists():
    js += "\n/* ===== finale.js ===== */\n" + read(src / "finale.js")
js += read(src / "ui.js")
assert "</script" not in js.lower(), "a chapter writes </script — that would cut the page in two"
page = read(src / "head.html").replace("/*CSS*/", css).replace("/*JS*/", js)
(root / "index.html").write_text(page, encoding="utf-8")
import re
used = sorted(set(re.findall(r"""shot:\s*['"]([a-z0-9-]+)['"]""", js)))
missing = [n for n in used if not (root / "shots" / f"{n}.jpg").exists()]
unused = sorted(p.stem for p in (root / "shots").glob("*.jpg") if p.stem not in used)
print(f"pictures: {len(used)} used" + (f", MISSING: {', '.join(missing)}" if missing else "") + (f", not used: {', '.join(unused)}" if unused else ""))
print(f"index.html: {len(page) // 1024} KB, {len(chapters)} chapters")
