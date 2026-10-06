"""Contract and source-integrity checks for the read-only directory importer."""

import hashlib
import tempfile
import unittest
import zipfile
from pathlib import Path
from unittest.mock import patch
from xml.etree import ElementTree as ET

import import_gym_directory as importer


def fixture(path, data_rows, *, headers=importer.EXPECTED_HEADERS, cell_override=None):
    namespace = importer.SPREADSHEET_NS
    worksheet = ET.Element(f"{{{namespace}}}worksheet")
    data = ET.SubElement(worksheet, f"{{{namespace}}}sheetData")
    for number, values in enumerate([headers, *data_rows], 1):
        row = ET.SubElement(data, f"{{{namespace}}}row", r=str(number))
        for column, value in zip("ABCDEFG", values):
            cell = ET.SubElement(row, f"{{{namespace}}}c", r=f"{column}{number}", t="inlineStr")
            inline = ET.SubElement(cell, f"{{{namespace}}}is")
            ET.SubElement(inline, f"{{{namespace}}}t").text = value
            if cell_override:
                cell_override(cell, column, number)
    workbook = (
        f'<workbook xmlns="{namespace}" xmlns:r="{importer.RELATIONSHIP_NS}">'
        '<sheets><sheet name="Fixture" sheetId="1" r:id="rId1"/></sheets></workbook>'
    )
    relations = '<Relationships><Relationship Id="rId1" Target="worksheets/sheet1.xml"/></Relationships>'
    with zipfile.ZipFile(path, "w") as archive:
        archive.writestr("xl/workbook.xml", workbook)
        archive.writestr("xl/_rels/workbook.xml.rels", relations)
        archive.writestr("xl/worksheets/sheet1.xml", ET.tostring(worksheet))


class ImportGymDirectoryTest(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.source = Path(self.directory.name) / "fixture.xlsx"

    def test_dedup_aliases_normalization_privacy_and_source_integrity(self):
        fixture(self.source, [
            ("1", "  Cafe\u0301   Gym ", "Legacy Gym", " City   District 10 ", "Old 10", "010-1111-2222", "Owner Phone"),
            ("2", "Café Gym", "New Alias", "City District 10", "Old 10", "010-3333-4444", ""),
            ("3", "", "Another Gym", "", "City District 11", "02-1234-5678", ""),
            ("4", "", "", "", "", "", ""),
        ])
        before = self.source.read_bytes()
        catalog, audit = importer.build_catalog(self.source)
        self.assertEqual(self.source.read_bytes(), before)
        self.assertEqual(catalog["source"]["sha256"], hashlib.sha256(before).hexdigest())
        self.assertEqual(catalog["source"]["inputRows"], 4)
        self.assertEqual(catalog["source"]["excludedEmptyRows"], 1)
        self.assertEqual(catalog["source"]["deduplicatedRows"], 1)
        self.assertEqual(len(catalog["gyms"]), 2)
        first, fallback = catalog["gyms"]
        self.assertEqual(first["name"], "Café Gym")
        self.assertEqual(first["aliases"], ["Legacy Gym", "New Alias"])
        self.assertEqual(first["address"], "City District 10")
        self.assertEqual(first["region"], "City")
        self.assertEqual(first["district"], "District")
        self.assertIsNone(fallback["roadAddress"])
        self.assertEqual(fallback["address"], "City District 11")
        self.assertEqual(audit["duplicateWorksheetRows"], [[2, 3]])
        for field in ("sourceUrl", "verifiedAt", "sourceDataDate"):
            self.assertIsNone(catalog["source"][field])
        output = importer.catalog_bytes(catalog)
        for omitted in (b"010-1111-2222", b"010-3333-4444", b"02-1234-5678", b"Owner Phone"):
            self.assertNotIn(omitted, output)
        self.assertEqual(set(first), {"id", "name", "aliases", "roadAddress", "lotAddress", "address", "region", "district"})

    def test_output_is_deterministic_and_preserves_distinct_addresses(self):
        fixture(self.source, [
            ("1", "Same Gym", "", "City District 10", "", "", ""),
            ("2", "Same Gym", "", "City District 11", "", "", ""),
        ])
        first, _ = importer.build_catalog(self.source)
        second, _ = importer.build_catalog(self.source)
        self.assertEqual(importer.catalog_bytes(first), importer.catalog_bytes(second))
        self.assertEqual(len({gym["id"] for gym in first["gyms"]}), 2)
        expected = hashlib.sha256(b"same gym\0city district 10").hexdigest()[:24]
        self.assertEqual(first["gyms"][0]["id"], "place-" + expected)

    def test_wrong_headers_fail(self):
        fixture(self.source, [], headers=("Name", "Address"))
        with self.assertRaisesRegex(importer.DirectoryImportError, "headers"):
            importer.build_catalog(self.source)

    def test_name_or_address_missing_fails(self):
        for row in [
            ("1", "Gym", "", "", "", "", ""),
            ("1", "", "", "City District 10", "", "", ""),
        ]:
            with self.subTest(row=row):
                fixture(self.source, [row])
                with self.assertRaisesRegex(importer.DirectoryImportError, "missing a name or address"):
                    importer.build_catalog(self.source)

    def test_invalid_workbook_and_formula_fail(self):
        self.source.write_bytes(b"not a workbook")
        with self.assertRaisesRegex(importer.DirectoryImportError, "Invalid source workbook"):
            importer.build_catalog(self.source)

        def add_formula(cell, column, number):
            if column == "B" and number == 2:
                ET.SubElement(cell, f"{{{importer.SPREADSHEET_NS}}}f").text = "1+1"

        fixture(self.source, [("1", "Gym", "", "City District 10", "", "", "")], cell_override=add_formula)
        with self.assertRaisesRegex(importer.DirectoryImportError, "Formula"):
            importer.build_catalog(self.source)

    def test_id_collisions_fail(self):
        fixture(self.source, [
            ("1", "First Gym", "", "City District 10", "", "", ""),
            ("2", "Second Gym", "", "City District 11", "", "", ""),
        ])
        with patch.object(importer, "place_id", return_value="place-collision"):
            with self.assertRaisesRegex(importer.DirectoryImportError, "ID collision"):
                importer.build_catalog(self.source)

    def test_excel_error_name_is_excluded_without_guessing_a_name(self):
        def error_names(cell, column, number):
            if number == 2 and column in "BC":
                cell.clear()
                cell.set("r", f"{column}{number}")
                cell.set("t", "e")
                ET.SubElement(cell, f"{{{importer.SPREADSHEET_NS}}}v").text = "#NAME?"

        fixture(self.source, [
            ("1", "Invalid", "Invalid", "City District 10", "", "", ""),
            ("2", "Valid Gym", "", "City District 11", "", "", ""),
        ], cell_override=error_names)
        catalog, audit = importer.build_catalog(self.source)
        self.assertEqual(len(catalog["gyms"]), 1)
        self.assertEqual(catalog["gyms"][0]["name"], "Valid Gym")
        self.assertEqual(catalog["source"]["excludedInvalidRows"], 1)
        self.assertEqual(audit["excludedInvalidWorksheetRows"], [2])
        self.assertEqual(audit["excelErrorCells"], ["B2", "C2"])
        self.assertNotIn(b"#NAME?", importer.catalog_bytes(catalog))

    def test_user_confirmed_provenance_keeps_exact_source_and_dates_unknown(self):
        fixture(self.source, [("1", "Reviewed Gym", "Registered Gym", "City District 10", "", "", "")])
        provenance = importer.reviewed_names_provenance(
            "김건우", "행정안전부 체력단련장업 인허가 자료", "https://www.data.go.kr/data/15155077/openapi.do"
        )
        catalog, audit = importer.build_catalog(
            self.source, source_label="행안부 인허가 자료 · 제공자 보완", provenance=provenance
        )
        self.assertEqual(catalog["source"]["label"], "행안부 인허가 자료 · 제공자 보완")
        self.assertEqual(catalog["source"]["provenance"]["nameReview"], "김건우 제공자 확인 이름 우선")
        self.assertTrue(catalog["source"]["provenance"]["confirmedByUser"])
        self.assertEqual(catalog["gyms"][0]["name"], "Reviewed Gym")
        self.assertEqual(catalog["gyms"][0]["aliases"], ["Registered Gym"])
        self.assertEqual(audit["source"], catalog["source"])
        for field in ("sourceUrl", "verifiedAt", "sourceDataDate"):
            self.assertIsNone(catalog["source"][field])
        generic, _ = importer.build_catalog(self.source)
        self.assertNotIn("provenance", generic["source"])
        with self.assertRaisesRegex(importer.DirectoryImportError, "source label"):
            importer.build_catalog(self.source, source_label=" ")

    def test_quality_flags_count_source_literals_without_rewriting_addresses(self):
        addresses = ["전남광주통합특별시 목포시 Road 1", "경기 용인시 Road 2", "인천광역시 검단구 Road 3", "경기도 용인시 Road 4"]
        fixture(self.source, [(str(index), "Gym " + str(index), "", address, "", "", "") for index, address in enumerate(addresses, 1)])
        catalog, audit = importer.build_catalog(self.source)
        self.assertEqual([gym["address"] for gym in catalog["gyms"]], addresses)
        self.assertEqual([flag["inputRows"] for flag in audit["qualityFlags"]], [1, 1, 1])
        self.assertEqual([flag["sourceLiteral"] for flag in audit["qualityFlags"]], ["전남광주통합특별시", "경기", "인천광역시 검단구"])


if __name__ == "__main__":
    unittest.main()
