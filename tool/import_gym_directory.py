"""Extract a minimal gym directory from a supplied workbook without changing it.

Usage: python tool/import_gym_directory.py --source <file.xlsx>
Only Python's standard library is needed. No Excel application is opened.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import unicodedata
import zipfile
from collections import Counter
from pathlib import Path, PurePosixPath
from typing import Any
from xml.etree import ElementTree as ET


SPREADSHEET_NS = "http://schemas.openxmlformats.org/spreadsheetml/2006/main"
RELATIONSHIP_NS = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"
NS = {"s": SPREADSHEET_NS}
EXPECTED_HEADERS = (
    "No.",
    "사업장명1(검증)",
    "사업장명2",
    "도로명주소",
    "지번주소",
    "전화번호",
    "전화번호 2",
)
REPO_ROOT = Path(__file__).resolve().parent.parent


class DirectoryImportError(ValueError):
    """The supplied workbook cannot safely produce the directory contract."""


def normalize_text(value: str) -> str:
    return " ".join(unicodedata.normalize("NFC", value).split())


def identity_text(value: str) -> str:
    return normalize_text(value).casefold()


def place_id(key: tuple[str, str]) -> str:
    digest = hashlib.sha256((key[0] + "\0" + key[1]).encode("utf-8"))
    return "place-" + digest.hexdigest()[:24]


def _text(element: ET.Element) -> str:
    return "".join(node.text or "" for node in element.iter(f"{{{SPREADSHEET_NS}}}t"))


def read_rows(source_bytes: bytes) -> tuple[str, list[tuple[int, dict[str, str]]], dict[int, list[str]]]:
    from io import BytesIO

    try:
        with zipfile.ZipFile(BytesIO(source_bytes)) as archive:
            workbook = ET.fromstring(archive.read("xl/workbook.xml"))
            relationships = ET.fromstring(archive.read("xl/_rels/workbook.xml.rels"))
            targets = {node.get("Id"): node.get("Target") for node in relationships}
            sheets = workbook.findall("s:sheets/s:sheet", NS)
            if len(sheets) != 1:
                raise DirectoryImportError("Expected exactly one source worksheet.")
            sheet = sheets[0]
            target = targets.get(sheet.get(f"{{{RELATIONSHIP_NS}}}id"))
            if not target:
                raise DirectoryImportError("Missing worksheet relationship.")
            path = str(PurePosixPath(target.lstrip("/")))
            if not path.startswith("xl/"):
                path = "xl/" + path
            shared_strings: list[str] = []
            if "xl/sharedStrings.xml" in archive.namelist():
                strings = ET.fromstring(archive.read("xl/sharedStrings.xml"))
                shared_strings = [_text(node) for node in strings.findall("s:si", NS)]
            worksheet = ET.fromstring(archive.read(path))
            rows: list[tuple[int, dict[str, str]]] = []
            error_cells: dict[int, list[str]] = {}
            for row in worksheet.findall("s:sheetData/s:row", NS):
                row_number = int(row.get("r", "0"))
                values: dict[str, str] = {}
                for cell in row.findall("s:c", NS):
                    reference = cell.get("r", "")
                    match = re.fullmatch(r"([A-Z]+)[1-9][0-9]*", reference)
                    if match is None:
                        raise DirectoryImportError(f"Invalid cell reference: {reference!r}.")
                    if cell.find("s:f", NS) is not None:
                        raise DirectoryImportError(f"Formula in source cell {reference}.")
                    value_node = cell.find("s:v", NS)
                    value = value_node.text or "" if value_node is not None else ""
                    if cell.get("t") == "s":
                        index = int(value)
                        if index < 0 or index >= len(shared_strings):
                            raise DirectoryImportError(f"Invalid shared string in {reference}.")
                        value = shared_strings[index]
                    elif cell.get("t") == "inlineStr":
                        value = _text(cell)
                    elif cell.get("t") == "e":
                        error_cells.setdefault(row_number, []).append(reference)
                        value = ""
                    values[match[1]] = normalize_text(value)
                if any(values.values()):
                    rows.append((row_number, values))
            return sheet.get("name", ""), rows, error_cells
    except DirectoryImportError:
        raise
    except (OSError, KeyError, ValueError, ET.ParseError, zipfile.BadZipFile) as error:
        raise DirectoryImportError(f"Invalid source workbook: {error}") from error


def reviewed_names_provenance(provider: str, base_source: str, reference_url: str | None) -> dict[str, Any]:
    provider = normalize_text(provider)
    base_source = normalize_text(base_source)
    if not provider or not base_source:
        raise DirectoryImportError("Reviewed-name provenance needs a provider and a base source.")
    return {
        "base": base_source,
        "nameReview": provider + " 제공자 확인 이름 우선",
        "originalRegisteredName": "검색 별칭",
        "confirmedByUser": True,
        "referenceUrl": normalize_text(reference_url) or None if reference_url is not None else None,
    }


def address_quality_flags(data_rows: list[tuple[int, dict[str, str]]], gyms: list[dict[str, Any]]) -> list[dict[str, Any]]:
    # These are literal source observations, not decisions about legal districts.
    prefixes = ("전남광주통합특별시", "경기", "인천광역시 검단구")
    flags = []
    for prefix in prefixes:
        def matches(address: str) -> bool:
            return address == prefix or address.startswith(prefix + " ")

        input_count = sum(matches(row.get("D") or row.get("E") or "") for _, row in data_rows)
        if input_count:
            flags.append({
                "code": "address_prefix_review",
                "sourceLiteral": prefix,
                "inputRows": input_count,
                "outputEntries": sum(matches(gym["address"]) for gym in gyms),
                "note": "원본 주소 표기를 보존했습니다. 행정구역 명칭과 자료 기준일은 별도 확인이 필요합니다.",
            })
    return flags


def build_catalog(
    source: Path,
    *,
    source_label: str = "제공된 헬스장 목록",
    provenance: dict[str, Any] | None = None,
) -> tuple[dict[str, Any], dict[str, Any]]:
    source_label = normalize_text(source_label)
    if not source_label:
        raise DirectoryImportError("The source label cannot be empty.")
    source_bytes = source.read_bytes()
    sheet_name, rows, error_cells = read_rows(source_bytes)
    if not rows:
        raise DirectoryImportError("The source worksheet is empty.")
    _, headers = rows[0]
    actual_headers = tuple(headers.get(column, "") for column in "ABCDEFG")
    if actual_headers != EXPECTED_HEADERS or any(
        value for column, value in headers.items() if column not in "ABCDEFG"
    ):
        raise DirectoryImportError("Unexpected headers: expected No., names, addresses and phones.")

    entries: dict[tuple[str, str], dict[str, Any]] = {}
    ids: dict[str, tuple[str, str]] = {}
    original_rows: dict[tuple[str, str], list[int]] = {}
    excluded_rows: list[int] = []
    excluded_invalid_rows: list[int] = []
    duplicate_rows = 0
    data_rows = rows[1:]
    for row_number, row in data_rows:
        name = row.get("B") or row.get("C") or ""
        road_address = row.get("D") or None
        lot_address = row.get("E") or None
        address = road_address or lot_address or ""
        if row_number in error_cells and (not name or not address):
            excluded_invalid_rows.append(row_number)
            continue
        if not name and not address:
            excluded_rows.append(row_number)
            continue
        if not name or not address:
            raise DirectoryImportError(f"Row {row_number} is missing a name or address.")
        if "\0" in name or "\0" in address:
            raise DirectoryImportError(f"Row {row_number} contains an invalid identity separator.")
        key = (identity_text(name), identity_text(address))
        aliases = [row["C"]] if row.get("C") and identity_text(row["C"]) != key[0] else []
        if key in entries:
            duplicate_rows += 1
            entry = entries[key]
            known_aliases = {identity_text(alias) for alias in entry["aliases"]}
            entry["aliases"].extend(alias for alias in aliases if identity_text(alias) not in known_aliases)
            if entry["lotAddress"] is None and lot_address is not None:
                entry["lotAddress"] = lot_address
            original_rows[key].append(row_number)
            continue
        identifier = place_id(key)
        if identifier in ids and ids[identifier] != key:
            raise DirectoryImportError(f"Directory ID collision: {identifier}.")
        ids[identifier] = key
        parts = address.split()
        entries[key] = {
            "id": identifier,
            "name": name,
            "aliases": aliases,
            "roadAddress": road_address,
            "lotAddress": lot_address,
            "address": address,
            "region": parts[0],
            "district": parts[1] if len(parts) > 1 else None,
        }
        original_rows[key] = [row_number]

    metadata = {
        "label": source_label,
        "fileName": source.name,
        "sha256": hashlib.sha256(source_bytes).hexdigest(),
        "sourceUrl": None,
        "verifiedAt": None,
        "sourceDataDate": None,
        "inputRows": len(data_rows),
        "excludedEmptyRows": len(excluded_rows),
        "excludedInvalidRows": len(excluded_invalid_rows),
        "deduplicatedRows": duplicate_rows,
    }
    if provenance is not None:
        metadata["provenance"] = dict(provenance)
    gyms = list(entries.values())
    catalog = {"schemaVersion": 1, "source": metadata, "gyms": gyms}
    audit = {
        "schemaVersion": 1,
        "source": metadata,
        "sheetName": sheet_name,
        "headers": list(EXPECTED_HEADERS),
        "outputEntries": len(gyms),
        "excludedWorksheetRows": excluded_rows,
        "excludedInvalidWorksheetRows": excluded_invalid_rows,
        "excelErrorCells": [reference for references in error_cells.values() for reference in references],
        "duplicateWorksheetRows": [row_numbers for row_numbers in original_rows.values() if len(row_numbers) > 1],
        "fieldPopulation": {column: sum(bool(row.get(column)) for _, row in data_rows) for column in "ABCDEFG"},
        "regionCounts": dict(Counter(entry["region"] for entry in gyms)),
        "qualityFlags": address_quality_flags(data_rows, gyms),
        "omittedFields": ["전화번호", "전화번호 2"],
        "limitations": [
            "원본 다운로드 URL과 이용 조건은 이 파일에서 확인되지 않습니다.",
            "자료 기준일과 현재 영업 여부를 확인할 수 없습니다.",
            "원본의 '(검증)' 헤더는 앱의 사업주 인증을 뜻하지 않습니다.",
            "좌표가 없어 거리 또는 지도상 위치를 추정하지 않았습니다.",
            "행정구역과 업체 종류는 원본 값을 보존했으며 별도 검증하지 않았습니다.",
        ],
    }
    return catalog, audit


def catalog_bytes(catalog: dict[str, Any]) -> bytes:
    return (json.dumps(catalog, ensure_ascii=False, separators=(",", ":")) + "\n").encode("utf-8")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--output", type=Path, default=REPO_ROOT / "assets/gym_directory/gyms.json")
    parser.add_argument("--audit-output", type=Path, default=REPO_ROOT / "artifacts/gym-directory/audit.json")
    parser.add_argument("--source-label", default="제공된 헬스장 목록")
    parser.add_argument("--provider-reviewed-names", action="store_true", help="Attach user-confirmed B-name/C-alias provenance.")
    parser.add_argument("--name-provider", help="Provider of the reviewed B-column names.")
    parser.add_argument("--base-source", help="User-confirmed base data source.")
    parser.add_argument("--reference-url", help="General source reference; does not replace the exact sourceUrl.")
    arguments = parser.parse_args()
    paths = [arguments.source.resolve(), arguments.output.resolve(), arguments.audit_output.resolve()]
    if len(set(paths)) != len(paths):
        parser.error("Source, output and audit output must be different paths.")
    if arguments.provider_reviewed_names and (not arguments.name_provider or not arguments.base_source):
        parser.error("--provider-reviewed-names requires --name-provider and --base-source.")
    if not arguments.provider_reviewed_names and any((arguments.name_provider, arguments.base_source, arguments.reference_url)):
        parser.error("Provenance fields require --provider-reviewed-names.")
    try:
        provenance = reviewed_names_provenance(arguments.name_provider, arguments.base_source, arguments.reference_url) if arguments.provider_reviewed_names else None
        catalog, audit = build_catalog(arguments.source, source_label=arguments.source_label, provenance=provenance)
        arguments.output.parent.mkdir(parents=True, exist_ok=True)
        arguments.audit_output.parent.mkdir(parents=True, exist_ok=True)
        arguments.output.write_bytes(catalog_bytes(catalog))
        arguments.audit_output.write_text(json.dumps(audit, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    except (OSError, DirectoryImportError) as error:
        parser.exit(1, f"Gym directory import failed: {error}\n")
    print(f"Exported {len(catalog['gyms'])} gym entries; source SHA-256 {catalog['source']['sha256']}.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
