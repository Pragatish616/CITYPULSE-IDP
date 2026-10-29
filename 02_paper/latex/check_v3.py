"""Static checks for paper v3 without a TeX installation (run from 02_paper/latex: python check_v3.py).

Checks: every custom macro used is defined in numbers.tex; every \\ref has a \\label; braces balance; every \\cite key is in the
bib files and in 03_literature_review/references_verified.tsv; abstract length with macros expanded (IEEE: at most 250 words);
and it lists every number still typed into the prose, so each can be confirmed as a setting or a formula constant, not a result.
"""

from __future__ import annotations

import csv
import re
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
tex = (HERE / "paper.tex").read_text(encoding="utf-8")
nums = (HERE / "numbers.tex").read_text(encoding="utf-8")
defined = dict(re.findall(r"\\newcommand\{\\(\w+)\}\{(.*)\}", nums))
ok = True

used = set(re.findall(r"\\([A-Z][A-Za-z]*)\b", tex))
known_latex = {"IEEEoverridecommandlockouts", "IEEEauthorblockN", "IEEEauthorblockA", "IEEEproof", "IEEEkeywords", "Latex", "UrlBreaks", "Pr", "Phi"}
missing = sorted(u for u in used if u not in defined and u not in known_latex)
print("undefined macros:", missing)
ok &= not missing

labels = set(re.findall(r"\\label\{([^}]+)\}", tex))
refs = set(re.findall(r"\\(?:eq)?ref\{([^}]+)\}", tex))
print("refs without labels:", sorted(refs - labels))
ok &= not (refs - labels)

depth = 0
for ch in re.sub(r"\\[{}]", "", tex):
    depth += ch == "{"
    depth -= ch == "}"
    if depth < 0:
        break
print("brace balance:", depth)
ok &= depth == 0

keys = []
for m in re.finditer(r"\\cite\{([^}]*)\}", tex):
    keys += [k.strip() for k in m.group(1).split(",")]
bib = (HERE / "refs.bib").read_text(encoding="utf-8") + (HERE / "extra.bib").read_text(encoding="utf-8")
bibkeys = set(re.findall(r"@\w+\{([^,\s]+),", bib))
tsv = HERE.parents[1] / "03_literature_review" / "references_verified.tsv"
verified = {r[0] for r in csv.reader(tsv.open(encoding="utf-8"), delimiter="\t") if r}
uniq = list(dict.fromkeys(keys))
print("references cited:", len(uniq), "| missing from bib:", [k for k in uniq if k not in bibkeys],
      "| not verified:", [k for k in uniq if k not in verified])
ok &= all(k in bibkeys and k in verified for k in uniq)

ab = re.search(r"\\begin\{abstract\}(.*?)\\end\{abstract\}", tex, re.S).group(1)
expanded = re.sub(r"\\(\w+)(\{\})?", lambda m: defined.get(m.group(1), m.group(0)), ab)
print("abstract words:", len(expanded.split()))
ok &= len(expanded.split()) <= 250

body = re.sub(r"\\begin\{tikzpicture\}.*?\\end\{tikzpicture\}", "", tex, flags=re.S)
body = re.sub(r"\$[^$]*\$", " ", body)  # maths: formula constants and settings
body = re.sub(r"\\(cite|ref|eqref|label|url|input|includegraphics)\{[^}]*\}", " ", body)
typed = sorted(set(re.findall(r"(?<![\w.])\d[\d,]*(?:\.\d+)?\b", body)))
print("numbers typed in prose (confirm each is a setting, year or constant):", typed)
sys.exit(0 if ok else 1)
