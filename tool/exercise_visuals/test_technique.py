"""Regression tests for independent row checks, without Blender imports."""
import json
import math
import unittest
from pathlib import Path

import technique


def bone(head, tail):
    return {"head": list(head), "tail": list(tail)}


def valid_row_audit():
    """Small fixed skeleton with straight starts, neutral wrists and a hinge."""
    rows = []
    for frame, amount in ((1, 0.0), (24, 1.0), (48, 0.0)):
        bones = {}
        for index, name in enumerate(("pelvis", "spine_01", "spine_02", "spine_03", "neck_01", "head")):
            z = 0.9 + index * 0.06
            bones[name] = bone((0, -index * 0.075, z), (0, -index * 0.075 - 0.03, z + 0.02))
        for side, label in ((1, "l"), (-1, "r")):
            x = side * 0.1
            hip = (x, 0, 0.9)
            knee = (x, -0.4 * math.sin(math.radians(12.5)), 0.9 - 0.4 * math.cos(math.radians(12.5)))
            ankle = (x, 0, 0.9 - 0.8 * math.cos(math.radians(12.5)))
            bones["thigh_" + label] = bone(hip, knee)
            bones["calf_" + label] = bone(knee, ankle)
            x = side * 0.25
            shoulder = (x, -0.45, 1.10)
            elbow = (x, -0.45 + 0.25 * amount, 1.10 - 0.25 * (1 - amount))
            wrist = (x, elbow[1], elbow[2] - 0.25)
            knuckle = (x, wrist[1], wrist[2] - 0.10)
            bones["upperarm_" + label] = bone(shoulder, elbow)
            bones["lowerarm_" + label] = bone(elbow, wrist)
            bones["hand_" + label] = bone(wrist, knuckle)
            bones["middle_01_" + label] = bone(knuckle, (x, knuckle[1], knuckle[2] - 0.03))
        rows.append({"frame": frame, "amount": amount, "bones": bones})
    return rows


class RowTechniqueTests(unittest.TestCase):
    def test_forward_cycle_keeps_actual_world_translation_and_periodic_limbs(self):
        rows = valid_row_audit()
        translation = (0, -1.2, 0)
        for index, row in enumerate(rows):
            progress = [part * index / (len(rows) - 1) for part in translation]
            row["root_motion_cycle_translation_m"] = list(translation)
            row["root_motion_translation_m"] = progress
            for record in row["bones"].values():
                for point in ("head", "tail"):
                    record[point] = [part + offset for part, offset in zip(record[point], progress)]
        delta, recorded = technique.native_loop_delta(rows)
        self.assertLess(delta, 1e-10)
        self.assertEqual(recorded, translation)
        rows[-1]["bones"]["hand_r"]["tail"][2] += .02
        self.assertAlmostEqual(technique.native_loop_delta(rows)[0], .02)

    def test_forward_cycle_cannot_hide_missing_or_changed_root_progress(self):
        rows = valid_row_audit()
        for row in rows:
            row["root_motion_cycle_translation_m"] = [0, -1.2, 0]
        with self.assertRaisesRegex(ValueError, "recorded progress"):
            technique.native_loop_delta(rows)
        for row in rows:
            row["root_motion_translation_m"] = [0, 0, 0]
        with self.assertRaisesRegex(ValueError, "endpoints"):
            technique.native_loop_delta(rows)
        rows[-1]["root_motion_cycle_translation_m"] = [0, -1.1, 0]
        with self.assertRaisesRegex(ValueError, "changes"):
            technique.native_loop_delta(rows)

    def test_stationary_loop_rejects_nonfinite_bone_coordinates(self):
        rows = valid_row_audit()
        self.assertEqual(technique.native_loop_delta(rows), (0, (0, 0, 0)))
        rows[-1]["bones"]["hand_r"]["tail"][2] = float("nan")
        with self.assertRaisesRegex(ValueError, "Nonfinite"):
            technique.native_loop_delta(rows)

    def test_detached_elbow_with_unchanged_bone_length_is_detected(self):
        audit=valid_row_audit()
        for row in audit:
            for label in ("l","r"):
                ankle=row["bones"]["calf_"+label]["tail"]
                row["bones"]["foot_"+label]=bone(ankle,(ankle[0],ankle[1]-.15,ankle[2]))
        self.assertLess(technique.connected_joint_gap(audit),1e-10)
        lower=audit[1]["bones"]["lowerarm_l"]
        for part in ("head","tail"):lower[part][0]+=.10
        self.assertAlmostEqual(technique.length(technique.subtract(lower["tail"],lower["head"])),.25)
        self.assertAlmostEqual(technique.connected_joint_gap(audit),.10)

    def test_independent_valid_geometry_passes(self):
        result = technique.validate_row(valid_row_audit())
        self.assertTrue(result["passed"])
        self.assertAlmostEqual(result["metrics"]["knee_min_bend_deg"], 25.0)

    def test_recorded_v1_row_is_rejected(self):
        fixture = json.loads((Path(__file__).parent / "fixtures/row_v1_invalid.json").read_text(encoding="utf-8"))
        report = technique.validate_row(fixture["audit"], raise_on_failure=False)
        self.assertFalse(report["passed"])
        self.assertGreater(report["metrics"]["wrist_axis_max_deviation_deg"], 40)
        self.assertGreater(report["metrics"]["start_elbow_max_bend_deg"], 60)
        self.assertGreater(report["metrics"]["knee_min_bend_deg"], 50)
        self.assertGreaterEqual(len(report["failures"]), 4)

    def test_bent_wrist_is_rejected(self):
        audit = valid_row_audit()
        wrist = audit[1]["bones"]["hand_l"]["head"]
        audit[1]["bones"]["middle_01_l"]["head"] = [wrist[0] + 0.10, wrist[1], wrist[2]]
        report = technique.validate_row(audit, raise_on_failure=False)
        self.assertIn("Wrist bends more than five degrees from the forearm", report["failures"])

    def test_flexed_start_is_rejected(self):
        audit = valid_row_audit()
        elbow = audit[0]["bones"]["lowerarm_l"]["head"]
        endpoint = [elbow[0], elbow[1] - 0.15, elbow[2] - 0.20]
        audit[0]["bones"]["lowerarm_l"]["tail"] = endpoint
        audit[0]["bones"]["hand_l"]["head"] = endpoint
        audit[0]["bones"]["middle_01_l"]["head"] = [endpoint[0], endpoint[1] - 0.06, endpoint[2] - 0.08]
        report = technique.validate_row(audit, raise_on_failure=False)
        self.assertIn("Lowered row starts with flexed elbows", report["failures"])

    def test_knee_movement_is_rejected(self):
        audit = valid_row_audit()
        audit[1]["bones"]["calf_l"]["tail"][1] += 0.08
        report = technique.validate_row(audit, raise_on_failure=False)
        self.assertIn("Knees change angle during the pull", report["failures"])

    def test_trunk_swing_is_rejected(self):
        audit = valid_row_audit()
        audit[1]["bones"]["head"]["head"][2] += 0.01
        report = technique.validate_row(audit, raise_on_failure=False)
        self.assertIn("Trunk or head moves to throw the weight", report["failures"])

    def test_actual_shaft_collision_is_rejected(self):
        sample = {"frame": 24, "amount": 1, "central_shaft_min_surface_clearance_m": -0.004}
        report = technique.validate_row(valid_row_audit(), [sample], raise_on_failure=False)
        self.assertIn("Actual bar shaft intersects the skinned torso surface", report["failures"])
        with self.assertRaisesRegex(ValueError, "skinned torso"):
            technique.validate_row(valid_row_audit(), [sample])

    def test_peak_target_missing_abdomen_is_rejected(self):
        sample = {"frame": 24, "amount": 1, "central_shaft_min_surface_clearance_m": 0.12,
                  "abdominal_landmark_distance_m": 0.18}
        report = technique.validate_row(valid_row_audit(), [sample], raise_on_failure=False)
        self.assertIn("Peak bar position misses the abdominal target region", report["failures"])

    def test_underhand_grip_is_rejected(self):
        sample = {"frame": 24, "amount": 1, "central_shaft_min_surface_clearance_m": 0.02,
                  "overhand_palmar_alignment_min": -1.0}
        report = technique.validate_row(valid_row_audit(), [sample], raise_on_failure=False)
        self.assertIn("Actual palm orientation does not match the overhand row grip", report["failures"])

    def test_intentional_hand_contact_uses_unsigned_other_body_proximity(self):
        self.assertAlmostEqual(technique.shaft_clearance(0.12, -0.004, True), 0.104)

    def test_torso_penetration_still_uses_complete_mesh_sign(self):
        self.assertAlmostEqual(technique.shaft_clearance(0.04, -0.04, False), -0.056)

    def test_hand_contact_does_not_hide_other_skin_touching_shaft(self):
        self.assertLess(technique.shaft_clearance(0.006, -0.004, True), 0)


if __name__ == "__main__":
    unittest.main()
