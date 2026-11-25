#!/usr/bin/env python3
"""Makes docs/intro/shots-raw/plan-course.xlsx: the invented plan with other test and zone numbers (156 / 114 / 74), for the two
pictures that show the zones (set-02-middle, tst-02-zones, pro-03-new-cards). Needs openpyxl. Run from anywhere."""
import pathlib, openpyxl
repo = pathlib.Path(__file__).resolve().parents[3]
src = repo / "UITests/Fixtures/plan.xlsx"; out = repo / "docs/intro/shots-raw/plan-course.xlsx"; out.parent.mkdir(exist_ok=True)
wb = openpyxl.load_workbook(src); vals = openpyxl.load_workbook(src, data_only=True)
swap = {150: 156, 121: 114, 80: 74, '< 122': '< 127', '122–134': '127–139', '135–143': '140–148', '144–153': '149–159', '> 153': '> 159'}
for ws in wb:
    for row in ws.iter_rows():
        for c in row:
            if isinstance(c.value, str) and c.value.startswith("="): c.value = vals[ws.title][c.coordinate].value
            elif ws.title == 'Test Results & Zones' and not isinstance(c.value, bool) and c.value in swap: c.value = swap[c.value]
wb.save(out); print(out)
