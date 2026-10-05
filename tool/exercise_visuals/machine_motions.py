"""Exact machine teaching drafts using Setflow's own generic apparatus.

Primary sources describe technique, never the geometry of these original
machines. Numeric ranges fit the CC0 athlete and remain trainer_pending.
This module is deliberately not added to the central registry here.
"""
import math

SUPPORTED = ("chest_press", "leg_curl", "leg_extension", "adductor_machine")
REGIONS = {"chest_press": ("chest", "triceps", "deltoids"),
           "leg_curl": ("hamstrings",), "leg_extension": ("quadriceps",),
           "adductor_machine": ("adductors",)}
FIXED_CONTACTS = {
    "chest_press": ("pelvis", "foot_l", "foot_r"),
    "leg_curl": ("pelvis", "thigh_l", "thigh_r", "hand_l", "hand_r"),
    "leg_extension": ("pelvis", "thigh_l", "thigh_r", "hand_l", "hand_r"),
    "adductor_machine": ("pelvis", "hand_l", "hand_r"),
}
VIEWS = {
    "chest_press": {"target": (0, -.15, .97), "location": (4.0, -3.8, 2.0), "ortho_scale": 2.8},
    "leg_curl": {"target": (0, .02, .79), "location": (4.0, -3.8, 2.0), "ortho_scale": 2.7},
    "leg_extension": {"target": (0, -.20, .88), "location": (4.0, -3.8, 1.8), "ortho_scale": 2.7},
    "adductor_machine": {"target": (0, -.12, .82), "location": (2.8, -5.0, 1.9), "ortho_scale": 2.7},
}
MANUAL = "https://kb.cybexintl.com/Owners_Manuals/Strength/Life_Fitness_Insignia_Series_Owners_Manual_9481201_Rev_BE.pdf"
REFERENCES = {
    "chest_press": {"references": ["https://www.acefitness.org/resources/everyone/exercise-library/188/seated-chest-press/"],
        "source_id": None, "variant": "Seated supported bilateral chest press, horizontal overhand handles",
        "cues": ["Mid-chest handles", "Neutral wrists", "Back and feet supported", "Extend without locking elbows"]},
    "leg_curl": {"references": [MANUAL, "https://www.acefitness.org/continuing-education/certified/special-research-issue/7228/what-is-the-best-exercise-for-the-hamstrings/"],
        "source_id": "Lying_Leg_Curls", "variant": "Bilateral prone angled-pad machine leg curl",
        "source_location": "Insignia printed page 26 / PDF page 28; ACE machine curl item 1",
        "cues": ["Knee on pivot", "Posterior lower-calf roller", "Pelvis supported", "Controlled knee flexion"]},
    "leg_extension": {"references": [MANUAL], "source_id": "Leg_Extensions",
        "variant": "Seated bilateral machine knee extension with anterior lower-shin roller",
        "source_location": "Insignia printed page 27 / PDF page 29",
        "cues": ["Knee on pivot", "Anterior lower-shin pad", "Side handles", "Near-full extension without lock"]},
    "adductor_machine": {"references": [MANUAL], "source_id": "Thigh_Adductor",
        "variant": "Seated machine hip adduction, inner-knee pads and moving foot supports",
        "source_location": "Insignia printed page 24 / PDF page 26",
        "cues": ["Knees bent", "Feet on supports", "Close legs against medial pads", "Controlled reopening"]},
}
for _reference in REFERENCES.values():
    _reference.update({"checked_date": "2026-10-06", "review_status": "trainer_pending",
        "trainerApproved": False, "motion_capture": False, "brand": None, "model": None,
        "geometry_scope": "Original Setflow generic lever/seat geometry, not a manufacturer model or sourced dimension",
        "values_are_not_universal_prescriptions": True})


def _api():
    import motions
    from mathutils import Quaternion, Vector
    return motions, Quaternion, Vector


def _leg_fk(rig, label, upper, lower, foot_rotation, upper_normal=None):
    m, _, V = _api()
    rest = rig.data.bones
    hip = rig.pose.bones["thigh_" + label].head.copy()
    knee = hip + V(upper).normalized() * rest["thigh_" + label].length
    ankle = knee + V(lower).normalized() * rest["calf_" + label].length
    # Preserve an anatomical anterior frame. A shortest-arc rotation alone
    # twists the enlarged knee skin as the femur abducts, detaching its pad.
    upper_axis = V(upper).normalized()
    upper_normal = V(upper_normal) if upper_normal is not None else V((0, 0, 1)) if abs(upper_axis.z) < .4 else V((0, -1, 0))
    _limb_frame(rig, "thigh_" + label, hip, upper_axis, upper_normal)
    lower_axis = V(lower).normalized()
    lower_normal = V((0, lower_axis.z, -lower_axis.y))
    _limb_frame(rig, "calf_" + label, knee, lower_axis, lower_normal)
    m.bone_rotation(rig, "foot_" + label, ankle, foot_rotation)


def _limb_frame(rig, name, head, direction, normal):
    from mathutils import Matrix, Vector
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


def _feet(rig):
    m, Q, V = _api()
    rest = rig.data.bones
    for side, label in ((1, "l"), (-1, "r")):
        target = V((side * .22, -.34, rest["foot_" + label].head_local.z))
        hip = rig.pose.bones["thigh_" + label].head.copy()
        knee, endpoint = m.two_bone(hip, target, rest["thigh_" + label].length,
                                   rest["calf_" + label].length, V((side * .22, -.8, .58)))
        if (endpoint - target).length > .0001:
            raise ValueError("Seated machine floor foot target outside native reach")
        m.point(rig, "thigh_" + label, hip, knee)
        m.point(rig, "calf_" + label, knee, endpoint)
        m.bone_rotation(rig, "foot_" + label, endpoint, Q((1, 0, 0), 0))


def _handles(rig, prone=False):
    m, _, V = _api()
    result = {}
    for side, label in ((1, "l"), (-1, "r")):
        shoulder = rig.pose.bones["upperarm_" + label].head.copy()
        palm = (side * .31, shoulder.y - .12 if prone else -.06,
                shoulder.z - .27 if prone else .51)
        result[label] = m.neutral_palm(rig, label, palm, (side * .31, shoulder.y + .15, shoulder.z - .4))
    return result


def _chest(rig, amount):
    m, Q, V = _api()
    m.torso(rig, V((0, .10, .48)), Q((1, 0, 0), 0))
    _feet(rig)
    shoulder = rig.pose.bones["upperarm_l"].head
    pivot = V((0, -.30, shoulder.z - .08 + .65 * math.cos(math.radians(2))))
    rest = rig.data.bones
    lateral = .020
    upper = math.sqrt(rest["upperarm_l"].length ** 2 - lateral ** 2)
    lower = rest["lowerarm_l"].length + (rest["middle_01_l"].head_local - rest["hand_l"].head_local).length * .97
    reach = upper + math.hypot(lower, .012) - .0015
    low, high = math.radians(2), math.radians(35)
    for _ in range(40):
        angle = (low + high) / 2
        distance = math.hypot(pivot.y - .65 * math.sin(angle) - shoulder.y,
                              pivot.z - .65 * math.cos(angle) - shoulder.z)
        if distance < reach:
            low = angle
        else:
            high = angle
    theta = math.radians(2) + (low - math.radians(2)) * amount
    contacts = {"machine": {"kind": "press", "angle": theta, "start_angle": math.radians(2),
                           "end_angle": low, "pivot": list(pivot), "radius": .65}}
    for side, label in ((1, "l"), (-1, "r")):
        x = side * (abs(shoulder.x) + lateral)
        palm = (x, pivot.y - .65 * math.sin(theta), pivot.z - .65 * math.cos(theta))
        contacts[label] = m.neutral_palm(rig, label, palm, (x, shoulder.y + .20, shoulder.z - .2))
    return contacts


def _curl(rig, amount):
    m, Q, V = _api()
    m.torso(rig, V((0, .20, .76)), Q((1, 0, 0), math.radians(70)))
    upper_angle = math.radians(15)
    lower_angle = math.radians(20 - 105 * amount)
    for side, label in ((1, "l"), (-1, "r")):
        _leg_fk(rig, label, (0, math.cos(upper_angle), -math.sin(upper_angle)),
                (0, math.cos(lower_angle), -math.sin(lower_angle)), Q((1, 0, 0), math.pi / 2 - lower_angle),
                (0, -math.sin(upper_angle), -math.cos(upper_angle)))
    contacts = _handles(rig, True)
    contacts["machine"] = {"kind": "curl", "angle": math.pi / 2 - lower_angle, "roller_fraction": .84}
    return contacts


def _extension(rig, amount):
    m, Q, V = _api()
    m.torso(rig, V((0, .10, .51)), Q((1, 0, 0), 0))
    theta = math.radians(82 * amount)
    for side, label in ((1, "l"), (-1, "r")):
        _leg_fk(rig, label, (0, -1, 0), (0, -math.sin(theta), -math.cos(theta)), Q((1, 0, 0), -theta))
    contacts = _handles(rig)
    contacts["machine"] = {"kind": "extension", "angle": -theta, "roller_fraction": .84}
    return contacts


def _adductor(rig, amount):
    m, Q, V = _api()
    m.torso(rig, V((0, .10, .49)), Q((1, 0, 0), 0))
    theta = math.radians(38 - 32 * amount)
    for side, label in ((1, "l"), (-1, "r")):
        _leg_fk(rig, label, (side * math.sin(theta), -math.cos(theta), 0),
                (0, 0, -1), Q((1, 0, 0), 0))
    contacts = _handles(rig)
    contacts["machine"] = {"kind": "adductor", "angle": theta}
    return contacts


def pose(rig, exercise_id, amount):
    if exercise_id not in SUPPORTED or not 0 <= amount <= 1:
        raise ValueError("No exact machine motion / invalid phase: " + exercise_id)
    _api()[0].reset(rig)
    return {"chest_press": _chest, "leg_curl": _curl, "leg_extension": _extension,
            "adductor_machine": _adductor}[exercise_id](rig, amount)


def audit(rows, exercise_id):
    import technique as t
    if exercise_id not in SUPPORTED or not rows:
        return {"passed": False, "failures": ["Missing exact machine frames"]}
    metrics, failures = {}, []
    def check(name, value, low, high):
        metrics[name] = value
        if not low <= value <= high:
            failures.append(name + " outside authored limits")
    check("connected_joint_max_gap_m", t.connected_joint_gap(rows), 0, .0001)
    check("fixed_support_max_drift_m", max(t.length(t.subtract(t.joint(row, bone, part), t.joint(rows[0], bone, part)))
          for row in rows for bone in FIXED_CONTACTS[exercise_id] for part in ("head", "tail")), 0, .0001)
    first, peak = min(rows, key=lambda row: row["amount"]), max(rows, key=lambda row: row["amount"])
    for label in ("l", "r"):
        if exercise_id == "chest_press":
            check(label + "_start_elbow_bend_deg", t.bend_degrees(first, "upperarm_" + label, "lowerarm_" + label), 75, 150)
            check(label + "_end_elbow_bend_deg", t.bend_degrees(peak, "upperarm_" + label, "lowerarm_" + label), 4, 20)
        else:
            start = t.bend_degrees(first, "thigh_" + label, "calf_" + label)
            end = t.bend_degrees(peak, "thigh_" + label, "calf_" + label)
            ranges = {"leg_curl": ((4, 6), (99, 101)), "leg_extension": ((89, 91), (7, 9)), "adductor_machine": ((89, 91), (89, 91))}
            check(label + "_start_knee_bend_deg", start, *ranges[exercise_id][0])
            check(label + "_end_knee_bend_deg", end, *ranges[exercise_id][1])
    if exercise_id == "adductor_machine":
        widths = [abs(t.joint(row, "calf_l")[0] - t.joint(row, "calf_r")[0]) for row in (first, peak)]
        check("adduction_knee_width_reduction_m", widths[0] - widths[1], .35, .5)
    for row in rows:
        for name, value in row.get("machine_constraints", {}).items():
            check("max_" + name, max(metrics.get("max_" + name, 0), value), 0, .002)
    return {"passed": not failures, "metrics": metrics, "failures": list(dict.fromkeys(failures)), "trainerReview": "pending"}


def anatomy_region(name, point, normal, rig):
    """Original medial-thigh teaching mask, not measured muscle activation."""
    import anatomy
    if name != "adductors":
        raise ValueError("No machine-specific muscle mask: " + name)
    label = "l" if point.x >= 0 else "r"
    side = 1 if label == "l" else -1
    bone = rig.data.bones["thigh_" + label]
    axis = bone.tail_local - bone.head_local
    relative = point - bone.head_local
    along = relative.dot(axis) / axis.length_squared
    radial = relative - axis * along
    return (anatomy.smooth(.08, .22, along) * (1 - anatomy.smooth(.72, .90, along))
            * anatomy.smooth(-.005, .045, -side * radial.x)
            * anatomy.smooth(-.10, .45, -side * normal.x)
            * (1 - anatomy.smooth(.12, .19, radial.length)))
