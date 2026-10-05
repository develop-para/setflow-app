"""Counterexamples for complete equipment evidence, using authored audit rows.

Run after the isolated native authoring batch. These guards do not certify
human technique or replace viewing the rendered poses.
"""
import json
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import remaining_strength_extra_equipment as equipment

ARTIFACTS = Path(__file__).resolve().parents[2] / "artifacts/exercise_visuals/remaining-strength-authoring"
IDS = ("preacher_curl", "skull_crusher", "chest_supported_row", "back_extension",
       "decline_bench", "overhead_triceps_extension", "upright_row")


class SurfaceEvidenceTests(unittest.TestCase):
    def rows(self, exercise_id):
        path = ARTIFACTS / exercise_id / "equipment-surface-audit.json"
        return json.loads(path.read_text(encoding="utf-8"))

    def rejected(self, exercise_id, rows):
        result = equipment.validate_surfaces(exercise_id, rows)
        self.assertIs(result["passed"], False)
        self.assertTrue(result["failures"])
        self.assertIs(result["trainerApproved"], False)
        self.assertIs(result["humanTrainerApproval"], False)

    def test_all_seven_actual_native_surface_records(self):
        for exercise_id in IDS:
            with self.subTest(exercise_id=exercise_id):
                rows = self.rows(exercise_id)
                self.assertEqual(len(rows), 96)
                result = equipment.validate_surfaces(exercise_id, rows)
                self.assertIs(result["passed"], True, result["failures"])
                self.assertIs(result["trainerApproved"], False)

    def test_unknown_exact_id_and_absent_evidence(self):
        self.rejected("unknown_exercise", self.rows("upright_row"))
        self.rejected("upright_row", [])

    def test_one_ez_segment_removed_or_separated(self):
        rows = self.rows("preacher_curl")
        rows[0]["bent_shaft_segments"].pop()
        self.rejected("preacher_curl", rows)
        rows = self.rows("preacher_curl")
        rows[0]["bent_shaft_segments"][1]["actual_segment_start_world"][2] += .01
        self.rejected("preacher_curl", rows)

    def test_short_shaft_cannot_pass_using_large_sample_count(self):
        rows = self.rows("upright_row")
        shaft = rows[0]["actual_complete_straight_shaft"]
        shaft["actual_segment_end_world"] = list(shaft["actual_segment_start_world"])
        shaft["actual_segment_end_world"][0] += .05
        shaft["sample_count"] = 1000
        self.rejected("upright_row", rows)

    def test_missing_pad_or_ankle_anchor_is_not_contact(self):
        rows = self.rows("back_extension")
        rows[0]["padding"].pop()
        self.rejected("back_extension", rows)
        rows = self.rows("decline_bench")
        rows[0]["ankle_rollers"].pop()
        self.rejected("decline_bench", rows)

    def test_decline_chest_gap_and_plate_intrusion_remain_failures(self):
        rows = self.rows("decline_bench")
        peak = max(rows, key=lambda row: row["amount"])
        peak["central_torso_endpoint_gap_m"] = .04
        self.rejected("decline_bench", rows)
        rows = self.rows("chest_supported_row")
        rows[0]["moving_weight_mesh_min_nonhand_clearance_m"] = -.02
        self.rejected("chest_supported_row", rows)

    def test_nonfinite_or_missing_clearance_cannot_pass(self):
        for field in ("actual_radius_m", "minimum_nonhand_skin_clearance_m"):
            rows = self.rows("upright_row")
            rows[0]["actual_complete_straight_shaft"][field] = float("nan")
            self.rejected("upright_row", rows)
        rows = self.rows("overhead_triceps_extension")
        rows[0]["moving_weight_mesh_min_nonhand_clearance_m"] = None
        self.rejected("overhead_triceps_extension", rows)

    def test_repeated_frames_and_floating_support_are_rejected(self):
        rows = self.rows("skull_crusher")
        rows[1]["frame"] = rows[0]["frame"]
        self.rejected("skull_crusher", rows)
        rows = self.rows("preacher_curl")
        rows[0]["padding"][0]["domain_surface_gap_m"] = .05
        self.rejected("preacher_curl", rows)


if __name__ == "__main__":
    unittest.main()
