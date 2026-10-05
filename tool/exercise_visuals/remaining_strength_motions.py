"""Exact remaining strength drafts; authored geometry, trainer review pending.

No source media are imported. Numeric angles select this athlete's variant,
not universal technique limits. Unsupported IDs fail instead of aliasing.
"""
import math

SUPPORTED = ("rack_pull", "tbar_row")
REGIONS = {
    "rack_pull": ("glutes", "hamstrings", "erectors", "traps"),
    "tbar_row": ("lats", "traps", "biceps", "erectors"),
    "upright_row": ("deltoids", "traps"),
}
REFERENCES = {
    "rack_pull": {"url": "https://www.nsca.com/contentassets/b70b70c5cb96417bbc58d5b6756a689e/ptq-8.3.1-resistance-training-progressions-for-the-older-adult-deadlifts.pdf", "variant": "Knee-height power-rack pull, double-overhand closed grip", "source_id": "Rack_Pulls", "source_scope": "NSCA PTQ rack-pull instructions; knee-height catches, hip hinge and pause. Model dimensions and grip type are selected.", "cues": ["Bar rests on safety catches before each pull", "Grip just outside shoulders", "Stand tall without leaning back", "Return to catches and pause"], "trainerApproved": False},
    "tbar_row": {"url": "https://doi.org/10.1519/SSC.0000000000000751", "additional_url": "https://www.researchgate.net/profile/Anthony-Weldon/publication/365629162_Exercise_Technique_The_Landmine_Row/links/66163ef139e7641c0ba88732/Exercise-Technique-The-Landmine-Row.pdf", "variant": "Bilateral neutral-grip landmine T-bar row with Double-D attachment", "source_id": "T-Bar_Row_with_Handle", "source_scope": "Original NSCA journal paper's bilateral landmine T-bar technique; Double-D chosen from exact upstream text. Rigid pivot and length are explicit.", "cues": ["Face away from fixed landmine pivot and straddle shaft", "Hold hip hinge and softly bent knees", "Pull elbows behind torso without standing up", "Controlled return"], "trainerApproved": False},
    "upright_row": {"url": "https://www.lookgreatnaked.com/articles/upright_row_implications_for_preventing_subacromial_impingement.pdf", "additional_url": "https://scholars.nova.edu/en/publications/the-upright-row-implications-for-preventing-subacromial-impingeme/", "variant": "Standing straight-bar upright row; upper arms stop below shoulder height", "source_scope": "NSCA SCJ original author-site paper, modified technique; no upstream source ID. Selected ROM and width are model parameters.", "cues": ["Closed overhand grip", "Elbows lead outward/upward", "Upper arms stop below shoulder level", "Stable torso and controlled return"], "trainerApproved": False},
}
VIEWS = {
    "rack_pull": {"location": (4.8, 3.6, 2.4), "target": (0, 0, .85), "ortho_scale": 2.80},
    "tbar_row": {"location": (4.8, 3.0, 2.6), "target": (0, .40, .73), "ortho_scale": 2.55},
    "upright_row": {"location": (4.8, -3.6, 2.3), "target": (0, -.03, .93), "ortho_scale": 2.70},
}
FIXED_CONTACTS = {"rack_pull": ("foot_l", "foot_r"), "tbar_row": ("foot_l", "foot_r"), "upright_row": ("foot_l", "foot_r")}
LANDMINE_PIVOT = (0, 1.145, .08)
LANDMINE_LENGTH = 1.94
LANDMINE_GRIP_RADIUS = 1.47


def _api():
    import motions
    from mathutils import Quaternion, Vector
    return motions, Quaternion, Vector


def _palm_length(rig, label):
    rest = rig.data.bones
    return (rest["middle_01_" + label].head_local - rest["hand_" + label].head_local).length * .97


def _axis_grip(rig, label, palm, pole, handle_axis, supinated=False):
    """Exact connected IK in the plane perpendicular to a real handle axis.

    A rotated landmine handle is not a world-X bar. Project the shoulder and
    the pole into its own grip plane and keep actual upper-arm length exact.
    """
    m, _, V = _api()
    rest = rig.data.bones
    target, axis = V(palm), V(handle_axis).normalized()
    shoulder = rig.pose.bones["upperarm_" + label].head.copy()
    offset = (shoulder - target).dot(axis)
    if abs(offset) >= rest["upperarm_" + label].length:
        raise ValueError("Handle grip plane lies outside upper-arm reach")
    projected = shoulder - axis * offset
    upper = math.sqrt(rest["upperarm_" + label].length ** 2 - offset ** 2)
    lower = rest["lowerarm_" + label].length + _palm_length(rig, label)
    pole = V(pole) - axis * (V(pole) - target).dot(axis)
    elbow, achieved = m.two_bone(projected, target, upper, math.hypot(lower, .012), pole)
    if (achieved - target).length > .00001:
        raise ValueError("Unreachable exact handle/palm target: " + label)
    combined = (target - elbow).normalized()
    normal_axis = axis.cross(combined) * (-1 if supinated else 1)
    angle = math.atan2(.012, lower)
    forward = combined * math.cos(angle) - normal_axis * math.sin(angle)
    normal = combined * math.sin(angle) + normal_axis * math.cos(angle)
    wrist = elbow + forward * rest["lowerarm_" + label].length
    m.point(rig, "upperarm_" + label, shoulder, elbow)
    m.pronated_forearm(rig, label, elbow, wrist, normal)
    contact = m.hand(rig, label, wrist, forward, normal, True)
    if (contact["palm"] - target).length > .00001:
        raise ValueError("Native palm/handle target mismatch")
    return contact


def _legs(rig, anchors=None, pole_y=-.6, foot_rotation=None):
    m, Q, V = _api()
    rest = rig.data.bones
    for side, label in ((1, "l"), (-1, "r")):
        target = V(anchors[label]) if anchors else rest["foot_" + label].head_local.copy()
        hip = rig.pose.bones["thigh_" + label].head.copy()
        knee, endpoint = m.two_bone(hip, target, rest["thigh_" + label].length,
                                    rest["calf_" + label].length, V((side * .25, pole_y, hip.z - .2)))
        if (endpoint - target).length > .00001:
            raise ValueError("Fixed sole target is unreachable: " + label)
        m.point(rig, "thigh_" + label, hip, knee)
        m.point(rig, "calf_" + label, knee, endpoint)
        m.bone_rotation(rig, "foot_" + label, endpoint, foot_rotation or Q((1, 0, 0), 0))


def _arm_fk(rig, label, upper, lower, normal, grip=True):
    m, _, V = _api()
    rest = rig.data.bones
    shoulder = rig.pose.bones["upperarm_" + label].head.copy()
    elbow = shoulder + V(upper).normalized() * rest["upperarm_" + label].length
    direction = V(lower).normalized()
    wrist = elbow + direction * rest["lowerarm_" + label].length
    m.point(rig, "upperarm_" + label, shoulder, elbow)
    m.pronated_forearm(rig, label, elbow, wrist, normal)
    return m.hand(rig, label, wrist, direction, normal, grip)


def landmine_frame(amount):
    _, _, V = _api()
    angle = math.radians(10.33 + 14.67 * amount)
    axis = V((0, -math.cos(angle), math.sin(angle)))
    upper = V((0, math.sin(angle), math.cos(angle)))
    pivot = V(LANDMINE_PIVOT)
    return pivot, axis, pivot + axis * LANDMINE_GRIP_RADIUS + upper * .055


def _rack(rig, amount):
    m, Q, V = _api()
    rest = rig.data.bones
    depth = 1 - amount
    m.torso(rig, m.hip_center(rig) + V((0, .16 * depth, -.17 * depth)), Q((1, 0, 0), math.radians(37 * depth)))
    _legs(rig)
    shoulder = rig.pose.bones["upperarm_l"].head.copy()
    grip_x, y = .224, -.27
    upper = math.sqrt(rest["upperarm_l"].length ** 2 - (grip_x - shoulder.x) ** 2)
    lower = math.hypot(rest["lowerarm_l"].length + _palm_length(rig, "l"), .012)
    z = shoulder.z - math.sqrt((upper + lower - .000101) ** 2 - (y - shoulder.y) ** 2)
    contacts = {"rack_bar_center": V((0, y, z)), "motion_amount": amount}
    for side, label in ((1, "l"), (-1, "r")):
        contacts[label] = _axis_grip(rig, label, (side * grip_x, y, z),
                                    (side * grip_x, y + .4, z + .2), (1, 0, 0))
    return contacts


def _landmine(rig, amount):
    m, Q, V = _api()
    rest = rig.data.bones
    ankle = rest["foot_l"].head_local
    hip_y = .23
    lateral = rest["thigh_l"].head_local.x - ankle.x
    hip_z = ankle.z + math.sqrt(.800 ** 2 - lateral ** 2 - (hip_y - ankle.y) ** 2)
    lean = Q((1, 0, 0), math.radians(65))
    m.torso(rig, V((0, hip_y, hip_z)), lean)
    _legs(rig)
    for side, label in ((1, "l"), (-1, "r")):
        clavicle = rig.pose.bones["clavicle_" + label]
        m.bone_rotation(rig, "clavicle_" + label, clavicle.head.copy(),
                        Q((0, 0, 1), math.radians(-side * 5 * amount)) @ lean)
    pivot, axis, centre = landmine_frame(amount)
    contacts = {"landmine_pivot": pivot, "landmine_axis": axis, "motion_amount": amount}
    for side, label in ((1, "l"), (-1, "r")):
        palm = centre + V((side * .195, 0, 0))
        shoulder = rig.pose.bones["upperarm_" + label].head.copy()
        contacts[label] = _axis_grip(rig, label, palm, shoulder + V((side * .35, .4, -.1)), axis * -side)
    return contacts


def _upright(rig, amount):
    m, Q, V = _api()
    m.torso(rig, m.hip_center(rig), Q((1, 0, 0), 0))
    _legs(rig)
    shoulder = rig.pose.bones["upperarm_l"].head.copy()
    contacts = {"motion_amount": amount}
    # A wide grip allows the upper arms to move outward while the whole
    # forearm/metacarpal chain stays unbent and the bar stays below shoulders.
    grip_x = .30
    centre = V((0, -.20, .78 + .15 * amount))
    for side, label in ((1, "l"), (-1, "r")):
        pole = (side * grip_x, shoulder.y - .4, shoulder.z + .10)
        contacts[label] = _axis_grip(rig, label, centre + V((side * grip_x, 0, 0)), pole, (1, 0, 0))
    return contacts


def phase(exercise_id, seconds):
    m, _, _ = _api()
    if exercise_id != "rack_pull":
        return m.cycle(seconds)
    def ease(value):
        return value * value * (3 - 2 * value)
    if seconds < .7:
        return 0.
    if seconds < 1.8:
        return ease((seconds - .7) / 1.1)
    if seconds < 2.1:
        return 1.
    if seconds < 3.3:
        return 1 - ease((seconds - 2.1) / 1.2)
    return 0.


def pose(rig, exercise_id, amount):
    if exercise_id not in SUPPORTED or not 0 <= amount <= 1:
        raise ValueError("Missing exact remaining strength motion or invalid phase: " + exercise_id)
    _api()[0].reset(rig)
    return {"rack_pull": _rack, "tbar_row": _landmine, "upright_row": _upright}[exercise_id](rig, amount)


def audit(rows, exercise_id):
    import technique as t
    if exercise_id not in SUPPORTED or not rows:
        return {"passed": False, "failures": ["Missing exact remaining strength frames"]}
    metrics, failures = {}, []
    def check(value, name, low, high):
        metrics[name] = value
        if not low <= value <= high:
            failures.append(name + " outside this authored variant")
    check(t.connected_joint_gap(rows), "connected_joint_max_gap_m", 0, .0001)
    for bone in FIXED_CONTACTS[exercise_id]:
        check(max(t.length(t.subtract(t.joint(row, bone, part), t.joint(rows[0], bone, part)))
                  for row in rows for part in ("head", "tail")), bone + "_max_drift_m", 0, .0001)
    for label in ("l", "r"):
        check(max(t.angle_degrees(t.subtract(t.joint(row, "middle_01_" + label), t.joint(row, "hand_" + label)),
                                 t.subtract(t.joint(row, "lowerarm_" + label, "tail"), t.joint(row, "lowerarm_" + label)))
                  for row in rows), "neutral_wrist_" + label + "_max_error_deg", 0, .01)
    first, peak = min(rows, key=lambda row: row["amount"]), max(rows, key=lambda row: row["amount"])
    if exercise_id == "rack_pull":
        for label in ("l", "r"):
            check(max(t.bend_degrees(row, "upperarm_" + label, "lowerarm_" + label) for row in rows), "straight_arm_" + label + "_max_bend_deg", 0, 6)
        check(t.joint(peak, "hand_l")[2] - t.joint(first, "hand_l")[2], "bar_lift_height_m", .10, .50)
        check(abs(t.joint(first, "hand_l")[2] - t.joint(first, "calf_l")[2]), "initial_wrist_to_knee_height_difference_m", 0, .14)
    else:
        for bone in ("pelvis", "spine_01", "spine_02", "spine_03", "head"):
            check(max(t.length(t.subtract(t.joint(row, bone, part), t.joint(first, bone, part)))
                      for row in rows for part in ("head", "tail")), "stable_" + bone + "_max_drift_m", 0, .0001)
    if exercise_id == "upright_row":
        for label in ("l", "r"):
            check(max(t.angle_degrees(t.subtract(t.joint(row, "upperarm_" + label, "tail"), t.joint(row, "upperarm_" + label)), (0, 0, -1))
                      for row in rows), "upperarm_" + label + "_maximum_elevation_deg", 50, 89.5)
            check(t.joint(peak, "lowerarm_" + label)[2] - t.joint(peak, "hand_" + label)[2], "peak_elbow_" + label + "_above_wrist_m", .02, .35)
    if exercise_id == "tbar_row":
        for label in ("l", "r"):
            check(t.bend_degrees(first, "upperarm_" + label, "lowerarm_" + label), "initial_elbow_" + label + "_bend_deg", 0, 12)
            check(t.bend_degrees(peak, "upperarm_" + label, "lowerarm_" + label), "peak_elbow_" + label + "_bend_deg", 65, 140)
    return {"exercise_id": exercise_id, "metrics": metrics, "passed": not failures,
            "failures": failures, "scope": "Selected model geometry guards; trainer review pending",
            "trainerApproved": False, "humanTrainerApproval": False}
