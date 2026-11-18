#!/usr/bin/env python3
"""Checks Resources/Localizations/*.json against the strings used in Sources/.

English and Polish are written at the call sites (L10n.text/format/plural), every other
language needs a catalog entry for each English key, with identical printf placeholders,
and all four plural forms (@key.one/few/many/other).

Usage: scripts/check-localization.py [--list]
"""
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CATALOGS = ROOT / "Resources" / "Localizations"
LANGUAGES = ["de", "fr", "es", "it", "pt", "nl", "sv", "cs", "uk", "ja", "ko", "zh-Hans", "zh-Hant"]
PLURAL_FORMS = ["one", "few", "many", "other"]

STRING = r'"((?:[^"\\]|\\.)*)"'
# Swift (L10n.text) and C# (L10n.Text) call sites.
TEXT_CALL = re.compile(r"L10n\.(?:[tT]ext|[fF]ormat)\(\s*" + STRING)
PLURAL_CALL = re.compile(r'L10n\.[pP]lural\(\s*"(\w+)"')
PLACEHOLDER = re.compile(r"%(?:@|ld|d)")
SOURCES = [("Sources", "*.swift"), ("windows/src", "*.cs")]


def source_files():
    for folder, pattern in SOURCES:
        yield from sorted((ROOT / folder).rglob(pattern))


def source_keys():
    keys, plurals = set(), set()
    for path in source_files():
        if "/obj/" in str(path) or "/bin/" in str(path):
            continue
        text = path.read_text(encoding="utf-8")
        keys.update(match.group(1).encode().decode("unicode_escape").encode("latin-1").decode("utf-8")
                    for match in TEXT_CALL.finditer(text))
        plurals.update(match.group(1) for match in PLURAL_CALL.finditer(text))
    return keys, plurals


def main():
    keys, plurals = source_keys()
    if "--list" in sys.argv:
        print(json.dumps(sorted(keys), ensure_ascii=False, indent=2))
        print("plural keys:", sorted(plurals))
        return 0

    problems = []
    for language in LANGUAGES:
        path = CATALOGS / f"{language}.json"
        if not path.exists():
            problems.append(f"{language}: missing catalog")
            continue
        catalog = json.loads(path.read_text(encoding="utf-8"))
        for key in sorted(keys):
            value = catalog.get(key)
            if not value:
                problems.append(f"{language}: missing {key!r}")
            elif PLACEHOLDER.findall(value) != PLACEHOLDER.findall(key):
                problems.append(f"{language}: placeholders differ in {key!r}")
        for plural in sorted(plurals):
            for form in PLURAL_FORMS:
                value = catalog.get(f"@{plural}.{form}")
                if not value:
                    problems.append(f"{language}: missing @{plural}.{form}")
                elif PLACEHOLDER.findall(value) != ["%ld"]:
                    problems.append(f"{language}: @{plural}.{form} must contain exactly one %ld")
        known = keys | {f"@{plural}.{form}" for plural in plurals for form in PLURAL_FORMS}
        for extra in sorted(set(catalog) - known):
            problems.append(f"{language}: unused {extra!r}")

    for problem in problems:
        print(problem)
    print(f"{len(keys)} strings, {len(plurals)} plurals, {len(LANGUAGES)} catalogs: "
          + ("OK" if not problems else f"{len(problems)} problems"))
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
