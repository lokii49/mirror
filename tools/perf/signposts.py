#!/usr/bin/env python3
"""Pairs com.lokesh.mirror/perf signpost Begin/End rows from `xctrace export` (os-signpost table)
and prints per-interval counts and durations. Usage: signposts.py <export.xml>"""
import sys, collections
import xml.etree.ElementTree as ET

root = ET.parse(sys.argv[1]).getroot()
by_id = {}
def val(el):
    if el is None: return None
    ref = el.get("ref")
    if ref is not None: return by_id.get(ref)
    v = el.text if el.text is not None else el.get("fmt")
    if el.get("id") is not None: by_id[el.get("id")] = v
    # register nested ids too
    for child in el.iter():
        if child is not el and child.get("id") is not None:
            by_id[child.get("id")] = child.text if child.text is not None else child.get("fmt")
    return v

open_ = collections.defaultdict(list)
rows = collections.defaultdict(list)
for row in root.iter("row"):
    t = int(val(row.find("event-time")) or 0)
    kind = val(row.find("event-type"))
    name = val(row.find("signpost-name"))
    sub = val(row.find("subsystem"))
    for el in row: val(el)  # register ids in every column
    if sub != "com.lokesh.mirror": continue
    if kind == "Begin": open_[name].append(t)
    elif kind == "End" and open_[name]:
        rows[name].append((t - open_[name].pop()) / 1e6)  # ns -> ms
print(f"{'interval':34} {'n':>3} {'median ms':>10} {'max ms':>10}")
for name, ds in sorted(rows.items()):
    ds.sort(); print(f"{name:34} {len(ds):>3} {ds[len(ds)//2]:>10.1f} {ds[-1]:>10.1f}")
