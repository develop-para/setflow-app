"""Three exact seated/mechanically coupled cardio drafts, trainer pending.

Cranks turn forwards, elliptical pedals and arms share one rigid linkage,
and rowing drive/recovery sequencing is authored separately. Angles, cadence
and equipment dimensions select this native athlete, not universal advice.
"""
import math
import json

SUPPORTED = ("stationary_bike", "elliptical", "rowing_machine")
REGIONS = {"stationary_bike": ("quadriceps", "glutes", "hamstrings", "calves"),
           "elliptical": ("quadriceps", "glutes", "hamstrings", "calves", "deltoids"),
           "rowing_machine": ("quadriceps", "glutes", "hamstrings", "lats", "biceps", "erectors")}
FIXED_CONTACTS = {"stationary_bike": ("pelvis", "head", "hand_l", "hand_r"),
                  "elliptical": ("pelvis", "head"), "rowing_machine": ("foot_l", "foot_r")}
POSE_SECONDS = {"stationary_bike": {"start": 0., "middle": .4947916667, "peak": .9895833333},
                "elliptical": {"start": 0., "middle": .4947916667, "peak": .9895833333},
                "rowing_machine": {"start": 0., "middle": .8, "peak": 1.2}}
VIEWS = {"stationary_bike": {"location": (4.8, -3.1, 2.6), "target": (0, -.12, 1.03), "ortho_scale": 2.85},
         "elliptical": {"location": (4.8, -3.2, 2.4), "target": (0, -.15, 1.00), "ortho_scale": 3.10},
         "rowing_machine": {"location": (4.8, -2.8, 2.4), "target": (0, -.36, .78), "ortho_scale": 3.25}}
REFERENCES = {
    "stationary_bike": {"references": ["https://support.lifefitness.com/hc/en-us/articles/42862231037335-How-to-Adjust-the-Seat-on-Your-Life-Fitness-Atmos-Upright-Bike", "https://support.lifefitness.com/hc/en-us/articles/42862246498199-How-to-Adjust-the-Pedal-Straps-on-Your-Atmos-Cardio-Series-Bike"],
        "source_id": "Bicycling_Stationary", "variant": "Seated upright stationary ergometer, fixed front bar, forward cranks and strapped trainer forefeet",
        "source_scope": "Official technique: balls of feet on pedals, nonlocking slight knee bend at fullest reach, stable saddle and fitted straps. Own generic geometry and slow demonstration cadence, not an Atmos product replica."},
    "elliptical": {"references": ["https://kb.cybexintl.com/Owners_Manuals/Cross_Trainer/OM_CSX_Club_Series_Cross_Trainer.pdf", "https://support.lifefitness.com/hc/en-us/articles/42861901438359-How-to-Mount-and-Dismount-Your-Atmos-Elliptical-Safely"],
        "source_id": "Elliptical_Trainer", "variant": "Forward elliptical pedaling, paired real crank/coupler/rocker linkage and moving push/pull grips",
        "source_scope": "Official CSX manual printed pages 4/6/25: elliptical pedal action, moving-arm push/pull, shoes and forward-facing mode. The original four-bar linkage and its phases are selected geometry, not manufacturer design data."},
    "rowing_machine": {"references": ["https://www.concept2.com/training/rowing-technique", "https://www.britishrowing.org/indoor-rowing/go-row-indoor/how-to-indoor-row/british-rowing-technique/"],
        "source_id": "Rowing_Stationary", "variant": "Sliding-seat ergometer with strapped footstretchers, overhand handle, legs/body/arms drive and arms/body/legs recovery",
        "source_scope": "Concept2 and British Rowing original instructions, not the ambiguous upstream order. Flat wrists, relaxed shoulders, catch shins near vertical, low-rib finish and recovery longer than drive. Own generic rower, no branded geometry."},
}
for _reference in REFERENCES.values():
    _reference["trainerApproved"] = False
    _reference["humanTrainerApproval"] = False

BIKE_CRANK = (0, -.26, .37)
BIKE_RADIUS = .145
ELLIPTICAL_REAR = (.42, .32)
ELLIPTICAL_FRONT = (-.55, .85)
ELLIPTICAL_RADIUS = .16
ELLIPTICAL_ROCKER = .75
ELLIPTICAL_COUPLER = 1.07
ELLIPTICAL_PEDAL_FRACTION = .55


def _api():
    import motions
    import cardio_footwear
    from mathutils import Vector, Quaternion
    return motions, cardio_footwear, Vector, Quaternion


def _circle_intersection(first, first_radius, second, second_radius):
    dy, dz = second[0] - first[0], second[1] - first[1]
    distance = math.hypot(dy, dz)
    if not abs(first_radius - second_radius) < distance < first_radius + second_radius:
        raise ValueError("Elliptical rigid linkage cannot close")
    along = (first_radius ** 2 - second_radius ** 2 + distance ** 2) / (2 * distance)
    height = math.sqrt(first_radius ** 2 - along ** 2)
    base = (first[0] + dy / distance * along, first[1] + dz / distance * along)
    candidates = ((base[0] - dz / distance * height, base[1] + dy / distance * height),
                  (base[0] + dz / distance * height, base[1] - dy / distance * height))
    return min(candidates, key=lambda point: point[1])


def elliptical_linkage(amount, side):
    angle = 4 * math.pi * amount + (math.pi if side < 0 else 0)
    # Forward-facing rider: the front (negative-Y) pedal portion descends.
    # The actual four-bar coupler reverses the sign relative to a bike's
    # forefoot crank target, so its orientation is checked on pedal samples.
    rear = (ELLIPTICAL_REAR[0] + ELLIPTICAL_RADIUS * math.cos(angle), ELLIPTICAL_REAR[1] + ELLIPTICAL_RADIUS * math.sin(angle))
    front = _circle_intersection(rear, ELLIPTICAL_COUPLER, ELLIPTICAL_FRONT, ELLIPTICAL_ROCKER)
    pedal = tuple(rear[axis] + (front[axis] - rear[axis]) * ELLIPTICAL_PEDAL_FRACTION for axis in range(2))
    handle = tuple(ELLIPTICAL_FRONT[axis] - (front[axis] - ELLIPTICAL_FRONT[axis]) * .55 / ELLIPTICAL_ROCKER for axis in range(2))
    pitch = math.atan2(-(front[1] - rear[1]), -(front[0] - rear[0]))
    return rear, front, pedal, handle, pitch


def _foot(rig, label, sole_target, rotation, pole):
    m, footwear, V, _ = _api()
    bone, local = footwear.rest_contact(rig, label, "forefoot")
    rest_point = rig.data.bones[bone].matrix_local @ local
    offset = rotation @ (rest_point - rig.data.bones["foot_" + label].head_local)
    ankle = V(sole_target) - offset
    hip = rig.pose.bones["thigh_" + label].head.copy()
    knee, achieved = m.two_bone(hip, ankle, rig.data.bones["thigh_" + label].length,
                               rig.data.bones["calf_" + label].length, V(pole))
    if (achieved - ankle).length > .00001:
        raise ValueError("Actual strapped sole target outside leg reach: " + label)
    m.point(rig, "thigh_" + label, hip, knee)
    m.point(rig, "calf_" + label, knee, ankle)
    m.bone_rotation(rig, "foot_" + label, ankle, rotation)
    return ankle


def _grip(rig, label, point, axis, pole):
    from remaining_strength_motions import _axis_grip
    return _axis_grip(rig, label, point, pole, axis)


def _bike(rig, amount):
    m, footwear, V, Q = _api()
    bone, local = footwear.rest_contact(rig, "l", "forefoot")
    offset = rig.data.bones[bone].matrix_local @ local - rig.data.bones["foot_l"].head_local
    upper, lower = rig.data.bones["thigh_l"].length, rig.data.bones["calf_l"].length
    reach = math.sqrt(upper ** 2 + lower ** 2 + 2 * upper * lower * math.cos(math.radians(27)))
    dx = .18 - rig.data.bones["thigh_l"].head_local.x
    plane = math.sqrt(reach ** 2 - dx ** 2) - BIKE_RADIUS
    dy = .12 - (BIKE_CRANK[1] - offset.y)
    hip_z = BIKE_CRANK[2] + .0168 / rig.scale.x - offset.z + math.sqrt(plane ** 2 - dy ** 2)
    m.torso(rig, V((0, .12, hip_z)), Q((1, 0, 0), math.radians(12)))
    contacts = {"motion_amount": amount, "crank_angle_rad": 4 * math.pi * amount}
    for side, label in ((1, "l"), (-1, "r")):
        angle = contacts["crank_angle_rad"] + (math.pi if side < 0 else 0)
        y, z = BIKE_CRANK[1] - BIKE_RADIUS * math.cos(angle), BIKE_CRANK[2] - BIKE_RADIUS * math.sin(angle)
        bone, local = footwear.rest_contact(rig, label, "forefoot")
        offset = rig.data.bones[bone].matrix_local @ local - rig.data.bones["foot_" + label].head_local
        contacts["pedal_" + label] = V((side * .18, y, z))
        target = V((side * .18 + offset.x, y, z + .0168 / rig.scale.x))
        _foot(rig, label, target, Q((1, 0, 0), 0), (side * .25, -.62, .63))
        contacts[label] = _grip(rig, label, (side * .23, -.34, 1.21), (1, 0, 0), (side * .23, -.18, 1.0))
    return contacts


def _elliptical(rig, amount):
    m, footwear, V, Q = _api()
    m.torso(rig, V((0, -.08, 1.01)), Q((1, 0, 0), math.radians(4)))
    contacts = {"motion_amount": amount, "linkage": {}}
    for side, label in ((1, "l"), (-1, "r")):
        rear, front, pedal, handle, pitch = elliptical_linkage(amount, side)
        rotation = Q((1, 0, 0), pitch)
        bone, local = footwear.rest_contact(rig, label, "forefoot")
        offset = rotation @ (rig.data.bones[bone].matrix_local @ local - rig.data.bones["foot_" + label].head_local)
        normal = rotation @ V((0, 0, 1))
        center = V((side * .21, *pedal))
        target = center + normal * (.0308 / rig.scale.x)
        target.x += offset.x
        _foot(rig, label, target, rotation, (side * .27, -.66, .76))
        axis = V((0, ELLIPTICAL_FRONT[0] - front[0], ELLIPTICAL_FRONT[1] - front[1])).normalized()
        grip = V((side * .34, *handle))
        contacts[label] = _grip(rig, label, grip, axis, (side * .45, -.18, 1.1))
        contacts["linkage"][label] = {"rear": V((side * .21, *rear)), "front": V((side * .21, *front)), "pedal": center, "handle": grip, "pitch_rad": pitch}
    return contacts


def _smooth(amount, start, finish):
    value = min(1., max(0., (amount - start) / (finish - start)))
    return value * value * (3 - 2 * value)


def rowing_sequence(amount):
    legs = _smooth(amount, 0, .18) if amount <= .30 else 1 - _smooth(amount, .60, 1.)
    body = _smooth(amount, .17, .24) if amount <= .30 else 1 - _smooth(amount, .46, .60)
    arms = _smooth(amount, .24, .30) if amount <= .30 else 1 - _smooth(amount, .30, .46)
    return legs, body, arms


def _rower(rig, amount):
    m, footwear, V, Q = _api()
    legs, body, arms = rowing_sequence(amount)
    foot_rotation = Q((1, 0, 0), math.radians(-40))
    anchors = {}
    for side, label in ((1, "l"), (-1, "r")):
        bone, local = footwear.rest_contact(rig, label, "forefoot")
        offset = foot_rotation @ (rig.data.bones[bone].matrix_local @ local - rig.data.bones["foot_" + label].head_local)
        target = V((side * .18 + offset.x, -.70, .31))
        anchors[label] = target - offset
    reference = anchors["l"]
    hip_z = .57 + float(rig.get("cardio_rower_fit_override", 0.))
    if rig.get("cardio_rower_hip_fit_json") and not rig.get("cardio_rower_fitting"):
        fit = json.loads(rig["cardio_rower_hip_fit_json"])
        scaled = amount * (len(fit) - 1)
        index = min(len(fit) - 2, int(scaled))
        hip_z += fit[index] * (1 - (scaled - index)) + fit[index + 1] * (scaled - index)
    hip_x = m.hip_center(rig).x + rig.data.bones["thigh_l"].head_local.x
    dx = hip_x - reference.x
    upper, lower = rig.data.bones["thigh_l"].length, rig.data.bones["calf_l"].length
    catch_y = reference.y + math.sqrt(upper ** 2 - dx ** 2 - (hip_z - reference.z - lower) ** 2)
    finish_y = reference.y + math.sqrt((upper + lower - .0015) ** 2 - dx ** 2 - (hip_z - reference.z) ** 2)
    hip = V((0, catch_y + (finish_y - catch_y) * legs, hip_z))
    m.torso(rig, hip, Q((1, 0, 0), math.radians(25 - 40 * body)))
    for side, label in ((1, "l"), (-1, "r")):
        target = reference.copy() if label == "l" else anchors[label]
        bone, local = footwear.rest_contact(rig, label, "forefoot")
        offset = foot_rotation @ (rig.data.bones[bone].matrix_local @ local - rig.data.bones["foot_" + label].head_local)
        _foot(rig, label, target + offset, foot_rotation, (target.x, target.y, target.z + 1))
    shoulder = rig.pose.bones["upperarm_l"].head.copy()
    from remaining_strength_motions import _palm_length
    # The native athlete has broad shoulders. Matching its shoulder planes
    # lets the actual upper arm and forearm extend in one plane; the former
    # narrow grip retained a 9-degree out-of-plane elbow bend at the catch.
    grip_x, bar_z = abs(shoulder.x), .82
    projected = math.sqrt(rig.data.bones["upperarm_l"].length ** 2 - (grip_x - shoulder.x) ** 2)
    effective = math.hypot(rig.data.bones["lowerarm_l"].length + _palm_length(rig, "l"), .012)
    straight_y = shoulder.y - math.sqrt((projected + effective - .000101) ** 2 - (bar_z - shoulder.z) ** 2)
    bar_y = straight_y * (1 - arms) + (shoulder.y - .23) * arms
    contacts = {"motion_amount": amount, "rowing_stages": (legs, body, arms), "rower_hip": hip,
                "rower_handle": V((0, bar_y, bar_z)), "rower_foot_rotation_rad": math.radians(-40)}
    for side, label in ((1, "l"), (-1, "r")):
        contacts[label] = _grip(rig, label, (side * grip_x, bar_y, bar_z), (1, 0, 0), (side * grip_x, shoulder.y + .35, shoulder.z - .2))
    return contacts


def phase(exercise_id, seconds):
    if exercise_id not in SUPPORTED:
        raise ValueError("Unknown exact cardio extra phase")
    return min(1., max(0., seconds / (95 / 24)))


def pose(rig, exercise_id, amount):
    if exercise_id not in SUPPORTED or not 0 <= amount <= 1:
        raise ValueError("Unknown exact cardio extra motion")
    _api()[0].reset(rig)
    return {"stationary_bike": _bike, "elliptical": _elliptical, "rowing_machine": _rower}[exercise_id](rig, amount)


def audit(rows, exercise_id):
    import technique as t
    if exercise_id not in SUPPORTED or not rows:
        return {"passed": False, "failures": ["Missing exact cardio extra native frames"]}
    failures, metrics = [], {}
    def check(value, name, low, high):
        metrics[name] = value
        if not math.isfinite(value) or not low <= value <= high:
            failures.append(name + " outside selected native model variant")
    check(t.connected_joint_gap(rows), "connected_joint_max_gap_m", 0, .0001)
    for label in ("l", "r"):
        check(max(t.angle_degrees(t.subtract(t.joint(row, "middle_01_" + label), t.joint(row, "hand_" + label)),
                                  t.subtract(t.joint(row, "lowerarm_" + label, "tail"), t.joint(row, "lowerarm_" + label))) for row in rows), label + "_neutral_wrist_axis_error_deg", 0, .01)
        if exercise_id == "stationary_bike":
            check(min(t.bend_degrees(row, "thigh_" + label, "calf_" + label) for row in rows), label + "_minimum_knee_bend_deg", 10, 45)
        if exercise_id == "rowing_machine":
            catch = min(rows, key=lambda row: row["amount"])
            shin = t.subtract(t.joint(catch, "calf_" + label, "tail"), t.joint(catch, "calf_" + label))
            check(t.angle_degrees(shin, (0, 0, -1)), label + "_catch_shin_from_vertical_deg", 0, 5)
            straight = [row for row in rows if rowing_sequence(row["amount"])[2] < .00001]
            check(max(t.bend_degrees(row, "upperarm_" + label, "lowerarm_" + label) for row in straight), label + "_straight_arm_stage_max_elbow_bend_deg", 0, 6)
            finish = min(rows, key=lambda row: abs(row["amount"] - .30))
            check(t.bend_degrees(finish, "thigh_" + label, "calf_" + label), label + "_finish_model_knee_bend_deg", 0, 12)
    if exercise_id == "rowing_machine":
        def pitch(row):
            direction = t.subtract(t.joint(row, "spine_03", "tail"), t.joint(row, "spine_03"))
            return math.degrees(math.atan2(-direction[1], direction[2]))
        initial = pitch(min(rows, key=lambda row: row["amount"]))
        check(max(abs(pitch(row) - initial + 40 * rowing_sequence(row["amount"])[1]) for row in rows), "actual_spine_body_phase_pitch_error_deg", 0, .05)
    return {"exercise_id": exercise_id, "metrics": metrics, "passed": not failures, "failures": failures,
            "trainerApproved": False, "humanTrainerApproval": False, "scope": "Native model geometry/sequence draft; not physiological safety or trainer approval"}
