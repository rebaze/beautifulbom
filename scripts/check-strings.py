"""Checks App/Localizable.xcstrings against the code: every L("…") key in the app has an
English and a German value, placeholders match, and no value claims conformity.

Run from the repository root (make strings-check, part of make test).
"""
import glob
import json
import re
import sys

FORBIDDEN = re.compile(r"compliant|conformant|konform|zertifiziert|certified", re.I)
PLACEHOLDER = re.compile(r"%(?:\d+\$)?[@d]")

catalog = json.load(open("App/Localizable.xcstrings"))["strings"]
keys = []
for path in sorted(glob.glob("App/**/*.swift", recursive=True)):
    text = open(path).read()
    # L("key", …) and Lp(n, "one", "other"): both forms of a count are keys.
    found = [m.group(1) for m in re.finditer(r'\bL\("((?:[^"\\]|\\.)*)"', text)]
    for m in re.finditer(r'\bLp\([^,]+,\s*"((?:[^"\\]|\\.)*)"\s*,\s*"((?:[^"\\]|\\.)*)"', text):
        found += [m.group(1), m.group(2)]
    for raw in found:
        key = raw.encode().decode("unicode_escape").encode("latin-1").decode("utf-8")
        if key not in keys:
            keys.append(key)

problems = []
for key in keys:
    entry = catalog.get(key)
    if entry is None:
        problems.append(f"missing from the catalog: {key!r}")
        continue
    for lang in ("en", "de"):
        value = entry.get("localizations", {}).get(lang, {}).get("stringUnit", {}).get("value")
        if not value:
            problems.append(f"no {lang} value: {key!r}")
        elif sorted(PLACEHOLDER.findall(value)) != sorted(PLACEHOLDER.findall(key)):
            problems.append(f"{lang} placeholders differ: {key!r} → {value!r}")
for key, entry in catalog.items():
    for lang, loc in entry.get("localizations", {}).items():
        value = loc.get("stringUnit", {}).get("value", "")
        if FORBIDDEN.search(value):
            problems.append(f"{lang} value claims conformity: {value!r}")
unused = [k for k in catalog if k not in keys]
if unused:
    problems.append(f"unused catalog keys: {unused}")

if problems:
    print("\n".join(problems))
    sys.exit(1)
print(f"{len(keys)} strings, English and German, checked")
