"""Original wheel rollout, two forward walking lunges and full burpee sequence.

These exact variants are independently authored. Primary movement cues and
selected model ranges are separate; all demonstrations await trainer review.
"""
import math

SUPPORTED = ("ab_wheel", "burpee", "walking_lunge")
REGIONS = {"ab_wheel": ("abs", "erectors"), "burpee": ("quadriceps", "glutes", "chest", "triceps"),
           "walking_lunge": ("quadriceps", "glutes", "hamstrings")}
FIXED_CONTACTS = {"ab_wheel": ("calf_l", "calf_r", "foot_l", "foot_r"), "burpee": (), "walking_lunge": ()}
CYCLE_TRANSLATION = {"walking_lunge": (0, -1.72, 0)}
VIEWS = {
    "ab_wheel": {"location": (4.8, -2.2, .65), "target": (0, -.35, .43), "ortho_scale": 2.65},
    "burpee": {"location": (4.5, -4.0, 2.3), "target": (0, .10, 1.15), "ortho_scale": 3.15},
    "walking_lunge": {"location": (4.6, -4.0, 2.3), "target": (0, -.28, .94), "ortho_scale": 2.8, "track_root": True},
}
POSE_SECONDS = {"walking_lunge": {"start": 0, "middle": .65, "peak": .912},
                "burpee": {"start": 0, "middle": 1.672, "peak": 3.116}}
REFERENCES = {
    "ab_wheel": {"variant": "Kneeling closed-grip ab wheel rollout, selected comfortable range with braced trunk",
        "references": ["https://www.nsca.com/globalassets/education/tsac-report/tsac-report-55.pdf"],
        "reference_scope": "NSCA TSAC Report 55 printed p17 supplies wheel handles, extended arms, supported knees, posterior pelvic tilt and controlled rollout/return. The selected comfortable range stops before a maximal rollout.",
        "reference_cues": ["Knees supported", "Closed wheel-handle grip", "Arms remain extended", "Brace trunk and retain posterior pelvic tilt", "Controlled rollout and return"],
        "trainerApproved": False, "values_are_not_universal_prescriptions": True},
    "burpee": {"variant": "Burpee including a push-up, simultaneous backward/forward foot jump, overhead jump and soft landing",
        "references": ["https://www.nasm.org/resource-center/exercise-library/squat-thrust-burpees"],
        "reference_scope": "NASM Squat Thrust Burpees explicitly supplies floor hands, feet back, one push-up, feet forward, overhead jump and bent-knee landing. Transitions and jump height are original model choices.",
        "reference_cues": ["Hands support the floor", "Jump both feet back", "Perform a controlled push-up", "Jump both feet toward hands", "Jump overhead", "Land with bent knees"],
        "trainerApproved": False, "values_are_not_universal_prescriptions": True},
    "walking_lunge": {"variant": "Two alternating forward walking lunges with dumbbells at the sides; actual forward travel",
        "references": ["https://dxpprod.nsca.com/contentassets/24dd7222ed1b4caeb8a0a46b81bd11f3/ptq-4.4.9-the-undervalued-lunge.pdf"],
        "reference_scope": "NSCA PTQ 4.4 printed pp44-46 supplies upright braced lunge, forward knee/toe alignment, rear heel raised, controlled lowering and walking/dumbbell progressions. The two-step clip and stride lengths are selected model choices.",
        "reference_cues": ["Alternate forward steps", "Upright braced trunk", "Front foot fixed during lowering", "Rear heel raised", "Controlled knee flexion", "Dumbbells remain at sides"],
        "trainerApproved": False, "values_are_not_universal_prescriptions": True},
}


def _api():
    import motions as m
    from mathutils import Quaternion, Vector
    return m, Quaternion, Vector


def _ease(value):
    value = min(1, max(0, value))
    return value * value * (3 - 2 * value)


def phase(exercise_id, seconds):
    import motions
    return min(1, max(0, seconds / 3.8)) if exercise_id in ("burpee", "walking_lunge") else motions.cycle(seconds)


def _leg(rig, label, ankle, pole, foot_rotation):
    from bodyweight_motions import _leg as solve
    solve(rig, label, ankle, pole, foot_rotation)


def _wheel(rig, amount):
    m, Q, V = _api()
    from remaining_cable_motions import _kneel, _fk
    _kneel(rig)
    knees = {label: rig.pose.bones["calf_" + label].head.copy() for label in ("l", "r")}
    ankles = {label: rig.pose.bones["calf_" + label].tail.copy() for label in ("l", "r")}
    rest = rig.data.bones
    thigh = math.radians(45 * amount)
    lean = math.radians(56 + 28 * amount)
    hip = V((0, -math.sin(thigh) * rest["thigh_l"].length, knees["l"].z + math.cos(thigh) * rest["thigh_l"].length))
    m.torso(rig, hip, Q((1, 0, 0), lean))
    for label in ("l", "r"):
        m.point(rig, "thigh_" + label, rig.pose.bones["thigh_" + label].head.copy(), knees[label])
        m.point(rig, "calf_" + label, knees[label], ankles[label])
        m.bone_rotation(rig, "foot_" + label, ankles[label], Q((1, 0, 0), math.pi))
        ball = rig.pose.bones["foot_" + label].tail.copy()
        m.point(rig, "ball_" + label, ball, ball + V((0, rest["ball_" + label].length, 0)))
    contacts = {}
    for label in ("l", "r"):
        shoulder = rig.pose.bones["upperarm_" + label].head.copy()
        length = rest["upperarm_" + label].length + rest["lowerarm_" + label].length + .97 * (rest["middle_01_" + label].head_local - rest["hand_" + label].head_local).length
        ratio = (shoulder.z - .13 / rig.scale.x) / math.hypot(length, .012)
        if not -1 <= ratio <= 1:
            raise ValueError("Wheel start is outside the athlete's actual straight-arm reach")
        angle = math.atan2(.012, length) + math.acos(ratio)
        direction = (0, -math.sin(angle), -math.cos(angle))
        contacts[label] = _fk(rig, label, direction, direction, (0, math.cos(angle), -math.sin(angle)))
    contacts["wheel_radius_m"] = .13
    return contacts


def _walking(rig, amount):
    m, Q, V = _api()
    from bodyweight_motions import _dumbbells
    rest = rig.data.bones
    index = min(1, int(amount * 2))
    local = amount * 2 - index
    base = -.86 * index
    step = _ease(local / .22)
    depth = _ease((local - .22) / .26) if local < .48 else 1 - _ease((local - .48) / .26)
    advance = _ease((local - .55) / .45)
    trail = _ease((local - .60) / .40)
    y = base - .50 * step - .36 * advance
    progress = V((0, y, 0))
    root = rig.pose.bones["Root"].matrix.copy()
    root.translation = progress
    rig.pose.bones["Root"].matrix = root
    m.update()
    m.torso(rig, V((0, y, m.hip_center(rig).z - .110 * step - .2626 * depth + .110 * advance)), Q((1, 0, 0), 0))
    leading = "l" if index == 0 else "r"
    for label in ("l", "r"):
        side = 1 if label == "l" else -1
        if label == leading:
            ankle = rest["calf_" + label].tail_local.copy()
            ankle.y += base - .86 * step
            ankle.z += .12 * math.sin(math.pi * step)
            rotation = Q((1, 0, 0), 0)
            pole = V((side * .17, base - .90, .20))
        else:
            rotation = Q((1, 0, 0), math.radians(40 * step * (1 - trail)))
            ball = rest["ball_" + label].head_local.copy()
            ball.y += base - .86 * trail
            ball.z += .034 * step * (1 - trail) + .12 * math.sin(math.pi * trail)
            ankle = ball - rotation @ (rest["foot_" + label].tail_local - rest["foot_" + label].head_local)
            pole = V((side * .17, y - .20, .16))
        _leg(rig, label, ankle, pole, rotation)
    if local <= 1e-9 or local >= 1 - 1e-9:
        m.legs(rig, {label: rest["calf_" + label].tail_local + progress for label in ("l", "r")}, pole_y=y - .6)
    contacts = _dumbbells(rig)
    contacts["root_translation"] = progress
    contacts["walking_step"] = {"index": index, "local": local, "leading": leading,
                                 "front_planted": local >= .22, "rear_planted": .22 <= local <= .60}
    return contacts


def _free_hands(rig, elevation=0):
    m, _, V = _api()
    from remaining_cable_motions import _fk
    angle = math.radians(170 * elevation)
    return {label: _fk(rig, label, (side * .24, -math.sin(angle), -math.cos(angle)),
                      (side * .24, -math.sin(angle), -math.cos(angle)), (-side, 0, 0), False)
            for side, label in ((1, "l"), (-1, "r"))}


def _floor_hands(rig):
    m, _, V = _api()
    contacts = {}
    for side, label in ((1, "l"), (-1, "r")):
        contacts[label] = m.arm(rig, label, V((side * .32, -.40, .032)), V((side * .52, -.15, .18)), V((0, -1, 0)), V((0, 0, -1)), False)
        m.floor_hand(rig, label)
    return contacts


def _crouch(rig, depth, hand_support=False):
    m, Q, V = _api()
    rest = rig.data.bones
    m.torso(rig, V((0, .06 * depth, m.hip_center(rig).z + (.26 - m.hip_center(rig).z) * depth)), Q((1, 0, 0), math.radians(65 * depth)))
    for side, label in ((1, "l"), (-1, "r")):
        hip_z = rig.pose.bones["thigh_" + label].head.z
        pole = V((side * (.20 - .03 * depth), -.60 - .10 * depth, (hip_z - .20) * (1 - depth) + .15 * depth))
        _leg(rig, label, rest["calf_" + label].tail_local.copy(), pole, Q((1, 0, 0), 0))
    if hand_support:
        return _floor_hands(rig)
    contacts = _free_hands(rig)
    if depth > 0:
        for side, label in ((1, "l"), (-1, "r")):
            shoulder = rig.pose.bones["upperarm_" + label].head.copy()
            natural = contacts[label]["wrist"]
            floor = V((side * .32, -.40, .032))
            direction = (natural - shoulder).normalized().lerp((floor - shoulder).normalized(), depth).normalized()
            span = rig.data.bones["upperarm_" + label].length + rig.data.bones["lowerarm_" + label].length
            distance = min(span - .0002, (1 - depth) * (span - .0002) + depth * (floor - shoulder).length)
            target = shoulder + direction * distance
            # Lift the approaching palm in a small arc before its fixed
            # planted pose; this clears actual thumb skin near the floor.
            target.z += .010 * math.sin(math.pi * depth)
            if depth < .001:
                continue
            orientation = _ease(depth / .8)
            forward = V((side * .15 * (1 - orientation), -orientation, -(1 - orientation))).normalized()
            normal = V((-side * (1 - orientation), 0, -orientation))
            contacts[label] = m.arm(rig, label, target, V((side * .52, -.15, .18)), forward, normal, False)
            m.floor_hand(rig, label)
    return contacts


def _pushup_geometry(rig, depth, transition=None):
    m, Q, V = _api()
    rest = rig.data.bones
    lean = math.radians(73 + 11 * depth)
    full = rest["thigh_l"].length + rest["calf_l"].length - .0005
    lateral = rest["calf_l"].tail_local.x - rest["thigh_l"].head_local.x
    planar = math.sqrt(full * full - lateral * lateral)
    hip = V((0, .84 - math.sin(lean) * planar, .145 + math.cos(lean) * planar))
    if transition is not None:
        u = transition
        hip = V((0, .06, .26)).lerp(hip, u) + V((0, 0, .20 * math.sin(math.pi * u)))
        lean = math.radians(65 + 8 * u + 19 * math.sin(math.pi * u))
    m.torso(rig, hip, Q((1, 0, 0), lean))
    for side, label in ((1, "l"), (-1, "r")):
        target = V((rest["calf_" + label].tail_local.x, .84, .145))
        if transition is not None:
            target = rest["calf_" + label].tail_local.lerp(target, transition)
            target.z += .08 * math.sin(math.pi * transition)
        rotation = Q((1, 0, 0), math.radians(60 * (1 if transition is None else transition)))
        _leg(rig, label, target, V((side * .17, -.70, .15)), rotation)
        ball = rig.pose.bones["foot_" + label].tail.copy()
        m.bone_rotation(rig, "ball_" + label, ball, Q((1, 0, 0), 0))
    return _floor_hands(rig)


def _burpee(rig, amount):
    m, Q, V = _api()
    if amount < .06:
        contacts = _crouch(rig, 0)
        segment = "standing"
    elif amount < .24:
        contacts = _crouch(rig, _ease((amount - .06) / .18))
        segment = "squat_to_hands"
    elif amount < .34:
        contacts = _pushup_geometry(rig, 0, _ease((amount - .24) / .10))
        segment = "feet_backward"
    elif amount < .44:
        contacts = _pushup_geometry(rig, _ease((amount - .34) / .10))
        segment = "pushup_down"
    elif amount < .54:
        contacts = _pushup_geometry(rig, 1 - _ease((amount - .44) / .10))
        segment = "pushup_up"
    elif amount < .64:
        contacts = _pushup_geometry(rig, 0, 1 - _ease((amount - .54) / .10))
        segment = "feet_forward"
    elif amount < .76:
        depth = 1 - _ease((amount - .64) / .12)
        contacts = _crouch(rig, depth)
        raised = _free_hands(rig, 1 - depth)
        if depth < .001:
            contacts = raised
        else:
            for side, label in ((1, "l"), (-1, "r")):
                target = V((side * .32, -.40, .032)).lerp(raised[label]["wrist"], 1 - depth)
                shoulder = rig.pose.bones["upperarm_" + label].head.copy()
                span = rig.data.bones["upperarm_" + label].length + rig.data.bones["lowerarm_" + label].length
                if (target - shoulder).length > span - .0002:
                    target = shoulder + (target - shoulder).normalized() * (span - .0002)
                orientation = _ease((1 - depth - .15) / .85)
                forward = V((0, -1, 0)).lerp(raised[label]["forward"], orientation).normalized()
                normal = V((0, 0, -1)).lerp(raised[label]["normal"], orientation)
                contacts[label] = m.arm(rig, label, target, V((side * .52, -.15, .18)), forward, normal, False)
        segment = "jump_drive"
    elif amount < .88:
        u = (amount - .76) / .12
        height = .15 * math.sin(math.pi * u)
        absorption = .12 * _ease((u - .65) / .35)
        m.torso(rig, V((0, 0, m.hip_center(rig).z + height - absorption)), Q((1, 0, 0), 0))
        anchors = {label: rig.data.bones["calf_" + label].tail_local + V((0, 0, height)) for label in ("l", "r")}
        m.legs(rig, anchors)
        contacts = _free_hands(rig, 1)
        segment = "jump_flight"
    else:
        u = (amount - .88) / .12
        drop = .12 * (1 - _ease(u)) + .02 * math.sin(math.pi * u)
        m.torso(rig, V((0, 0, m.hip_center(rig).z - drop)), Q((1, 0, 0), 0))
        m.legs(rig)
        contacts = _free_hands(rig, 1 - _ease(u))
        segment = "soft_landing"
    contacts["burpee_segment"] = segment
    return contacts


def pose(rig, exercise_id, amount):
    m, _, _ = _api()
    if exercise_id not in SUPPORTED:
        raise ValueError("No authored remaining bodyweight motion: " + exercise_id)
    m.reset(rig)
    return {"ab_wheel": _wheel, "walking_lunge": _walking, "burpee": _burpee}[exercise_id](rig, min(1, max(0, amount)))


def audit(rows, exercise_id):
    import technique as t
    def p(row, name, part="head"):
        return row["bones"][name][part]
    failures = []
    metrics = {}
    if exercise_id == "ab_wheel":
        elbows = [t.bend_degrees(row, "upperarm_" + label, "lowerarm_" + label) for row in rows for label in ("l", "r")]
        metrics["maximum_elbow_bend_deg"] = max(elbows)
        if max(elbows) > .1:
            failures.append("Wheel rollout flexes elbows rather than maintaining straight arms")
        peak = max(rows, key=lambda row: row["amount"])
        metrics["peak_trunk_above_horizontal_deg"] = 90 - t.angle_degrees((0, 0, 1), t.subtract(p(peak, "spine_03", "tail"), p(peak, "spine_03")))
        metrics["wheel_grip_forward_travel_m"] = p(rows[0], "middle_01_l")[1] - p(peak, "middle_01_l")[1]
        if metrics["wheel_grip_forward_travel_m"] < .50:
            failures.append("Wheel rollout lacks actual forward rolling travel")
    elif exercise_id == "walking_lunge":
        metrics["net_pelvis_forward_m"] = p(rows[-1], "pelvis")[1] - p(rows[0], "pelvis")[1]
        stance = []
        for index, label in ((0, "l"), (1, "r")):
            selected = [row for row in rows if index + .22 <= row["amount"] * 2 <= index + 1]
            stance.extend(math.dist(p(row, "foot_" + label), p(selected[0], "foot_" + label)) for row in selected)
        metrics["maximum_planted_front_foot_drift_m"] = max(stance, default=0)
        rear_drift = []
        for index, label in ((0, "r"), (1, "l")):
            selected = [row for row in rows if index + .22 <= row["amount"] * 2 <= index + .60]
            rear_drift.extend(math.dist(p(row, "ball_" + label), p(selected[0], "ball_" + label)) for row in selected)
        metrics["maximum_planted_rear_forefoot_drift_m"] = max(rear_drift, default=0)
        if metrics["maximum_planted_front_foot_drift_m"] > .0001:
            failures.append("Walking lunge slides its planted leading foot")
        if metrics["maximum_planted_rear_forefoot_drift_m"] > .0001:
            failures.append("Walking lunge slides its planted rear forefoot")
        if metrics["net_pelvis_forward_m"] > -1.7:
            failures.append("Walking lunge lacks actual two-step forward progression")
        bottoms = [row for row in rows if abs((row["amount"] * 2) % 1 - .48) < .025]
        metrics["bottom_knee_bends_deg"] = [{label: t.bend_degrees(row, "thigh_" + label, "calf_" + label) for label in ("l", "r")} for row in bottoms]
        if any(not 70 <= angle <= 105 for item in metrics["bottom_knee_bends_deg"] for angle in item.values()):
            failures.append("Walking lunge bottom flexion exceeds the selected near-right-angle range")
    else:
        supported = [row for row in rows if .24 <= row["amount"] <= .64]
        drift = max((math.dist(p(row, "hand_" + label), p(supported[0], "hand_" + label)) for row in supported for label in ("l", "r")), default=0)
        metrics["supported_wrist_drift_m"] = drift
        if drift > .0001:
            failures.append("Burpee moves hands while they support the body")
        push = [row for row in rows if .34 <= row["amount"] <= .54]
        metrics["pushup_shoulder_descent_m"] = max((p(row, "upperarm_l")[2] for row in push), default=0) - min((p(row, "upperarm_l")[2] for row in push), default=0)
        if len(push) > 2 and metrics["pushup_shoulder_descent_m"] < .1:
            failures.append("Burpee lacks an actual push-up descent")
        landing = [row for row in rows if .88 <= row["amount"] <= .91]
        metrics["landing_knee_bends_deg"] = [t.bend_degrees(row, "thigh_" + label, "calf_" + label) for row in landing for label in ("l", "r")]
        if landing and min(metrics["landing_knee_bends_deg"]) < 35:
            failures.append("Burpee lands with straight knees")
        jumping = [row for row in rows if .76 <= row["amount"] <= .88]
        overhead = max((min(p(row, "middle_01_" + label)[2] - p(row, "head", "tail")[2] for label in ("l", "r")) for row in jumping), default=0)
        metrics["jump_hands_above_head_m"] = overhead
        if jumping and overhead < .10:
            failures.append("Burpee jump lacks overhead reaching")
    return {"exercise_id": exercise_id, "passed": not failures, "failures": failures, "metrics": metrics,
            "trainerApproved": False, "review_status": "trainer_pending", "scope": "Selected original model guards; not technique certification"}
