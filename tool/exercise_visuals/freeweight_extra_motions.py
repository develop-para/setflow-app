"""Three exact bench-supported variants, authored for the CC0 native athlete.

Official pages supply technique cues only. Geometry below belongs to Setflow;
values describe this model and remain pending the user's trainer review.
This module does not register any IDs or modify established render sources.
"""
import math

SUPPORTED = ("arnold_press", "one_arm_dumbbell_row", "close_grip_bench")
REGIONS = {"arnold_press": ("deltoids", "triceps"),
           "one_arm_dumbbell_row": ("lats", "upper_back", "biceps"),
           "close_grip_bench": ("triceps", "chest", "deltoids")}
FIXED_CONTACTS = {"arnold_press": ("pelvis", "foot_l", "foot_r"),
                  "one_arm_dumbbell_row": ("pelvis", "hand_l", "calf_l", "foot_r"),
                  "close_grip_bench": ("pelvis", "foot_l", "foot_r")}
VIEWS = {
    "arnold_press": {"target": (0, -.03, .99), "location": (4.3, -3.6, 2.0), "ortho_scale": 2.65},
    "one_arm_dumbbell_row": {"target": (0, .12, .59), "location": (-4.3, -3.0, 1.8), "ortho_scale": 2.05},
    "close_grip_bench": {"target": (0, .35, .65), "location": (4.3, -3.0, 2.2), "ortho_scale": 2.75},
}
REFERENCES = {
    "arnold_press": {
        "references": ["https://www.acefitness.org/resources/pros/expert-articles/6467/fast-and-efficient-upper-body-training/"],
        "source_id": "Arnold_Dumbbell_Press", "variant": "Seated bilateral dumbbell Arnold press with backrest",
        "source_scope": "ACE describes arm/palm rotation and overhead press. Seated backrest setup follows the exact pinned source and corrected local guide.",
        "cues": ["Start with elbows flexed and palms toward body", "Rotate arms outward as weights rise", "Finish overhead with palms forward", "Reverse the same path", "Stable supported torso"],
    },
    "one_arm_dumbbell_row": {
        "references": ["https://www.acefitness.org/resources/everyone/exercise-library/126/single-arm-row/"],
        "source_id": "One-Arm_Dumbbell_Row", "variant": "Right-hand dumbbell row, left palm and left knee on bench, right foot on floor",
        "cues": ["Support hand below shoulder and knee below hip", "Flat stable back and aligned head", "Arm extends toward floor", "Pull elbow backward close to ribs", "No torso rotation"],
    },
    "close_grip_bench": {
        "references": ["https://www.acefitness.org/resources/everyone/exercise-library/311/close-grip-bench-press/"],
        "source_id": "Close-Grip_Barbell_Bench_Press", "variant": "Flat barbell bench press with hands in line with shoulders",
        "model_support": "Setflow's own generic 27 cm wide horizontal bench clears the enlarged upper-arm skin at the fully lowered bar. A small original head bolster fits the enlarged upper-back sculpt while preserving the neutral native head/neck pose. Neither width nor bolster is an ACE or manufacturer prescription. The measured pelvis-domain skin remains 7.9 mm above the main cushion: pressure and briefs/cloth contact are not simulated, and this measurement does not establish literal loaded skin contact.",
        "model_range": "This sculpt's shoulder-line grip lowers the shaft to about 2.43 mm from evaluated nonhand skin with 146.52 degrees of elbow flexion. These values describe the authored fit only, not universal ROM or an expert-approved angle.",
        "cues": ["Feet planted and hips on bench", "Hands at shoulder line", "Elbows toward feet and close to ribs", "Lower toward chest", "Controlled press"],
    },
}
for _reference in REFERENCES.values():
    _reference.update({"checked_date": "2026-10-06", "review_status": "trainer_pending",
                       "values_are_not_universal_prescriptions": True, "motion_capture": False})


def _api():
    import motions
    from mathutils import Quaternion, Vector
    return motions, Quaternion, Vector


def _arm_fk(rig, label, upper, lower, normal):
    m, _, V = _api()
    rest = rig.data.bones
    shoulder = rig.pose.bones["upperarm_" + label].head.copy()
    upper, lower = V(upper).normalized(), V(lower).normalized()
    normal = (V(normal) - lower * V(normal).dot(lower)).normalized()
    elbow = shoulder + upper * rest["upperarm_" + label].length
    wrist = elbow + lower * rest["lowerarm_" + label].length
    m.point(rig, "upperarm_" + label, shoulder, elbow)
    m.pronated_forearm(rig, label, elbow, wrist, normal)
    return m.hand(rig, label, wrist, lower, normal, True)


def _leg_target(rig, label, ankle, pole, foot_rotation):
    m, _, V = _api()
    rest = rig.data.bones
    hip = rig.pose.bones["thigh_" + label].head.copy()
    knee, achieved = m.two_bone(hip, V(ankle), rest["thigh_" + label].length,
                               rest["calf_" + label].length, V(pole))
    if (achieved - V(ankle)).length > .0001:
        raise ValueError("Unreachable supported leg: " + label)
    m.point(rig, "thigh_" + label, hip, knee)
    m.point(rig, "calf_" + label, knee, achieved)
    m.bone_rotation(rig, "foot_" + label, achieved, foot_rotation)


def _arnold(rig, amount):
    m, Q, V = _api()
    rest = rig.data.bones
    m.torso(rig, V((0, .10, .48)), Q((1, 0, 0), 0))
    for side, label in ((1, "l"), (-1, "r")):
        _leg_target(rig, label, (side * .22, -.34, rest["foot_" + label].head_local.z),
                    (side * .22, -.8, .58), Q((1, 0, 0), 0))
    contacts = {"feet": "foot"}
    for side, label in ((1, "l"), (-1, "r")):
        upper = (side * (.10 + .95 * math.sin(math.pi * amount)), -.30 * (1 - amount), -.95 + 1.95 * amount)
        lower = (side * .04 * amount, -.60 * (1 - amount), .80 + .20 * amount)
        normal = (side * math.sin(math.pi * amount), math.cos(math.pi * amount), 0)
        contacts[label] = _arm_fk(rig, label, upper, lower, normal)
    return contacts


def _one_arm_row(rig, amount):
    m, Q, V = _api()
    rest = rig.data.bones
    offset = rest["upperarm_l"].head_local - m.hip_center(rig)
    wrist_z = .399
    shoulder_z = wrist_z + rest["upperarm_l"].length + rest["lowerarm_l"].length - .0002
    angle = math.atan2(offset.y, offset.z) + math.acos((shoulder_z - .83) / math.hypot(offset.y, offset.z))
    lean = Q((1, 0, 0), angle)
    m.torso(rig, V((0, .30, .83)), lean)
    # Supporting left thigh descends under the hip; calf rests behind it.
    hip = rig.pose.bones["thigh_l"].head.copy()
    knee = hip + V((0, 0, -rest["thigh_l"].length))
    ankle = knee + V((0, rest["calf_l"].length, 0))
    m.point(rig, "thigh_l", hip, knee)
    m.point(rig, "calf_l", knee, ankle)
    m.bone_rotation(rig, "foot_l", ankle, Q((1, 0, 0), math.radians(120)))
    _leg_target(rig, "r", (-.23, .38, rest["foot_r"].head_local.z), (-.23, -.3, .52), Q((1, 0, 0), 0))
    shoulder = rig.pose.bones["upperarm_l"].head.copy()
    contacts = {"l": m.arm(rig, "l", (shoulder.x, shoulder.y, wrist_z),
                          (shoulder.x + .15, shoulder.y + .08, .61), (0, -1, 0), (0, 0, -1))}
    m.floor_hand(rig, "l")
    # A fixed torso and a sagittal elbow path: the working upper arm moves
    # from downward to backward. The hand stays neutral, not wrist-curled.
    angle = math.radians(12 + 105 * amount)
    # The IFBB sculpt needs a small lateral allowance so the dumbbell's
    # plates clear the lat/hip surface; the elbow remains close to the ribs.
    upper = (-.24, math.sin(angle), -math.cos(angle))
    lower = (-.30, -.06 * amount, -1)
    contacts["r"] = _arm_fk(rig, "r", upper, lower, (1, 0, 0))
    contacts["row_knee"] = knee.copy()
    contacts["row_support_palm"] = contacts["l"]["palm"].copy()
    return contacts


def _close_grip(rig, amount):
    m, Q, V = _api()
    rest = rig.data.bones
    m.torso(rig, V((0, .33, .50)), Q((1, 0, 0), math.radians(-90)))
    for side, label in ((1, "l"), (-1, "r")):
        _leg_target(rig, label, (side * .29, -.30, rest["foot_" + label].head_local.z),
                    (side * .29, -1.5, .30), Q((1, 0, 0), 0))
    contacts = {"feet": "foot"}
    for side, label in ((1, "l"), (-1, "r")):
        shoulder = rig.pose.bones["upperarm_" + label].head.copy()
        grip_x = abs(shoulder.x)
        lower = rest["lowerarm_" + label].length + (rest["middle_01_" + label].head_local - rest["hand_" + label].head_local).length * .97
        reach = rest["upperarm_" + label].length + math.hypot(lower, .012) - .0002
        extension = math.sqrt(reach * reach - .07 ** 2)
        palm = (side * grip_x, shoulder.y - .07 - .10 * amount,
                # Evaluated chest/shaft clearance at the lower hold is
                # approximately 4 mm on this sculpt; do not stop 4 cm high.
                shoulder.z + extension * (1 - amount) + .132 * amount)
        contacts[label] = m.neutral_palm(rig, label, palm, (side * grip_x, shoulder.y - .5, shoulder.z - .3))
    return contacts


def pose(rig, exercise_id, amount):
    if exercise_id not in SUPPORTED:
        raise ValueError("No exact extra freeweight motion: " + exercise_id)
    if not 0 <= amount <= 1:
        raise ValueError("Motion amount must be between zero and one")
    _api()[0].reset(rig)
    if exercise_id == "arnold_press":
        return _arnold(rig, amount)
    if exercise_id == "one_arm_dumbbell_row":
        return _one_arm_row(rig, amount)
    return _close_grip(rig, amount)


def audit(rows, exercise_id):
    import technique as t
    if exercise_id not in SUPPORTED or not rows:
        return {"passed": False, "failures": ["Missing exact extra freeweight/frame records"]}
    metrics, failures = {}, []
    def check(value, name, low, high):
        metrics[name] = value
        if not low <= value <= high:
            failures.append(name + " outside authored variant limits")
    check(t.connected_joint_gap(rows), "connected_joint_max_gap_m", 0, .0001)
    fixed = FIXED_CONTACTS[exercise_id]
    check(max(t.length(t.subtract(t.joint(row, bone, part), t.joint(rows[0], bone, part)))
              for row in rows for bone in fixed for part in ("head", "tail")), "support_bone_max_drift_m", 0, .0001)
    first, peak = min(rows, key=lambda row: row["amount"]), max(rows, key=lambda row: row["amount"])
    if exercise_id == "arnold_press":
        def palm_y(row, side):
            forward = t.subtract(t.joint(row, "middle_01_" + side), t.joint(row, "hand_" + side))
            across = t.subtract(t.joint(row, "index_01_" + side), t.joint(row, "pinky_01_" + side))
            normal = (forward[1] * across[2] - forward[2] * across[1],
                      forward[2] * across[0] - forward[0] * across[2],
                      forward[0] * across[1] - forward[1] * across[0])
            return normal[1] * (1 if side == "l" else -1) / t.length(normal)
        for side in ("l", "r"):
            check(t.bend_degrees(first, "upperarm_" + side, "lowerarm_" + side), "initial_elbow_" + side + "_bend_deg", 105, 155)
            check(t.bend_degrees(peak, "upperarm_" + side, "lowerarm_" + side), "top_elbow_" + side + "_bend_deg", 0, 12)
            check(t.joint(peak, "hand_" + side)[2] - t.joint(first, "hand_" + side)[2], "hand_" + side + "_rise_m", .30, .70)
            check(palm_y(first, side), "initial_palm_" + side + "_toward_body_cosine", .70, 1.001)
            check(-palm_y(peak, side), "top_palm_" + side + "_forward_cosine", .95, 1.001)
            elbow_x = [abs(t.joint(row, "lowerarm_" + side)[0]) for row in rows]
            check(max(elbow_x) - min(elbow_x), "upperarm_" + side + "_outward_excursion_m", .15, .28)
            check(max(t.angle_degrees(t.subtract(t.joint(row, "middle_01_" + side), t.joint(row, "hand_" + side)),
                                      t.subtract(t.joint(row, "lowerarm_" + side, "tail"), t.joint(row, "lowerarm_" + side))) for row in rows),
                  "neutral_wrist_" + side + "_max_axis_error_deg", 0, .01)
    if exercise_id == "one_arm_dumbbell_row":
        for name in ("spine_01", "spine_02", "spine_03", "head"):
            check(max(t.length(t.subtract(t.joint(row, name, part), t.joint(rows[0], name, part)))
                      for row in rows for part in ("head", "tail")), "stable_" + name + "_max_drift_m", 0, .0001)
        check(t.bend_degrees(first, "upperarm_r", "lowerarm_r"), "initial_working_elbow_bend_deg", 0, 16)
        check(t.bend_degrees(peak, "upperarm_r", "lowerarm_r"), "top_working_elbow_bend_deg", 95, 135)
        check(abs(t.joint(first, "calf_l")[1] - t.joint(first, "thigh_l")[1]), "support_knee_under_hip_error_m", 0, .001)
        check(max(abs(t.joint(row, "lowerarm_r")[0] - t.joint(row, "upperarm_r")[0]) for row in rows), "working_elbow_lateral_offset_m", 0, .075)
        check(max(t.bend_degrees(row, "upperarm_l", "lowerarm_l") for row in rows), "support_left_elbow_max_bend_deg", 0, 5)
        check(max(t.angle_degrees(t.subtract(t.joint(row, "lowerarm_l", "tail"), t.joint(row, "upperarm_l")), (0, 0, -1)) for row in rows), "support_left_arm_vertical_deviation_deg", 0, 1)
    if exercise_id == "close_grip_bench":
        check(max(abs(abs(t.joint(row, "hand_l")[0]) - abs(t.joint(row, "upperarm_l")[0])) for row in rows), "shoulder_line_grip_error_m", 0, .001)
        check(t.bend_degrees(first, "upperarm_l", "lowerarm_l"), "top_elbow_bend_deg", 0, 8)
        # Full lowering on this narrow grip and enlarged chest needs about
        # 147 degrees of elbow flexion; the earlier shallow stop was 139.
        check(t.bend_degrees(peak, "upperarm_l", "lowerarm_l"), "bottom_elbow_bend_deg", 75, 150)
        for side in ("l", "r"):
            check(max(t.angle_degrees(t.subtract(t.joint(row, "middle_01_" + side), t.joint(row, "hand_" + side)),
                                      t.subtract(t.joint(row, "lowerarm_" + side, "tail"), t.joint(row, "lowerarm_" + side))) for row in rows),
                  "neutral_wrist_" + side + "_max_axis_error_deg", 0, .01)
        for name in ("spine_01", "spine_02", "spine_03", "head"):
            check(max(t.length(t.subtract(t.joint(row, name, part), t.joint(rows[0], name, part)))
                      for row in rows for part in ("head", "tail")), "stable_" + name + "_max_drift_m", 0, .0001)
    return {"exercise_id": exercise_id, "metrics": metrics, "passed": not failures, "failures": failures,
            "scope": "Selected authored geometry guards; trainer review pending"}
