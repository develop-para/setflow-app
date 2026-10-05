"""Seven explicitly authored strength variants; no animation aliasing.

The selected angles and equipment fit this athlete, not every body. Publisher
instructions and exact upstream text are distinguished; trainer review pending.
"""
import math

SUPPORTED = ("preacher_curl", "skull_crusher", "chest_supported_row", "back_extension", "decline_bench", "overhead_triceps_extension", "upright_row")
REGIONS = {
    "preacher_curl": ("biceps",), "skull_crusher": ("triceps",),
    "chest_supported_row": ("lats", "traps", "biceps", "rear_deltoids"),
    "back_extension": ("erectors", "glutes", "hamstrings"),
    "decline_bench": ("chest", "triceps", "deltoids"),
    "overhead_triceps_extension": ("triceps_r",),
    "upright_row": ("deltoids", "traps"),
}
REFERENCES = {
    "preacher_curl": {"url": "https://www.muscleandstrength.com/exercises/ez-bar-preacher-curl.html", "additional_url": "https://www.muscleandfitness.com/exercise/workouts/arm-exercises/ez-bar-preacher-curl/", "variant": "Seated preacher curl, close inner EZ-bar grip, supported upper arms", "source_id": "Preacher_Curl", "source_scope": "Original M&S EZ-bar page permits narrow grip, fitted arm padding and still torso. Exact upstream text selects close inner handles. Separate fitted arm/chest pads accommodate this enlarged model; not a brand model."},
    "skull_crusher": {"url": "https://www.muscleandstrength.com/exercises/ez-bar-skullcrusher.html", "additional_url": "https://www.acefitness.org/resources/everyone/exercise-library/36/lying-barbell-triceps-extensions/", "variant": "Flat-bench supine EZ-bar skull crusher, fixed upper arms, above-forehead stop", "source_id": "EZ-Bar_Skullcrusher", "source_scope": "Publisher's EZ-bar instructions; ACE corroborates fixed-arm supine elbow extension with a straight bar. Above-forehead clearance and inner EZ grip are selected."},
    "chest_supported_row": {"url": "https://www.muscleandstrength.com/node/48713", "variant": "Prone 45-degree supported bilateral neutral-grip dumbbell row, feet on floor", "source_scope": "Original publisher explicitly specifies 45 degrees, prone support, neutral grips and controlled scapular/arm movement; selected planted-foot variant."},
    "back_extension": {"url": "https://bretcontreras.com/wp-content/uploads/Are-All-Hip-Extension-Exercises-Created-Equal.pdf", "additional_url": "https://www.muscleandstrength.com/exercises/hyperextension.html", "variant": "45-degree Roman-chair hip extension, neutral spine, crossed arms, body-line stop", "source_id": "Hyperextensions_Back_Extensions", "source_scope": "Original NSCA SCJ 2013 author-site paper explicitly analyzes the 45-degree hip extension with a relatively neutral spine/pelvis and nearly straight knees. Exact upstream text supplies neutral-back upper-thigh padding. M&S corroborates anchored feet and body-line endpoint, but its thoracic-flexion option is not this selected variant."},
    "decline_bench": {"url": "https://www.muscleandstrength.com/exercises/decline-bench-press.html", "variant": "15-degree decline straight-bar press, closed pronated grip, secured feet, low-sternum endpoint", "source_scope": "Original publisher's decline press: supported glutes/upper back, secured feet, just-outside-shoulder grip, chest endpoint and straight bar path. Selected 15 degrees is model setup, not a universal prescription."},
    "overhead_triceps_extension": {"url": "https://www.muscleandstrength.com/exercises/one-arm-dumbbell-extension.html", "variant": "Standing single-arm dumbbell overhead extension, working right arm, forward-facing palm", "source_scope": "Original publisher's one-arm standing instructions, mirrored from left to right: forward-facing palm at start, slightly flexed elbow, behind-neck lowering and still upper arm. One dumbbell, not the two-hand variant."},
    "upright_row": {"url": "https://www.lookgreatnaked.com/articles/upright_row_implications_for_preventing_subacromial_impingement.pdf", "additional_url": "https://scholars.nova.edu/en/publications/the-upright-row-implications-for-preventing-subacromial-impingeme/", "variant": "Wide-grip straight-bar modified upright row, outward-leading elbows below shoulders", "source_scope": "Original NSCA SCJ author-site paper: elbows lead, arms anterior to coronal plane, endpoint below shoulder level. This model selects a 20-degree anterior plane and approximately 14-20 degrees of wrist ulnar deviation to keep the real straight-bar grip; those values are not universal recommendations and need trainer review."},
}
for _reference in REFERENCES.values():
    _reference["trainerApproved"] = False
    _reference["humanTrainerApproval"] = False
VIEWS = {
    "preacher_curl": {"location": (4.8, -3.8, 2.4), "target": (0, -.10, .72), "ortho_scale": 2.30},
    "skull_crusher": {"location": (4.8, 3.5, 2.5), "target": (0, .36, .66), "ortho_scale": 2.70},
    "chest_supported_row": {"location": (4.8, 3.4, 2.6), "target": (0, -.10, .78), "ortho_scale": 2.45},
    "back_extension": {"location": (4.8, 3.2, 2.4), "target": (0, -.12, .87), "ortho_scale": 2.65},
    "decline_bench": {"location": (4.8, 3.5, 2.4), "target": (0, .13, .62), "ortho_scale": 2.90},
    "overhead_triceps_extension": {"location": (-4.8, 3.6, 2.4), "target": (0, 0, 1.13), "ortho_scale": 2.85},
    "upright_row": {"location": (4.8, -3.6, 2.3), "target": (0, -.03, .93), "ortho_scale": 2.70},
}
FIXED_CONTACTS = {
    "preacher_curl": ("foot_l", "foot_r"), "skull_crusher": ("foot_l", "foot_r"),
    "chest_supported_row": ("foot_l", "foot_r"),
    "back_extension": ("foot_l", "foot_r", "calf_l", "calf_r"),
    "decline_bench": ("foot_l", "foot_r", "calf_l", "calf_r"),
    "overhead_triceps_extension": ("foot_l", "foot_r"),
    "upright_row": ("foot_l", "foot_r"),
}
EZ_CANT_DEG = -8.
DECLINE_BOTTOM_Z = .803119


def _api():
    import motions
    from mathutils import Quaternion, Vector
    return motions, Quaternion, Vector


def _helpers():
    import remaining_strength_motions as common
    return common


def _fixed_leg_fk(rig, thigh, calf, foot_angle):
    m, Q, V = _api()
    for label in ("l", "r"):
        rest = rig.data.bones
        hip = rig.pose.bones["thigh_" + label].head.copy()
        knee = hip + V(thigh).normalized() * rest["thigh_" + label].length
        ankle = knee + V(calf).normalized() * rest["calf_" + label].length
        m.point(rig, "thigh_" + label, hip, knee)
        m.point(rig, "calf_" + label, knee, ankle)
        m.bone_rotation(rig, "foot_" + label, ankle, Q((1, 0, 0), math.radians(foot_angle)))


def _ez_forearm(rig, label, upper, angle, supinated):
    _, _, V = _api()
    side = 1 if label == "l" else -1
    cant = math.radians(EZ_CANT_DEG)
    forward = V((side * math.sin(cant), -math.sin(angle) * math.cos(cant), -math.cos(angle) * math.cos(cant)))
    axis = V((math.cos(cant), side * math.sin(angle) * math.sin(cant), side * math.cos(angle) * math.sin(cant)))
    normal = forward.cross(axis) * (1 if supinated else -1)
    return _helpers()._arm_fk(rig, label, upper, forward, normal)


def _preacher(rig, amount):
    m, Q, V = _api()
    m.torso(rig, V((0, .22, .68)), Q((1, 0, 0), 0))
    z = rig.data.bones["foot_l"].head_local.z
    _helpers()._legs(rig, {"l": (.19, -.30, z), "r": (-.19, -.30, z)})
    angle = math.radians(35 + 118 * amount)
    contacts = {"motion_amount": amount, "ez_angle": angle}
    for side, label in ((1, "l"), (-1, "r")):
        cant = math.radians(EZ_CANT_DEG)
        upper = V((side * math.sin(cant), -math.sin(math.radians(35)) * math.cos(cant), -math.cos(math.radians(35)) * math.cos(cant)))
        contacts[label] = _ez_forearm(rig, label, upper, angle, True)
    return contacts


def _skull(rig, amount):
    m, Q, V = _api()
    m.torso(rig, V((0, .30, .50)), Q((1, 0, 0), -math.pi / 2))
    z = rig.data.bones["foot_l"].head_local.z
    _helpers()._legs(rig, {"l": (.22, -.38, z), "r": (-.22, -.38, z)}, pole_y=-.50, foot_rotation=Q((1, 0, 0), 0))
    angle = math.radians(180 + 94 * amount)
    contacts = {"motion_amount": amount, "ez_angle": angle}
    for side, label in ((1, "l"), (-1, "r")):
        cant = math.radians(EZ_CANT_DEG)
        contacts[label] = _ez_forearm(rig, label, (side * math.sin(cant), 0, math.cos(cant)), angle, False)
    return contacts


def _supported_row(rig, amount):
    m, Q, V = _api()
    m.torso(rig, V((0, .04, .74)), Q((1, 0, 0), math.pi / 4))
    z = rig.data.bones["foot_l"].head_local.z
    _helpers()._legs(rig, {"l": (.20, .40, z), "r": (-.20, .40, z)}, pole_y=.18)
    # Retract through the native shoulder girdle; chest/spine/neck stay put.
    for side, label in ((1, "l"), (-1, "r")):
        clavicle = rig.pose.bones["clavicle_" + label]
        rotation = Q((0, 0, 1), math.radians(-side * 5 * amount))
        m.bone_rotation(rig, "clavicle_" + label, clavicle.head.copy(), rotation @ Q((1, 0, 0), math.pi / 4))
    upper_angle = math.radians(-7 + 60 * amount)
    contacts = {"motion_amount": amount}
    for side, label in ((1, "l"), (-1, "r")):
        upper = V((side * .10, math.sin(upper_angle), -math.cos(upper_angle)))
        lower = V((0, -.50 * amount, -1))
        contacts[label] = _helpers()._arm_fk(rig, label, upper, lower, (-side, 0, 0))
    return contacts


def _back_extension(rig, amount):
    m, Q, V = _api()
    angle = math.radians(45 + 75 * amount)
    rotation = Q((1, 0, 0), angle)
    m.torso(rig, V((0, -.08, 1.00)), rotation)
    _fixed_leg_fk(rig, (0, 1, -1), (0, 1, -1), 45)
    contacts = {"motion_amount": amount}
    rest = rig.data.bones
    hip_offset = V((0, -.08, 1.00)) - rotation @ m.hip_center(rig)
    for side, label in ((1, "l"), (-1, "r")):
        # Open crossed arms lie in front of the opposite pectoral surface.
        wrist = hip_offset + rotation @ V((-side * .12, -.22, 1.24))
        shoulder = rig.pose.bones["upperarm_" + label].head.copy()
        elbow, reached = m.two_bone(shoulder, wrist, rest["upperarm_" + label].length,
                                    rest["lowerarm_" + label].length,
                                    hip_offset + rotation @ V((side * .38, -.14, 1.10)))
        if (reached - wrist).length > .00001:
            raise ValueError("Crossed-arm wrist target outside native reach")
        m.point(rig, "upperarm_" + label, shoulder, elbow)
        direction = (wrist - elbow).normalized()
        normal = rotation @ V((0, 1, 0))
        m.pronated_forearm(rig, label, elbow, wrist, normal)
        contacts[label] = m.hand(rig, label, wrist, direction, normal, False)
    return contacts


def _decline(rig, amount):
    m, Q, V = _api()
    m.torso(rig, V((0, 0, .70)), Q((1, 0, 0), math.radians(-105)))
    _fixed_leg_fk(rig, (0, -.85, .30), (0, -.30, -.80), 0)
    shoulder = rig.pose.bones["upperarm_l"].head.copy()
    contacts = {"motion_amount": amount}
    rest = rig.data.bones
    grip_x = .224
    upper = math.sqrt(rest["upperarm_l"].length ** 2 - (grip_x - shoulder.x) ** 2)
    lower = math.hypot(rest["lowerarm_l"].length + _helpers()._palm_length(rig, "l"), .012)
    top_z = shoulder.z + math.sqrt((upper + lower - .00030) ** 2 - .18 ** 2)
    center = V((0, shoulder.y - .18, DECLINE_BOTTOM_Z + (top_z - DECLINE_BOTTOM_Z) * (1 - amount)))
    for side, label in ((1, "l"), (-1, "r")):
        contacts[label] = _helpers()._axis_grip(rig, label, center + V((side * grip_x, 0, 0)),
                        (side * grip_x, shoulder.y - .47, shoulder.z + .05), (1, 0, 0))
    return contacts


def _overhead(rig, amount):
    m, Q, V = _api()
    m.torso(rig, m.hip_center(rig), Q((1, 0, 0), 0))
    _helpers()._legs(rig)
    angle = math.radians(8 + 108 * amount)
    contacts = {"motion_amount": amount}
    upper = V((-.36, 0, .933)).normalized()
    lower = upper * math.cos(angle) + V((0, 1, 0)) * math.sin(angle)
    contacts["r"] = _helpers()._arm_fk(rig, "r", upper, lower, (0, -1, 0))
    contacts["l"] = _helpers()._arm_fk(rig, "l", (.09, 0, -1), (0, -.06, -1), (-1, 0, 0), False)
    return contacts


def _upright(rig, amount):
    m, Q, V = _api()
    m.torso(rig, m.hip_center(rig), Q((1, 0, 0), 0))
    _helpers()._legs(rig)
    elevation, anterior = math.radians(20 + 60 * amount), math.radians(20)
    rest = rig.data.bones
    contacts = {"motion_amount": amount}
    for side, label in ((1, "l"), (-1, "r")):
        shoulder = rig.pose.bones["upperarm_" + label].head.copy()
        upper = V((side * math.sin(elevation) * math.cos(anterior),
                   -math.sin(elevation) * math.sin(anterior), -math.cos(elevation)))
        elbow = shoulder + upper * rest["upperarm_" + label].length
        lateral = side * .345 - elbow.x
        lower_length = rest["lowerarm_" + label].length
        planar_length = math.sqrt(lower_length ** 2 - lateral ** 2)
        palm_length = _helpers()._palm_length(rig, label)
        effective = math.hypot(planar_length + palm_length, .012)
        dy = -.185 - elbow.y
        dz = -math.sqrt(effective ** 2 - dy ** 2)
        combined = V((0, dy, dz)).normalized()
        normal_axis = V((1, 0, 0)).cross(combined)
        angle = math.atan2(.012, planar_length + palm_length)
        hand_forward = combined * math.cos(angle) - normal_axis * math.sin(angle)
        normal = combined * math.sin(angle) + normal_axis * math.cos(angle)
        forearm = V((lateral / lower_length, hand_forward.y * planar_length / lower_length,
                     hand_forward.z * planar_length / lower_length))
        wrist = elbow + forearm * lower_length
        m.point(rig, "upperarm_" + label, shoulder, elbow)
        m.pronated_forearm(rig, label, elbow, wrist, normal)
        contacts[label] = m.hand(rig, label, wrist, hand_forward, normal, True)
    return contacts


def phase(exercise_id, seconds):
    if exercise_id not in SUPPORTED:
        raise ValueError("No exact remaining extra strength phase: " + exercise_id)
    return _api()[0].cycle(seconds)


def pose(rig, exercise_id, amount):
    if exercise_id not in SUPPORTED or not 0 <= amount <= 1:
        raise ValueError("No exact remaining extra strength motion: " + exercise_id)
    _api()[0].reset(rig)
    return {"preacher_curl": _preacher, "skull_crusher": _skull,
            "chest_supported_row": _supported_row, "back_extension": _back_extension,
            "decline_bench": _decline, "overhead_triceps_extension": _overhead,
            "upright_row": _upright}[exercise_id](rig, amount)


def audit(rows, exercise_id):
    import technique as t
    if exercise_id not in SUPPORTED or not rows:
        return {"passed": False, "failures": ["Missing exact extra strength frames"]}
    failures, metrics = [], {}
    def check(value, name, low, high):
        metrics[name] = value
        if not low <= value <= high:
            failures.append(name + " outside the selected authored variant")
    check(t.connected_joint_gap(rows), "connected_joint_max_gap_m", 0, .0001)
    first, peak = min(rows, key=lambda row: row["amount"]), max(rows, key=lambda row: row["amount"])
    for name in FIXED_CONTACTS[exercise_id]:
        check(max(t.length(t.subtract(t.joint(row, name, end), t.joint(first, name, end)))
                  for row in rows for end in ("head", "tail")), name + "_fixed_drift_m", 0, .0001)
    for label in ("l", "r"):
        check(max(t.angle_degrees(t.subtract(t.joint(row, "middle_01_" + label), t.joint(row, "hand_" + label)),
                                 t.subtract(t.joint(row, "lowerarm_" + label, "tail"), t.joint(row, "lowerarm_" + label)))
                  for row in rows), label + ("_model_wrist_ulnar_deviation_deg" if exercise_id == "upright_row" else "_neutral_wrist_axis_error_deg"), 0, 22 if exercise_id == "upright_row" else .01)
    if exercise_id != "back_extension":
        for bone in ("pelvis", "spine_01", "spine_02", "spine_03", "head"):
            check(max(t.length(t.subtract(t.joint(row, bone, end), t.joint(first, bone, end)))
                      for row in rows for end in ("head", "tail")), bone + "_drift_m", 0, .0001)
    if exercise_id in ("preacher_curl", "skull_crusher", "overhead_triceps_extension"):
        for label in (("r",) if exercise_id == "overhead_triceps_extension" else ("l", "r")):
            check(max(t.angle_degrees(t.subtract(t.joint(row, "upperarm_" + label, "tail"), t.joint(row, "upperarm_" + label)),
                                     t.subtract(t.joint(first, "upperarm_" + label, "tail"), t.joint(first, "upperarm_" + label)))
                      for row in rows), label + "_loaded_upperarm_direction_drift_deg", 0, .02)
            check(t.bend_degrees(peak, "upperarm_" + label, "lowerarm_" + label), label + "_peak_elbow_bend_deg", 80, 135)
            check(t.bend_degrees(first, "upperarm_" + label, "lowerarm_" + label), label + "_initial_elbow_bend_deg", 5 if exercise_id == "overhead_triceps_extension" else 0, 10 if exercise_id == "overhead_triceps_extension" else 3)
    if exercise_id == "decline_bench":
        for label in ("l", "r"):
            check(t.bend_degrees(first, "upperarm_" + label, "lowerarm_" + label), label + "_press_top_elbow_bend_deg", 0, 10)
            check(t.bend_degrees(peak, "upperarm_" + label, "lowerarm_" + label), label + "_press_bottom_elbow_bend_deg", 80, 150)
    if exercise_id == "back_extension":
        for label in ("l", "r"):
            check(max(t.length(t.subtract(t.joint(row, "thigh_" + label), t.joint(first, "thigh_" + label))) for row in rows), label + "_hinge_center_drift_m", 0, .0001)
        for upper, lower in (("spine_01", "spine_02"), ("spine_02", "spine_03"), ("spine_03", "head")):
            first_angle = t.angle_degrees(t.subtract(t.joint(first, upper, "tail"), t.joint(first, upper)), t.subtract(t.joint(first, lower, "tail"), t.joint(first, lower)))
            check(max(abs(t.angle_degrees(t.subtract(t.joint(row, upper, "tail"), t.joint(row, upper)), t.subtract(t.joint(row, lower, "tail"), t.joint(row, lower))) - first_angle) for row in rows), upper + "_" + lower + "_neutral_relative_angle_drift_deg", 0, .01)
    if exercise_id == "chest_supported_row":
        for label in ("l", "r"):
            check(t.bend_degrees(first, "upperarm_" + label, "lowerarm_" + label), label + "_initial_elbow_bend_deg", 0, 12)
            check(t.bend_degrees(peak, "upperarm_" + label, "lowerarm_" + label), label + "_peak_elbow_bend_deg", 45, 115)
    if exercise_id == "upright_row":
        for label in ("l", "r"):
            delta = t.subtract(t.joint(peak, "upperarm_" + label, "tail"), t.joint(peak, "upperarm_" + label))
            check(t.angle_degrees(delta, (0, 0, -1)), label + "_peak_humerus_elevation_deg", 75, 89.5)
            check(math.degrees(math.atan2(-delta[1], abs(delta[0]))), label + "_peak_plane_anterior_to_coronal_deg", 18, 22)
            check(t.joint(peak, "lowerarm_" + label)[2] - t.joint(peak, "hand_" + label)[2], label + "_peak_elbow_above_wrist_m", .15, .30)
    return {"exercise_id": exercise_id, "metrics": metrics, "passed": not failures,
            "failures": failures, "scope": "Model geometry guards only; source scope and physical loading require trainer review",
            "trainerApproved": False, "humanTrainerApproval": False}
