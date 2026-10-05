"""Authored exact-ID accessory movements; review pending, no name aliases."""
import math

from mathutils import Quaternion, Vector
import motions as m
import technique

SUPPORTED = ("hammer_curl", "reverse_curl", "front_raise", "rear_delt_raise", "reverse_fly",
             "cable_curl", "triceps_pushdown", "seated_cable_row", "latpull")
REGIONS = {
    "hammer_curl": ("biceps", "forearms"), "reverse_curl": ("forearms", "biceps"),
    "front_raise": ("deltoids",), "rear_delt_raise": ("rear_deltoids", "upper_back"),
    "reverse_fly": ("rear_deltoids", "upper_back"), "cable_curl": ("biceps",),
    "triceps_pushdown": ("triceps",), "seated_cable_row": ("lats", "upper_back", "biceps"),
    "latpull": ("lats", "biceps"),
}
REFERENCES = {
    "hammer_curl": {"url": "https://www.acefitness.org/resources/everyone/exercise-library/10/hammer-curl/", "variant": "Bilateral standing neutral-grip dumbbell hammer curl", "cues": ["Palms face each other throughout", "Upper arms stationary", "Neutral wrist", "Controlled return"]},
    "reverse_curl": {"url": "https://www.acefitness.org/resources/everyone/exercise-library/310/reverse-bicep-curl/", "variant": "Standing overhand straight-bar reverse curl", "cues": ["Shoulder-width pronated grip", "Elbows remain beside torso", "No trunk swing"]},
    "front_raise": {"url": "https://www.acefitness.org/resources/everyone/exercise-library/54/front-raise/", "variant": "Bilateral dumbbell front raise", "cues": ["Slight fixed elbow bend", "Stop at shoulder height", "Neutral wrists", "Trunk stationary"]},
    "rear_delt_raise": {"source": "Setflow exercise guide, corrected dumbbell variant", "variant": "Hip-hinged bilateral dumbbell rear deltoid raise", "cues": ["Fixed hip hinge", "Soft elbows", "Arms open laterally", "No back extension"]},
    "reverse_fly": {"source": "Setflow exercise guide, MIT text", "variant": "Standing hip-hinged dumbbell reverse fly", "cues": ["Palms face each other", "Fixed slight elbow flexion", "Torso remains stationary"]},
    "cable_curl": {"url": "https://contentcdn.eacefitness.com/cp/pdfs/CertifiedNews/AugSept09Cert.pdf", "variant": "Standing low-pulley supinated straight-bar curl", "cues": ["Low pulley", "Fixed upper arms", "Neutral wrists"]},
    "triceps_pushdown": {"url": "https://www.catalystathletics.com/exercise/911/Tricep-Pushdown/", "variant": "Standing high-pulley pronated straight-bar pushdown", "cues": ["Fixed upper arms beside torso", "Only elbow extension", "Controlled return"]},
    "seated_cable_row": {"url": "https://contentcdn.eacefitness.com/cp/pdfs/CertifiedNews/AugSept09Cert.pdf", "variant": "Seated low-pulley shoulder-width pronated straight-bar row", "cues": ["Feet braced", "Slight knee bend", "No torso swing", "Pull toward abdomen"]},
    "latpull": {"url": "https://www.acefitness.org/resources/everyone/exercise-library/158/seated-lat-pulldown/", "variant": "Seated wide pronated front-of-chest lat pulldown", "cues": ["Thigh pad secures legs", "Small fixed backward lean", "Bar in front of head", "Elbows down, not behind torso"]},
}
FIXED_CONTACTS = {exercise_id: ("foot_l", "foot_r") for exercise_id in SUPPORTED}
VIEWS = {
    "cable_curl": {"location": (4.8, -4.5, 2.5), "target": (0, -.18, 1.10), "ortho_scale": 2.8},
    "triceps_pushdown": {"location": (4.8, -4.5, 2.5), "target": (0, -.18, 1.10), "ortho_scale": 2.8},
    "latpull": {"location": (4.8, -4.8, 2.8), "target": (0, -.12, 1.02), "ortho_scale": 2.9},
    "seated_cable_row": {"location": (4.8, -4.5, 2.2), "target": (0, -.18, .75), "ortho_scale": 2.6},
    "rear_delt_raise": {"location": (4.8, 3.4, 2.2), "target": (0, -.08, .77), "ortho_scale": 2.4},
    "reverse_fly": {"location": (4.8, 3.4, 2.2), "target": (0, -.08, .77), "ortho_scale": 2.4},
}


def chain(rig, label, shoulder, upper_direction, lower_direction, normal):
    rest = rig.data.bones
    upper_direction, lower_direction = Vector(upper_direction).normalized(), Vector(lower_direction).normalized()
    elbow = shoulder + upper_direction * rest["upperarm_" + label].length
    wrist = elbow + lower_direction * rest["lowerarm_" + label].length
    m.point(rig, "upperarm_" + label, shoulder, elbow)
    m.pronated_forearm(rig, label, elbow, wrist, normal)
    return m.hand(rig, label, wrist, lower_direction, normal, True)


def palm_target(rig, side, label, target, pole, supinated=False):
    """Solve the hand-centre target, keeping hand/forearm collinear."""
    rest = rig.data.bones
    shoulder = rig.pose.bones["upperarm_" + label].head.copy()
    root = Vector((target.x, shoulder.y, shoulder.z))
    upper = math.sqrt(rest["upperarm_" + label].length ** 2 - (target.x - shoulder.x) ** 2)
    lower = rest["lowerarm_" + label].length + (rest["middle_01_" + label].head_local - rest["hand_" + label].head_local).length * .97
    effective = math.hypot(lower, .012)
    planar_pole=Vector(pole)
    planar_pole.x=target.x
    elbow, endpoint = m.two_bone(root, target, upper, effective, planar_pole)
    if (endpoint - target).length > .00002:
        raise ValueError("Accessory palm target outside reach")
    combined = (target - elbow).normalized()
    n = Vector((0, -combined.z, combined.y)) * (-1 if supinated else 1)
    angle = math.atan2(.012, lower)
    forward = combined * math.cos(angle) - n * math.sin(angle)
    normal = Vector((0, -forward.z, forward.y)) * (-1 if supinated else 1)
    wrist = elbow + forward * rest["lowerarm_" + label].length
    m.point(rig, "upperarm_" + label, shoulder, elbow)
    m.pronated_forearm(rig, label, elbow, wrist, normal)
    return m.hand(rig, label, wrist, forward, normal, True)


def seat(rig, lat=False):
    rest = rig.data.bones
    hip = Vector((0, .32 if not lat else 0, .48))
    m.torso(rig, hip, Quaternion((1, 0, 0), math.radians(-12 if lat else 0)))
    anchors = {label: Vector((side * .22, -.36 if lat else -.38, rest["foot_" + label].head_local.z if lat else .12)) for side, label in ((1,"l"),(-1,"r"))}
    m.legs(rig, anchors, pole_y=-1, pole_z=.65)
    for label in ("l", "r"):
        if (rig.pose.bones["foot_"+label].head-anchors[label]).length>.0001:
            raise ValueError("Seated foot support outside leg reach")


def pose(rig, exercise_id, amount):
    rest = rig.data.bones
    contacts = {}
    if exercise_id in ("latpull", "seated_cable_row"):
        seat(rig, exercise_id == "latpull")
        shoulder = rig.pose.bones["upperarm_l"].head.copy()
        for side, label in ((1,"l"),(-1,"r")):
            grip_x = .30 if exercise_id == "latpull" else .28
            arm_upper = math.sqrt(rest["upperarm_"+label].length**2 - (grip_x-shoulder.x)**2)
            palm_length = (rest["middle_01_"+label].head_local-rest["hand_"+label].head_local).length*.97
            reach = arm_upper + math.hypot(rest["lowerarm_"+label].length+palm_length,.012) - .0002
            if exercise_id == "latpull":
                start = Vector((side * .30, shoulder.y - .07, shoulder.z + math.sqrt(reach**2-.07**2)))
                finish = Vector((side * .30, shoulder.y - .27, shoulder.z + .03))
                pole = Vector((side * .7, shoulder.y -.02, shoulder.z -.25))
            else:
                start = Vector((side * .28, shoulder.y -math.sqrt(reach**2-.12**2), shoulder.z -.12))
                finish = Vector((side * .28, shoulder.y -.24, shoulder.z -.30))
                pole = Vector((side * .32, shoulder.y +.50, shoulder.z -.20))
            contacts[label] = palm_target(rig, side, label, start.lerp(finish, amount), pole)
        return contacts
    if exercise_id in ("rear_delt_raise", "reverse_fly"):
        ankle = rest["foot_l"].head_local
        lateral = rest["thigh_l"].head_local.x - ankle.x
        hip_y = .23
        hip_z = ankle.z + math.sqrt(.800 ** 2 - lateral ** 2 - (hip_y - ankle.y) ** 2)
        m.torso(rig, Vector((0,hip_y,hip_z)), Quaternion((1,0,0), math.radians(65)))
        m.legs(rig)
    else:
        m.standing(rig)
    for side, label in ((1,"l"),(-1,"r")):
        shoulder = rig.pose.bones["upperarm_"+label].head.copy()
        if exercise_id in ("hammer_curl", "reverse_curl", "cable_curl", "triceps_pushdown"):
            down = amount if exercise_id != "triceps_pushdown" else 1-amount
            if exercise_id=="hammer_curl":
                angle=math.radians(3+123*down)
                upper=Vector((side*.20,-.04,-.98)).normalized()
            else:
                angle=math.atan2(.40,.98)+math.radians(3+(65 if exercise_id=="triceps_pushdown" else 122)*down)
                upper=Vector((0,-.40,-.98)).normalized()
            lower = Vector((0, -math.sin(angle), -math.cos(angle)))
            if exercise_id == "hammer_curl":
                normal = Vector((-side,0,0))
            else:
                normal = Vector((0,-lower.z,lower.y)) * (-1 if exercise_id == "cable_curl" else 1)
            contacts[label] = chain(rig,label,shoulder,upper,lower,normal)
        elif exercise_id == "front_raise":
            angle = math.radians(2 + 80*amount)
            upper = Vector((side*.05,-math.sin(angle),-math.cos(angle)))
            lower = Vector((side*.05,-math.sin(angle+.14),-math.cos(angle+.14)))
            normal = Vector((0,-lower.z,lower.y))
            rotation_amount=max(0,min(1,(amount-.7)/.3))
            normal=Quaternion(lower.normalized(),math.radians(-side*12*rotation_amount)) @ normal
            contacts[label] = chain(rig,label,shoulder,upper,lower,normal)
        else:
            angle = math.radians(5+72*amount)
            upper = Vector((side*math.sin(angle),-.02,-math.cos(angle)))
            lower = Vector((side*math.sin(angle+.16),-.02,-math.cos(angle+.16)))
            normal = Vector((-side*math.cos(angle+.16),0,-math.sin(angle+.16)))
            contacts[label] = chain(rig,label,shoulder,upper,lower,normal)
    return contacts


def audit(rows, exercise_id):
    def vec(row, name, part="head"):
        return row["bones"][name][part]
    wrists = [technique.angle_degrees(technique.subtract(vec(row,"lowerarm_"+label,"tail"),vec(row,"lowerarm_"+label)), technique.subtract(vec(row,"middle_01_"+label),vec(row,"hand_"+label))) for row in rows for label in ("l","r")]
    core = max((Vector(vec(row,name))-Vector(vec(rows[0],name))).length for row in rows for name in ("pelvis","spine_01","spine_02","spine_03","head"))
    elbow_drift = max((Vector(vec(row,"lowerarm_"+label))-Vector(vec(rows[0],"lowerarm_"+label))).length for row in rows for label in ("l","r"))
    fixed_elbows = exercise_id in ("hammer_curl","reverse_curl","cable_curl","triceps_pushdown")
    errors=[]
    if max(wrists)>1: errors.append("Wrist not neutral")
    if core>.0001: errors.append("Trunk sway")
    if fixed_elbows and elbow_drift>.0001: errors.append("Upper arm moves during isolated elbow action")
    if exercise_id=="latpull":
        peaks=[row for row in rows if row["amount"]>=.999]
        for row in peaks:
            for label in ("l","r"):
                shoulder,elbow=vec(row,"upperarm_"+label),vec(row,"lowerarm_"+label)
                if shoulder[2]-elbow[2]<.15: errors.append("Pulldown elbow does not descend")
                if elbow[1]-shoulder[1]>.015: errors.append("Pulldown elbow moves behind torso")
    return {"passed": not errors, "errors": errors, "max_wrist_axis_angle_deg": max(wrists), "core_drift_m":core, "elbow_drift_m":elbow_drift, "checks_are_geometry_only":True, "trainerReview":"pending"}
