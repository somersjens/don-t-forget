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

# Every language the app offers, in picker order. Mirrors AppLanguage.supportedCodes
# in AppSettings.swift — keep the two lists in sync.
SUPPORTED_CODES = [
    "af", "sq", "am", "ar", "hy", "as", "az", "eu", "bn", "my",
    "bs", "bg", "ca", "zh", "da", "de", "en", "et", "fo", "fi",
    "fr", "gl", "ka", "el", "gu", "he", "hi", "hu", "ga", "is",
    "id", "it", "ja", "kn", "kk", "km", "ko", "hr", "lo", "lv",
    "lt", "mk", "ms", "ml", "mr", "mn", "nl", "ne", "no", "uk",
    "or", "ug", "uz", "fa", "pl", "pt", "pa", "ro", "ru", "sr",
    "si", "sk", "sl", "es", "sw", "ta", "te", "th", "bo", "cs",
    "tr", "ur", "vi", "cy", "be", "zu", "sv",
]
# Languages that still need translating (en + nl are the maintained sources).
TARGET_CODES = [c for c in SUPPORTED_CODES if c not in ("en", "nl")]
PLACEHOLDER = re.compile(r"%(?:(\d+)\$)?(?:[-+#0']*\d*(?:\.\d+)?)?(?:hh|h|ll|l|q|z|t|j)?[@dDuUxXoOfFeEgGcCsSpaA%]")


def load_catalogs() -> dict[str, dict]:
    return {name: json.loads(path.read_text(encoding="utf-8")) for name, path in CATALOGS.items()}


def save_catalog(name: str, catalog: dict) -> None:
    # Match Xcode's String Catalog serialisation: two-space indent, a space on
    # both sides of the key separator and the existing key order preserved, so
    # imports produce minimal diffs instead of reshuffling the whole file.
    CATALOGS[name].write_text(
        json.dumps(catalog, ensure_ascii=False, indent=2, separators=(",", " : ")) + "\n",
        encoding="utf-8",
    )


def iter_units(localization: dict | None) -> list[tuple[str, dict]]:
    """Return every ``stringUnit`` in a localization with its variation path.

    A plain string yields ``[("", unit)]``; a pluralised string yields one entry
    per category, e.g. ``[("plural.one", unit), ("plural.other", unit)]``. Nested
    variations (plural inside device, …) are flattened into a dotted path so the
    tooling stays correct as more languages with richer plural rules are added.
    """
    results: list[tuple[str, dict]] = []
    if not localization:
        return results

    def walk(node: dict, path: str) -> None:
        if "stringUnit" in node:
            results.append((path.rstrip("."), node["stringUnit"]))
        for variation_type, categories in node.get("variations", {}).items():
            for category, sub in categories.items():
                walk(sub, f"{path}{variation_type}.{category}.")

    walk(localization, "")
    return results


def set_unit(localization: dict, variation: str, string_unit: dict) -> None:
    """Write ``string_unit`` at ``variation`` (``""`` for a plain string)."""
    if not variation:
        localization["stringUnit"] = string_unit
        localization.pop("variations", None)
        return
    parts = variation.split(".")
    node = localization
    for variation_type, category in zip(parts[0::2], parts[1::2]):
        node = node.setdefault("variations", {}).setdefault(variation_type, {}).setdefault(category, {})
    node["stringUnit"] = string_unit
    localization.pop("stringUnit", None)


def unit(entry: dict, language: str) -> dict | None:
    localization = entry.get("localizations", {}).get(language)
    if not localization:
        return None
    units = iter_units(localization)
    return units[0][1] if units else None


def value(entry: dict, language: str) -> str:
    return (unit(entry, language) or {}).get("value", "")


def variation_keys(entry: dict, languages: list[str]) -> list[str]:
    """Ordered union of variation paths across the given languages and source."""
    localizations = entry.get("localizations", {})
    order: list[str] = []
    seen: set[str] = set()
    for language in languages:
        for variation, _ in iter_units(localizations.get(language)):
            if variation not in seen:
                seen.add(variation)
                order.append(variation)
    return order or [""]


def variation_value(entry: dict, language: str, variation: str) -> str:
    for candidate, string_unit in iter_units(entry.get("localizations", {}).get(language)):
        if candidate == variation:
            return string_unit.get("value", "")
    return ""


def reference_placeholders(entry: dict, source_language: str, key: str, variation: str) -> list[str]:
    """Placeholders a translation must match: the source form, then any source
    form, then the key itself (legacy Dutch source sentences)."""
    exact = variation_value(entry, source_language, variation)
    if exact:
        return placeholders(exact)
    for _, string_unit in iter_units(entry.get("localizations", {}).get(source_language)):
        if string_unit.get("value"):
            return placeholders(string_unit["value"])
    return placeholders(key)


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
        source_language = catalog.get("sourceLanguage", "en")
        for key, entry in catalog.get("strings", {}).items():
            for language in languages:
                localization = entry.get("localizations", {}).get(language)
                if not localization:
                    problems.append(f"{catalog_name}: {key!r}: ontbreekt voor {language}")
                    continue
                units = iter_units(localization)
                if not units:
                    problems.append(f"{catalog_name}: {key!r}: lege vertaling voor {language}")
                    continue
                for variation, string_unit in units:
                    label = f"{key!r}" if not variation else f"{key!r} ({variation})"
                    if string_unit.get("state") != "translated":
                        problems.append(f"{catalog_name}: {label}: status voor {language} is {string_unit.get('state')!r}")
                    translation = string_unit.get("value")
                    reference = reference_placeholders(entry, source_language, key, variation)
                    if translation is None or (not translation and reference):
                        problems.append(f"{catalog_name}: {label}: lege vertaling voor {language}")
                    elif placeholders(translation) != reference:
                        problems.append(
                            f"{catalog_name}: {label}: placeholders verschillen voor {language}: "
                            f"{placeholders(translation)} != {reference}"
                        )
    if problems:
        print("\n".join(problems))
        print(f"\n{len(problems)} lokalisatieprobleem/problemen gevonden.", file=sys.stderr)
        return 1
    print(f"Alle {', '.join(languages)} vertalingen zijn compleet en geldig.")
    return 0


def export(catalogs: dict[str, dict], output: Path, languages: list[str]) -> None:
    output.mkdir(parents=True, exist_ok=True)
    fieldnames = ["catalog", "key", "variation", "comment", *languages]
    matrix = output / "all-localizations.csv"
    rows = []
    for catalog_name, catalog in catalogs.items():
        for key, entry in sorted(catalog.get("strings", {}).items()):
            for variation in variation_keys(entry, languages):
                row = {
                    "catalog": catalog_name,
                    "key": key,
                    "variation": variation,
                    "comment": entry.get("comment", ""),
                }
                row.update({language: variation_value(entry, language, variation) for language in languages})
                rows.append(row)
    write_csv(matrix, fieldnames, rows)

    for language in languages:
        language_rows = [
            {
                "catalog": row["catalog"],
                "key": row["key"],
                "variation": row["variation"],
                "comment": row["comment"],
                "translation": row[language],
            }
            for row in rows
        ]
        write_csv(
            output / f"all-{language}.csv",
            ["catalog", "key", "variation", "comment", "translation"],
            language_rows,
        )

    template_rows = [
        {
            "catalog": row["catalog"],
            "key": row["key"],
            "variation": row["variation"],
            "comment": row["comment"],
            "source_en": row.get("en", ""),
            "translation": "",
        }
        for row in rows
    ]
    write_csv(
        output / "new-language-template.csv",
        ["catalog", "key", "variation", "comment", "source_en", "translation"],
        template_rows,
    )
    print(f"{len(rows)} regels geëxporteerd naar {output}")


def write_csv(path: Path, fieldnames: list[str], rows: list[dict], delimiter: str = ",") -> None:
    with path.open("w", encoding="utf-8-sig", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames, extrasaction="ignore", delimiter=delimiter)
        writer.writeheader()
        writer.writerows(rows)


def escape_cell(text: str) -> str:
    """Keep every cell on a single line so the file stays easy to hand-edit."""
    return text.replace("\\", "\\\\").replace("\n", "\\n").replace("\r", "\\r").replace("\t", "\\t")


def unescape_cell(text: str) -> str:
    out, i = [], 0
    while i < len(text):
        if text[i] == "\\" and i + 1 < len(text):
            nxt = text[i + 1]
            out.append({"n": "\n", "r": "\r", "t": "\t", "\\": "\\"}.get(nxt, nxt))
            i += 2
        else:
            out.append(text[i])
            i += 1
    return "".join(out)


def build_instruction(key: str, variation: str, en_value: str, nl_value: str) -> str:
    """Human guidance for translating one cell: length budget, placeholders,
    special characters and plural context."""
    parts: list[str] = []
    if variation.startswith("plural."):
        category = variation.split(".", 1)[1]
        parts.append(
            f"Meervoudsvorm '{category}' (one=enkelvoud, other=meervoud). "
            "Gebruik de telregels van de doeltaal."
        )
    holders = placeholders(en_value) or placeholders(key)
    if holders:
        parts.append(
            "Behoud de dynamische plaatshouders exact en in dezelfde volgorde: "
            + ", ".join(holders)
            + " (%@ = tekst, %lld = getal). Niet vertalen."
        )
    specials = sorted({c for c in en_value if c in "·•✓°—…‘’“”" or ord(c) > 0x2000})
    if specials:
        parts.append("Behoud speciale tekens: " + " ".join(specials) + ".")
    if "\n" in en_value:
        parts.append("Behoud de regelafbreek (\\n).")
    budget = max(len(en_value), len(nl_value))
    if budget:
        parts.append(f"Streef naar ± {budget} tekens (UI-ruimte).")
    if en_value and en_value == nl_value:
        parts.append("Mogelijk niet vertalen (merknaam/symbool/getal).")
    if not parts:
        parts.append("Vertaal deze tekst.")
    return " ".join(parts)


def export_matrix(catalogs: dict[str, dict], output: Path) -> None:
    fieldnames = ["instructie", "en", "nl", *TARGET_CODES, "catalog", "key", "variation"]
    rows: list[dict] = []
    for catalog_name, catalog in catalogs.items():
        for key, entry in sorted(catalog.get("strings", {}).items()):
            for variation in variation_keys(entry, ["en", "nl"]):
                en_v = variation_value(entry, "en", variation)
                nl_v = variation_value(entry, "nl", variation)
                row = {
                    "instructie": build_instruction(key, variation, en_v, nl_v),
                    "en": escape_cell(en_v),
                    "nl": escape_cell(nl_v),
                    "catalog": catalog_name,
                    "key": escape_cell(key),
                    "variation": variation,
                }
                for code in TARGET_CODES:
                    row[code] = escape_cell(variation_value(entry, code, variation))
                rows.append(row)
    output.parent.mkdir(parents=True, exist_ok=True)
    write_csv(output, fieldnames, rows, delimiter=";")
    print(f"{len(rows)} regels geëxporteerd naar {output} ({len(TARGET_CODES)} doeltalen).")


def import_matrix(catalogs: dict[str, dict], csv_path: Path) -> int:
    with csv_path.open(encoding="utf-8-sig", newline="") as handle:
        reader = csv.DictReader(handle, delimiter=";")
        rows = list(reader)
        headers = reader.fieldnames or []
    if not rows or not {"catalog", "key"}.issubset(headers):
        print("CSV moet minstens de kolommen 'catalog' en 'key' bevatten (puntkomma-gescheiden).", file=sys.stderr)
        return 1

    lang_cols = [h for h in headers if h in SUPPORTED_CODES and h != "en"]
    if not lang_cols:
        print("Geen taalkolommen gevonden om te importeren.", file=sys.stderr)
        return 1

    errors: list[str] = []
    edits: list[tuple[str, str, str, str, str]] = []  # catalog, lang, key, variation, value
    for number, row in enumerate(rows, 2):
        catalog_name = (row.get("catalog") or "").strip()
        key = unescape_cell(row.get("key") or "")
        variation = (row.get("variation") or "").strip()
        catalog = catalogs.get(catalog_name)
        entry = catalog and catalog.get("strings", {}).get(key)
        if entry is None:
            errors.append(f"regel {number}: onbekende combinatie {catalog_name!r}/{key!r}")
            continue
        reference = reference_placeholders(entry, catalog.get("sourceLanguage", "en"), key, variation)
        for code in lang_cols:
            raw = row.get(code)
            if raw is None or raw == "":
                continue  # empty cell -> leave untranslated (runtime falls back to English)
            value = unescape_cell(raw)
            if placeholders(value) != reference:
                errors.append(
                    f"regel {number}: plaatshouders verschillen voor {catalog_name}/{key!r} ({code}): "
                    f"{placeholders(value)} != {reference}"
                )
                continue
            edits.append((catalog_name, code, key, variation, value))

    if errors:
        print("\n".join(errors), file=sys.stderr)
        print("Er is niets geïmporteerd.", file=sys.stderr)
        return 1

    per_language: dict[str, int] = {}
    for catalog_name, code, key, variation, value in edits:
        entry = catalogs[catalog_name]["strings"][key]
        localization = entry.setdefault("localizations", {}).setdefault(code, {})
        set_unit(localization, variation, {"state": "translated", "value": value})
        per_language[code] = per_language.get(code, 0) + 1
    for catalog_name, catalog in catalogs.items():
        save_catalog(catalog_name, catalog)
    summary = ", ".join(f"{code}: {count}" for code, count in sorted(per_language.items()))
    print(f"{len(edits)} vertalingen geïmporteerd voor {len(per_language)} talen. {summary}")
    return 0


def import_language(catalogs: dict[str, dict], csv_path: Path, language: str) -> int:
    with csv_path.open(encoding="utf-8-sig", newline="") as handle:
        rows = list(csv.DictReader(handle))
    required = {"catalog", "key", "translation"}
    if not rows or not required.issubset(rows[0]):
        print(f"CSV moet de kolommen {sorted(required)} bevatten.", file=sys.stderr)
        return 1

    errors: list[str] = []
    seen: set[tuple[str, str, str]] = set()
    for number, row in enumerate(rows, 2):
        catalog_name, key = row["catalog"], row["key"]
        variation, translation = row.get("variation", "") or "", row["translation"]
        marker = (catalog_name, key, variation)
        if marker in seen:
            errors.append(f"regel {number}: dubbele combinatie {catalog_name}/{key!r} ({variation or 'plain'})")
            continue
        seen.add(marker)
        catalog = catalogs.get(catalog_name)
        entry = catalog and catalog.get("strings", {}).get(key)
        if entry is None:
            errors.append(f"regel {number}: onbekende combinatie {catalog_name}/{key!r}")
            continue
        reference = reference_placeholders(entry, catalog.get("sourceLanguage", "en"), key, variation)
        if not translation and reference:
            errors.append(f"regel {number}: lege vertaling voor {catalog_name}/{key!r} ({variation or 'plain'})")
            continue
        if placeholders(translation) != reference:
            errors.append(f"regel {number}: placeholders verschillen voor {catalog_name}/{key!r} ({variation or 'plain'})")

    expected = {
        (catalog_name, key, variation)
        for catalog_name, catalog in catalogs.items()
        for key, entry in catalog.get("strings", {}).items()
        for variation in variation_keys(entry, [catalog.get("sourceLanguage", "en")])
    }
    missing = expected - seen
    if missing:
        sample = ", ".join(f"{c}/{k!r}" + (f" ({v})" if v else "") for c, k, v in sorted(missing)[:5])
        errors.append(f"CSV mist {len(missing)} catalogusregels: {sample}")
    if errors:
        print("\n".join(errors), file=sys.stderr)
        print("Er is niets geïmporteerd.", file=sys.stderr)
        return 1

    for row in rows:
        entry = catalogs[row["catalog"]]["strings"][row["key"]]
        localization = entry.setdefault("localizations", {}).setdefault(language, {})
        set_unit(localization, row.get("variation", "") or "", {"state": "translated", "value": row["translation"]})
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
    export_matrix_parser = subparsers.add_parser(
        "export-matrix", help="Eén puntkomma-CSV met instructie, en, nl en een kolom per doeltaal."
    )
    export_matrix_parser.add_argument(
        "--output", type=Path, default=ROOT / "Localization" / "translations.csv"
    )
    import_matrix_parser = subparsers.add_parser(
        "import-matrix", help="Laad een gevulde vertaalmatrix (alle talen tegelijk) in."
    )
    import_matrix_parser.add_argument("csv", type=Path)
    args = parser.parse_args()
    catalogs = load_catalogs()
    if args.command == "validate":
        return validate(catalogs, args.languages)
    if args.command == "export":
        export(catalogs, args.output, args.languages)
        return 0
    if args.command == "export-matrix":
        export_matrix(catalogs, args.output)
        return 0
    if args.command == "import-matrix":
        return import_matrix(catalogs, args.csv)
    return import_language(catalogs, args.csv, args.language)


if __name__ == "__main__":
    raise SystemExit(main())
