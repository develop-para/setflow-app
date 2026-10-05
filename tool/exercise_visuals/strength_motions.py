"""Authored strength variants for the native CC0 athlete.

Every ID below selects a deliberate movement and equipment variant. Values
describe this one model, not universal technique prescriptions. References
are technique sources only; their photographs or animations are not imported.
"""
import math

SUPPORTED = (
    "squat", "front_squat", "goblet_squat", "barbell_curl", "ohp",
    "incline", "incline_barbell", "hip_thrust", "glute_bridge",
    "896189fc-30d9-51df-aa19-fd5ea7fa76eb",
    "58acf002-4e6d-5e95-b252-cae16252cef8",
)
REGIONS = {
    "squat": ("quadriceps", "glutes"),
    "front_squat": ("quadriceps", "glutes", "abs"),
    "goblet_squat": ("quadriceps", "glutes", "abs"),
    "barbell_curl": ("biceps",),
    "ohp": ("deltoids", "triceps"),
    "incline": ("chest", "deltoids", "triceps"),
    "incline_barbell": ("chest", "deltoids", "triceps"),
    "hip_thrust": ("glutes", "hamstrings"),
    "glute_bridge": ("glutes", "hamstrings"),
    "896189fc-30d9-51df-aa19-fd5ea7fa76eb": ("glutes", "quadriceps", "hamstrings", "erectors"),
    "58acf002-4e6d-5e95-b252-cae16252cef8": ("hamstrings", "glutes", "erectors"),
}
REFERENCES = {
    "squat": {"url": "https://www.acefitness.org/resources/everyone/exercise-library/11/back-squat/", "variant": "High-bar back squat; feet slightly wider than shoulders, heels planted", "cues": ["Bar supported across upper back", "Neutral spine", "Hips below knees", "Extend hips and knees together"]},
    "front_squat": {"url": "https://www.nsca.com/contentassets/24f7e187e9aa4a588439c9612231c7fd/tsac-module-3.0--3.3.pdf", "additional_url": "https://www.nsca.com/globalassets/education/nsca-coach/nsca-coach-10.1.pdf", "variant": "Barbell front squat with clean front rack", "grip_contact": "Bar supported on the anterior deltoids; fingers wrap the horizontal shaft with static wrist extension. Hands remain outside shoulder width on the same side as their shoulder, with no crossed forearms.", "cues": ["Bar rests on anterior shoulders", "Elbows remain forward at shoulder height", "Neutral spine", "Thighs parallel or just below", "Maintain the front rack throughout"]},
    "goblet_squat": {"url": "https://www.nasm.org/resource-center/exercise-library/goblet-squat", "variant": "Kettlebell goblet squat; both hands hold the upright horns", "grip_contact": "Each hand follows the curved kettlebell horns; the equipment root follows the two palm centres and is not a horizontal straight-bar shaft", "cues": ["Weight in front of chest", "Elbows close to torso", "Heels remain planted", "Hips below knees"]},
    "barbell_curl": {"url": "https://www.acefitness.org/resources/everyone/exercise-library/70/bicep-curl/", "variant": "Standing straight-bar supinated curl", "cues": ["Upper arms stay beside torso", "Palms supinated", "Neutral wrists", "Torso remains fixed"]},
    "ohp": {"url": "https://www.acefitness.org/resources/everyone/exercise-library/71/standing-shoulder-press/", "variant": "Strict standing barbell overhead press, in front of head", "cues": ["No leg drive", "Neutral trunk", "Press from shoulders to overhead", "Closed grip"]},
    "incline": {"url": "https://www.acefitness.org/resources/everyone/exercise-library/25/incline-chest-press/", "variant": "45-degree incline dumbbell chest press with pronated grip", "cues": ["Head, shoulders and hips supported", "Feet stay planted", "Neutral wrists", "Lower toward upper chest", "Elbows beneath wrists"]},
    "incline_barbell": {"url": "https://www.acefitness.org/resources/everyone/exercise-library/5/chest-press/", "additional_url": "https://www.nsca.com/education/articles/ptq/building-a-balanced-and-symmetrical-physique/", "variant": "45-degree incline barbell press; bar lowers toward upper chest", "cues": ["Body stays supported on incline bench", "Pronated grip", "Neutral wrists", "Controlled upper-chest descent"]},
    "hip_thrust": {"url": "https://www.acefitness.org/resources/everyone/exercise-library/367/elevated-glute-bridge/", "additional_url": "https://www.nsca.com/education/articles/ptq/program-design-strength-hypertrophy-glute/", "variant": "Barbell hip thrust with upper back on a bench and protective bar pad", "cues": ["Upper back stays supported", "Feet remain flat", "Extend hips to torso-thigh alignment", "No lumbar hyperextension"]},
    "glute_bridge": {"url": "https://www.acefitness.org/resources/everyone/exercise-library/318/hip-bridge/", "variant": "Barbell floor glute bridge with protective bar pad", "cues": ["Upper back remains on mat", "Bar rests across hips", "Press through feet", "Lift hips to torso-thigh alignment"]},
    "896189fc-30d9-51df-aa19-fd5ea7fa76eb": {"url": "https://www.nsca.com/education/articles/tsac-report/the-deadlift-and-its-application-to-overall-performance/", "source_id": "Sumo_Deadlift", "variant": "Wide-stance barbell sumo deadlift, double-overhand grip inside knees", "cues": ["Feet turned outward", "Knees track outward with toes", "Hands inside legs", "Straight arms", "Hip and knee extension together"]},
    "58acf002-4e6d-5e95-b252-cae16252cef8": {"url": "https://www.nsca.com/contentassets/24f7e187e9aa4a588439c9612231c7fd/tsac-module-3.0--3.3.pdf", "source_id": "Stiff-Legged_Barbell_Deadlift", "variant": "Barbell stiff-legged hip hinge; small fixed knee bend, straight arms", "cues": ["Slight knee flexion stays fixed", "Neutral spine", "Bar travels close to legs", "Range limited by hip hinge"]},
}
VIEWS = {
    "squat": {"location": (4.8, -3.5, 2.4), "target": (0, 0, 0.92), "ortho_scale": 2.70},
    "front_squat": {"location": (4.8, -3.5, 2.4), "target": (0, -0.05, 0.92), "ortho_scale": 2.70},
    "goblet_squat": {"location": (4.8, -3.5, 2.4), "target": (0, -0.05, 0.89), "ortho_scale": 2.35},
    "barbell_curl": {"location": (4.8, -3.5, 2.3), "target": (0, -0.08, 0.94), "ortho_scale": 2.70},
    "ohp": {"location": (4.8, -3.5, 2.5), "target": (0, -0.02, 1.16), "ortho_scale": 2.90},
    "incline": {"location": (4.8, 3.5, 2.3), "target": (0, 0.27, 0.75), "ortho_scale": 2.45},
    "incline_barbell": {"location": (4.8, 3.5, 2.3), "target": (0, 0.27, 0.75), "ortho_scale": 2.80},
    "hip_thrust": {"location": (4.8, -2.5, 1.65), "target": (0, 0.11, 0.48), "ortho_scale": 2.65},
    "glute_bridge": {"location": (4.8, -2.5, 1.50), "target": (0, 0.05, 0.35), "ortho_scale": 2.65},
    "896189fc-30d9-51df-aa19-fd5ea7fa76eb": {"location": (4.8, -3.5, 2.4), "target": (0, -0.06, 0.88), "ortho_scale": 2.80},
    "58acf002-4e6d-5e95-b252-cae16252cef8": {"location": (5.0, 2.8, 2.35), "target": (0, -0.02, 0.83), "ortho_scale": 2.75},
}
FIXED_CONTACTS = {exercise_id: ("foot_l", "foot_r") for exercise_id in SUPPORTED}


def _api():
    # Lazy import also permits reading registrations without Blender installed.
    import motions
    from mathutils import Quaternion, Vector
    return motions, Quaternion, Vector


def _body_point(rig, point):
    """Transform a rest landmark with the rigid pelvis/core transform."""
    _, _, Vector = _api()
    return rig.pose.bones["pelvis"].matrix @ rig.data.bones["pelvis"].matrix_local.inverted() @ Vector(point)


def _palm_length(rig, label):
    bones = rig.data.bones
    return (bones["middle_01_" + label].head_local - bones["hand_" + label].head_local).length * 0.97


def _grip_at(rig, label, palm, forward, normal, pole):
    """A fixed palm target; front/back rack intentionally permits wrist angle."""
    m, _, Vector = _api()
    forward, normal = Vector(forward).normalized(), Vector(normal).normalized()
    normal = (normal - forward * normal.dot(forward)).normalized()
    wrist = Vector(palm) - forward * _palm_length(rig, label) - normal * 0.012
    shoulder = rig.pose.bones["upperarm_" + label].head.copy()
    elbow, achieved = m.two_bone(shoulder, wrist, rig.data.bones["upperarm_" + label].length,
                                 rig.data.bones["lowerarm_" + label].length, Vector(pole))
    if (achieved - wrist).length > 0.00001:
        raise ValueError("Unreachable fixed grip: " + label)
    m.point(rig, "upperarm_" + label, shoulder, elbow)
    m.pronated_forearm(rig, label, elbow, wrist, normal)
    return m.hand(rig, label, wrist, forward, normal, True)


def _neutral_grip(rig, label, palm, pole, supinated=False):
    """Solve the complete forearm plus palm chain, with an unbent wrist.

    A horizontal straight handle requires each forearm in a sagittal plane.
    The upper-arm's available length is projected into that plane, rather
    than forcing an out-of-plane forearm or allowing a fixed palm to slide.
    """
    m, _, Vector = _api()
    rest = rig.data.bones
    target = Vector(palm)
    shoulder = rig.pose.bones["upperarm_" + label].head.copy()
    lateral = target.x - shoulder.x
    if abs(lateral) >= rest["upperarm_" + label].length:
        raise ValueError("Grip is outside upper-arm sagittal reach")
    upper = math.sqrt(rest["upperarm_" + label].length ** 2 - lateral ** 2)
    lower = rest["lowerarm_" + label].length + _palm_length(rig, label)
    effective = math.hypot(lower, 0.012)
    projected = Vector((target.x, shoulder.y, shoulder.z))
    pole = Vector((target.x, pole[1], pole[2]))
    elbow, achieved = m.two_bone(projected, target, upper, effective, pole)
    if (achieved - target).length > 0.00001:
        raise ValueError("Unreachable neutral palm target: " + label)
    direction = (target - elbow).normalized()
    sign = -1 if supinated else 1
    perpendicular = Vector((0, -direction.z, direction.y)) * sign
    angle = math.atan2(0.012, lower)
    forward = direction * math.cos(angle) - perpendicular * math.sin(angle)
    normal = Vector((0, -forward.z, forward.y)) * sign
    wrist = elbow + forward * rest["lowerarm_" + label].length
    m.point(rig, "upperarm_" + label, shoulder, elbow)
    m.pronated_forearm(rig, label, elbow, wrist, normal)
    contact = m.hand(rig, label, wrist, forward, normal, True)
    if (contact["palm"] - target).length > 0.00001:
        raise ValueError("Palm/shaft contact drift")
    return contact


def _neutral_palm(rig, label, palm, pole, preferred_normal):
    """Three-dimensional neutral hand chain for crossed-arm bar support."""
    m, _, Vector = _api()
    rest = rig.data.bones
    shoulder = rig.pose.bones["upperarm_" + label].head.copy()
    lower = rest["lowerarm_" + label].length + _palm_length(rig, label)
    elbow, endpoint = m.two_bone(shoulder, Vector(palm), rest["upperarm_" + label].length,
                                 math.hypot(lower, 0.012), Vector(pole))
    if (endpoint - Vector(palm)).length > 0.00001:
        raise ValueError("Three-dimensional support palm cannot be reached")
    direction = (Vector(palm) - elbow).normalized()
    normal = Vector(preferred_normal)
    normal = (normal - direction * normal.dot(direction)).normalized()
    angle = math.atan2(0.012, lower)
    forward = direction * math.cos(angle) - normal * math.sin(angle)
    normal = direction * math.sin(angle) + normal * math.cos(angle)
    wrist = elbow + forward * rest["lowerarm_" + label].length
    m.point(rig, "upperarm_" + label, shoulder, elbow)
    m.pronated_forearm(rig, label, elbow, wrist, normal)
    return m.hand(rig, label, wrist, forward, normal, True)


def _front_rack(rig):
    """Clean rack with fixed elbow height and actual wrist extension.

    Protracting the shoulder girdle creates an anterior deltoid shelf. The
    wrist supports a shoulder-borne bar instead of being forced into the
    neutral-wrist dynamic-grip solver. Both arm lengths remain exact.
    """
    m, Quaternion, Vector = _api()
    rest = rig.data.bones
    m.bone_rotation(rig, "neck_01", rig.pose.bones["neck_01"].head.copy(), Quaternion((1, 0, 0), 0))
    for side, label in ((1, "l"), (-1, "r")):
        m.bone_rotation(rig, "clavicle_" + label, rig.pose.bones["clavicle_" + label].head.copy(),
                        Quaternion((0, 0, 1), math.radians(-side * 35)))
    centre = (rig.pose.bones["upperarm_l"].head + rig.pose.bones["upperarm_r"].head) / 2 + Vector((0, 0, 0.079))
    contacts = {"feet": "foot", "bar_body_landmark": centre}
    for side, label in ((1, "l"), (-1, "r")):
        shoulder = rig.pose.bones["upperarm_" + label].head.copy()
        forward = Vector((0, 0.15, math.sqrt(1 - 0.15 ** 2)))
        normal = Vector((0, math.sqrt(1 - 0.15 ** 2), -0.15))
        palm = centre + Vector((side * 0.34, 0, 0))
        wrist = palm - forward * _palm_length(rig, label) - normal * 0.012
        # Intersect the two fixed-length arm spheres in the plane through
        # the shoulder. Choosing its forward solution keeps elbows high.
        lower_horizontal_squared = rest["lowerarm_" + label].length ** 2 - (wrist.z - shoulder.z) ** 2
        delta = Vector((wrist.x - shoulder.x, wrist.y - shoulder.y, 0))
        distance = delta.length
        upper = rest["upperarm_" + label].length
        along = (upper ** 2 - lower_horizontal_squared + distance ** 2) / (2 * distance)
        rise_squared = upper ** 2 - along ** 2
        if lower_horizontal_squared < 0 or rise_squared < 0:
            raise ValueError("Clean front rack cannot maintain shoulder-height elbows")
        direction = delta.normalized()
        cross = Vector((-direction.y, direction.x, 0))
        centre_elbow = shoulder + direction * along
        elbows = [centre_elbow + cross * math.sqrt(rise_squared), centre_elbow - cross * math.sqrt(rise_squared)]
        elbow = min(elbows, key=lambda point: point.y)
        elbow.z = shoulder.z
        m.point(rig, "upperarm_" + label, shoulder, elbow)
        m.pronated_forearm(rig, label, elbow, wrist, normal)
        contacts[label] = m.hand(rig, label, wrist, forward, normal, True)
    return contacts


def _squat(rig, exercise_id, depth):
    m, Quaternion, Vector = _api()
    rest = rig.data.bones
    back = exercise_id == "squat"
    stance = 0.27 if back else 0.245
    toe_angle = math.radians(15)
    shin_angle = math.radians(4 + (27 if back else 30) * depth)
    thigh_angle = math.radians(6 + 90 * depth)
    anchors, knees = {}, {}
    for side, label in ((1, "l"), (-1, "r")):
        ankle = Vector((side * stance, rest["calf_" + label].tail_local.y, rest["calf_" + label].tail_local.z))
        # At standing the knee lies between the narrow hip joint and the
        # wider ankle. It tracks outward with the toes during descent.
        knee_x = side * ((abs(rest["thigh_" + label].head_local.x) + stance) / 2 + (0.132 if back else 0.117) * depth)
        shin_sagittal = math.sqrt(rest["calf_" + label].length ** 2 - (knee_x - ankle.x) ** 2)
        knee = Vector((knee_x, ankle.y - shin_sagittal * math.sin(shin_angle), ankle.z + shin_sagittal * math.cos(shin_angle)))
        anchors[label], knees[label] = ankle, knee
    projected = math.sqrt(rest["thigh_l"].length ** 2 - (knees["l"].x - rest["thigh_l"].head_local.x) ** 2)
    hip = Vector((0, knees["l"].y + projected * math.sin(thigh_angle), knees["l"].z + projected * math.cos(thigh_angle)))
    lean = Quaternion((1, 0, 0), math.radians(2 + (35 if back else 10 if exercise_id == "front_squat" else 20) * depth))
    m.torso(rig, hip, lean)
    for side, label in ((1, "l"), (-1, "r")):
        m.point(rig, "thigh_" + label, rig.pose.bones["thigh_" + label].head.copy(), knees[label])
        m.point(rig, "calf_" + label, knees[label], anchors[label])
        m.bone_rotation(rig, "foot_" + label, anchors[label], Quaternion((0, 0, 1), side * toe_angle))
    contacts = {"feet": "foot"}
    if exercise_id == "front_squat":
        return _front_rack(rig)
    if exercise_id == "goblet_squat":
        center = _body_point(rig, (0, -0.29, 1.245))
        for side, label in ((1, "l"), (-1, "r")):
            palm = center + Vector((side * 0.07, 0, 0))
            shoulder = rig.pose.bones["upperarm_" + label].head.copy()
            contacts[label] = _neutral_palm(rig, label, palm,
                shoulder + lean @ Vector((side * 0.22, -0.02, -0.32)), (0, -1, 0))
            # This prop is a curved kettlebell handle, not a straight shaft.
            contacts[label]["shaft_axis_required"] = False
        contacts["goblet_center"] = center
    else:
        center = _body_point(rig, (0, 0.096 if back else -0.135, 1.363 if back else 1.420))
        for side, label in ((1, "l"), (-1, "r")):
            palm = center + Vector((side * 0.34 if back else -side * 0.12, 0, 0))
            shoulder = rig.pose.bones["upperarm_" + label].head.copy()
            direction = lean @ Vector((0, -0.25 if back else 0, 1)).normalized()
            normal = lean @ Vector((0, -1, -0.25 if back else 0)).normalized()
            pole = shoulder + lean @ Vector((side * 0.38, 0.18 if back else -0.45, -0.28 if back else -0.22))
            if back:
                contacts[label] = _grip_at(rig, label, palm, direction, normal, pole)
            else:
                contacts[label] = _neutral_palm(rig, label, palm, shoulder + lean @ Vector((-side * 0.12, -0.38, 0)), lean @ Vector((0, 0, -1)))
                # Crossed hands stabilize the bar on the anterior shoulders;
                # this is not a closed grip around a straight shaft.
                contacts[label]["shaft_axis_required"] = False
        contacts["bar_body_landmark"] = center
    return contacts


def _curl(rig, amount):
    m, _, Vector = _api()
    rest = rig.data.bones
    m.standing(rig)
    contacts = {"feet": "foot"}
    upper_angle = math.radians(17)
    angle = upper_angle + math.radians(120 * amount)
    forward = Vector((0, -math.sin(angle), -math.cos(angle)))
    normal = Vector((0, forward.z, -forward.y))
    for side, label in ((1, "l"), (-1, "r")):
        shoulder = rig.pose.bones["upperarm_" + label].head.copy()
        upper = Vector((side * 0.12, -math.sin(upper_angle), -math.cos(upper_angle))).normalized()
        elbow = shoulder + upper * rest["upperarm_" + label].length
        wrist = elbow + forward * rest["lowerarm_" + label].length
        m.point(rig, "upperarm_" + label, shoulder, elbow)
        m.pronated_forearm(rig, label, elbow, wrist, normal)
        contacts[label] = m.hand(rig, label, wrist, forward, normal, True)
    return contacts


def _overhead(rig, amount):
    m, _, Vector = _api()
    m.standing(rig)
    rest = rig.data.bones
    shoulder = rig.pose.bones["upperarm_l"].head.copy()
    grip_x = 0.245
    projected = math.sqrt(rest["upperarm_l"].length ** 2 - (grip_x - shoulder.x) ** 2)
    lower = math.hypot(rest["lowerarm_l"].length + _palm_length(rig, "l"), 0.012)
    top_y = -0.025
    top_z = shoulder.z + math.sqrt((projected + lower - 0.000101) ** 2 - (top_y - shoulder.y) ** 2)
    amount_back = min(1, max(0, (amount - 0.58) / 0.42))
    amount_back = amount_back * amount_back * (3 - 2 * amount_back)
    center = Vector((0, -0.205 + 0.18 * amount_back, shoulder.z + 0.06 + (top_z - shoulder.z - 0.06) * amount))
    contacts = {"feet": "foot"}
    for side, label in ((1, "l"), (-1, "r")):
        palm = center + Vector((side * grip_x, 0, 0))
        contacts[label] = _neutral_grip(rig, label, palm, Vector((side * grip_x, -0.60, shoulder.z - 0.10)))
    return contacts


def _incline(rig, exercise_id, depth):
    m, Quaternion, Vector = _api()
    rest = rig.data.bones
    m.torso(rig, Vector((0, 0.15, 0.43)), Quaternion((1, 0, 0), math.radians(-45)))
    anchors = {label: Vector((side * 0.27, -0.30, rest["calf_" + label].tail_local.z)) for side, label in ((1, "l"), (-1, "r"))}
    m.legs(rig, anchors, pole_y=-1.5)
    contacts = {"feet": "foot", "bench": {"incline_deg": 45}}
    shoulder = rig.pose.bones["upperarm_l"].head.copy()
    for side, label in ((1, "l"), (-1, "r")):
        grip_x = 0.26 if exercise_id == "incline_barbell" else 0.25 + 0.10 * depth
        projected = math.sqrt(rest["upperarm_" + label].length ** 2 - (grip_x - abs(shoulder.x)) ** 2)
        lower = math.hypot(rest["lowerarm_" + label].length + _palm_length(rig, label), 0.012)
        y_offset = -0.08
        extension = math.sqrt((projected + lower - 0.000101) ** 2 - y_offset ** 2)
        bottom = 0.18
        palm = Vector((side * grip_x, shoulder.y + y_offset, shoulder.z + extension * (1 - depth) + bottom * depth))
        contacts[label] = _neutral_grip(rig, label, palm, Vector((side * grip_x, shoulder.y - 0.48, shoulder.z - 0.25)))
    return contacts


def _straight_deadlift(rig, exercise_id, depth):
    m, Quaternion, Vector = _api()
    rest = rig.data.bones
    sumo = exercise_id == "896189fc-30d9-51df-aa19-fd5ea7fa76eb"
    stance = 0.45 if sumo else 0.18849063
    anchors = {label: Vector((side * stance, rest["calf_" + label].tail_local.y, rest["calf_" + label].tail_local.z)) for side, label in ((1, "l"), (-1, "r"))}
    if sumo:
        # Wide-stance top height follows the exact fixed leg lengths. The
        # bottom has more knee flexion and a more upright torso than a hinge.
        lateral = stance - rest["thigh_l"].head_local.x
        top_z = anchors["l"].z + math.sqrt((rest["thigh_l"].length + rest["calf_l"].length - 0.0004) ** 2 - lateral ** 2 - (0.012 - anchors["l"].y) ** 2)
        hip = Vector((0, 0.012 + 0.165 * depth, top_z - 0.339 * depth))
        lean = Quaternion((1, 0, 0), math.radians(36 * depth))
        m.torso(rig, hip, lean)
        for side, label in ((1, "l"), (-1, "r")):
            head = rig.pose.bones["thigh_" + label].head.copy()
            pole = Vector((side * 0.62, -0.55, hip.z - 0.20))
            knee, achieved = m.two_bone(head, anchors[label], rest["thigh_" + label].length, rest["calf_" + label].length, pole)
            if (achieved - anchors[label]).length > 0.00001:
                raise ValueError("Sumo fixed foot cannot be reached")
            m.point(rig, "thigh_" + label, head, knee)
            m.point(rig, "calf_" + label, knee, anchors[label])
            m.bone_rotation(rig, "foot_" + label, anchors[label], Quaternion((0, 0, 1), side * math.radians(35)))
        grip_x = 0.205
    else:
        # Twelve-degree knees are deliberately distinct from the 25-degree RDL.
        length = 0.815
        ankle = anchors["l"]
        lateral = rest["thigh_l"].head_local.x - ankle.x
        hip_y = 0.02 + 0.275 * depth
        hip_z = ankle.z + math.sqrt(length ** 2 - lateral ** 2 - (hip_y - ankle.y) ** 2)
        m.torso(rig, Vector((0, hip_y, hip_z)), Quaternion((1, 0, 0), math.radians(75 * depth)))
        m.legs(rig, anchors)
        grip_x = 0.23
    shoulder = rig.pose.bones["upperarm_l"].head.copy()
    upper = math.sqrt(rest["upperarm_l"].length ** 2 - (grip_x - shoulder.x) ** 2)
    lower = math.hypot(rest["lowerarm_l"].length + _palm_length(rig, "l"), 0.012)
    # The heavy athlete's thigh surface sits in front of its bone centres.
    # A bar hung at shoulder Y would pass through that surface at lockout.
    # The authored path remains in front of the legs throughout the lift.
    y = -0.215
    z = shoulder.z - math.sqrt((upper + lower - 0.000101) ** 2 - (y - shoulder.y) ** 2)
    contacts = {"feet": "foot"}
    for side, label in ((1, "l"), (-1, "r")):
        palm = Vector((side * grip_x, y, z))
        contacts[label] = _neutral_grip(rig, label, palm, Vector((side * grip_x, shoulder.y + 0.30, shoulder.z - 0.25)))
    return contacts


def _hip_load_surface(rig, hip, pad_radius=0.050):
    """Find the actual upper hip skin before seating the protective bar pad.

    Bending this sculpted athlete moves its thigh volume above the bony hip
    landmark. Sampling the evaluated skin prevents the initial loaded thrust
    from placing its bar through those thighs. Only the armature modifier is
    temporarily enabled; the renderer restores its own modifier state.
    """
    import bpy
    from mathutils.bvhtree import BVHTree
    _, _, Vector = _api()
    body = bpy.data.objects["SetflowAthlete.body"]
    states = [(modifier, modifier.show_viewport) for modifier in body.modifiers]
    for modifier, _ in states:
        modifier.show_viewport = modifier.type == "ARMATURE"
    bpy.context.view_layer.update()
    evaluated = body.evaluated_get(bpy.context.evaluated_depsgraph_get())
    mesh = evaluated.to_mesh()
    world = rig.matrix_world
    try:
        vertices = [body.matrix_world @ vertex.co for vertex in mesh.vertices]
        tree = BVHTree.FromPolygons(vertices, [tuple(face.vertices) for face in mesh.polygons])
        centre = world @ (hip + Vector((0, 0.02, 0)))
        height = max(vertex.z for vertex in vertices) + 1
        tops = []
        xs = [-0.19 + 0.38 * index / 48 for index in range(49)]
        for x in xs:
            hit, _, _, _ = tree.ray_cast(Vector((x, centre.y, height)), Vector((0, 0, -1)))
            if hit is not None:
                tops.append(hit.z)
        if not tops:
            raise ValueError("Hip bar has no skin surface support")
        # A sloping surface needs more vertical separation than the radius.
        # Solve the cylinder-to-skin distance, rather than assuming a flat
        # bony hip plane or letting a thick foam pad penetrate the thighs.
        low, high = max(tops), max(tops) + pad_radius * 4
        for _ in range(13):
            trial = (low + high) / 2
            nearest = [tree.find_nearest(Vector((x, centre.y, trial)))[3] for x in xs]
            if min(nearest) >= pad_radius + 0.003:
                high = trial
            else:
                low = trial
        centre.z = high
        return world.inverted() @ centre
    finally:
        evaluated.to_mesh_clear()
        for modifier, state in states:
            modifier.show_viewport = state
        bpy.context.view_layer.update()


_BACK_CLOUD = None
_BACK_IDS = None


def _back_cloud():
    """Native rest-skin profile for a rolling floor shoulder contact."""
    global _BACK_CLOUD, _BACK_IDS
    if _BACK_CLOUD is None:
        import bpy
        _, _, Vector = _api()
        body = bpy.data.objects["SetflowAthlete.body"]
        vertices = [vertex for vertex in body.data.vertices
                    if abs(vertex.co.x) < 0.16 and vertex.co.y > 0.025
                    and 1.15 < vertex.co.z < 1.42]
        _BACK_CLOUD = tuple(Vector(vertex.co) for vertex in vertices)
        _BACK_IDS = tuple(vertex.index for vertex in vertices)
    return _BACK_CLOUD


def _back_skin_floor():
    """Actual weighted skin, including its small upper-arm blend weights."""
    import bpy
    body = bpy.data.objects["SetflowAthlete.body"]
    states = [(modifier, modifier.show_viewport) for modifier in body.modifiers]
    for modifier, _ in states:
        modifier.show_viewport = modifier.type == "ARMATURE"
    bpy.context.view_layer.update()
    evaluated = body.evaluated_get(bpy.context.evaluated_depsgraph_get())
    mesh = evaluated.to_mesh()
    try:
        return min((body.matrix_world @ mesh.vertices[index].co).z for index in _BACK_IDS)
    finally:
        evaluated.to_mesh_clear()
        for modifier, state in states:
            modifier.show_viewport = state
        bpy.context.view_layer.update()


def _bridge(rig, exercise_id, amount):
    m, Quaternion, Vector = _api()
    rest = rig.data.bones
    elevated = exercise_id == "hip_thrust"
    angle = (-50 - 40 * amount) if elevated else (-90 - 26 * amount)
    rotation = Quaternion((1, 0, 0), math.radians(angle))
    shoulder_rest = (rest["upperarm_l"].head_local + rest["upperarm_r"].head_local) / 2
    hip_rest = m.hip_center(rig)
    if elevated:
        # The support is the posterior shoulder skin at the bench's front
        # edge, rather than a bony shoulder pivot inside the thick torso.
        pivot = Vector((0, 0.62 - 0.19 / rig.scale.x, 0.40))
        hip = pivot - rotation @ (Vector((0, 0.104, 1.280)) - hip_rest)
    else:
        # As hips rise, contact rolls toward the upper shoulders. Preserve
        # an actual floor surface contact instead of suspending that skin.
        hip_y = 0.48 - (rotation @ (shoulder_rest - hip_rest)).y
        lowest_back = min((rotation @ (point - hip_rest)).z for point in _back_cloud())
        hip = Vector((0, hip_y, 0.007 / rig.scale.x - lowest_back))
        pivot = None
    m.torso(rig, hip, rotation)
    anchors = {label: Vector((side * 0.23, -0.32 if elevated else -0.40, rest["calf_" + label].tail_local.z)) for side, label in ((1, "l"), (-1, "r"))}
    m.legs(rig, anchors, pole_y=-0.22, pole_z=0.85)
    # Keep the head above its support instead of driving it into the floor
    # as the pelvis rises around a fixed shoulder contact.
    neck = rig.pose.bones["neck_01"].head.copy()
    m.bone_rotation(rig, "neck_01", neck, Quaternion((1, 0, 0), math.radians(angle + 15 if elevated else -86.5)))
    center = _hip_load_surface(rig, hip)
    contacts = {"feet": "foot", "upper_back_pivot": pivot, "bar_hip_landmark": center}
    for side, label in ((1, "l"), (-1, "r")):
        palm = center + Vector((side * 0.30, 0, 0))
        shoulder = rig.pose.bones["upperarm_" + label].head.copy()
        direction = Vector((0, -1, 0))
        normal = Vector((0, 0, -1))
        contacts[label] = _grip_at(rig, label, palm, direction, normal, shoulder + Vector((side * 0.35, -0.25, -0.15)))
    if not elevated:
        correction = (0.007 - _back_skin_floor()) / rig.scale.x
        if abs(correction) > 0.0001:
            hip.z += correction
            m.torso(rig, hip, rotation)
            m.legs(rig, anchors, pole_y=-0.22, pole_z=0.85)
            neck = rig.pose.bones["neck_01"].head.copy()
            m.bone_rotation(rig, "neck_01", neck, Quaternion((1, 0, 0), math.radians(-86.5)))
            center = _hip_load_surface(rig, hip)
            contacts["bar_hip_landmark"] = center
            for side, label in ((1, "l"), (-1, "r")):
                palm = center + Vector((side * 0.30, 0, 0))
                shoulder = rig.pose.bones["upperarm_" + label].head.copy()
                contacts[label] = _grip_at(rig, label, palm, (0, -1, 0), (0, 0, -1),
                                         shoulder + Vector((side * 0.35, -0.25, -0.15)))
    return contacts


def pose(rig, exercise_id, amount):
    if exercise_id not in SUPPORTED:
        raise ValueError("Strength motion not authored: " + exercise_id)
    m, _, _ = _api()
    m.reset(rig)
    if exercise_id in ("squat", "front_squat", "goblet_squat"):
        contacts = _squat(rig, exercise_id, amount)
    elif exercise_id == "barbell_curl":
        contacts = _curl(rig, amount)
    elif exercise_id == "ohp":
        contacts = _overhead(rig, amount)
    elif exercise_id in ("incline", "incline_barbell"):
        contacts = _incline(rig, exercise_id, amount)
    elif exercise_id in ("hip_thrust", "glute_bridge"):
        contacts = _bridge(rig, exercise_id, amount)
    else:
        contacts = _straight_deadlift(rig, exercise_id, amount)
    m.update()
    return contacts


def phase(exercise_id, seconds):
    m, _, _ = _api()
    amount = m.cycle(seconds)
    # A sumo deadlift starts from a grounded bar; a stiff-legged hinge starts
    # from standing. They do not share an interchangeable animation phase.
    return 1 - amount if exercise_id == "896189fc-30d9-51df-aa19-fd5ea7fa76eb" else amount


def _sub(a, b):
    return tuple(x - y for x, y in zip(a, b))


def _length(a):
    return math.sqrt(sum(x * x for x in a))


def _angle(a, b):
    ratio = sum(x * y for x, y in zip(a, b)) / (_length(a) * _length(b))
    return math.degrees(math.acos(max(-1, min(1, ratio))))


def audit(rows, exercise_id):
    """Per-variant production guards, separate from human trainer review."""
    if not rows:
        return {"passed": False, "failures": ["No samples"]}
    start = min(rows, key=lambda row: row["amount"])
    peak = max(rows, key=lambda row: row["amount"])
    def elbow(row, label):
        bones = row["bones"]
        return _angle(_sub(bones["upperarm_" + label]["tail"], bones["upperarm_" + label]["head"]),
                      _sub(bones["lowerarm_" + label]["tail"], bones["lowerarm_" + label]["head"]))
    def knee(row, label):
        bones = row["bones"]
        return _angle(_sub(bones["thigh_" + label]["tail"], bones["thigh_" + label]["head"]),
                      _sub(bones["calf_" + label]["tail"], bones["calf_" + label]["head"]))
    def wrist(row, label):
        bones = row["bones"]
        return _angle(_sub(bones["lowerarm_" + label]["tail"], bones["lowerarm_" + label]["head"]),
                      _sub(bones["middle_01_" + label]["head"], bones["hand_" + label]["head"]))
    def drift(names):
        return max(_length(_sub(row["bones"][name]["head"], start["bones"][name]["head"])) for row in rows for name in names)
    metrics = {
        "start_elbow_bend_deg": max(elbow(start, label) for label in ("l", "r")),
        "peak_elbow_bend_deg": max(elbow(peak, label) for label in ("l", "r")),
        "max_wrist_angle_deg": max(wrist(row, label) for row in rows for label in ("l", "r")),
        "start_knee_bend_deg": max(knee(start, label) for label in ("l", "r")),
        "peak_knee_bend_deg": max(knee(peak, label) for label in ("l", "r")),
        "fixed_foot_drift_m": drift(("foot_l", "foot_r")),
    }
    failures = []
    def require(condition, message):
        if not condition:
            failures.append(message)
    require(metrics["fixed_foot_drift_m"] < 0.0001, "Planted feet moved")
    if exercise_id in ("squat", "front_squat", "goblet_squat"):
        b = peak["bones"]
        metrics["peak_hip_minus_knee_z_m"] = max(b["thigh_" + label]["head"][2] - b["thigh_" + label]["tail"][2] for label in ("l", "r"))
        require(metrics["peak_hip_minus_knee_z_m"] <= 0.008, "Squat did not reach thigh-parallel")
        require(metrics["peak_knee_bend_deg"] > 100, "Squat flexion range missing")
        require(metrics["start_knee_bend_deg"] < 18, "Squat failed to return to standing")
    if exercise_id == "front_squat":
        heights = [row["bones"]["lowerarm_" + label]["head"][2] - row["bones"]["upperarm_" + label]["head"][2]
                   for row in rows for label in ("l", "r")]
        forward_offsets = [row["bones"]["upperarm_" + label]["head"][1] - row["bones"]["lowerarm_" + label]["head"][1]
                           for row in rows for label in ("l", "r")]
        flexions = [elbow(row, label) for row in rows for label in ("l", "r")]
        metrics["min_elbow_above_shoulder_m"] = min(heights)
        metrics["min_elbow_forward_m"] = min(forward_offsets)
        metrics["rack_elbow_bend_range_deg"] = max(flexions) - min(flexions)
        metrics["rack_elbow_bend_min_deg"] = min(flexions)
        metrics["rack_elbow_bend_max_deg"] = max(flexions)
        require(min(heights) >= -0.0001 and max(heights) < 0.004, "Front-rack elbows must remain at shoulder height")
        require(min(forward_offsets) > 0.20, "Front-rack elbows are not forward")
        require(min(flexions) > 120 and max(flexions) < 155, "Front rack excessively folds or extends elbows")
        require(metrics["rack_elbow_bend_range_deg"] < 0.1, "Front rack changes elbow position during the squat")
        require(metrics["max_wrist_angle_deg"] < 95, "Front-rack wrist extension is excessive for this authored pose")
    if exercise_id == "barbell_curl":
        metrics["upper_arm_drift_m"] = drift(("lowerarm_l", "lowerarm_r"))
        metrics["core_drift_m"] = drift(("pelvis", "spine_01", "spine_03", "neck_01"))
        require(metrics["upper_arm_drift_m"] < 0.0001, "Curl moved upper arms")
        require(metrics["core_drift_m"] < 0.0001, "Curl swung torso")
        require(metrics["start_elbow_bend_deg"] < 10 and metrics["peak_elbow_bend_deg"] > 110, "Curl range missing")
    if exercise_id in ("barbell_curl", "ohp", "incline", "incline_barbell", "896189fc-30d9-51df-aa19-fd5ea7fa76eb", "58acf002-4e6d-5e95-b252-cae16252cef8"):
        require(metrics["max_wrist_angle_deg"] < 5, "Dynamic load-bearing wrist is bent")
    if exercise_id in ("ohp", "incline", "incline_barbell"):
        extension = metrics["peak_elbow_bend_deg"] if exercise_id == "ohp" else metrics["start_elbow_bend_deg"]
        require(extension < 18, "Press lockout remains bent")
        metrics["core_drift_m"] = drift(("pelvis", "spine_01", "spine_03", "neck_01"))
        require(metrics["core_drift_m"] < 0.0001, "Press moved supported trunk")
    if exercise_id in ("hip_thrust", "glute_bridge"):
        def shoulder(row):
            return tuple((x + y) / 2 for x, y in zip(row["bones"]["upperarm_l"]["head"], row["bones"]["upperarm_r"]["head"]))
        metrics["shoulder_bone_drift_m"] = max(_length(_sub(shoulder(row), shoulder(start))) for row in rows)
        metrics["hip_rise_m"] = peak["bones"]["thigh_l"]["head"][2] - start["bones"]["thigh_l"]["head"][2]
        torso_vector = _sub(shoulder(peak), peak["bones"]["thigh_l"]["head"])
        thigh_vector = _sub(peak["bones"]["thigh_l"]["head"], peak["bones"]["thigh_l"]["tail"])
        torso_vector = (0, torso_vector[1], torso_vector[2])
        thigh_vector = (0, thigh_vector[1], thigh_vector[2])
        metrics["peak_torso_thigh_alignment_deg"] = _angle(torso_vector, thigh_vector)
        if exercise_id == "hip_thrust":
            def contact_point(row):
                bones = row["bones"]
                hips = tuple((x + y) / 2 for x, y in zip(bones["thigh_l"]["head"], bones["thigh_r"]["head"]))
                offset = _sub(shoulder(row), hips)
                rest_y, rest_z = -0.02498307, 0.4451238
                angle = math.atan2(-offset[1], offset[2]) - math.atan2(-rest_y, rest_z)
                scale = _length(offset) / math.hypot(rest_y, rest_z)
                dy, dz = 0.104 - 0.01146485, 1.280 - 0.8825742
                return (hips[0], hips[1] + scale * (dy * math.cos(angle) - dz * math.sin(angle)),
                        hips[2] + scale * (dy * math.sin(angle) + dz * math.cos(angle)))
            metrics["posterior_support_landmark_drift_m"] = max(_length(_sub(contact_point(row), contact_point(start))) for row in rows)
            require(metrics["posterior_support_landmark_drift_m"] < 0.0001, "Hip thrust moved bench contact landmark")
        else:
            metrics["support_variant"] = "Posterior upper-back skin rolls on mat while feet stay planted"
        require(metrics["hip_rise_m"] > 0.15, "Bridge lacks hip extension")
        require(metrics["peak_torso_thigh_alignment_deg"] < 15, "Bridge top is not aligned")
    if exercise_id == "896189fc-30d9-51df-aa19-fd5ea7fa76eb":
        require(metrics["start_elbow_bend_deg"] < 8 and metrics["peak_elbow_bend_deg"] < 8, "Sumo deadlift arms bend")
        require(metrics["peak_knee_bend_deg"] > 45 and metrics["start_knee_bend_deg"] < 12, "Sumo knee-extension range missing")
        metrics["foot_width_m"] = abs(start["bones"]["foot_l"]["head"][0] - start["bones"]["foot_r"]["head"][0])
        metrics["grip_width_m"] = abs(start["bones"]["middle_01_l"]["head"][0] - start["bones"]["middle_01_r"]["head"][0])
        require(metrics["foot_width_m"] > 0.85 and metrics["grip_width_m"] < 0.55, "Sumo stance or inside grip missing")
    if exercise_id == "58acf002-4e6d-5e95-b252-cae16252cef8":
        knees = [knee(row, label) for row in rows for label in ("l", "r")]
        metrics["knee_bend_range_deg"] = max(knees) - min(knees)
        require(3 < min(knees) and max(knees) < 16, "Stiff-leg knee bend must stay slight")
        require(metrics["knee_bend_range_deg"] < 0.1, "Stiff-leg knees change through hinge")
        require(max(elbow(row, label) for row in rows for label in ("l", "r")) < 8, "Stiff-leg arms bend")
    return {"exercise_id": exercise_id, "passed": not failures, "metrics": metrics, "failures": failures,
            "review_status": "trainer_pending", "threshold_scope": "Production guards for this authored model variant; not trainer certification"}
