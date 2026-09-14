#!/usr/bin/env -S uv run --with beautifulsoup4 --with lxml python
# ptx_shapes.py - download the current PTX ISA and print the mma/wmma "Matrix Shape" table,
# the block-scaling kind table, and the Target ISA notes for mma and mma.sp.
# Usage: ./ptx_shapes.py [cached.html]
import re, sys, urllib.request
from bs4 import BeautifulSoup

URL = "https://docs.nvidia.com/cuda/parallel-thread-execution/index.html"
src = sys.argv[1] if len(sys.argv) > 1 else None
html = open(src, encoding="utf8").read() if src else urllib.request.urlopen(URL).read().decode("utf8")
s = BeautifulSoup(html, "lxml")

def section(prefix):
    for h in s.find_all(["h3", "h4", "h5"]):
        t = h.get_text(" ", strip=True)
        if t.startswith(prefix):
            return t, (h.find_parent("section") or h.parent)
    return None, None

def print_tables(sec, n=1):
    for tbl in sec.find_all("table")[:n]:
        for tr in tbl.find_all("tr"):
            print(" | ".join(c.get_text(" ", strip=True) for c in tr.find_all(["th", "td"])))
        print("---")

def print_isa_notes(sec):
    txt = re.sub(r"\n+", "\n", sec.get_text("\n"))
    i = txt.find("Target ISA Notes"); j = txt.find("Examples", i)
    print(re.sub(r"\n(?=[a-z.,/])", " ", txt[i:j]))

t, sec = section("9.7.15.1"); print("=====", t); print_tables(sec)
t, sec = section("9.7.15.3"); print("=====", t, "(scale_vec / kind table)"); print_tables(sec, 2)
for pfx in ("9.7.15.5.14", "9.7.15.6.3"):
    t, sec = section(pfx); print("=====", t); print_isa_notes(sec)
