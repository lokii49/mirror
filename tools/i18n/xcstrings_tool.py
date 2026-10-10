"""Edit Localizable.xcstrings without reformatting it (Xcode's exact JSON layout and key order).

`python3 tools/i18n/xcstrings_tool.py <catalog>...` checks that load+dump round-trips byte for byte.
From Python: load(path) -> dict, insert(d, key, entry), then write dump(d) back. New translations
use state "needs_review"; English uses "translated" with the key as its value. Languages: de, es,
fr, it, ja, ko, pt-BR, ru, zh-Hans. Insert only your keys; never re-sort or rewrite others.
"""
import json, re, sys
from collections import OrderedDict
def load(p): return json.load(open(p), object_pairs_hook=OrderedDict)
def dump(d):
    s=json.dumps(d, indent=2, ensure_ascii=False, separators=(",", " : "))
    # Xcode writes an empty object as "{\n\n<indent>}"
    s=re.sub(r'^(\s*)(.*)\{\}', lambda m: m.group(1)+m.group(2)+'{\n\n'+m.group(1)+'}', s, flags=re.M)
    return s
def natkey(k):
    return [ (0,int(t)) if t.isdigit() else (1,t) for t in re.findall(r'\d+|\D+', k.casefold())]
def insert(d, key, entry):
    strings=d['strings']
    if key in strings: raise SystemExit(f'exists: {key}')
    items=list(strings.items()); out=OrderedDict(); placed=False
    for k,v in items:
        if not placed and natkey(k) > natkey(key):
            out[key]=entry; placed=True
        out[k]=v
    if not placed: out[key]=entry
    d['strings']=out
if __name__=='__main__':
    for p in sys.argv[1:]:
        raw=open(p).read()
        print(p, 'roundtrip-identical' if dump(load(p))==raw else 'DIFFERS')
