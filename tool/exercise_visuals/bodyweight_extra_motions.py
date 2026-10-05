"""Three separately authored floor/wall variants; trainer review is pending.

These IDs are not registered by this file. Common render/registry sources and
the earlier 15 bodyweight motions remain unchanged. Blender imports are lazy.
"""
import math

SUPPORTED = ("wall_sit", "russian_twist", "mountain_climber")
REGIONS = {"wall_sit": ("quadriceps", "glutes", "calves"),
           "russian_twist": ("abs",),
           "mountain_climber": ("abs", "quadriceps", "deltoids")}
STATIC = ("wall_sit",)
FIXED_CONTACTS = {"wall_sit": ("pelvis", "foot_l", "foot_r"),
                  "russian_twist": ("pelvis",),
                  "mountain_climber": ("hand_l", "hand_r")}
VIEWS = {
    "wall_sit": {"target": (0, -0.10, 0.77), "location": (4.3, -4.1, 1.6), "ortho_scale": 2.15},
    "russian_twist": {"target": (0, -0.07, 0.51), "location": (4.2, -4.2, 2.1), "ortho_scale": 2.10},
    "mountain_climber": {"target": (0, 0.04, 0.39), "location": (4.5, -3.3, 1.3), "ortho_scale": 2.40},
}
REFERENCES = {
    "wall_sit": {
        "variant": "Static bilateral wall sit with back/butt wall support and both feet planted",
        "references": ["https://www.nasm.org/resource-center/blog/training/wall-sits"],
        "reference_cues": ["Back against wall", "Feet in front, hip/shoulder width", "Controlled near-right-angle seated hold", "Knees track feet", "Steady breathing"],
        "review_status": "trainer_pending", "checked_date": "2026-10-06",
        "values_are_not_universal_prescriptions": True, "motion_capture": False,
    },
    "russian_twist": {
        "variant": "Floor seated bodyweight Russian twist, knees bent, feet elevated, hands clasped in front",
        "references": ["https://www.nasm.org/resource-center/exercise-library/russian-twist"],
        "reference_cues": ["Floor seated", "Slight backward torso lean", "Bent knees and slightly elevated feet", "Controlled alternating shoulder-led trunk rotation", "Bodyweight option explicitly supported in FAQ"],
        "catalog_source_id": "Russian_Twist", "local_guide_variant_selected": True,
        "source_variant_difference": "Pinned dataset anchors feet; current local guide elevates them. This authored clip explicitly follows the local guide, not ACE's stability-ball variation.",
        "review_status": "trainer_pending", "checked_date": "2026-10-06",
        "values_are_not_universal_prescriptions": True, "motion_capture": False,
    },
    "mountain_climber": {
        "variant": "Floor-palm supported alternating mountain climber with airborne leg-switch transition",
        "references": ["https://www.acefitness.org/resources/everyone/exercise-library/258/mountain-climbers/"],
        "reference_cues": ["Palms remain firmly on floor", "One hip/knee flexed with front foot down", "Other leg extended behind", "Both feet briefly leave floor while switching", "Braced stable trunk"],
        "catalog_source_id": "Mountain_Climbers", "review_status": "trainer_pending",
        "checked_date": "2026-10-06", "values_are_not_universal_prescriptions": True, "motion_capture": False,
    },
}

# Armature-space wall plane; chosen after actual skinned-surface review.
WALL_FRONT_Y = 0.0882
TRAINING_SURFACE_Z = 0.004


def _modules():
    import motions
    from mathutils import Quaternion, Vector
    return motions, Quaternion, Vector


def _free_leg(rig, label, thigh_direction, calf_direction, foot_rotation):
    m, _, V = _modules()
    rest = rig.data.bones
    hip = rig.pose.bones["thigh_" + label].head.copy()
    knee = hip + V(thigh_direction).normalized() * rest["thigh_" + label].length
    ankle = knee + V(calf_direction).normalized() * rest["calf_" + label].length
    m.point(rig, "thigh_" + label, hip, knee)
    m.point(rig, "calf_" + label, knee, ankle)
    m.bone_rotation(rig, "foot_" + label, ankle, foot_rotation)


def _fixed_length_leg(rig, label, ankle, pole, rotation):
    m, Q, V = _modules()
    rest = rig.data.bones
    hip = rig.pose.bones["thigh_" + label].head.copy()
    knee, endpoint = m.two_bone(hip, V(ankle), rest["thigh_" + label].length,
                                 rest["calf_" + label].length, V(pole))
    if (endpoint - V(ankle)).length > 0.0001:
        raise ValueError("Mountain-climber ankle beyond native reach")
    m.point(rig, "thigh_" + label, hip, knee)
    m.point(rig, "calf_" + label, knee, endpoint)
    m.bone_rotation(rig, "foot_" + label, endpoint, rotation)
    ball = rig.pose.bones["foot_" + label].tail.copy()
    m.bone_rotation(rig, "ball_" + label, ball, Q((1, 0, 0), 0))


def _wall(rig):
    m, Q, V = _modules()
    height = rig.data.bones["calf_l"].length + 0.069
    m.torso(rig, V((0, 0, height)), Q((1, 0, 0), math.radians(2)))
    contacts = {}
    for side, label in ((1, "l"), (-1, "r")):
        _free_leg(rig, label, (0, -1, 0), (0, 0, -1), Q((1, 0, 0), 0))
        shoulder = rig.pose.bones["upperarm_" + label].head.copy()
        wrist = shoulder + V((side * 0.035, -0.08, -0.49))
        contacts[label] = m.arm(rig, label, wrist, shoulder + V((side * 0.24, -0.12, -0.20)),
                                V((0, -0.2, -1)), V((-side, 0, 0)))
    return contacts


def _clasped_hand(rig, label, palm, pole, normal):
    m, _, V = _modules()
    rest = rig.data.bones
    shoulder = rig.pose.bones["upperarm_" + label].head.copy()
    palm_length = (rest["middle_01_" + label].head_local - rest["hand_" + label].head_local).length * .97
    lower = rest["lowerarm_" + label].length + palm_length
    desired = V(normal).normalized()
    for _ in range(8):
        elbow, endpoint = m.two_bone(shoulder, V(palm) - desired * .012,
                                     rest["upperarm_" + label].length, lower, V(pole))
        forward = (endpoint - elbow).normalized()
        desired = (V(normal) - forward * V(normal).dot(forward)).normalized()
    wrist = elbow + forward * rest["lowerarm_" + label].length
    m.point(rig, "upperarm_" + label, shoulder, elbow)
    m.point(rig, "lowerarm_" + label, elbow, wrist)
    m.pronated_forearm(rig, label, elbow, wrist, desired)
    contact = m.hand(rig, label, wrist, forward, desired)
    if (contact["palm"] - V(palm)).length > .001:
        raise ValueError("Russian-twist clasped hand exceeds native reach")
    # Relaxed fingers wrap partly around the opposite hand, without an
    # invisible weight or a forced tight barbell grip.
    for digit in ("index", "middle", "ring", "pinky"):
        for segment, degrees in ((1, 18), (2, 45), (3, 70)):
            name = f"{digit}_0{segment}_{label}"
            head = rig.pose.bones[name].head.copy()
            angle = math.radians(degrees)
            direction = forward * math.cos(angle) + desired * math.sin(angle)
            m.point(rig, name, head, head + direction * rest[name].length)
    return contact


def _russian(rig, amount):
    m, Q, V = _modules()
    lean = Q((1, 0, 0), math.radians(-35))
    m.torso(rig, V((0, 0, 0.0985 + TRAINING_SURFACE_Z)), lean)
    for label in ("l", "r"):
        _free_leg(rig, label, (0, -0.87, 0.50), (0, -0.95, -0.30), Q((1, 0, 0), math.radians(-40)))
    yaw = math.radians(-28 + 56 * amount)
    axis = lean @ V((0, 0, 1))
    for name, portion in (("spine_01", .25), ("spine_02", .60), ("spine_03", 1)):
        head = rig.pose.bones[name].head.copy()
        m.bone_rotation(rig, name, head, Q(axis, yaw * portion) @ lean)
    rotation = Q(axis, yaw) @ lean
    shoulders = (rig.pose.bones["upperarm_l"].head + rig.pose.bones["upperarm_r"].head) / 2
    center = shoulders + rotation @ V((0, -.30, -.12))
    return {label: _clasped_hand(rig, label, center + rotation @ V((side * .003, 0, 0)),
                                shoulders + rotation @ V((side * .38, -.08, -.30)),
                                rotation @ V((-side, 0, 0)))
            for side, label in ((1, "l"), (-1, "r"))}


def _mountain(rig, amount):
    m, Q, V = _modules()
    rest = rig.data.bones
    lean = math.radians(85)
    length = rest["thigh_l"].length + rest["calf_l"].length - .0005
    lateral = rest["calf_l"].tail_local.x - rest["thigh_l"].head_local.x
    projected = math.sqrt(length * length - lateral * lateral)
    hip_z = .49 + TRAINING_SURFACE_Z
    hip_y = .84 - math.sqrt(projected * projected - (hip_z - .145 - TRAINING_SURFACE_Z) ** 2)
    m.torso(rig, V((0, hip_y, hip_z)), Q((1, 0, 0), lean))
    contacts = {}
    for side, label in ((1, "l"), (-1, "r")):
        contacts[label] = m.arm(rig, label, (side * .32, -.40, .032 + TRAINING_SURFACE_Z),
                                (side * .52, -.15, .18), (0, -1, 0), (0, 0, -1))
        m.floor_hand(rig, label)
        front = 1 - amount if label == "l" else amount
        ankle = V((side * (.18849 + .03151 * front), .84 - 1.08 * front,
                   .145 + TRAINING_SURFACE_Z - .076 * front + .04 * math.sin(math.pi * amount)))
        hip = rig.pose.bones["thigh_" + label].head.copy()
        delta = ankle - hip
        # Keep the knee's bend direction forward in the sagittal plane.
        # Interpolating opposite rear/front poles crosses the straight-chain
        # axis mid-switch and flips the knees above/behind the trunk.
        pole = hip + V((0, delta.z, -delta.y))
        _fixed_length_leg(rig, label, ankle, pole, Q((1, 0, 0), math.radians(60 * (1 - front))))
    return contacts


def pose(rig, exercise_id, amount):
    if exercise_id not in SUPPORTED:
        raise ValueError("No exact extra bodyweight motion: " + exercise_id)
    if not 0 <= amount <= 1:
        raise ValueError("Motion amount must be between zero and one")
    m, _, _ = _modules()
    m.reset(rig)
    if exercise_id == "wall_sit":
        return _wall(rig)
    if exercise_id == "russian_twist":
        return _russian(rig, amount)
    return _mountain(rig, amount)


def phase(exercise_id, seconds):
    if exercise_id not in SUPPORTED:
        raise ValueError("No exact extra bodyweight phase: " + exercise_id)
    if exercise_id == "wall_sit":
        return 0.0
    if exercise_id != "mountain_climber":
        return _modules()[0].cycle(seconds)
    # Two brief, one-way leg switches within four seconds. The default
    # 1.4-second lowering curve would depict feet suspended too long for the
    # selected ACE airborne switch. Held ends make support positions clear.
    def ease(value):
        value = max(0.0, min(1.0, value))
        return value * value * (3 - 2 * value)
    if seconds < .8:
        return 0.0
    if seconds < 1.2:
        return ease((seconds - .8) / .4)
    if seconds < 2.8:
        return 1.0
    if seconds < 3.2:
        return 1.0 - ease((seconds - 2.8) / .4)
    return 0.0


def audit(rows, exercise_id):
    import technique as t
    if exercise_id not in SUPPORTED or not rows:
        return {"passed": False, "failures": ["Missing exact extra motion/frame records"]}
    metrics, failures = {}, []
    def check(value, name, low, high):
        metrics[name] = value
        if not low <= value <= high:
            failures.append(name + " outside authored variant limits")
    check(t.connected_joint_gap(rows), "connected_joint_max_gap_m", 0, .0001)
    fixed = FIXED_CONTACTS[exercise_id]
    drift = max(t.length(t.subtract(t.joint(row, bone, part), t.joint(rows[0], bone, part)))
                for row in rows for bone in fixed for part in ("head", "tail"))
    check(drift, "support_bone_max_drift_m", 0, .0001)
    if exercise_id == "wall_sit":
        all_drift = max(t.length(t.subtract(t.joint(row, bone, part), t.joint(rows[0], bone, part)))
                        for row in rows for bone in row["bones"] for part in ("head", "tail"))
        check(all_drift, "static_body_max_drift_m", 0, .00001)
        knees = [t.bend_degrees(row, "thigh_" + side, "calf_" + side) for row in rows for side in ("l", "r")]
        check(min(knees), "knee_min_bend_deg", 85, 95)
        check(max(knees), "knee_max_bend_deg", 85, 95)
    if exercise_id == "russian_twist":
        foot_drift = max(t.length(t.subtract(t.joint(row, "foot_" + side), t.joint(rows[0], "foot_" + side)))
                         for row in rows for side in ("l", "r"))
        check(foot_drift, "elevated_foot_max_drift_m", 0, .0001)
        check(min(t.joint(row, "foot_" + side)[2] for row in rows for side in ("l", "r")), "min_ankle_height_m", .12, .40)
        first_axis = t.subtract(t.joint(min(rows, key=lambda row: row["amount"]), "upperarm_l"), t.joint(min(rows, key=lambda row: row["amount"]), "upperarm_r"))
        last_axis = t.subtract(t.joint(max(rows, key=lambda row: row["amount"]), "upperarm_l"), t.joint(max(rows, key=lambda row: row["amount"]), "upperarm_r"))
        check(t.angle_degrees(first_axis, last_axis), "shoulder_rotation_range_deg", 50, 62)
    if exercise_id == "mountain_climber":
        for name in ("pelvis", "spine_01", "spine_02", "spine_03", "head"):
            drift = max(t.length(t.subtract(t.joint(row, name, part), t.joint(rows[0], name, part))) for row in rows for part in ("head", "tail"))
            check(drift, "stable_" + name + "_max_drift_m", 0, .0001)
        first, last = min(rows, key=lambda row: row["amount"]), max(rows, key=lambda row: row["amount"])
        check(t.bend_degrees(first, "thigh_l", "calf_l"), "initial_front_knee_bend_deg", 70, 150)
        check(t.bend_degrees(first, "thigh_r", "calf_r"), "initial_rear_knee_bend_deg", 0, 8)
        check(t.bend_degrees(last, "thigh_r", "calf_r"), "opposite_front_knee_bend_deg", 70, 150)
        check(t.bend_degrees(last, "thigh_l", "calf_l"), "opposite_rear_knee_bend_deg", 0, 8)
        knees = [t.joint(row, "calf_" + side) for row in rows for side in ("l", "r")]
        check(min(knee[2] for knee in knees), "switch_min_knee_height_m", .05, .60)
        switches = [row for row in rows if .3 <= row["amount"] <= .7]
        if not switches:
            failures.append("Leg-switch transition was not sampled")
        else:
            check(max(t.joint(row, "calf_" + side)[1] - t.joint(row, "thigh_" + side)[1]
                      for row in switches for side in ("l", "r")),
                  "switch_max_knee_behind_hip_m", -.30, .10)
    return {"exercise_id": exercise_id, "metrics": metrics, "passed": not failures,
            "failures": failures, "scope": "Selected authored geometry guards; trainer review pending"}
