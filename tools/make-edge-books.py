#!/usr/bin/env python3
"""
make-edge-books.py <out-dir>

Workbooks shaped to reach the branches of the writer that his real plans and
the web app's fixtures never do. Every fixture openpyxl writes already carries
fullCalcOnLoad and no calcChain, dates as text or plain numbers, minutes and
kilometres — so the first 336 scenarios could not have told a broken branch
for any of these from a working one:

  edge-nocalc        no <calcPr> at all             -> one is added
  edge-calc-noflag   <calcPr> without the flag       -> the flag is added to it
  edge-formulas      formulas in the result columns
                     and an xl/calcChain.xml         -> formula dropped, chain removed
  edge-dates         real Excel dates, a date-styled
                     "Logged on" column, hours, metres -> serials written
  edge-1904          the same on the 1904 date system
  edge-time          durations formatted as h:mm:ss  -> time fractions written
  edge-sections      one row per section             -> section-rows mode
  edge-dimension     a stale <dimension>, self-closed
                     rows and cells, no spans        -> the splice paths
"""
import datetime
import os
import re
import shutil
import sys
import tempfile
import zipfile

import openpyxl
from openpyxl.utils.datetime import CALENDAR_MAC_1904

OUT = sys.argv[1]
os.makedirs(OUT, exist_ok=True)
DAYS = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
SPORTS = [("Swim", 45), ("Bike", 90), ("Run", 40), ("Strength", 30), ("Run", 50), ("Bike", 120), ("Rest", None)]
MONDAY = datetime.date(2026, 9, 14)


def rows(weeks=3):
    for w in range(weeks):
        for d, (sport, minutes) in enumerate(SPORTS):
            yield w, d, MONDAY + datetime.timedelta(days=7 * w + d), sport, minutes


def rezip(path, edit):
    """Rewrite some parts of an archive through `edit(name, text) -> text or None to drop`."""
    fd, tmp = tempfile.mkstemp(suffix=".xlsx")
    os.close(fd)
    with zipfile.ZipFile(path) as zin, zipfile.ZipFile(tmp, "w", zipfile.ZIP_DEFLATED) as zout:
        for info in zin.infolist():
            data = zin.read(info.filename)
            if info.filename.endswith(".xml") or info.filename.endswith(".rels"):
                text = edit(info.filename, data.decode("utf-8"))
                if text is None:
                    continue
                data = text.encode("utf-8")
            zout.writestr(info, data)
        extra = edit("__add__", "")
        if extra:
            for name, text in extra:
                zout.writestr(name, text)
    shutil.move(tmp, path)


def simple(path, *, text_dates=True, hours=False, metres=False, logged_on=False, epoch1904=False, time_col=False):
    wb = openpyxl.Workbook()
    if epoch1904:
        wb.epoch = CALENDAR_MAC_1904
    ws = wb.active
    ws.title = "Weekly Schedules"
    dur = "Duration" if time_col else ("Duration (h)" if hours else "Duration (min)")
    act = "Actual time" if time_col else ("Actual (h)" if hours else "Actual (min)")
    dist = "Actual distance (m)" if metres else "Actual (km)"
    headers = ["Week", "Date", "Day", "Sport", "Workout", dur, "Zone", "Done", act, dist, "Avg Pace", "Avg HR", "Effort", "Notes"]
    if logged_on:
        headers.append("Logged on")
    ws.append(headers)
    r = 2
    for w, d, date, sport, minutes in rows():
        planned = None if minutes is None else (minutes / 60 if hours else minutes)
        ws.append([w + 1, date.isoformat() if text_dates else date, DAYS[d], sport, sport + " session", planned, "Z2"])
        if not text_dates:
            ws.cell(r, 2).number_format = "yyyy-mm-dd"
        if time_col:
            ws.cell(r, 9).number_format = "h:mm:ss"
            if w == 0 and minutes:
                ws.cell(r, 9).value = datetime.time(minutes // 60, minutes % 60)
        if logged_on:
            ws.cell(r, 15).number_format = "yyyy-mm-dd"
        r += 1
    wb.save(path)


def main():
    p = os.path.join(OUT, "edge-nocalc.xlsx")
    simple(p)
    rezip(p, lambda n, t: re.sub(r"<calcPr[^>]*/>", "", t) if n == "xl/workbook.xml" else (None if n == "__add__" else t))

    p = os.path.join(OUT, "edge-calc-noflag.xlsx")
    simple(p)
    rezip(p, lambda n, t: re.sub(r"<calcPr[^>]*/>", '<calcPr calcId="191029"/>', t) if n == "xl/workbook.xml" else (None if n == "__add__" else t))

    # Formulas where results go, and a calculation chain that lists them.
    p = os.path.join(OUT, "edge-formulas.xlsx")
    wb = openpyxl.Workbook()
    ws = wb.active
    ws.title = "Weekly Schedules"
    ws.append(["Week", "Date", "Day", "Sport", "Workout", "Duration (min)", "Done", "Actual (min)", "Actual (km)", "Avg HR", "Notes", "Compliance"])
    r = 2
    for w, d, date, sport, minutes in rows():
        ws.append([w + 1, date.isoformat(), DAYS[d], sport, sport + " session", minutes])
        ws.cell(r, 8).value = f"=F{r}"
        ws.cell(r, 12).value = f'=IF(H{r}="","",H{r}/F{r})'
        r += 1
    wb.save(p)
    chain = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n<calcChain xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">' + \
        "".join(f'<c r="H{i}" i="1"/><c r="L{i}"/>' for i in range(2, r)) + "</calcChain>"

    def formulas(n, t):
        if n == "__add__":
            return [("xl/calcChain.xml", chain)]
        if n == "[Content_Types].xml":
            return t.replace("</Types>", '<Override PartName="/xl/calcChain.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.calcChain+xml"/></Types>')
        if n == "xl/_rels/workbook.xml.rels":
            return t.replace("</Relationships>", '<Relationship Id="rId99" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/calcChain" Target="calcChain.xml"/></Relationships>')
        return t
    rezip(p, formulas)

    simple(os.path.join(OUT, "edge-dates.xlsx"), text_dates=False, hours=True, metres=True, logged_on=True)
    simple(os.path.join(OUT, "edge-1904.xlsx"), text_dates=False, logged_on=True, epoch1904=True)
    simple(os.path.join(OUT, "edge-time.xlsx"), time_col=True)

    # One row per section, the sport named on the first row of each group.
    p = os.path.join(OUT, "edge-sections.xlsx")
    wb = openpyxl.Workbook()
    ws = wb.active
    ws.title = "Plan"
    ws.append(["Date", "Sport", "Section", "Description", "Duration (min)", "Done", "Actual (min)", "Avg HR", "Notes"])
    for w, d, date, sport, minutes in rows(2):
        if minutes is None:
            ws.append([date.isoformat(), sport, "", "Rest day"])
            continue
        ws.append([date.isoformat(), sport, "Warm-up", "Easy", 10])
        ws.append([None, None, "Main set", sport + " main set", minutes - 15])
        ws.append([None, None, "Cool-down", "Loose", 5])
        ws.append([])
    wb.save(p)

    # A stale dimension, self-closed rows and cells, no spans hints.
    p = os.path.join(OUT, "edge-dimension.xlsx")
    simple(p)

    def dimension(n, t):
        if n == "__add__":
            return None
        if not n.startswith("xl/worksheets/"):
            return t
        t = re.sub(r'<dimension ref="[^"]*"/>', '<dimension ref="A1:C3"/>', t)
        t = re.sub(r'\sspans="[^"]*"', "", t)
        t = t.replace("</sheetData>", '<row r="40"/><row r="41"><c r="A41" s="0"/></row></sheetData>')
        return t
    rezip(p, dimension)

    print("edge books written to", OUT)


if __name__ == "__main__":
    main()
