"""Original exact-ID bodyweight and dumbbell bodyweight exercise drafts.

The rig, poses and props are authored locally. References supply movement
cues, never their images. One-sided repetitions demonstrate one side only;
trainer review is pending. Imports remain Blender-free until posing begins.
"""
import math

SUPPORTED = (
    "bulgarian_split_squat", "pullup", "dips", "bench_dip",
    "hanging_leg_raise", "leg_raise", "bird_dog", "dead_bug", "side_plank",
    "0f177240-029b-543a-be27-2e8ed0526bca",
    "3c358477-aeb3-5d78-a6aa-91c9fb6c81db",
    "bff7dff4-2b99-5357-b365-f10e1187cbb3",
    "d1ecb818-0235-5e2f-9113-39be506aa98a",
    "823846f5-2414-58b7-911e-2d9397a28f49",
    "dd9ea4cf-1bc9-56f6-b8e0-06b6ef5f7ebe",
)
SPLIT = "0f177240-029b-543a-be27-2e8ed0526bca"
CHIN = "3c358477-aeb3-5d78-a6aa-91c9fb6c81db"
FORWARD = "bff7dff4-2b99-5357-b365-f10e1187cbb3"
REVERSE = "d1ecb818-0235-5e2f-9113-39be506aa98a"
STEP = "823846f5-2414-58b7-911e-2d9397a28f49"
TRICEPS_DIP = "dd9ea4cf-1bc9-56f6-b8e0-06b6ef5f7ebe"
LOADED = ("bulgarian_split_squat", SPLIT, FORWARD, REVERSE, STEP)

REGIONS = {key: ("quadriceps", "glutes", "hamstrings") for key in LOADED}
REGIONS.update({
    "pullup": ("lats", "upper_back", "biceps"), CHIN: ("lats", "biceps"),
    "dips": ("chest", "triceps", "deltoids"),
    TRICEPS_DIP: ("triceps", "chest", "deltoids"), "bench_dip": ("triceps",),
    "hanging_leg_raise": ("abs",), "leg_raise": ("abs",),
    "bird_dog": ("abs", "erectors", "glutes"), "dead_bug": ("abs",),
    "side_plank": ("abs",),
})


def _reference(variant, urls, cues, source_id=None, side=None):
    result = {"variant": variant, "references": urls, "reference_cues": cues,
              "values_are_not_universal_prescriptions": True,
              "review_status": "trainer_pending", "motion_capture": False}
    if source_id:
        result["catalog_source_id"] = source_id
    if side:
        result["demonstrated_side"] = side
        result["opposite_side"] = "Repeat on the opposite side; this clip shows one side."
    return result


_DB = "https://raw.githubusercontent.com/yuhonas/free-exercise-db/main/exercises/"
_ACE = "https://www.acefitness.org/resources/everyone/exercise-library/"
_NASM = "https://www.nasm.org/resource-center/exercise-library/"
REFERENCES = {
    "bulgarian_split_squat": _reference("Dumbbell rear-foot-elevated split squat",
        [_NASM + "bulgarian-split-squat"],
        ["Rear foot supported on bench", "Front thigh approaches horizontal", "Upright torso", "Dumbbells at sides"],
        side="left leg in front"),
    SPLIT: _reference("Dumbbell rear-foot-elevated split squat; exact source variation",
        [_DB + "Split_Squat_with_Dumbbells.json", _NASM + "bulgarian-split-squat"],
        ["Rear foot elevated on bench", "Front knee tracks foot", "Vertical descent", "Dumbbells at sides"],
        "Split_Squat_with_Dumbbells", "left leg in front"),
    FORWARD: _reference("Dumbbell forward lunge, returning to standing",
        [_DB + "Dumbbell_Lunges.json", _ACE + "94/forward-lunge/"],
        ["Step forward before descending", "Front foot planted during descent", "Push back to standing"],
        "Dumbbell_Lunges", "left leg steps forward"),
    REVERSE: _reference("Dumbbell reverse lunge, returning to standing",
        [_DB + "Dumbbell_Rear_Lunge.json"],
        ["Right foot steps backward", "Left foot stays planted", "Upright torso", "Return to standing"],
        "Dumbbell_Rear_Lunge", "right leg steps back"),
    STEP: _reference("Dumbbell step-up from a pre-positioned leading foot",
        [_ACE + "28/step-up/", _DB + "Dumbbell_Step_Ups.json"],
        ["Leading foot fully on platform", "Extend leading hip and knee", "Trailing foot joins platform", "Controlled return"],
        "Dumbbell_Step_Ups", "left leg leads"),
    "pullup": _reference("Pronated pull-up without kipping", [_NASM + "pull-up"],
        ["Overhand grip wider than shoulders", "Extended elbows at start", "Chin above bar", "No swinging"], "Pullups"),
    CHIN: _reference("Supinated chin-up without kipping", [_ACE + "190/chin-ups/"],
        ["Palms toward face", "Neutral wrists", "Elbows pull down", "Chin above bar", "Controlled descent"], "Chin-Up"),
    "dips": _reference("Forward-leaning chest dip on parallel bars", [_DB + "Dips_-_Chest_Version.json"],
        ["Arms nearly straight at top", "Forward-leaning torso", "Elbows slightly flared", "Controlled lower and press"], "Dips_-_Chest_Version"),
    TRICEPS_DIP: _reference("Upright triceps dip on parallel bars", [_DB + "Dips_-_Triceps_Version.json"],
        ["Upright torso", "Elbows close to body", "Approximately 90-degree elbow bend at bottom"], "Dips_-_Triceps_Version"),
    "bench_dip": _reference("Bench dip with knees bent and heels on floor", [_NASM + "bench-dips"],
        ["Hands fixed to front edge", "Bent knees are the selected variation", "Elbows bend backward to approximately 90 degrees", "Hips stay near bench"], "Bench_Dips"),
    "hanging_leg_raise": _reference("Straight-leg hanging raise without swinging",
        [_DB + "Hanging_Leg_Raise.json", "https://www.nasm.org/resource-center/blog/training/best-abs-exercises"],
        ["Overhand grip", "Arms remain extended", "Straight legs rise to horizontal", "Trunk remains still"], "Hanging_Leg_Raise"),
    "leg_raise": _reference("Flat-bench lying leg raise with hands by the hips", [_DB + "Flat_Bench_Lying_Leg_Raise.json"],
        ["Back supported by bench", "Legs extend off end", "Raise straight legs to vertical", "Controlled lowering"], "Flat_Bench_Lying_Leg_Raise"),
    "bird_dog": _reference("Quadruped contralateral bird dog", [_ACE + "14/bird-dog/"],
        ["Hands below shoulders", "Knees below hips", "Opposite arm and leg extend", "Level trunk and pelvis"], side="left arm and right leg extend"),
    "dead_bug": _reference("Supine contralateral dead bug", [_NASM + "dead-bug"],
        ["Initial hips and knees at 90 degrees", "Arms initially vertical", "Opposite arm and leg extend", "Back stays on mat"], side="right arm and left leg extend"),
    "side_plank": _reference("Static forearm side plank with top arm vertical", [_NASM + "side-plank"],
        ["Elbow below shoulder", "Forearm supported", "Feet staggered", "Straight trunk held without rotation"], side="right forearm supports"),
}

VIEWS = {key: {"target": (0, -0.03, 0.94), "location": (4.5, -4.5, 2.2), "ortho_scale": 2.40}
         for key in LOADED}
VIEWS.update({
    "pullup": {"target": (0, 0, 1.30), "location": (4.3, -4.8, 2.9), "ortho_scale": 3.02},
    CHIN: {"target": (0, 0, 1.30), "location": (4.3, -4.8, 2.9), "ortho_scale": 3.02},
    "hanging_leg_raise": {"target": (0, -0.12, 1.27), "location": (4.8, -3.4, 2.6), "ortho_scale": 3.02},
    "dips": {"target": (0, -0.06, 1.05), "location": (4.4, -4.4, 2.0), "ortho_scale": 2.63},
    TRICEPS_DIP: {"target": (0, 0, 1.08), "location": (4.4, -4.4, 2.0), "ortho_scale": 2.63},
    "bench_dip": {"target": (0, -0.17, 0.57), "location": (4.6, -3.0, 1.6), "ortho_scale": 2.10},
    "leg_raise": {"target": (0, 0.08, 0.63), "location": (4.6, -3.4, 2.0), "ortho_scale": 2.43},
    "bird_dog": {"target": (0, 0.12, 0.37), "location": (4.5, -3.4, 1.5), "ortho_scale": 2.30},
    "dead_bug": {"target": (0, 0.02, 0.37), "location": (4.4, 3.4, 2.6), "ortho_scale": 2.34},
    "side_plank": {"target": (0, 0.09, 0.48), "location": (4.8, -2.5, 1.45), "ortho_scale": 2.50},
})
# These are bone heads that truly remain planted. Grips on fixed bars use
# independently reconstructed palm contacts in audit(), not moving wrists.
FIXED_CONTACTS = {key: () for key in SUPPORTED}
FIXED_CONTACTS.update({
    "bulgarian_split_squat": ("foot_l", "foot_r"), SPLIT: ("foot_l", "foot_r"),
    REVERSE: ("foot_l",), STEP: ("foot_l",),
    "bench_dip": ("foot_l", "foot_r", "hand_l", "hand_r"),
    "bird_dog": ("hand_r", "calf_l"), "dead_bug": ("pelvis",),
    "leg_raise": ("pelvis",), "side_plank": ("pelvis", "lowerarm_r", "foot_r"),
})
STATIC = ("side_plank",)


def _modules():
    import motions
    from mathutils import Quaternion, Vector
    return motions, Quaternion, Vector


def _ease(value):
    value = max(0, min(1, value))
    return value * value * (3 - 2 * value)


def _leg(rig, label, target, pole, rotation):
    m, _, V = _modules()
    hip = rig.pose.bones["thigh_" + label].head.copy()
    rest = rig.data.bones
    knee, ankle = m.two_bone(hip, V(target), rest["thigh_" + label].length,
                             rest["calf_" + label].length, V(pole))
    if (ankle - V(target)).length > 0.0005:
        raise ValueError("Leg target beyond native bone reach: " + label)
    m.point(rig, "thigh_" + label, hip, knee)
    m.point(rig, "calf_" + label, knee, ankle)
    m.bone_rotation(rig, "foot_" + label, ankle, rotation)


def _free_leg(rig, label, thigh_direction, calf_direction, foot_rotation):
    m, _, V = _modules()
    rest = rig.data.bones
    hip = rig.pose.bones["thigh_" + label].head.copy()
    knee = hip + V(thigh_direction).normalized() * rest["thigh_" + label].length
    ankle = knee + V(calf_direction).normalized() * rest["calf_" + label].length
    m.point(rig, "thigh_" + label, hip, knee)
    m.point(rig, "calf_" + label, knee, ankle)
    m.bone_rotation(rig, "foot_" + label, ankle, foot_rotation)


def _straight_arm(rig, label, direction, normal):
    m, _, V = _modules()
    rest = rig.data.bones
    shoulder = rig.pose.bones["upperarm_" + label].head.copy()
    direction = V(direction).normalized()
    elbow = shoulder + direction * rest["upperarm_" + label].length
    wrist = elbow + direction * rest["lowerarm_" + label].length
    m.point(rig, "upperarm_" + label, shoulder, elbow)
    m.point(rig, "lowerarm_" + label, elbow, wrist)
    return m.hand(rig, label, wrist, direction, V(normal))


def _floor_arm(rig, label, palm, pole):
    m, _, V = _modules()
    rest = rig.data.bones
    length = (rest["middle_01_" + label].head_local - rest["hand_" + label].head_local).length * 0.97
    wrist = V(palm) + V((0, length, 0.012))
    contact = m.arm(rig, label, wrist, pole, V((0, -1, 0)), V((0, 0, -1)))
    if (contact["palm"] - V(palm)).length > 0.001:
        raise ValueError("Supported palm beyond native arm reach: " + label)
    _flat_hand(rig, label)
    return contact


def _flat_hand(rig, label):
    """Open the fingers and thumb along the supporting palm surface."""
    m, _, V = _modules()
    for digit in ("index", "middle", "ring", "pinky"):
        for segment in (1, 2, 3):
            name = digit + "_0" + str(segment) + "_" + label
            head = rig.pose.bones[name].head.copy()
            m.point(rig, name, head, head + V((0, -rig.data.bones[name].length, 0)))
    direction = V((-1 if label == "l" else 1, -0.35, 0)).normalized()
    for segment in (1, 2, 3):
        name = "thumb_0" + str(segment) + "_" + label
        head = rig.pose.bones[name].head.copy()
        m.point(rig, name, head, head + direction * rig.data.bones[name].length)


def _grip_arm(rig, label, palm, pole, normal):
    """Solve to a fixed palm with neutral wrist, including palm depth."""
    m, _, V = _modules()
    rest = rig.data.bones
    shoulder = rig.pose.bones["upperarm_" + label].head.copy()
    palm_length = (rest["middle_01_" + label].head_local - rest["hand_" + label].head_local).length * 0.97
    lower = rest["lowerarm_" + label].length + palm_length
    desired_normal = V(normal).normalized()
    target = V(palm)
    for _ in range(8):
        elbow, endpoint = m.two_bone(shoulder, target - desired_normal * 0.012,
                                     rest["upperarm_" + label].length, lower, V(pole))
        forward = (endpoint - elbow).normalized()
        desired_normal = (V(normal) - forward * V(normal).dot(forward)).normalized()
    wrist = elbow + forward * rest["lowerarm_" + label].length
    m.point(rig, "upperarm_" + label, shoulder, elbow)
    m.point(rig, "lowerarm_" + label, elbow, wrist)
    m.pronated_forearm(rig, label, elbow, wrist, desired_normal)
    contact = m.hand(rig, label, wrist, forward, desired_normal, True)
    if (contact["palm"] - target).length > 0.001:
        raise ValueError("Fixed grip unreachable: " + label + " error=" + str((contact["palm"] - target).length))
    return contact


def _dumbbells(rig):
    m, _, V = _modules()
    contacts = {}
    rest = rig.data.bones
    for side, label in ((1, "l"), (-1, "r")):
        shoulder = rig.pose.bones["upperarm_" + label].head.copy()
        direction = V((side * 0.65, -0.03, -1)).normalized()
        elbow = shoulder + direction * rest["upperarm_" + label].length
        wrist = elbow + V((side * 0.20, -0.03, -1)).normalized() * rest["lowerarm_" + label].length
        m.point(rig, "upperarm_" + label, shoulder, elbow)
        m.point(rig, "lowerarm_" + label, elbow, wrist)
        normal = V((-side, 0, 0))
        m.pronated_forearm(rig, label, elbow, wrist, normal)
        contacts[label] = m.hand(rig, label, wrist, wrist - elbow, normal, True)
    return contacts


def _split_pose(rig, exercise_id, amount):
    m, Q, V = _modules()
    rest = rig.data.bones
    qflat = Q((1, 0, 0), 0)
    if exercise_id in ("bulgarian_split_squat", SPLIT):
        m.torso(rig, V((0, -0.16 + 0.12 * amount, 0.84 - 0.33 * amount)), qflat)
        _leg(rig, "l", (0.17, -0.40, 0.069), (0.17, -0.8, 0.15), qflat)
        _leg(rig, "r", (-0.17, 0.37, 0.5145), (-0.17, -0.20, 0.16), Q((1, 0, 0), math.radians(145)))
    else:
        step = _ease(amount / 0.35)
        depth = _ease((amount - 0.35) / 0.65)
        is_forward = exercise_id == FORWARD
        shift = -0.13 * step + 0.09 * depth if is_forward else 0.25 * step + 0.13 * depth
        m.torso(rig, V((0, shift, 0.8826 - 0.0926 * step - 0.28 * depth)), qflat)
        rear_rotation = Q((1, 0, 0), math.radians(40 * step))
        if is_forward:
            front = rest["calf_l"].tail_local.copy()
            front.y += (-0.40 - front.y) * step
            front.z += 0.12 * math.sin(math.pi * step)
            rear_ball = rest["ball_r"].head_local.copy()
            rear_ball.z += 0.034 * step
            rear = rear_ball - rear_rotation @ (rest["foot_r"].tail_local - rest["foot_r"].head_local)
        else:
            front = rest["calf_l"].tail_local.copy()
            rear_ball = rest["ball_r"].head_local.copy()
            rear_ball.y += (0.61 - rear_ball.y) * step
            rear_ball.z += 0.12 * math.sin(math.pi * step)
            rear_ball.z += 0.034 * step
            rear = rear_ball - rear_rotation @ (rest["foot_r"].tail_local - rest["foot_r"].head_local)
        _leg(rig, "l", front, (0.17, -0.70, 0.15), qflat)
        _leg(rig, "r", rear, (-0.17, shift - 0.20, 0.16), rear_rotation)
    return _dumbbells(rig)


def _step_up(rig, amount):
    m, Q, V = _modules()
    m.torso(rig, V((0, -0.25 * amount, 0.84 + 0.389 * amount)), Q((1, 0, 0), 0))
    _leg(rig, "l", (0.17, -0.25, 0.419), (0.17, -0.65, 0.55), Q((1, 0, 0), 0))
    lift = _ease(amount / 0.40)
    travel = _ease((amount - 0.40) / 0.60)
    trailing = (-0.17, 0.15 - 0.40 * travel, 0.069 + 0.35 * lift + 0.10 * math.sin(math.pi * lift))
    _leg(rig, "r", trailing, (-0.17, -0.5, 0.5), Q((1, 0, 0), 0))
    return _dumbbells(rig)


def _hang(rig, exercise_id, amount):
    m, Q, V = _modules()
    raise_legs = exercise_id == "hanging_leg_raise"
    supinated = exercise_id == CHIN
    start_height = 0.178 if supinated else 0.181
    m.torso(rig, m.hip_center(rig) + V((0, 0, start_height + (0 if raise_legs else 0.40 * amount))), Q((1, 0, 0), 0))
    contacts = {}
    for side, label in ((1, "l"), (-1, "r")):
        target = (side * (0.22 if supinated else 0.29), -0.10, 2.10)
        contacts[label] = _grip_arm(rig, label, target,
            (side * (0.24 if supinated else 0.48), -0.30, 1.65), (0, 1 if supinated else -1, 0))
        angle = math.radians(90 * amount if raise_legs else 0)
        direction = V((0, -math.sin(angle), -math.cos(angle)))
        _free_leg(rig, label, direction, direction, Q((1, 0, 0), -angle))
    return contacts


def _dip(rig, exercise_id, amount):
    m, Q, V = _modules()
    chest = exercise_id == "dips"
    lean = math.radians(25 if chest else 0)
    top, descent = (1.373, 0.223) if chest else (1.328, 0.183)
    m.torso(rig, V((0, 0.03 if chest else 0, top - descent * amount)), Q((1, 0, 0), lean))
    contacts = {}
    for side, label in ((1, "l"), (-1, "r")):
        contacts[label] = _grip_arm(rig, label, (side * 0.30, -0.08, 1.18),
            (side * (0.46 if chest else 0.30), 0.32, 1.35), (-side, 0, 0))
        _free_leg(rig, label, (0, 0.12, -1), (0, 0.40, -1), Q((1, 0, 0), math.radians(20)))
    return contacts


def _bench_dip(rig, amount):
    m, Q, V = _modules()
    m.torso(rig, V((0, -0.20, 0.47 - 0.21 * amount)), Q((1, 0, 0), math.radians(-20)))
    contacts = {}
    for side, label in ((1, "l"), (-1, "r")):
        _leg(rig, label, (side * 0.18, -0.80, 0.069), (side * 0.18, -0.56, 0.27), Q((1, 0, 0), 0))
        contacts[label] = _floor_arm(rig, label, (side * 0.28, 0.09, 0.47), (side * 0.28, 0.42, 0.58))
    return contacts


def _lying_raise(rig, amount):
    m, Q, V = _modules()
    m.torso(rig, V((0, 0, 0.44)), Q((1, 0, 0), -math.pi / 2))
    angle = math.pi * amount / 2
    contacts = {}
    for side, label in ((1, "l"), (-1, "r")):
        direction = (0, -math.cos(angle), math.sin(angle))
        _free_leg(rig, label, direction, direction, Q((1, 0, 0), -math.pi / 2 - angle))
        contacts[label] = m.arm(rig, label, (side * 0.15, 0.12, 0.36),
            (side * 0.34, 0.24, 0.45), V((0, -1, 0)), V((0, 0, -1)))
        _flat_hand(rig, label)
    return contacts


def _bird(rig, amount):
    m, Q, V = _modules()
    rest = rig.data.bones
    # Keep the original knee-supported hip height. This rig's arm chain is
    # longer than its thigh: a horizontal torso leaves the supporting elbows
    # deeply bent. A small rigid torso incline raises the shoulders enough
    # for near-straight vertical arms without lifting the knees or palms.
    offset = rest["upperarm_r"].head_local - m.hip_center(rig)
    shoulder_z = .025 + .012 + rest["upperarm_r"].length + rest["lowerarm_r"].length - .0002
    lean = math.atan2(offset.y, offset.z) + math.acos((shoulder_z - .47) / math.hypot(offset.y, offset.z))
    m.torso(rig, V((0, 0.22, 0.47)), Q((1, 0, 0), lean))
    contacts = {}
    for side, label in ((1, "l"), (-1, "r")):
        shoulder = rig.pose.bones["upperarm_" + label].head.copy()
        palm_length = (rest["middle_01_" + label].head_local - rest["hand_" + label].head_local).length * .97
        support = _floor_arm(rig, label, (shoulder.x, shoulder.y - palm_length, .025),
                             shoulder + V((side * .05, .12, -.25)))
        if label == "l" and amount:
            shoulder = rig.pose.bones["upperarm_l"].head.copy()
            reach = rig.data.bones["upperarm_l"].length + rig.data.bones["lowerarm_l"].length
            finish = shoulder + V((0, -reach + 0.0002, 0))
            wrist = support["wrist"].lerp(finish, amount) + V((0, 0, 0.12 * math.sin(math.pi * amount)))
            if amount == 1:
                support = _straight_arm(rig, label, (0, -1, 0), (0, 0, -1))
            else:
                support = m.arm(rig, label, wrist, shoulder + V((0.08, -0.10, -0.35)), V((0, -1, 0)), V((0, 0, -1)))
                if (support["wrist"] - wrist).length > 0.0005:
                    raise ValueError("Bird-dog moving wrist exceeds native reach")
            _flat_hand(rig, label)
        contacts[label] = support
        thigh = V((0, amount if label == "r" else 0, -(1 - amount) if label == "r" else -1)).normalized()
        foot_angle = 147 - (57 * _ease((amount - 0.25) / 0.75) if label == "r" else 0)
        _free_leg(rig, label, thigh, (0, 1, 0), Q((1, 0, 0), math.radians(foot_angle)))
    return contacts


def _dead_bug(rig, amount):
    m, Q, V = _modules()
    m.torso(rig, V((0, 0, 0.102)), Q((1, 0, 0), -math.pi / 2))
    angle = math.radians(85 * amount)
    contacts = {}
    for side, label in ((1, "l"), (-1, "r")):
        active_leg = label == "l"
        thigh = V((0, -math.sin(angle), math.cos(angle))) if active_leg else V((0, 0, 1))
        calf = V((0, -1, 0)).lerp(thigh, amount).normalized() if active_leg else V((0, -1, 0))
        _free_leg(rig, label, thigh, calf, Q((1, 0, 0), -math.pi / 2))
        arm_direction = (0, math.sin(angle), math.cos(angle)) if label == "r" else (0, 0, 1)
        contacts[label] = _straight_arm(rig, label, arm_direction, (-side, 0, 0))
    return contacts


def _side_plank(rig, angle=75.4, hip_height=0.379):
    m, Q, V = _modules()
    prone = Q((1, 0, 0), math.radians(angle))
    rotation = Q(prone @ V((0, 0, 1)), math.pi / 2) @ prone
    m.torso(rig, V((0, 0, hip_height)), rotation)
    direction = rotation @ V((0, 0, -1))
    _free_leg(rig, "r", direction, direction, rotation)
    # Staggered feet both support the hold. Keeping both legs parallel after
    # rolling the wide pelvis puts the upper foot 20 cm into the air. Adduct
    # the upper straight leg, with its foot slightly nearer the torso.
    upper_hip = rig.pose.bones["thigh_l"].head.copy()
    ground_ankle = rig.pose.bones["calf_r"].tail.copy()
    leg_length = rig.data.bones["thigh_l"].length + rig.data.bones["calf_l"].length
    # The mirrored foot skin has a different edge contact after rolling;
    # adjust its ankle 14 mm so both actual foot surfaces meet the mat.
    vertical = (ground_ankle.z - 0.014 - upper_hip.z) / leg_length
    upper_direction = V((0, math.sqrt(1 - vertical * vertical), vertical))
    _free_leg(rig, "l", upper_direction, upper_direction, rotation)
    shoulder = rig.pose.bones["upperarm_r"].head.copy()
    elbow = shoulder + V((0, 0, -rig.data.bones["upperarm_r"].length))
    wrist = elbow + V((0, -rig.data.bones["lowerarm_r"].length, 0))
    m.point(rig, "upperarm_r", shoulder, elbow)
    m.point(rig, "lowerarm_r", elbow, wrist)
    right = m.hand(rig, "r", wrist, V((0, -1, 0)), V((0, 0, -1)))
    _flat_hand(rig, "r")
    left = _straight_arm(rig, "l", (0, 0, 1), (-1, 0, 0))
    return {"l": left, "r": right}


def pose(rig, exercise_id, amount):
    if exercise_id not in SUPPORTED:
        raise ValueError("No exact bodyweight motion: " + exercise_id)
    if not 0 <= amount <= 1:
        raise ValueError("Motion amount must be between zero and one")
    m, _, _ = _modules()
    m.reset(rig)
    if exercise_id in ("bulgarian_split_squat", SPLIT, FORWARD, REVERSE):
        return _split_pose(rig, exercise_id, amount)
    if exercise_id == STEP:
        return _step_up(rig, amount)
    if exercise_id in ("pullup", CHIN, "hanging_leg_raise"):
        return _hang(rig, exercise_id, amount)
    if exercise_id in ("dips", TRICEPS_DIP):
        return _dip(rig, exercise_id, amount)
    if exercise_id == "bench_dip":
        return _bench_dip(rig, amount)
    if exercise_id == "leg_raise":
        return _lying_raise(rig, amount)
    if exercise_id == "bird_dog":
        return _bird(rig, amount)
    if exercise_id == "dead_bug":
        return _dead_bug(rig, amount)
    return _side_plank(rig)


def audit(rows, exercise_id):
    """Exercise-specific geometry guards, separate from generic loop checks."""
    import technique as t
    if exercise_id not in SUPPORTED or not rows:
        return {"passed": False, "failures": ["Missing authored exercise or recorded frames"]}
    start = [row for row in rows if row["amount"] <= 0.001]
    peak = [row for row in rows if row["amount"] >= 0.999]
    if not start or not peak:
        return {"passed": False, "failures": ["Both start and peak frames are required"]}
    metrics, failures = {}, []

    def check(value, name, low, high):
        metrics[name] = value
        if not low <= value <= high:
            failures.append(name + " outside authored variant limits")

    def bends(samples, prefix):
        return [t.bend_degrees(row, prefix[0] + label, prefix[1] + label)
                for row in samples for label in ("l", "r")]

    if exercise_id in ("pullup", CHIN, "dips", TRICEPS_DIP, "hanging_leg_raise", "bench_dip"):
        def palm(row, label):
            wrist = t.joint(row, "hand_" + label)
            middle = t.joint(row, "middle_01_" + label)
            forward = t.subtract(middle, wrist)
            side = t.subtract(t.joint(row, "index_01_" + label), t.joint(row, "pinky_01_" + label))
            normal = (forward[1]*side[2]-forward[2]*side[1], forward[2]*side[0]-forward[0]*side[2], forward[0]*side[1]-forward[1]*side[0])
            factor = (1 if label == "l" else -1) * 0.012 * 1.0643638372421265 / t.length(normal)
            return tuple(wrist[i] + forward[i] * 0.97 + normal[i] * factor for i in range(3))
        drift = max(t.length(t.subtract(palm(row, label), palm(rows[0], label))) for row in rows for label in ("l", "r"))
        check(drift, "fixed_palm_max_drift_m", 0, 0.001)
    if exercise_id in ("pullup", CHIN):
        check(max(bends(start, ("upperarm_", "lowerarm_"))), "start_elbow_max_bend_deg", 0, 20)
        check(min(bends(peak, ("upperarm_", "lowerarm_"))), "peak_elbow_min_bend_deg", 80, 160)
        rise = t.joint(peak[0], "head")[2] - t.joint(start[0], "head")[2]
        check(rise, "body_rise_m", 0.30, 0.60)
    if exercise_id in ("dips", TRICEPS_DIP, "bench_dip"):
        check(max(bends(start, ("upperarm_", "lowerarm_"))), "top_elbow_max_bend_deg", 0, 30)
        check(min(bends(peak, ("upperarm_", "lowerarm_"))), "bottom_elbow_min_bend_deg", 75, 115)
        check(max(bends(peak, ("upperarm_", "lowerarm_"))), "bottom_elbow_max_bend_deg", 75, 115)
    if exercise_id in ("hanging_leg_raise", "leg_raise"):
        check(max(bends(rows, ("thigh_", "calf_"))), "knee_max_bend_deg", 0, 1)
        for label in ("l", "r"):
            direction = t.subtract(t.joint(peak[0], "calf_" + label, "tail"), t.joint(peak[0], "thigh_" + label))
            expected = (0, -1, 0) if exercise_id == "hanging_leg_raise" else (0, 0, 1)
            check(t.angle_degrees(direction, expected), "peak_leg_axis_deviation_" + label + "_deg", 0, 1)
    if exercise_id in ("bird_dog", "dead_bug", "leg_raise", "hanging_leg_raise", "side_plank"):
        trunk = ("pelvis", "spine_01", "spine_02", "spine_03", "head")
        drift = max(t.length(t.subtract(t.joint(row, name, part), t.joint(rows[0], name, part)))
                    for row in rows for name in trunk for part in ("head", "tail"))
        check(drift, "fixed_trunk_max_drift_m", 0, 0.0001)
    if exercise_id == "bird_dog":
        # At 24 fps the first amount >= .999 sample is still extending. The
        # exact end hold, rather than this transition frame, defines the pose.
        held_peak = max(peak, key=lambda row: row["amount"])
        check(t.bend_degrees(held_peak, "upperarm_l", "lowerarm_l"), "extended_arm_bend_deg", 0, 1)
        check(max(t.bend_degrees(row, "upperarm_r", "lowerarm_r") for row in rows),
              "support_right_elbow_max_bend_deg", 0, 5)
        held_start = [row for row in start if row["amount"] == min(item["amount"] for item in start)]
        check(max(t.bend_degrees(row, "upperarm_l", "lowerarm_l") for row in held_start),
              "support_left_elbow_max_bend_deg", 0, 5)
        check(max(t.angle_degrees(t.subtract(t.joint(row, "lowerarm_r", "tail"), t.joint(row, "upperarm_r")), (0, 0, -1)) for row in rows),
              "support_right_arm_vertical_deviation_deg", 0, 1)
        check(t.bend_degrees(held_peak, "thigh_r", "calf_r"), "extended_leg_bend_deg", 0, 1)
    if exercise_id == "dead_bug":
        check(t.bend_degrees(start[0], "thigh_l", "calf_l"), "initial_knee_bend_deg", 89, 91)
        check(t.bend_degrees(peak[0], "thigh_l", "calf_l"), "extended_knee_bend_deg", 0, 1)
    if exercise_id in LOADED:
        check(t.bend_degrees(peak[0], "thigh_l", "calf_l"), "leading_knee_peak_bend_deg", 0 if exercise_id == STEP else 70, 25 if exercise_id == STEP else 120)
    if exercise_id == "side_plank":
        shoulder = t.joint(rows[0], "upperarm_r")
        elbow = t.joint(rows[0], "lowerarm_r")
        check(math.hypot(shoulder[0]-elbow[0], shoulder[1]-elbow[1]), "support_elbow_horizontal_offset_m", 0, 0.0001)
        check(t.bend_degrees(rows[0], "upperarm_r", "lowerarm_r"), "support_elbow_bend_deg", 89, 91)
        check(max(bends(rows, ("thigh_", "calf_"))), "straight_knee_max_bend_deg", 0, 1)
        check(abs(t.joint(rows[0], "foot_l")[2] - t.joint(rows[0], "foot_r")[2]), "staggered_ankle_height_difference_m", 0, 0.025)
    return {"exercise_id": exercise_id, "metrics": metrics, "passed": not failures,
            "failures": failures, "scope": "Authored geometry guards; trainer review pending"}
