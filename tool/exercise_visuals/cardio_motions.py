"""Original exact walking, treadmill running, bounce rope and stepmill cycles.

Primary sources supply technique cues. Cadence, stride and machine dimensions
are selected for this rig; these are teaching drafts awaiting trainer review.
"""
import json
import math

SUPPORTED = ("brisk_walk", "run", "jump_rope", "stair_climber")
REGIONS = {"brisk_walk": ("quadriceps", "glutes", "calves"),
           "run": ("quadriceps", "glutes", "hamstrings", "calves"),
           "jump_rope": ("calves", "quadriceps", "abs"),
           "stair_climber": ("quadriceps", "glutes", "calves")}
FIXED_CONTACTS = {"brisk_walk": (), "run": (), "jump_rope": (), "stair_climber": ()}
CYCLE_TRANSLATION = {"brisk_walk": (0, -4.64, 0)}
VIEWS = {
    "brisk_walk": {"location": (4.8, -2.3, 1.8), "target": (0, -.12, 1.01), "ortho_scale": 2.45, "track_root": True},
    "run": {"location": (4.8, -2.4, 2.5), "target": (0, -.12, 1.18), "ortho_scale": 3.05},
    "jump_rope": {"location": (4.8, -3.0, 2.0), "target": (0, 0, 1.11), "ortho_scale": 2.95},
    "stair_climber": {"location": (4.8, 3.6, 2.8), "target": (0, -.26, 1.40), "ortho_scale": 3.60},
}
POSE_SECONDS = {"brisk_walk": {"start": 0, "middle": .20, "peak": .70},
                "run": {"start": 0, "middle": .125, "peak": .275},
                "jump_rope": {"start": 0, "middle": .125, "peak": .25},
                "stair_climber": {"start": 0, "middle": .40, "peak": .75}}
REFERENCES = {
    "brisk_walk": {"variant": "Forward ground brisk walking with heel-to-toe roll and opposite arm swing",
        "references": ["https://contentcdn.eacefitness.com/assets/about-ace/advocacy/Walking_Toolkit_Community.pdf"],
        "reference_scope": "ACE Walking Toolkit printed pp9 and16 supplies continuous ground contact, upright head/trunk, bent relaxed arms, neutral pelvis, forward knee/toe alignment and heel-to-toe roll. Free hands are lightly cupped without a loaded grip. Eight steps and model stride are original selected values.",
        "reference_cues": ["At least one foot supports the ground", "Heel-to-toe roll", "Upright torso", "Relaxed opposite arm swing"],
        "trainerApproved": False, "values_are_not_universal_prescriptions": True},
    "run": {"variant": "Level treadmill easy running with a moving belt and attached emergency-stop cord",
        "references": ["https://www.acefitness.org/resources/pros/expert-articles/5415/5-tips-for-optimizing-running-form/",
            "https://support.lifefitness.com/hc/en-us/articles/42814055083031-Life-Fitness-Atmos-Treadmill-How-to-Use-the-Emergency-Stop-and-Prevent-Child-Use"],
        "reference_scope": "ACE supplies soft under-hip contact, individual footstrike, approximately right-angle sagittal arm swing, relaxed shoulders and small ankle-based lean. Free hands are lightly cupped without holding rails. Life Fitness supplies clipping the emergency-stop cord to clothing. The original neutral machine is not a manufacturer replica; the clip shows established running, not the start/stop procedure.",
        "reference_cues": ["Land close beneath hips", "Soft bent-knee contact", "Hands do not hold rails", "Attached emergency-stop cord", "Actual belt-relative support"],
        "trainerApproved": False, "values_are_not_universal_prescriptions": True},
    "jump_rope": {"variant": "Two-foot basic bounce jump rope with small wrist circles and forefoot landing",
        "references": ["https://jumpropeinstitute.com/howto-htm/"],
        "reference_scope": "Jump Rope Institute coach-authored Basic Bounce and Correct Technique supplies closed handles, elbows near sides, small wrist circles, forward head, low jumps and light forefoot landing. The original rope and selected slowed cadence are not source media.",
        "reference_cues": ["Feet close together", "Elbows close to sides", "Small wrist circles", "Low two-foot bounce", "Light forefoot landing"],
        "trainerApproved": False, "values_are_not_universal_prescriptions": True},
    "stair_climber": {"variant": "Forward alternating climbing on a continuously rotating stepmill with lightly held rails",
        "references": ["https://fitnessengros.dk/media/c8/82/f7/1670237019/Owners%20Manual%20G8.pdf?ts=1727943233"],
        "reference_scope": "Manufacturer-authored Core Health & Fitness 8G Owner Manual 620-8297F, printed pp3,6-7, supplies forward-facing use, athletic shoes, stairs/handrails and step-rate operation. Manufacturer-hosted links were inaccessible, so the unchanged primary manual was read through a distributor mirror. Geometry is original generic stepmill, not a branded model; the supported upright stepping range follows the exact local guide.",
        "reference_cues": ["Face forward", "Alternate whole-foot treads", "Upright braced trunk", "Do not hang from rails", "Wait for complete stop before dismounting"],
        "trainerApproved": False, "values_are_not_universal_prescriptions": True},
}


def _api():
    import motions as m
    from mathutils import Quaternion, Vector
    return m, Quaternion, Vector


def _ease(value):
    value = min(1., max(0., value))
    return value * value * (3 - 2 * value)


def phase(exercise_id, seconds):
    return min(1., max(0., seconds / 3.8))


def _shoe(rig, label):
    """Read the actual original shoe's rest vertices captured by create()."""
    _, _, V = _api()
    data = json.loads(rig["cardio_original_sole_rest_json"])[label]
    ankle = rig.data.bones["foot_" + label].head_local
    ball = rig.data.bones["ball_" + label].head_local
    return V(data["heel"]) - ankle, V(data["forefoot"]) - ball, data["bounds"]


def _leg(rig, label, target, angle, ball_angle=0, pole_y=None):
    m, Q, V = _api()
    from bodyweight_motions import _leg as solve
    hip = rig.pose.bones["thigh_" + label].head.copy()
    pole = V((target.x, hip.y - .60 if pole_y is None else pole_y, hip.z - .10))
    solve(rig, label, target, pole, Q((1, 0, 0), angle))
    m.bone_rotation(rig, "ball_" + label, rig.pose.bones["foot_" + label].tail.copy(), Q((1, 0, 0), ball_angle))


def _ankle_for_contact(rig, label, anchor, angle, kind, ball_angle=0):
    _, Q, _ = _api()
    heel, fore, _ = _shoe(rig, label)
    rotation = Q((1, 0, 0), angle)
    if kind == "heel":
        return anchor - rotation @ heel
    delta = rig.data.bones["foot_" + label].tail_local - rig.data.bones["foot_" + label].head_local
    return anchor - rotation @ delta - Q((1, 0, 0), ball_angle) @ fore


def _arms(rig, gait, running=False):
    m, _, V = _api()
    from remaining_cable_motions import _fk
    contacts = {}
    for side, label in ((1, "l"), (-1, "r")):
        angle = math.radians((35 if running else 25) * (-1 if label == "l" else 1) * math.cos(2 * math.pi * gait))
        contacts[label] = _fk(rig, label, (0, -math.sin(angle), -math.cos(angle)),
            (0, -math.sin(angle + math.pi / 2), -math.cos(angle + math.pi / 2)), (-side, 0, 0), False)
        # Lightly cupped free hands instead of a spread-finger rest pose.
        # These original unloaded finger angles are not a closed load grip.
        forward, normal = contacts[label]["forward"], contacts[label]["normal"]
        for digit, offset in (("index", 0), ("middle", 4), ("ring", 8), ("pinky", 12)):
            for segment, degrees in ((1, 30 + offset), (2, 60 + offset), (3, 85 + offset)):
                name = digit + "_0" + str(segment) + "_" + label
                head = rig.pose.bones[name].head.copy()
                rotation = math.radians(degrees)
                direction = forward * math.cos(rotation) + normal * math.sin(rotation)
                m.point(rig, name, head, head + direction * rig.data.bones[name].length)
        name = "thumb_02_" + label
        head = rig.pose.bones[name].head.copy()
        m.point(rig, name, head, head + (forward + normal * .2).normalized() * rig.data.bones[name].length)
    return contacts


def _gait(rig, amount, running):
    m, Q, V = _api()
    cycles, stride = (6, .62) if running else (4, .58)
    total = cycles * amount
    progress = V((0, 0 if running else -2 * stride * total, 0))
    root = rig.pose.bones["Root"].matrix.copy()
    root.translation = progress
    rig.pose.bones["Root"].matrix = root
    m.update()
    gait = total % 1 if amount < 1 else 0.
    deck = .16 if running else 0.
    if running:
        half = (gait % .5) / .5
        if half < .72:
            z = .80 + .04 * _ease(half / .72)
        else:
            flight = (half - .72) / .28
            z = .84 + .065 * math.sin(math.pi * flight) - .04 * _ease(flight)
        hip = V((0, -.04, z + deck))
    else:
        hip = progress + V((0, 0, .8475 - .0275 * math.cos(4 * math.pi * gait)))
    # Include the real sole thickness rather than placing shoes below the
    # barefoot ankle. The local rest landmark is a sole surface vertex.
    heel, _, _ = _shoe(rig, "l")
    sole_lift = -heel.z - rig.data.bones["foot_l"].head_local.z
    hip.z += sole_lift
    m.torso(rig, hip, Q((1, 0, 0), math.radians(5 if running else 0)))
    states = {}
    for label, offset in (("l", 0.), ("r", .5)):
        unwrapped = total + offset
        index = math.floor(unwrapped + 1e-10)
        q = unwrapped - index
        heel, fore, _ = _shoe(rig, label)
        ankle_rest = rig.data.bones["foot_" + label].head_local
        ankle_x = (1 if label == "l" else -1) * (.12 if running else .13)
        landing = -(.065 if running else .30) + (0 if running else -2 * stride * index + 2 * stride * offset)
        belt = 2 * stride * total if running else 0.
        landing += belt - 2 * stride * index + 2 * stride * offset if running else 0.
        stance_end = .36 if running else .62
        stance = q <= stance_end + 1e-10
        if stance:
            if running:
                angle = math.radians(50 * _ease((q - .15) / .21))
                kind = "forefoot"
                anchor = V((ankle_x + (rig.data.bones["foot_" + label].tail_local - ankle_rest).x + fore.x,
                            landing + (rig.data.bones["foot_" + label].tail_local - ankle_rest).y + fore.y, deck + .0004))
            elif q < .12:
                angle = math.radians(-12 * (1 - _ease(q / .12)))
                kind = "heel"
                anchor = V((ankle_x + heel.x, landing + heel.y, .0004))
            else:
                angle = math.radians(40 * _ease((q - .48) / .14))
                kind = "forefoot" if q > .48 else "heel"
                offset_y = (rig.data.bones["foot_" + label].tail_local - ankle_rest).y + fore.y if kind == "forefoot" else heel.y
                offset_x = (rig.data.bones["foot_" + label].tail_local - ankle_rest).x + fore.x if kind == "forefoot" else heel.x
                anchor = V((ankle_x + offset_x, landing + offset_y, .0004))
            target = _ankle_for_contact(rig, label, anchor, angle, kind)
        else:
            u = (q - stance_end) / (1 - stance_end)
            angle = math.radians((50 if running else 40) * (1 - _ease(u)) - (0 if running else 12) * _ease(u))
            toeoff_angle = math.radians(50 if running else 40)
            toeoff_anchor = V((ankle_x + (rig.data.bones["foot_" + label].tail_local - ankle_rest).x + fore.x,
                                landing + (rig.data.bones["foot_" + label].tail_local - ankle_rest).y + fore.y, deck + .0004))
            start = _ankle_for_contact(rig, label, toeoff_anchor, toeoff_angle, "forefoot")
            end_anchor = V((ankle_x + heel.x, landing - 2 * stride + heel.y, deck + .0004))
            end = _ankle_for_contact(rig, label, end_anchor, 0 if running else math.radians(-12), "heel")
            target = start.lerp(end, _ease(u))
            target.z += (.34 if running else .105) * math.sin(math.pi * u)
            kind, anchor = "air", None
        _leg(rig, label, target, angle)
        states[label] = {"q": q, "index": index, "stance": stance, "contact": kind,
                         "anchor": list(anchor) if anchor is not None else None}
    contacts = _arms(rig, gait, running)
    contacts["cardio"] = {"gait": gait, "feet": states, "belt_progress_native": 2 * stride * total if running else 0.}
    if not running:
        contacts["root_translation"] = progress
    return contacts


def _rope(rig, amount):
    m, Q, V = _api()
    from strength_motions import _neutral_palm
    q = (6 * amount) % 1 if amount < 1 else 0.
    height = .065 * max(0., math.sin(2 * math.pi * (q - .20)))
    loaded = .030 * (1 - max(0., math.sin(2 * math.pi * (q - .20))))
    m.torso(rig, V((0, 0, .910 + height - loaded)), Q((1, 0, 0), 0))
    states = {}
    for side, label in ((1, "l"), (-1, "r")):
        _, fore, _ = _shoe(rig, label)
        rest = rig.data.bones
        angle = math.radians(12)
        anchor = V((side * .13 + (rest["foot_" + label].tail_local - rest["foot_" + label].head_local).x + fore.x, -.13, .0004 + height))
        target = _ankle_for_contact(rig, label, anchor, angle, "forefoot")
        _leg(rig, label, target, angle)
        states[label] = {"stance": height <= .0001, "contact": "forefoot" if height <= .0001 else "air", "q": q,
                         "anchor": list(anchor) if height <= .0001 else None}
    contacts = {}
    for side, label in ((1, "l"), (-1, "r")):
        target = V((side * .34, -.21 + .004 * math.sin(2 * math.pi * q), 1.03 + .004 * math.cos(2 * math.pi * q)))
        contacts[label] = _neutral_palm(rig, label, target, V((side * .34, .12, 1.12)), V((-side, 0, 0)))
    contacts["cardio"] = {"gait": q, "feet": states, "rope_angle": 2 * math.pi * (q - .45)}
    return contacts


def _stairs(rig, amount):
    m, Q, V = _api()
    from strength_motions import _neutral_palm
    total = 2 * amount
    gait = total % 1 if amount < 1 else 0.
    m.torso(rig, V((0, -.12, 1.43 + .010 * math.sin(4 * math.pi * gait))), Q((1, 0, 0), 0))
    states = {}
    for label, offset in (("l", 0.), ("r", .5)):
        u = total + offset
        index = math.floor(u + 1e-10)
        q = u - index
        tread = 2 * index + (3 if label == "l" else 2)
        relative = tread - 2 * total
        center = V((rig.data.bones["foot_" + label].head_local.x, .60 - .30 * relative, .25 + .18 * relative))
        heel, _, bounds = _shoe(rig, label)
        rest_ankle = rig.data.bones["foot_" + label].head_local
        center.y -= (bounds["min_y"] + bounds["max_y"]) / 2 - rest_ankle.y
        anchor = center + V((heel.x, heel.y, .0004))
        if q <= .55:
            target = _ankle_for_contact(rig, label, anchor, 0, "heel")
            stance = True
        else:
            v = (q - .55) / .45
            new_center = center + V((0, -.60, .36))
            new_anchor = new_center + V((heel.x, heel.y, .0004))
            start = _ankle_for_contact(rig, label, anchor, 0, "heel")
            end = _ankle_for_contact(rig, label, new_anchor, 0, "heel")
            advance = _ease((v - .20) / .60)
            target = start.lerp(end, advance) + V((0, 0, .25 * math.sin(math.pi * v)))
            stance = False
        _leg(rig, label, target, 0)
        states[label] = {"q": q, "index": index, "tread": tread, "stance": stance, "contact": "heel" if stance else "air",
                         "anchor": list(anchor) if stance else None}
    contacts = {}
    for side, label in ((1, "l"), (-1, "r")):
        target = V((side * .36, -.35, 1.59))
        contacts[label] = _neutral_palm(rig, label, target, V((side * .36, .05, 1.55)), V((-side, 0, 0)))
    contacts["cardio"] = {"gait": gait, "feet": states, "stair_progress": 2 * total}
    return contacts


def pose(rig, exercise_id, amount):
    m, _, _ = _api()
    if exercise_id not in SUPPORTED:
        raise ValueError("Unregistered exact cardio motion: " + exercise_id)
    m.reset(rig)
    amount = min(1., max(0., amount))
    if exercise_id in ("brisk_walk", "run"):
        return _gait(rig, amount, exercise_id == "run")
    return (_rope if exercise_id == "jump_rope" else _stairs)(rig, amount)


def audit(rows, exercise_id):
    import technique as t
    elbow = [t.bend_degrees(row, "upperarm_" + label, "lowerarm_" + label) for row in rows for label in ("l", "r")]
    metrics = {"elbow_flexion_min_deg": min(elbow), "elbow_flexion_max_deg": max(elbow)}
    failures = []
    if exercise_id in ("run", "brisk_walk") and max(abs(value - 90) for value in elbow) > .01:
        failures.append("Gait loses its selected right-angle arm swing")
    if exercise_id == "brisk_walk":
        metrics["net_forward_pelvis_m"] = rows[-1]["bones"]["pelvis"]["head"][1] - rows[0]["bones"]["pelvis"]["head"][1]
        if metrics["net_forward_pelvis_m"] > -4.5:
            failures.append("Ground walking lacks actual eight-step forward progress")
    if exercise_id == "run":
        landing = []
        for row in rows:
            for label, offset in (("l", 0), ("r", .5)):
                q = (6 * row["amount"] + offset) % 1
                if q <= .05:
                    hip_y = (row["bones"]["thigh_l"]["head"][1] + row["bones"]["thigh_r"]["head"][1]) / 2
                    landing.append(abs(row["bones"]["foot_" + label]["head"][1] - hip_y))
        metrics["maximum_landing_ankle_hip_fore_aft_offset_m"] = max(landing, default=0)
        if max(landing, default=0) > .15:
            failures.append("Selected treadmill landing overstrides far from the hip")
    lean = []
    for row in rows:
        shoulder = [(row["bones"]["upperarm_l"]["head"][axis] + row["bones"]["upperarm_r"]["head"][axis]) / 2 for axis in range(3)]
        hip = [(row["bones"]["thigh_l"]["head"][axis] + row["bones"]["thigh_r"]["head"][axis]) / 2 for axis in range(3)]
        lean.append(t.angle_degrees((0, 0, 1), t.subtract(shoulder, hip)))
    metrics["trunk_forward_lean_min_deg"] = min(lean)
    metrics["trunk_forward_lean_max_deg"] = max(lean)
    if max(lean) - min(lean) > .01:
        failures.append("Selected fixed trunk/head posture changes during the cardio cycle")
    return {"exercise_id": exercise_id, "passed": not failures, "failures": failures, "metrics": metrics,
            "trainerApproved": False, "scope": "Selected-model geometry; actual shoe and machine support is inspected separately"}
