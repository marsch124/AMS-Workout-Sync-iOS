#!/usr/bin/env python3
"""
Copies the web app's hand-drawn icons into the asset catalog, so both apps
draw every sport with the same stroke. Each <symbol> in the web app's
index.html becomes an SVG template image named after it (icon-swim, ...).
CoreSVG does not understand currentColor, so strokes are painted black and
the image is marked as a template: SwiftUI tints it with whatever colour the
view gives it.

    python3 tools/make_assets.py ../"AMS Workout Sync"/index.html
"""
import json, os, re, sys

src = open(sys.argv[1], encoding="utf-8").read()
root = os.path.join(os.path.dirname(__file__), "..", "App", "Resources", "Assets.xcassets")
os.makedirs(root, exist_ok=True)
json.dump({"info": {"author": "xcode", "version": 1}}, open(os.path.join(root, "Contents.json"), "w"))

count = 0
for m in re.finditer(r'<symbol id="(icon-[a-z-]+)"([^>]*)>(.*?)</symbol>', src, re.S):
    name, attrs, body = m.group(1), m.group(2), m.group(3)
    attrs = attrs.replace("currentColor", "#000000")
    body = body.replace("currentColor", "#000000")
    svg = f'<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24"{attrs}>{body}</svg>\n'
    folder = os.path.join(root, name + ".imageset")
    os.makedirs(folder, exist_ok=True)
    open(os.path.join(folder, name + ".svg"), "w", encoding="utf-8").write(svg)
    json.dump({
        "images": [{"filename": name + ".svg", "idiom": "universal"}],
        "info": {"author": "xcode", "version": 1},
        "properties": {"preserves-vector-representation": True, "template-rendering-intent": "template"}
    }, open(os.path.join(folder, "Contents.json"), "w"))
    count += 1
print(count, "icons")
