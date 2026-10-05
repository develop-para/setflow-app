"""Further exact machine variants, separate from the frozen first four.

These original procedural drafts use primary technique references. Equipment
is Setflow's own unbranded geometry, and all variants remain trainer_pending.
"""
import math

SUPPORTED = ("pec_deck", "reverse_pec_deck", "assisted_pullup")
REGIONS = {"pec_deck": ("chest",), "reverse_pec_deck": ("rear_deltoids", "upper_back"),
           "assisted_pullup": ("lats", "upper_back", "biceps")}
FIXED_CONTACTS = {"pec_deck": ("pelvis", "foot_l", "foot_r"),
                  "reverse_pec_deck": ("pelvis", "foot_l", "foot_r"),
                  "assisted_pullup": ()}
VIEWS = {"pec_deck": {"target": (0, -.12, 1.05), "location": (3.0, -5.0, 2.1), "ortho_scale": 3.1},
         "reverse_pec_deck": {"target": (0, -.08, 1.04), "location": (4.0, 3.0, 2.0), "ortho_scale": 3.1},
         "assisted_pullup": {"target": (0, .10, 1.23), "location": (4.0, -5.0, 2.6), "ortho_scale": 3.15}}
MANUAL = "https://kb.cybexintl.com/Owners_Manuals/Strength/Life_Fitness_Insignia_Series_Owners_Manual_9481201_Rev_BE.pdf"
REVERSE_STUDY = "https://bretcontreras.com/wp-content/uploads/Effect-of-hand-position-on-EMG-activity-of-the-posterior-shoulder-musculature-during-a-horizontal-abduction-exercise.pdf"
REFERENCES = {
    "pec_deck": {"source_id": "Butterfly", "references": [MANUAL],
        "variant": "Back-supported seated machine fly with neutral vertical handles",
        "source_location": "Insignia printed pages 18 and 28 / PDF pages 20 and 30",
        "cues": ["Back supported", "Vertical neutral grips", "Slight fixed elbow bend", "Converge hands slowly"],
        "source_scope": "Butterfly specifies hand grips but no palm-down prescription; this own vertical-handle variant uses the primary manual's neutral grip."},
    "reverse_pec_deck": {"source_id": "Reverse_Machine_Flyes", "references": [REVERSE_STUDY, MANUAL],
        "variant": "Chest-supported machine reverse fly, thumb-up neutral vertical grips",
        "source_location": "Schoenfeld et al. 2013, DOI 10.1519/JSC.0b013e318281e1e9, printed page 2647 Exercise Description",
        "cues": ["Chest supported", "Grips at shoulder height", "Thumb-up neutral grip", "Shoulder horizontal abduction", "Slight fixed elbow bend"],
        "source_scope": "Author-hosted primary paper directly defines the thumb-up reverse-machine fly. Insignia only supports general chest-pad apparatus setup; its horizontal rear-delt grip is not silently treated as the neutral variant. Neither paper figures nor manufacturer geometry are copied."},
    "assisted_pullup": {"source_id": None, "references": [MANUAL],
        "variant": "Pronated counterweighted machine pull-up with both knees on rising assistance pad",
        "source_location": "Insignia printed page 11 / PDF page 13",
        "cues": ["Both knees supported", "Assistance subtracts from body weight", "Controlled vertical pull", "Pronated shoulder-width grip", "No kipping"],
        "source_scope": "No pinned dataset source ID is invented. Own machine follows the primary kneeling-assistance setup; it is not an alias of the unassisted pull-up asset."},
}
for _reference in REFERENCES.values():
    _reference.update({"checked_date": "2026-10-06", "review_status": "trainer_pending", "trainerApproved": False,
        "brand": None, "model": None, "motion_capture": False, "values_are_not_universal_prescriptions": True,
        "geometry_scope": "Own Setflow procedural apparatus; primary references support technique only"})


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


def _feet(rig):
    m, Q, V = _api()
    rest = rig.data.bones
    for side, label in ((1, "l"), (-1, "r")):
        target = V((side * .22, -.34, rest["foot_" + label].head_local.z))
        hip = rig.pose.bones["thigh_" + label].head.copy()
        knee, endpoint = m.two_bone(hip, target, rest["thigh_" + label].length, rest["calf_" + label].length, V((side * .22, -.8, .58)))
        if (endpoint - target).length > .0001:
            raise ValueError("Extra seated floor contact is unreachable")
        m.point(rig, "thigh_" + label, hip, knee)
        m.point(rig, "calf_" + label, knee, endpoint)
        m.bone_rotation(rig, "foot_" + label, endpoint, Q((1, 0, 0), 0))


def _fixed_grip(rig, label, palm, pole, normal):
    m, _, V = _api()
    rest = rig.data.bones
    shoulder = rig.pose.bones["upperarm_" + label].head.copy()
    lower = rest["lowerarm_" + label].length + (rest["middle_01_" + label].head_local - rest["hand_" + label].head_local).length * .97
    target, desired_normal = V(palm), V(normal).normalized()
    for _ in range(8):
        elbow, endpoint = m.two_bone(shoulder, target - desired_normal * .012, rest["upperarm_" + label].length, lower, V(pole))
        forward = (endpoint - elbow).normalized()
        desired_normal = (V(normal) - forward * V(normal).dot(forward)).normalized()
    wrist = elbow + forward * rest["lowerarm_" + label].length
    m.point(rig, "upperarm_" + label, shoulder, elbow)
    m.pronated_forearm(rig, label, elbow, wrist, desired_normal)
    contact = m.hand(rig, label, wrist, forward, desired_normal, True)
    if (contact["palm"] - target).length > .001:
        raise ValueError("Extra fixed grip is unreachable")
    return contact


def _leg_fk(rig, label, upper, lower, foot_rotation):
    m, _, V = _api()
    rest = rig.data.bones
    hip = rig.pose.bones["thigh_" + label].head.copy()
    knee = hip + V(upper).normalized() * rest["thigh_" + label].length
    ankle = knee + V(lower).normalized() * rest["calf_" + label].length
    m.point(rig, "thigh_" + label, hip, knee)
    m.point(rig, "calf_" + label, knee, ankle)
    m.bone_rotation(rig, "foot_" + label, ankle, foot_rotation)








def _fly(rig, key, amount):
    m, Q, V = _api()
    m.torso(rig, V((0, .10, .48)), Q((1, 0, 0), 0))
    _feet(rig)
    phi = math.radians(70 - 67 * amount if key == "pec_deck" else 3 + 87 * amount)
    bend = math.radians(25)
    contacts = {"machine": {"kind": "fly", "angle": phi, "elbow_bend": bend}}
    for side, label in ((1, "l"), (-1, "r")):
        upper = (side * math.sin(phi), -math.cos(phi), 0)
        lower = (side * math.sin(phi - bend), -math.cos(phi - bend), 0)
        normal = (-side * math.cos(phi - bend), -math.sin(phi - bend), 0)
        contacts[label] = _arm_fk(rig, label, upper, lower, normal)
    return contacts


def _assisted(rig, amount):
    m, Q, V = _api()
    hip = m.hip_center(rig) + V((0, .10, .204 + .40 * amount))
    m.torso(rig, hip, Q((1, 0, 0), 0))
    contacts = {"machine": {"kind": "assisted", "travel": .40 * amount}}
    for side, label in ((1, "l"), (-1, "r")):
        contacts[label] = _fixed_grip(rig, label, (side * .29, -.10, 2.10),
                                              (side * .48, -.30, 1.65), (0, -1, 0))
        # Knees descend below the supported hips; shins/feet extend behind
        # the narrow knee pad, rather than standing through a floating pad.
        _leg_fk(rig, label, (0, 0, -1), (0, 1, 0), Q((1, 0, 0), math.pi / 2))
    return contacts


def pose(rig, exercise_id, amount):
    if exercise_id not in SUPPORTED or not 0 <= amount <= 1:
        raise ValueError("No exact extra machine motion / invalid amount: " + exercise_id)
    _api()[0].reset(rig)
    if exercise_id == "assisted_pullup":
        return _assisted(rig, amount)
    return _fly(rig, exercise_id, amount)


def audit(rows, exercise_id):
    import technique as t
    metrics, failures = {}, []
    if exercise_id not in SUPPORTED or not rows:
        return {"passed": False, "failures": ["Missing exact extra machine frames"]}
    def check(name, value, low, high):
        metrics[name] = value
        if not low <= value <= high:
            failures.append(name + " outside authored variant limits")
    check("connected_joint_max_gap_m", t.connected_joint_gap(rows), 0, .0001)
    check("fixed_contact_max_drift_m", max((t.length(t.subtract(t.joint(row, bone, part), t.joint(rows[0], bone, part)))
          for row in rows for bone in FIXED_CONTACTS[exercise_id] for part in ("head", "tail")), default=0), 0, .0001)
    first, peak = min(rows, key=lambda row: row["amount"]), max(rows, key=lambda row: row["amount"])
    for label in ("l", "r"):
        if exercise_id in ("pec_deck", "reverse_pec_deck"):
            check(label + "_elbow_min_bend_deg", min(t.bend_degrees(row, "upperarm_" + label, "lowerarm_" + label) for row in rows), 24.9, 25.1)
            check(label + "_elbow_max_bend_deg", max(t.bend_degrees(row, "upperarm_" + label, "lowerarm_" + label) for row in rows), 24.9, 25.1)
            check(label + "_horizontal_upperarm_error_m", max(abs(t.joint(row, "upperarm_" + label)[2] - t.joint(row, "upperarm_" + label, "tail")[2]) for row in rows), 0, .0001)
        elif exercise_id == "assisted_pullup":
            check(label + "_start_elbow_bend_deg", t.bend_degrees(first, "upperarm_" + label, "lowerarm_" + label), 0, 10)
            check(label + "_peak_elbow_bend_deg", t.bend_degrees(peak, "upperarm_" + label, "lowerarm_" + label), 115, 165)
            check(label + "_knee_bend_deg", max(abs(90 - t.bend_degrees(row, "thigh_" + label, "calf_" + label)) for row in rows), 0, .001)
    required_constraints = (["bar_grip_alignment_m", "assisted_l_fixed_palm_error_m", "assisted_r_fixed_palm_error_m", "assisted_counterweight_cable_length_error_m"]
                            if exercise_id == "assisted_pullup" else
                            ["dumbbell_l_contact_m", "dumbbell_r_contact_m", "fly_l_constant_radius_error_m", "fly_r_constant_radius_error_m", "fly_l_actual_drop_endpoint_error_m", "fly_r_actual_drop_endpoint_error_m"])
    for row in rows:
        constraints = row.get("machine_constraints", row.get("equipment_contacts", {}))
        if any(name not in constraints for name in required_constraints):
            failures.append("Missing actual machine lever/grip constraints")
        for name, value in constraints.items():
            check("max_" + name, max(metrics.get("max_" + name, 0), value), 0, .002)
    return {"passed": not failures, "metrics": metrics, "failures": list(dict.fromkeys(failures)), "trainerReview": "pending"}
