#!/usr/bin/env python3
"""Validate, export and import Xcode String Catalog translations."""

from __future__ import annotations

import argparse
import csv
import json
import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CATALOGS = {
    "app": ROOT / "Don't forget" / "Don't forget" / "Localizable.xcstrings",
    "widget": ROOT / "Don't forget" / "Don't forgetWidget" / "Localizable.xcstrings",
}
PLACEHOLDER = re.compile(r"%(?:(\d+)\$)?(?:[-+#0']*\d*(?:\.\d+)?)?(?:hh|h|ll|l|q|z|t|j)?[@dDuUxXoOfFeEgGcCsSpaA%]")


def load_catalogs() -> dict[str, dict]:
    return {name: json.loads(path.read_text(encoding="utf-8")) for name, path in CATALOGS.items()}


def save_catalog(name: str, catalog: dict) -> None:
    CATALOGS[name].write_text(
        json.dumps(catalog, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )


def unit(entry: dict, language: str) -> dict | None:
    localization = entry.get("localizations", {}).get(language)
    if not localization:
        return None
    return localization.get("stringUnit")


def value(entry: dict, language: str) -> str:
    return (unit(entry, language) or {}).get("value", "")


def placeholders(text: str) -> list[str]:
    result = []
    for match in PLACEHOLDER.finditer(text):
        token = match.group(0)
        if token != "%%":
            result.append(re.sub(r"%\d+\$", "%", token))
    return sorted(result)


def validate(catalogs: dict[str, dict], languages: list[str]) -> int:
    problems: list[str] = []
    for catalog_name, catalog in catalogs.items():
        for key, entry in catalog.get("strings", {}).items():
            reference = value(entry, catalog.get("sourceLanguage", "en")) or key
            for language in languages:
                string_unit = unit(entry, language)
                if string_unit is None:
                    problems.append(f"{catalog_name}: {key!r}: ontbreekt voor {language}")
                    continue
                if string_unit.get("state") != "translated":
                    problems.append(f"{catalog_name}: {key!r}: status voor {language} is {string_unit.get('state')!r}")
                translation = string_unit.get("value")
                if translation is None or (not translation and reference):
                    problems.append(f"{catalog_name}: {key!r}: lege vertaling voor {language}")
                elif placeholders(reference) != placeholders(translation):
                    problems.append(
                        f"{catalog_name}: {key!r}: placeholders verschillen voor {language}: "
                        f"{placeholders(reference)} != {placeholders(translation)}"
                    )
    if problems:
        print("\n".join(problems))
        print(f"\n{len(problems)} lokalisatieprobleem/problemen gevonden.", file=sys.stderr)
        return 1
    print(f"Alle {', '.join(languages)} vertalingen zijn compleet en geldig.")
    return 0


def export(catalogs: dict[str, dict], output: Path, languages: list[str]) -> None:
    output.mkdir(parents=True, exist_ok=True)
    fieldnames = ["catalog", "key", "comment", *languages]
    matrix = output / "all-localizations.csv"
    rows = []
    for catalog_name, catalog in catalogs.items():
        for key, entry in sorted(catalog.get("strings", {}).items()):
            row = {
                "catalog": catalog_name,
                "key": key,
                "comment": entry.get("comment", ""),
            }
            row.update({language: value(entry, language) for language in languages})
            rows.append(row)
    write_csv(matrix, fieldnames, rows)

    for language in languages:
        language_rows = [
            {
                "catalog": row["catalog"],
                "key": row["key"],
                "comment": row["comment"],
                "translation": row[language],
            }
            for row in rows
        ]
        write_csv(output / f"all-{language}.csv", ["catalog", "key", "comment", "translation"], language_rows)

    template_rows = [
        {
            "catalog": row["catalog"],
            "key": row["key"],
            "comment": row["comment"],
            "source_en": row.get("en", ""),
            "translation": "",
        }
        for row in rows
    ]
    write_csv(
        output / "new-language-template.csv",
        ["catalog", "key", "comment", "source_en", "translation"],
        template_rows,
    )
    print(f"{len(rows)} regels geëxporteerd naar {output}")


def write_csv(path: Path, fieldnames: list[str], rows: list[dict]) -> None:
    with path.open("w", encoding="utf-8-sig", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames, extrasaction="ignore")
        writer.writeheader()
        writer.writerows(rows)


def import_language(catalogs: dict[str, dict], csv_path: Path, language: str) -> int:
    with csv_path.open(encoding="utf-8-sig", newline="") as handle:
        rows = list(csv.DictReader(handle))
    required = {"catalog", "key", "translation"}
    if not rows or not required.issubset(rows[0]):
        print(f"CSV moet de kolommen {sorted(required)} bevatten.", file=sys.stderr)
        return 1

    errors: list[str] = []
    seen: set[tuple[str, str]] = set()
    for number, row in enumerate(rows, 2):
        catalog_name, key, translation = row["catalog"], row["key"], row["translation"]
        marker = (catalog_name, key)
        if marker in seen:
            errors.append(f"regel {number}: dubbele combinatie {catalog_name}/{key!r}")
            continue
        seen.add(marker)
        catalog = catalogs.get(catalog_name)
        entry = catalog and catalog.get("strings", {}).get(key)
        if entry is None:
            errors.append(f"regel {number}: onbekende combinatie {catalog_name}/{key!r}")
            continue
        reference = value(entry, catalog.get("sourceLanguage", "en")) or key
        if not translation and reference:
            errors.append(f"regel {number}: lege vertaling voor {catalog_name}/{key!r}")
            continue
        if placeholders(reference) != placeholders(translation):
            errors.append(f"regel {number}: placeholders verschillen voor {catalog_name}/{key!r}")

    expected = {
        (catalog_name, key)
        for catalog_name, catalog in catalogs.items()
        for key in catalog.get("strings", {})
    }
    missing = expected - seen
    if missing:
        errors.append(f"CSV mist {len(missing)} catalogusregels")
    if errors:
        print("\n".join(errors), file=sys.stderr)
        print("Er is niets geïmporteerd.", file=sys.stderr)
        return 1

    for row in rows:
        entry = catalogs[row["catalog"]]["strings"][row["key"]]
        entry.setdefault("localizations", {})[language] = {
            "stringUnit": {"state": "translated", "value": row["translation"]}
        }
    for catalog_name, catalog in catalogs.items():
        save_catalog(catalog_name, catalog)
    print(f"Taal {language} is met {len(rows)} vertalingen geïmporteerd.")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)
    validate_parser = subparsers.add_parser("validate")
    validate_parser.add_argument("--languages", nargs="+", default=["en", "nl"])
    export_parser = subparsers.add_parser("export")
    export_parser.add_argument("--languages", nargs="+", default=["en", "nl"])
    export_parser.add_argument("--output", type=Path, default=ROOT / "Localization" / "Exports")
    import_parser = subparsers.add_parser("import")
    import_parser.add_argument("--language", required=True, help="BCP-47-taalcode, bijvoorbeeld de of fr")
    import_parser.add_argument("csv", type=Path)
    args = parser.parse_args()
    catalogs = load_catalogs()
    if args.command == "validate":
        return validate(catalogs, args.languages)
    if args.command == "export":
        export(catalogs, args.output, args.languages)
        return 0
    return import_language(catalogs, args.csv, args.language)


if __name__ == "__main__":
    raise SystemExit(main())
