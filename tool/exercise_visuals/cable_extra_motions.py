"""Exact rope face pull; original teaching draft awaiting trainer review."""
import math
from mathutils import Vector
import motions as m
import technique

SUPPORTED = ("face_pull",)
REGIONS = {"face_pull": ("rear_deltoids", "upper_back", "biceps")}
FIXED_CONTACTS = {"face_pull": ("foot_l", "foot_r")}
VIEWS = {"face_pull": {"target": (0, -.24, 1.03), "location": (4.8, 3.2, 2.4), "ortho_scale": 2.8}}
REFERENCES = {"face_pull": {
    "variant": "Standing eye-height cable rope face pull with separated rope ends",
    "url": "https://www.nasm.org/resource-center/exercise-library/face-pull",
    "reference_cues": ["Eye-height pulley", "Slightly bent knees", "Step back to tension rope", "Pull toward face with elbows back", "Controlled arm extension"],
    "model_limits": "Clavicles approximate shoulder girdle; no independent scapula bones. Selected rope-end separation and joint angles require trainer review.",
    "values_are_not_universal_prescriptions": True,
}}


def _rope_hand(rig, side, label, target, pole):
    rest = rig.data.bones
    shoulder = rig.pose.bones["upperarm_" + label].head.copy()
    upper = rest["upperarm_" + label].length
    forearm = rest["lowerarm_" + label].length
    palm = (rest["middle_01_" + label].head_local - rest["hand_" + label].head_local).length * .97
    effective = math.hypot(forearm + palm, .012)
    elbow, endpoint = m.two_bone(shoulder, target, upper, effective, pole)
    if (endpoint - target).length > .0001:
        raise ValueError("Face-pull grip outside native reach")
    combined = (target - elbow).normalized()
    normal = Vector((-side, 0, 0))
    normal = (normal - combined * normal.dot(combined)).normalized()
    angle = math.atan2(.012, forearm + palm)
    forward = combined * math.cos(angle) - normal * math.sin(angle)
    normal = (normal - forward * normal.dot(forward)).normalized()
    wrist = elbow + forward * forearm
    m.point(rig, "upperarm_" + label, shoulder, elbow)
    m.pronated_forearm(rig, label, elbow, wrist, normal)
    contact = m.hand(rig, label, wrist, forward, normal, True)
    if (contact["palm"] - target).length > .001:
        raise ValueError("Rope handle does not match actual palm")
    return contact


def pose(rig, exercise_id, amount):
    if exercise_id not in SUPPORTED:
        raise ValueError(exercise_id)
    m.standing(rig)
    # A small fixed knee bend; trunk and feet do not swing with the rope.
    hip = rig.pose.bones["thigh_l"].head.copy()
    m.torso(rig, Vector((0, .02, hip.z - .012)), m.Quaternion((1, 0, 0), 0))
    m.legs(rig)
    contacts = {}
    for side, label in ((1, "l"), (-1, "r")):
        shoulder = rig.pose.bones["upperarm_" + label].head.copy()
        rest = rig.data.bones
        reach = rest["upperarm_" + label].length + math.hypot(
            rest["lowerarm_" + label].length + (rest["middle_01_" + label].head_local - rest["hand_" + label].head_local).length * .97, .012)
        start_x = side * .16
        start_z = shoulder.z + .10
        start_y = shoulder.y - math.sqrt((reach - .001) ** 2 - (start_x - shoulder.x) ** 2 - .10 ** 2)
        start = Vector((start_x, start_y, start_z))
        end = Vector((side * .37, shoulder.y - .15, shoulder.z + .20))
        pole = shoulder + Vector((side * .6, .08, .02))
        contacts[label] = _rope_hand(rig, side, label, start.lerp(end, amount), pole)
    return contacts


def audit(rows, exercise_id):
    def p(row, bone, part="head"):
        return Vector(row["bones"][bone][part])
    start = rows[0]
    peak = max(rows, key=lambda row: row["amount"])
    wrists = [technique.angle_degrees(p(row, "lowerarm_" + label, "tail") - p(row, "lowerarm_" + label), p(row, "middle_01_" + label) - p(row, "hand_" + label)) for row in rows for label in ("l", "r")]
    core = max((p(row, bone) - p(start, bone)).length for row in rows for bone in ("pelvis", "spine_01", "spine_03", "head"))
    bends = [180 - technique.angle_degrees(p(start, "upperarm_" + label) - p(start, "lowerarm_" + label), p(start, "lowerarm_" + label, "tail") - p(start, "lowerarm_" + label)) for label in ("l", "r")]
    face_height = min(p(peak, "middle_01_" + label).z - p(peak, "upperarm_" + label).z for label in ("l", "r"))
    separation = abs(p(peak, "middle_01_l").x - p(peak, "middle_01_r").x)
    failures = []
    if max(wrists) > 1: failures.append("Rope-bearing wrist bends")
    if core > .0001: failures.append("Trunk swings")
    if max(bends) > 12: failures.append("Start arm extension missing")
    if face_height < .15 or separation < .65: failures.append("Rope is pulled toward chest instead of face sides")
    return {"exercise_id": exercise_id, "passed": not failures, "failures": failures,
            "metrics": {"max_wrist_angle_deg": max(wrists), "core_drift_m": core, "start_elbow_bend_deg": max(bends), "peak_hand_above_shoulder_m": face_height, "peak_hand_separation_m": separation},
            "review_status": "trainer_pending", "threshold_scope": "Selected model production guards, not professional approval"}
