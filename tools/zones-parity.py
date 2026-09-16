#!/usr/bin/env python3
"""
python3 tools/zones-parity.py <zones-dump.json> <book.xlsx> ...

Reads the Test Results & Zones sheet of each workbook with openpyxl by the
same shape rules the app uses, works out the same worked examples, and
compares with what zones-dump printed. Two readers written apart that agree
on his real workbook and on workbooks with no such sheet.
"""
import json, os, re, sys
import openpyxl

def read(path):
    try:
        wb = openpyxl.load_workbook(path, data_only=True)
    except Exception:
        return None    # not a workbook at all — the app reads nothing from it either
    name = next((n for n in wb.sheetnames if 'zone' in n.lower()), None)
    if not name:
        return None
    ws = wb[name]
    def t(r, c):
        v = ws.cell(row=r, column=c).value
        return '' if v is None else str(v).strip()
    def cells(r):
        return [(c, t(r, c)) for c in range(1, ws.max_column + 1) if t(r, c)]
    rows = range(1, ws.max_row + 1)
    header_row = next((r for r in rows if any(x.lower() == 'test block' for _, x in cells(r))), None)
    if header_row is None:
        return None
    header = cells(header_row)
    label_col = next(c for c, x in header if x.lower() == 'test block')
    def col(needle):
        return next((c for c, x in header if needle in x.lower()), None)
    value_cols = [c for c in (col('lthr'), col('ftp'), col('css'), col('weight')) if c]
    dates_col = col('date')
    current_row = latest = None
    for r in rows:
        if r <= header_row:
            continue
        a = t(r, label_col)
        if a.upper().startswith('CURRENT'):
            current_row = r
            break
        if a.lower().startswith('test') and any(t(r, c) for c in value_cols):
            latest = r
    current = [{'label': x, 'value': t(current_row, c)} for c, x in header if c in value_cols] if current_row else []
    latest_s = ''
    if latest:
        latest_s = t(latest, label_col) + ((', ' + t(latest, dates_col)) if dates_col and t(latest, dates_col) else '')
    after = current_row or header_row
    tables, tables_end = [], after
    title_row = next((r for r in rows if r > after and 'ZONE' in t(r, label_col).upper()), None)
    if title_row:
        for c, title in cells(title_row):
            trs, r = [], title_row + 1
            while r <= ws.max_row and t(r, c):
                trs.append({'label': t(r, c), 'value': t(r, c + 1)})
                r += 1
            tables_end = max(tables_end, r)
            if trs:
                tables.append({'title': title, 'rows': trs})
    if not tables:
        return None
    note = next((t(r, label_col) for r in rows if r >= tables_end and t(r, label_col).lower().startswith('note')), '')
    abbr = []
    ar = next((r for r in rows if r > after and t(r, label_col).upper() == 'ABBREVIATIONS'), None)
    if ar:
        r = ar + 1
        while r <= ws.max_row and t(r, label_col) and t(r, label_col + 1):
            abbr.append({'label': t(r, label_col), 'value': t(r, label_col + 1)})
            r += 1
    return {'sheet': name, 'current': current, 'latestTest': latest_s, 'tables': tables, 'note': note, 'abbreviations': abbr}

def zone_number(label):
    m = re.match(r'\s*[Zz](\d)(?!\d)', label)
    return int(m.group(1)) if m and 1 <= int(m.group(1)) <= 9 else None

def zones_in(text):
    found = [int(m.group(1)) for m in re.finditer(r'(?<![A-Za-z])[Zz](\d)(?!\d)', text) if 1 <= int(m.group(1)) <= 9]
    if not found:
        return []
    return list(range(min(found), max(found) + 1)) if len(found) >= 2 else [found[0]]

def kind(title):
    t = title.upper()
    return 'swim' if 'SWIM' in t else ('bike' if 'POWER' in t or 'BIKE' in t else 'heart')

def explain(z, intensity, sport):
    zs = zones_in(intensity)
    out = []
    for table in z['tables']:
        k = kind(table['title'])
        if k == 'heart':
            rows = [r for r in table['rows'] if zone_number(r['label']) in zs]
        elif k == 'bike':
            rows = [r for r in table['rows'] if zone_number(r['label']) in zs] if sport in ('bike', 'brick') else []
        else:
            rows = table['rows'] if sport == 'swim' else []
        rows = [r for r in rows if r['value']]
        if rows:
            out.append({'title': table['title'], 'rows': rows})
    return out

SAMPLES = [("Z4–Z5", "bike"), ("Z2", "run"), ("Z1–Z2", "swim"), ("RPE 6", "strength"), ("upper Z2–low Z3", "brick")]

dump = json.load(open(sys.argv[1]))
problems = 0
for path in sys.argv[2:]:
    name = os.path.basename(path)
    mine = read(path)
    theirs = dump.get(name, {}).get('zones')
    if mine != theirs:
        problems += 1
        print(f'! {name}: zones differ')
        print('  openpyxl:', json.dumps(mine, ensure_ascii=False)[:400])
        print('  native:  ', json.dumps(theirs, ensure_ascii=False)[:400])
        continue
    for (intensity, sport), ex in zip(SAMPLES, dump.get(name, {}).get('examples', [])):
        want = explain(mine, intensity, sport) if mine else []
        if ex['tables'] != want or ex['intensity'] != intensity:
            problems += 1
            print(f'! {name}: {intensity} on {sport} differs')
            print('  openpyxl:', json.dumps(want, ensure_ascii=False)[:300])
            print('  native:  ', json.dumps(ex['tables'], ensure_ascii=False)[:300])
    print(f'  {name}: {"zones sheet read" if mine else "no zones sheet"} — same')
print('differences:', problems or 'none')
