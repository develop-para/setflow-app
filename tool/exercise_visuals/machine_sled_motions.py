"""Original seated calf apparatus motion; other sled variants added after validation.
All dimensions fit the CC0 Setflow athlete and remain trainer_pending.
"""
import math
SUPPORTED = ("seated_calf_raise", "legpress", "hack_squat")
REGIONS = {"seated_calf_raise": ("calves",), "legpress": ("quadriceps", "glutes"), "hack_squat": ("quadriceps", "glutes")}
FIXED_CONTACTS = {"seated_calf_raise": ("pelvis", "hand_l", "hand_r"), "legpress": ("pelvis", "hand_l", "hand_r"), "hack_squat": ("foot_l", "foot_r")}
VIEWS = {"seated_calf_raise": {"target": (0, -.13, .89), "location": (3.8, -4.2, 1.8), "ortho_scale": 2.55}}
VIEWS.update({key: {"target": (0, -.02, 1.0), "location": (4.8, -4.0, 2.1), "ortho_scale": 3.35} for key in ("legpress", "hack_squat")})
VIEWS["legpress"] = {"target": (0, -.03, .78), "location": (5.8, -.35, 2.2), "ortho_scale": 3.1}
SLED_MANUAL = "https://assets.kogan.com/files/usermanuals/FSLEGHCKSQA_UG_V1.1.pdf"
REFERENCES = {
    "legpress": {"source_id": "Leg_Press", "references": [SLED_MANUAL], "source_location": "PDF page 25, no printed numeral",
        "variant": "Supported reclined fixed seat with translating loaded footplate on original inclined straight rails",
        "cues": ["Back and hips supported", "Shoulder-width feet", "Heels remain on moving plate", "Controlled return", "Nonlocking extension"],
        "source_scope": "Official operation supports leg press with back support and moving footplate. Original 45-degree rails and measured native range are own model-fit choices; no manufacturer geometry or universal knee angle is claimed."},
    "hack_squat": {"source_id": "Hack_Squat", "references": [SLED_MANUAL], "source_location": "PDF page 25, no printed numeral",
        "variant": "Back-and-shoulder-supported translating loaded sled on own inclined rails, fixed footplate",
        "cues": ["Back and shoulders on pads", "Feet supported", "Side handles travel with carriage", "Controlled comfortable depth", "Nonlocking extension"],
        "source_scope": "Official operation supports shoulder/back pads and platform stance. Rail angle and measured depth are own model-fit choices. Pinned source universal never-knees-past-toes claim is not used as a guard."},
    "seated_calf_raise": {"source_id": "Seated_Calf_Raise", "references": ["https://kb.cybexintl.com/Owners_Manuals/Strength/16212-999-4.pdf"],
        "variant": "Seated plate-loaded bent-knee calf raise, fixed seat-side handles, forefeet on raised plate and free heels",
        "source_location": "Cybex 16212 own manual printed/PDF page 10",
        "cues": ["Pad above distal thighs", "Forefeet supported", "Heels free", "Controlled ankle plantarflexion"],
        "source_scope": "Primary manual describes thigh pad, forefoot platform and controlled calf raise. Fixed seat-side hands are an explicit original apparatus choice matching the local guide; pinned source instead puts hands on the moving lever. No branded geometry is copied."},
}
REFERENCES["hack_squat"]["model_fit"] = {"native_rail_angle_deg": 45, "native_rail_travel_m": .35, "additional_foot_out_turn_deg": 8, "foot_turn_axis": "footplate normal", "dimensions_are_original_not_official": True}
REFERENCES["legpress"]["model_fit"] = {"native_rail_angle_deg": 45, "native_footplate_travel_m": .23, "whole_sole_contacts": "heel and forefoot independently measured", "dimensions_are_original_not_official": True}
REFERENCES["seated_calf_raise"]["model_fit"] = {"ankle_rotation_deg": 20, "heels_free": True, "thigh_pad": "Rigid hinged carriage follows native thigh frame; actual evaluated distal thigh and plantar pressure contacts guarded"}
for _reference in REFERENCES.values():
    _reference.update({"checked_date": "2026-10-06", "review_status": "trainer_pending", "trainerApproved": False,
        "brand": None, "model": None, "motion_capture": False, "values_are_not_universal_prescriptions": True,
        "geometry_scope": "Own Setflow procedural apparatus; primary references support technique only",
        "surface_scope": "Skin-to-pad distances and clearances are model geometry measurements, not pressure, cloth compression or trainer-approved loading"})


def _api():
    import motions
    from mathutils import Quaternion, Vector
    return motions, Quaternion, Vector


def _limb_frame(rig, name, head, direction, normal):
    from mathutils import Matrix
    m, _, V = _api()
    rest = rig.data.bones[name]
    original = (rest.tail_local - rest.head_local).normalized()
    original_normal = V((0, -1, 0))
    original_normal = (original_normal - original * original_normal.dot(original)).normalized()
    direction = V(direction).normalized()
    normal = (V(normal) - direction * V(normal).dot(direction)).normalized()
    source = Matrix((original, original_normal, original.cross(original_normal))).transposed()
    target = Matrix((direction, normal, direction.cross(normal))).transposed()
    m.bone_rotation(rig, name, head, (target @ source.inverted()).to_quaternion())


def _leg_to(rig, label, target, rotation, pole):
    m, _, V = _api()
    rest = rig.data.bones
    hip = rig.pose.bones["thigh_" + label].head.copy()
    knee, endpoint = m.two_bone(hip, target, rest["thigh_" + label].length, rest["calf_" + label].length, pole)
    if (endpoint - target).length > .0001:
        raise ValueError("Extra machine foot target exceeds fixed native leg reach")
    for name, head, tail in (("thigh_" + label, hip, knee), ("calf_" + label, knee, endpoint)):
        direction = (tail - head).normalized()
        _limb_frame(rig, name, head, direction, V((0, direction.z, -direction.y)))
    m.bone_rotation(rig, "foot_" + label, endpoint, rotation)


def _calf(rig, amount):
    m, Q, V = _api()
    m.torso(rig, V((0, .08, .60)), Q((1, 0, 0), 0))
    rotation = Q((1, 0, 0), math.radians(20 * amount))
    contacts = {"machine": {"kind": "calf", "angle": math.radians(20 * amount)}}
    for side, label in ((1, "l"), (-1, "r")):
        flat = list(rig.get("calf_forefoot_offsets_" + label, (.003 * side, -.13, -.068)))
        offsets = [rotation @ V(flat[i:i + 3]) for i in range(0, len(flat), 3)]
        pressure = min(offsets, key=lambda point: point.z)
        ankle = V((rig.data.bones["thigh_" + label].head_local.x, -.49 - pressure.y, .121 - pressure.z))
        _leg_to(rig, label, ankle, rotation, V((ankle.x, -.85, .70)))
        shoulder = rig.pose.bones["upperarm_" + label].head
        contacts[label] = m.neutral_palm(rig, label, (side * .31, .0, .63), (side * .31, .20, shoulder.z - .40))
        contacts["forefoot_" + label] = ankle + pressure
    return contacts

def _sled(rig, key, amount):
    m, Q, V = _api()
    torso_q = Q((1, 0, 0), math.radians(-45))
    if key == "legpress":
        hip = V((0, .18, .35))
        direction = V((0, -1, 1)).normalized()
        travel = -direction * .23 * amount
        foot_q = Q((1, 0, 0), math.radians(-135))
        foot_center = V((0, hip.y - .570, hip.z + .570)) + travel
    else:
        direction = V((0, 1, 1)).normalized()
        travel = -direction * .35 * amount
        hip = V((0, .16, .895)) + travel
        foot_q = Q((1, 0, 0), math.radians(-10))
        foot_center = V((0, -.30, .23))
    m.torso(rig, hip, torso_q)
    contacts = {"machine": {"kind": key, "travel": travel, "hip": hip, "torso_rotation": torso_q,
                            "foot_center": foot_center, "foot_rotation": foot_q}}
    for side, label in ((1, "l"), (-1, "r")):
        ankle = foot_center + V((side * .18, 0, 0))
        supported_foot_q = foot_q @ Q((0, 0, 1), math.radians(side * 8)) if key == "hack_squat" else foot_q
        _leg_to(rig, label, ankle, supported_foot_q, V((ankle.x, -1.20, .90)))
        palm = hip + torso_q @ V((side * .34, -.08, .04))
        shoulder = rig.pose.bones["upperarm_" + label].head
        contacts[label] = m.neutral_palm(rig, label, palm, (palm.x, shoulder.y + .15, shoulder.z - .4))
        contacts["plate_ankle_" + label] = ankle
    return contacts


def pose(rig, exercise_id, amount):
    if exercise_id not in SUPPORTED or not 0 <= amount <= 1:
        raise ValueError("No exact sled/calf motion / invalid amount: " + exercise_id)
    _api()[0].reset(rig)
    return _calf(rig, amount) if exercise_id == "seated_calf_raise" else _sled(rig, exercise_id, amount)


def audit(rows, exercise_id):
    import technique as t
    metrics, failures = {}, []
    if exercise_id not in SUPPORTED or not rows:
        return {"passed": False, "failures": ["Missing exact sled/calf frames"]}
    def check(name, value, low, high):
        metrics[name] = value
        if not math.isfinite(value) or not low <= value <= high:
            failures.append(name + " outside authored variant limits")
    check("connected_joint_max_gap_m", t.connected_joint_gap(rows), 0, .0001)
    check("fixed_contact_max_drift_m", max((t.length(t.subtract(t.joint(row, bone, part), t.joint(rows[0], bone, part)))
          for row in rows for bone in FIXED_CONTACTS[exercise_id] for part in ("head", "tail")), default=0), 0, .0001)
    first, peak = min(rows, key=lambda row: row["amount"]), max(rows, key=lambda row: row["amount"])
    for label in ("l", "r"):
        if exercise_id == "seated_calf_raise":
            check(label + "_min_knee_bend_deg", min(t.bend_degrees(row, "thigh_" + label, "calf_" + label) for row in rows), 75, 110)
            check(label + "_max_knee_bend_deg", max(t.bend_degrees(row, "thigh_" + label, "calf_" + label) for row in rows), 75, 110)
            check(label + "_heel_rise_m", t.joint(peak, "foot_" + label)[2] - t.joint(first, "foot_" + label)[2], .025, .07)
        else:
            check(label + "_start_knee_bend_deg", t.bend_degrees(first, "thigh_" + label, "calf_" + label), 8, 30)
            check(label + "_peak_knee_bend_deg", t.bend_degrees(peak, "thigh_" + label, "calf_" + label), 80, 125)
    if exercise_id == "hack_squat":
        for side, label in ((1, "l"), (-1, "r")):
            toe = t.subtract(t.joint(first, "ball_" + label), t.joint(first, "foot_" + label))
            check(label + "_toe_out_world_projection_deg", math.degrees(math.atan2(side * toe[0], -toe[1])), 8, 13)
    if exercise_id != "seated_calf_raise":
        first_hip = t.midpoint(t.joint(first, "thigh_l"), t.joint(first, "thigh_r"))
        peak_hip = t.midpoint(t.joint(peak, "thigh_l"), t.joint(peak, "thigh_r"))
        delta = t.subtract(peak_hip, first_hip)
        if exercise_id == "hack_squat":
            # bone_audit is world metres; .35 authored native travel becomes
            # .372527 m for the v5 athlete's 1.06436 uniform object scale.
            check("hip_world_rail_travel_m", t.length(delta), .370, .375)
            check("hip_rail_diagonal_error_m", abs(delta[1] - delta[2]), 0, .0001)
            check("hip_rail_descent_y_m", -delta[1], .260, .265)
            check("hip_rail_linear_progress_error_m", max(t.length(t.subtract(t.midpoint(t.joint(row, "thigh_l"), t.joint(row, "thigh_r")),
                  tuple(first_hip[i] + delta[i] * row["amount"] for i in range(3)))) for row in rows), 0, .0001)
        else:
            check("fixed_hip_travel_m", t.length(delta), 0, .0001)
    required = (["calf_l_plantar_contact_height_error_m", "calf_r_plantar_contact_height_error_m", "calf_l_plantar_contact_progress_error_m", "calf_r_plantar_contact_progress_error_m", "calf_carriage_pivot_error_m"]
                if exercise_id == "seated_calf_raise" else
                ["sled_body_carriage_contact_error_m", "sled_footplate_carriage_contact_error_m", "sled_l_actual_ankle_anchor_error_m", "sled_r_actual_ankle_anchor_error_m"])
    for row in rows:
        constraints = row.get("machine_constraints", row.get("equipment_contacts", {}))
        if any(name not in constraints for name in required):
            failures.append("Missing actual sled/plantar constraints")
        for name, value in constraints.items():
            check("max_" + name, max(metrics.get("max_" + name, 0), value), 0, .002)
    return {"passed": not failures, "metrics": metrics, "failures": list(dict.fromkeys(failures)), "trainerReview": "pending"}
