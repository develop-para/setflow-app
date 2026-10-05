"""Regressions for retaining the exact native, guard and authoring revision."""

import json
import tempfile
import unittest
import zipfile
from pathlib import Path
from unittest.mock import patch

import package_trainer_review as packager
from export_media import sha256


class PackageTrainerReviewTests(unittest.TestCase):
    def fixture(self, root):
        visuals = root / "output/exercise_visuals"

        def write(relative, value):
            path = root / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(value if isinstance(value, bytes) else value.encode())
            return path

        for relative in ("tool/exercise_visuals/build_trainer_review.py", "lib/data/exercise_guides.dart",
                         "lib/data/exercise_visuals.dart", "docs/exercise-guides.md",
                         "docs/exercise-visual-production.md", "output/exercise_visuals/catalog.json",
                         "output/exercise_visuals/production/specifications.json",
                         "output/exercise_visuals/bodyweight_squat/v5/source-manifest.json",
                         "output/exercise_visuals/bodyweight_squat/v5/README.md"):
            write(relative, "{}")
        directory = visuals / "chest_press/v1"

        def visual_record(filename, content):
            path = write("output/exercise_visuals/chest_press/v1/" + filename, content)
            return {"path": path.relative_to(visuals).as_posix(), "sha256": sha256(path)}

        video = visual_record("exercise.mp4", b"exact reviewed video")
        native = visual_record("exercise.blend", b"exact reviewed native")
        guard = visual_record("equipment-surface-audit.json", '{"frame":96,"gap_m":0.001}')
        metadata = visual_record("metadata.json", '{"exerciseId":"chest_press"}')
        report = write("artifacts/exercise_visuals/independent-review.json", '{"trainerApproved":false}')
        signature = "a" * 64
        state = visual_record("production-state.json", json.dumps({"fingerprint": signature}))
        snapshot_directory = "output/exercise_visuals/production/source-snapshots/" + signature
        frozen_source = write(snapshot_directory + "/machine_motions.py", "# original reviewed revision\n")
        body = write("output/exercise_visuals/bodyweight_squat/v5/squat.blend", b"CC0 rig")
        snapshot = {"exerciseId": "chest_press", "renderSourceFingerprint": signature,
                    "sourceFiles": {"tool/exercise_visuals/machine_motions.py": {
                        "snapshotPath": frozen_source.relative_to(root).as_posix(), "sha256": sha256(frozen_source)}},
                    "sharedBodyInputs": {body.relative_to(root).as_posix(): sha256(body)}}
        snapshot_path = write(snapshot_directory + "/source-manifest.json", json.dumps(snapshot))
        # An unlicensed local reference download must never enter by directory glob.
        write("artifacts/exercise_visuals/primary-manuals/manufacturer.pdf", b"reference only")
        pinned = {key: {**record, "path": "output/exercise_visuals/" + record["path"]}
                  for key, record in {"exercise.mp4": video, "exercise.blend": native,
                                      "equipment-surface-audit.json": guard, "metadata.json": metadata}.items()}
        row = {"exerciseId": "chest_press", "trainerApproved": False,
               "media": {"directory": "chest_press/v1", "reviewEligible": True,
                         "files": {"exercise.mp4": video}, "native": native},
               "qaFiles": {"production-state.json": state},
               "independentReview": {"reviewReport": report.relative_to(root).as_posix(),
                                     "reviewReportSha256": sha256(report), "mediaFilesAtReview": pinned}}
        data = {"sourceGuideSnapshotCurrent": True, "invalidExports": [], "exercises": [row],
                "counts": {"renderedDemos": 1, "trainerApproved": 0},
                "inputSha256": {"catalog": sha256(visuals / "catalog.json"),
                                "specifications": sha256(visuals / "production/specifications.json"),
                                "builder": sha256(root / "tool/exercise_visuals/build_trainer_review.py")}}
        page = write("output/exercise_visuals/trainer-review.html",
                     '<script type="application/json" id="review-data">' + json.dumps(data) + '</script>')
        return visuals, page, directory, frozen_source, snapshot_path

    def package(self, root, visuals, page):
        with patch.object(packager, "ROOT", root), patch.object(packager, "VISUALS", visuals), \
                patch.object(packager, "registrations", return_value={}):
            return packager.package(page, root / "review.zip")

    def test_exact_independent_guard_metadata_report_and_frozen_source_are_included(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            visuals, page, _, frozen, _ = self.fixture(root)
            self.package(root, visuals, page)
            with zipfile.ZipFile(root / "review.zip") as archive:
                for name in ("chest_press/v1/equipment-surface-audit.json", "chest_press/v1/metadata.json",
                             "source/artifacts/exercise_visuals/independent-review.json",
                             frozen.relative_to(visuals).as_posix()):
                    self.assertIn(name, archive.namelist())
                self.assertEqual(archive.read(frozen.relative_to(visuals).as_posix()), frozen.read_bytes())
                self.assertFalse(any(name.endswith(".pdf") for name in archive.namelist()))
                self.assertFalse(json.loads(archive.read("bundle-manifest.json"))["trainerApproved"])

    def test_changed_actual_guard_fails_instead_of_packaging_stale_inspection(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            visuals, page, directory, _, _ = self.fixture(root)
            (directory / "equipment-surface-audit.json").write_text('{"changed":true}')
            with self.assertRaisesRegex(ValueError, "Independent review guard file missing or changed"):
                self.package(root, visuals, page)
            self.assertFalse((root / "review.zip").exists())

    def test_changed_independent_report_fails_even_without_explicit_evidence_argument(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            visuals, page, _, _, _ = self.fixture(root)
            (root / "artifacts/exercise_visuals/independent-review.json").write_text('{"changed":true}')
            with self.assertRaisesRegex(ValueError, "Independent review report missing or changed"):
                self.package(root, visuals, page)

    def test_frozen_source_hash_drift_cannot_be_replaced_by_current_source(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            visuals, page, _, frozen, _ = self.fixture(root)
            frozen.write_text("# later authoring revision\n")
            with self.assertRaisesRegex(ValueError, "Frozen authoring source changed or missing"):
                self.package(root, visuals, page)

    def test_source_snapshot_for_another_exercise_cannot_match_by_fingerprint_only(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            visuals, page, _, _, snapshot = self.fixture(root)
            manifest = json.loads(snapshot.read_text())
            manifest["exerciseId"] = "pec_deck"
            snapshot.write_text(json.dumps(manifest))
            with self.assertRaisesRegex(ValueError, "Authoring snapshot does not match"):
                self.package(root, visuals, page)


if __name__ == "__main__":
    unittest.main()
