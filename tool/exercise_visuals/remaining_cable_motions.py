"""Four separately authored exact cable variants, with neutral load wrists.

Reference cues are distinguished from selected setup choices. The meshes and
animation are original; numerical guards never grant trainer approval.
"""
import math

SUPPORTED = ("cable_crunch", "cable_fly", "cable_lateral_raise", "straight_arm_pulldown")
REGIONS = {"cable_crunch": ("abs",), "cable_fly": ("chest", "deltoids"),
           "cable_lateral_raise": ("deltoids",), "straight_arm_pulldown": ("lats", "upper_back")}
FIXED_CONTACTS = {"cable_crunch": ("pelvis", "thigh_l", "thigh_r", "calf_l", "calf_r", "foot_l", "foot_r"),
                  "cable_fly": ("foot_l", "foot_r"), "cable_lateral_raise": ("foot_l", "foot_r"),
                  "straight_arm_pulldown": ("foot_l", "foot_r")}
VIEWS = {
    "cable_crunch": {"location": (4.8, -3.3, 1.8), "target": (0, -.20, 1.08), "ortho_scale": 3.05},
    "cable_fly": {"location": (4.0, -5.0, 2.6), "target": (0, -.04, 1.02), "ortho_scale": 3.0},
    "cable_lateral_raise": {"location": (4.2, -4.7, 2.1), "target": (0, -.08, 1.0), "ortho_scale": 2.8},
    "straight_arm_pulldown": {"location": (4.7, 3.4, 2.0), "target": (0, -.25, 1.15), "ortho_scale": 3.1},
}
_ACE_CABLE = "https://contentcdn.eacefitness.com/cp/pdfs/CertifiedNews/AugSept09Cert.pdf"
REFERENCES = {
    "cable_crunch": {"variant": "Kneeling facing-pulley rope cable crunch with wrists beside the head and fixed hips",
        "references": [_ACE_CABLE], "reference_scope": "ACE Certified News August/September 2009 printed p10, Kneeling Crunches; face weight stack, high rope, wrists beside head, abdominal torso flexion",
        "guide_correction": "The earlier back-to-machine/head-behind setup is replaced by the cited facing-pulley variant.",
        "reference_cues": ["Kneel facing high pulley", "Rope remains stationary relative to head", "Flex trunk using abdominals", "Controlled return"],
        "values_are_not_universal_prescriptions": True, "trainerApproved": False},
    "cable_fly": {"variant": "Standing bilateral chest-height cable fly in a staggered stance, neutral handles meeting without crossing",
        "references": ["https://www.nasm.org/resource-center/exercise-library/cable-crossover", _ACE_CABLE],
        "reference_scope": "NASM Cable Crossover directly supplies shoulder-height pulleys, neutral grip, braced slight lean and forward arc; its crossover finish differs from the selected non-crossing fly. ACE printed p8 supplies staggered stance/neutral wrists but its high-to-low finish is not used.",
        "selected_setup": "Current exact local cable_fly guide chest-height non-crossing arc; inward neutral grip corrects its prior ambiguous overhand/front wording.",
        "reference_cues": ["Chest-height pulleys", "Closed neutral handles", "Slight fixed elbow bend", "Braced torso", "Slow reverse arc"],
        "values_are_not_universal_prescriptions": True, "trainerApproved": False},
    "cable_lateral_raise": {"variant": "Standing left-arm low-cable lateral raise starting at right hip with slight fixed elbow bend",
        "references": [_ACE_CABLE], "reference_scope": "ACE Certified News printed p9 Lateral Raise: low single handle; right side toward weight stack; left hand at right hip; shoulder-height abduction",
        "reference_cues": ["Low pulley on opposite side", "Raise with slight fixed elbow bend", "Stop at shoulder height", "Torso remains braced"],
        "demonstrated_side": "left arm", "opposite_side": "Repeat with the right arm; this clip demonstrates the left arm.",
        "values_are_not_universal_prescriptions": True, "trainerApproved": False},
    "straight_arm_pulldown": {"variant": "Standing pronated straight-bar cable straight-arm pulldown with a small fixed elbow bend",
        "references": ["https://www.acefitness.org/resources/pros/expert-articles/5565/4-moves-to-help-you-master-the-pull-up/",
                       "https://www.acefitness.org/resources/everyone/exercise-library/334/straight-arm-pulldown/"],
        "reference_scope": "ACE pull-up article supplies straight-arm shoulder-driven cable pull-down cues. Library 334 has mixed bar/rope wording, so it is not claimed as independent proof of the straight-bar attachment; the exact current guide selects the straight bar.",
        "reference_cues": ["High pulley", "Pronated shoulder-width bar grip", "Shoulder extension with fixed elbows", "Bar descends in front of thighs", "No torso swing"],
        "values_are_not_universal_prescriptions": True, "trainerApproved": False},
}


def _api():
    import motions as m
    from mathutils import Quaternion, Vector
    return m, Quaternion, Vector


def _fk(rig, label, upper, lower, normal, grip=True):
    m, _, V = _api()
    rest = rig.data.bones
    shoulder = rig.pose.bones["upperarm_" + label].head.copy()
    elbow = shoulder + V(upper).normalized() * rest["upperarm_" + label].length
    forward = V(lower).normalized()
    wrist = elbow + forward * rest["lowerarm_" + label].length
    normal = (V(normal) - forward * V(normal).dot(forward)).normalized()
    m.point(rig, "upperarm_" + label, shoulder, elbow)
    m.pronated_forearm(rig, label, elbow, wrist, normal)
    return m.hand(rig, label, wrist, forward, normal, grip)


def _standing(rig, lean=0, stagger=False):
    m, Q, V = _api()
    m.torso(rig, V((0, .012, .843 if stagger else .868)), Q((1, 0, 0), math.radians(lean)))
    anchors = {label: V((side * .19, -.17 if label == "l" and stagger else .15 if stagger else -.01137906,
                           rig.data.bones["calf_" + label].tail_local.z)) for side, label in ((1, "l"), (-1, "r"))}
    m.legs(rig, anchors)
    for label in ("l", "r"):
        if (rig.pose.bones["foot_" + label].head - anchors[label]).length > .0001:
            raise ValueError("Cable stance ankle is beyond the athlete's actual reach")


def _fly(rig, amount):
    m, _, V = _api()
    _standing(rig, 8, True)
    contacts = {}
    for side, label in ((1, "l"), (-1, "r")):
        rest = rig.data.bones
        shoulder = rig.pose.bones["upperarm_" + label].head.copy()
        lower = rest["lowerarm_" + label].length + .97 * (rest["middle_01_" + label].head_local - rest["hand_" + label].head_local).length
        # Preserve the selected 20-degree elbow bend while finding a finish
        # separated by actual hand width; this is a fly, not a chest press.
        low, high = math.radians(65), math.radians(125)
        for _ in range(30):
            angle = (low + high) / 2
            x = abs(shoulder.x) + rest["upperarm_" + label].length * math.cos(angle) + lower * math.cos(angle + math.radians(20))
            if x > .105:
                low = angle
            else:
                high = angle
        angle = math.radians(7) + ((low + high) / 2 - math.radians(7)) * amount
        forearm = angle + math.radians(20)
        upper = V((side * math.cos(angle), -math.sin(angle), 0))
        lower_dir = V((side * math.cos(forearm), -math.sin(forearm), 0))
        normal = V((-side * math.sin(forearm), -math.cos(forearm), 0))
        contacts[label] = _fk(rig, label, upper, lower_dir, normal)
    return contacts


def _lateral(rig, amount):
    m, _, V = _api()
    _standing(rig)
    angle = math.radians(-32 + 116 * amount)
    lower = angle + math.radians(10)
    contacts = {"l": _fk(rig, "l", (math.sin(angle), -.50, -math.cos(angle)),
                           (math.sin(lower), -.50, -math.cos(lower)), (-math.cos(lower), 0, -math.sin(lower)))}
    contacts["r"] = _fk(rig, "r", (-.13, -.10, -1), (-.13, -.10, -1), (1, 0, 0), False)
    return contacts


def _pulldown(rig, amount):
    m, _, V = _api()
    _standing(rig, 15)
    upper = math.radians(120 - 96 * amount)
    lower = upper + math.radians(4)
    return {label: _fk(rig, label, (0, -math.sin(upper), -math.cos(upper)),
                        (0, -math.sin(lower), -math.cos(lower)), (0, -math.cos(lower), math.sin(lower)))
            for label in ("l", "r")}


def _kneel(rig):
    m, Q, V = _api()
    rest = rig.data.bones
    hip_z = .061 + rest["thigh_l"].length
    m.torso(rig, V((0, 0, hip_z)), Q((1, 0, 0), math.radians(8)))
    for side, label in ((1, "l"), (-1, "r")):
        hip = rig.pose.bones["thigh_" + label].head.copy()
        knee = hip - V((0, 0, rest["thigh_" + label].length))
        # The tibia's skin radius narrows toward the ankle. A small downward
        # slope seats the actual shins alongside the knees on a flat mat.
        drop = .008 if label == "l" else .0115
        ankle = knee + V((0, math.sqrt(rest["calf_" + label].length ** 2 - drop ** 2), -drop))
        m.point(rig, "thigh_" + label, hip, knee)
        m.point(rig, "calf_" + label, knee, ankle)
        foot_angle = math.pi
        m.bone_rotation(rig, "foot_" + label, ankle, Q((1, 0, 0), foot_angle))
        ball = rig.pose.bones["foot_" + label].tail.copy()
        m.point(rig, "ball_" + label, ball, ball + V((0, rest["ball_" + label].length, 0)))


def _crunch(rig, amount):
    m, Q, V = _api()
    from bodyweight_motions import _grip_arm
    _kneel(rig)
    for bone, degrees in (("spine_01", 8 + 12 * amount), ("spine_02", 8 + 25 * amount),
                          ("spine_03", 8 + 38 * amount), ("neck_01", 8 + 38 * amount)):
        m.bone_rotation(rig, bone, rig.pose.bones[bone].head.copy(), Q((1, 0, 0), math.radians(degrees)))
    head = rig.pose.bones["head"].head.copy()
    orientation = Q((1, 0, 0), math.radians(8 + 38 * amount))
    contacts = {"rope_junction": head + orientation @ V((0, -.14, .28))}
    for side, label in ((1, "l"), (-1, "r")):
        target = head + orientation @ V((side * .205, -.03, .10))
        shoulder = rig.pose.bones["upperarm_" + label].head.copy()
        contacts[label] = _grip_arm(rig, label, target, shoulder + orientation @ V((side * .25, -.35, -.25)), V((-side, 0, 0)))
    return contacts


def pose(rig, exercise_id, amount):
    m, _, _ = _api()
    if exercise_id not in SUPPORTED:
        raise ValueError("Cable motion not authored: " + exercise_id)
    m.reset(rig)
    return {"cable_fly": _fly, "cable_lateral_raise": _lateral,
            "straight_arm_pulldown": _pulldown, "cable_crunch": _crunch}[exercise_id](rig, amount)


def audit(rows, exercise_id):
    import technique as t
    def p(row, name, part="head"):
        return row["bones"][name][part]
    labels = ("l",) if exercise_id == "cable_lateral_raise" else ("l", "r")
    wrists = [t.angle_degrees(t.subtract(p(row, "lowerarm_" + label, "tail"), p(row, "lowerarm_" + label)),
                             t.subtract(p(row, "middle_01_" + label), p(row, "hand_" + label)))
              for row in rows for label in labels]
    elbows = {label: [t.bend_degrees(row, "upperarm_" + label, "lowerarm_" + label) for row in rows] for label in labels}
    stationary = ("pelvis", "head") if exercise_id != "cable_crunch" else ("pelvis", "calf_l", "calf_r")
    drift = max(math.dist(p(row, bone), p(rows[0], bone)) for row in rows for bone in stationary)
    failures = []
    if max(wrists) > .1:
        failures.append("Load-bearing wrists bend instead of remaining aligned")
    if drift > .0001:
        failures.append("Required trunk/hip/support anchor moves")
    if exercise_id != "cable_crunch" and max(max(values) - min(values) for values in elbows.values()) > .1:
        failures.append("Fly/raise/pulldown changes elbow bend instead of shoulder angle")
    peak = max(rows, key=lambda row: row["amount"])
    metrics = {"wrist_max_deg": max(wrists), "stationary_drift_m": drift,
               "elbow_ranges_deg": {label: [min(values), max(values)] for label, values in elbows.items()}}
    if exercise_id == "cable_lateral_raise":
        height = p(peak, "middle_01_l")[2] - p(peak, "upperarm_l")[2]
        metrics["peak_hand_relative_shoulder_m"] = height
        if not -.04 <= height <= .045:
            failures.append("Lateral raise does not finish at shoulder height")
    if exercise_id == "cable_crunch":
        descent = p(rows[0], "upperarm_l")[2] - p(peak, "upperarm_l")[2]
        metrics["shoulder_descent_m"] = descent
        if descent < .10:
            failures.append("Kneeling crunch lacks actual trunk flexion")
    return {"exercise_id": exercise_id, "passed": not failures, "failures": failures, "metrics": metrics,
            "trainerApproved": False, "review_status": "trainer_pending", "threshold_scope": "Selected original model production guards; not technique certification"}
