import json
import tempfile
import unittest
from pathlib import Path

from collect_review_evidence import verified_entry
from export_media import sha256


class ReviewEvidenceTests(unittest.TestCase):
    def fixture(self, root):
        names = ("exercise.mp4", "exercise.gif", "pose-start.png", "pose-middle.png", "pose-peak.png", "exercise.blend")
        records = {}
        for name in names:
            path = root / name
            path.write_bytes(("reviewed " + name).encode())
            records[name] = {"path": name, "sha256": sha256(path)}
        report = root / "review.json"
        report.write_text("{}")
        return {"exerciseId": "exact_id", "trainerApproved": False, "humanTrainerApproval": False,
                "decodedFrameCount": 96, "mainPoseImagesActuallyOpened": list(names[2:5]),
                "mediaFilesAtReview": records, "findings": []}, report

    def test_replacement_native_requires_new_inspection_even_if_export_is_updated(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            row, report = self.fixture(root)
            self.assertEqual(verified_entry(row, report, root)["exerciseId"], "exact_id")
            (root / "exercise.blend").write_bytes(b"corrected but not reviewed")
            with self.assertRaisesRegex(ValueError, "Reviewed file changed"):
                verified_entry(row, report, root)

    def test_unresolved_support_defect_cannot_be_marked_checked(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            row, report = self.fixture(root)
            row["findings"] = [{"severity": "medium", "code": "support_elbow_overflexion"}]
            with self.assertRaisesRegex(ValueError, "Unresolved geometric finding"):
                verified_entry(row, report, root)

    def test_reference_scope_stays_visible_and_pending_without_claiming_approval(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            row, report = self.fixture(root)
            finding = {"severity": "medium", "code": "reference_variant_scope",
                       "detail": "Standing setup needs trainer assessment; cited setup is seated"}
            row["findings"] = [finding]
            result = verified_entry(row, report, root)
            self.assertEqual(result["findings"], [finding])
            self.assertEqual(result["sourceReviewQuestions"], [finding])
            self.assertFalse(result["trainerApproved"])

    def test_prepared_video_frames_do_not_count_as_completed_visual_review(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            row, report = self.fixture(root)
            row.update(reviewComplete=False, visuallyInspectedDecodedFrames=[])
            with self.assertRaisesRegex(ValueError, "not all been visually inspected"):
                verified_entry(row, report, root)
            row.update(reviewComplete=True, visuallyInspectedDecodedFrames=list(range(1, 96)))
            with self.assertRaisesRegex(ValueError, "not all been visually inspected"):
                verified_entry(row, report, root)
            row['visuallyInspectedDecodedFrames'] = list(range(1, 97))
            self.assertEqual(verified_entry(row, report, root)['inspectedMP4Frames'], 96)


if __name__ == "__main__":
    unittest.main()
