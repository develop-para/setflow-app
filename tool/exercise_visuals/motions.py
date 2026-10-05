"""Original, deterministic exercise poses for the CC0 Setflow athlete.

Targets are expressed in armature space. Equipment uses the resulting palm
transforms, not a separately approximated path. These are reviewable teaching
drafts, not motion-captured or trainer-approved demonstrations.
"""

import math

import bpy
from mathutils import Matrix, Quaternion, Vector

SUPPORTED = (
    "pushup", "bench", "dumbbell_bench", "deadlift", "romanian_deadlift",
    "row", "curl", "dumbbell_shoulder_press", "lateral", "calf_raise",
    "plank", "crunch",
)
UP = Vector((0, 0, 1))
REFERENCES = {
    "bench":{"url":"https://www.acefitness.org/resources/everyone/exercise-library/5/chest-press/","variant":"Flat barbell bench press, pronated grip, supported torso, planted feet"},
    "dumbbell_bench":{"url":"https://www.acefitness.org/resources/everyone/exercise-library/19/chest-press/","variant":"Flat dumbbell chest press, pronated neutral wrists, planted feet"},
    "dumbbell_shoulder_press":{"url":"https://www.acefitness.org/resources/everyone/exercise-library/45/seated-overhead-press/","variant":"Seated bilateral dumbbell overhead press with backrest"},
    "deadlift":{"url":"https://www.acefitness.org/resources/everyone/exercise-library/6/deadlift/","variant":"Conventional pronated barbell deadlift, beginning with plates on floor"},
    "romanian_deadlift":{"url":"https://www.nsca.com/education/articles/kinetic-select/romanian-deadlift-rdl/","variant":"Standing-start pronated barbell Romanian deadlift"},
    "calf_raise":{"source":"Setflow exact standing calf raise guide","variant":"Standing machine calf raise with fixed forefeet and fixed horizontal support handles"},
}


def phase(exercise_id,seconds):
    amount=cycle(seconds)
    return 1-amount if exercise_id=="deadlift" else amount


def cycle(seconds):
    def ease(t):
        t = min(1.0, max(0.0, t))
        return t * t * (3 - 2 * t)
    if seconds < 0.4:
        return 0.0
    if seconds < 1.8:
        return ease((seconds - 0.4) / 1.4)
    if seconds < 2.2:
        return 1.0
    if seconds < 3.6:
        return 1 - ease((seconds - 2.2) / 1.4)
    return 0.0


def update():
    bpy.context.view_layer.update()


def bone_rotation(rig, name, head, rotation):
    rest = rig.data.bones[name]
    matrix = (rotation.to_matrix() @ rest.matrix_local.to_3x3()).to_4x4()
    matrix.translation = head
    rig.pose.bones[name].matrix = matrix
    update()


def point(rig, name, head, tail):
    rest = rig.data.bones[name]
    rotation = (rest.tail_local - rest.head_local).rotation_difference(tail - head)
    bone_rotation(rig, name, head, rotation)


def two_bone(root, target, upper, lower, pole):
    """Solve a fixed-length chain without stretching at near-full extension."""
    delta = target - root
    distance = min(upper + lower - 0.0001, max(abs(upper - lower) + 0.0001, delta.length))
    direction = delta.normalized()
    pole_direction = pole - root
    side = pole_direction - direction * pole_direction.dot(direction)
    if side.length < 0.00001:
        side = direction.cross(Vector((1, 0, 0)))
    side.normalize()
    along = (upper * upper - lower * lower + distance * distance) / (2 * distance)
    rise = math.sqrt(max(0, upper * upper - along * along))
    joint = root + direction * along + side * rise
    endpoint = root + direction * distance
    return joint, endpoint


def reset(rig):
    for bone in rig.pose.bones:
        bone.matrix_basis = Matrix.Identity(4)
        bone.rotation_mode = "QUATERNION"
    update()


def hip_center(rig):
    return (rig.data.bones["thigh_l"].head_local + rig.data.bones["thigh_r"].head_local) / 2


def torso(rig, hip, rotation):
    rest = rig.data.bones
    pelvis = hip - rotation @ (hip_center(rig) - rest["pelvis"].head_local)
    bone_rotation(rig, "pelvis", pelvis, rotation)


def legs(rig, anchors=None, pole_y=-0.6, foot_rotation=None, pole_z=None):
    rest = rig.data.bones
    for side, label in ((1, "l"), (-1, "r")):
        ankle = anchors[label] if anchors else rest["calf_" + label].tail_local.copy()
        hip = rig.pose.bones["thigh_" + label].head.copy()
        knee, endpoint = two_bone(hip, ankle, rest["thigh_" + label].length,
                                  rest["calf_" + label].length,
                                  Vector((side * 0.2, pole_y, hip.z - 0.2 if pole_z is None else pole_z)))
        point(rig, "thigh_" + label, hip, knee)
        point(rig, "calf_" + label, knee, endpoint)
        bone_rotation(rig, "foot_" + label, endpoint,
                      foot_rotation or Quaternion((1, 0, 0), 0))


def hand(rig, label, wrist, direction, palm_normal, grip=False):
    """Orient the actual hand mesh using its knuckle axis and palm normal."""
    rest = rig.data.bones
    rest_forward = (rest["middle_01_" + label].head_local - rest["hand_" + label].head_local).normalized()
    rest_side = (rest["index_01_" + label].head_local - rest["pinky_01_" + label].head_local).normalized()
    rest_normal = rest_forward.cross(rest_side).normalized()
    if label == "r":
        rest_normal.negate()
    # Make the normal orthogonal, so grip frames remain rotations rather than
    # accidental shear when the forearm approaches the upper arm.
    forward = Vector(direction).normalized()
    normal = Vector(palm_normal)
    normal = (normal - forward * normal.dot(forward)).normalized()
    desired_side = normal.cross(forward).normalized()
    source = Matrix((rest_forward, rest_normal, rest_forward.cross(rest_normal))).transposed()
    destination = Matrix((forward, normal, forward.cross(normal))).transposed()
    rotation = (destination @ source.inverted()).to_quaternion()
    bone_rotation(rig, "hand_" + label, wrist, rotation)
    if grip:
        for digit in ("index", "middle", "ring", "pinky"):
            for segment, angle in ((1, math.radians(78)), (2, math.radians(163)), (3, math.radians(235))):
                name = digit + "_0" + str(segment) + "_" + label
                head = rig.pose.bones[name].head.copy()
                target_direction = forward * math.cos(angle) + normal * math.sin(angle)
                point(rig, name, head, head + target_direction * rest[name].length)
        thumb = "thumb_02_" + label
        head = rig.pose.bones[thumb].head.copy()
        point(rig, thumb, head, head + (forward * 0.8 + normal * 0.6) * rest[thumb].length)
    # This contact is a rest-mesh palm-centre point, carried by the same hand
    # rotation as the skinned surface. Handles are placed through this point.
    palm_offset = rest["middle_01_" + label].head_local - rest["hand_" + label].head_local
    palm = wrist + rotation @ (palm_offset * 0.97) + normal * 0.012
    return {"wrist": wrist, "palm": palm, "forward": forward,
            "normal": normal, "handle_axis": desired_side}


def floor_hand(rig,label):
    """Spread the fingers and thumb parallel to a supporting floor surface."""
    for digit in ("index","middle","ring","pinky"):
        for segment in (1,2,3):
            name=f"{digit}_0{segment}_{label}"
            head=rig.pose.bones[name].head.copy()
            point(rig,name,head,head+Vector((0,-rig.data.bones[name].length,0)))
    direction=Vector((-1 if label=="l" else 1,-.35,0)).normalized()
    for segment in (1,2,3):
        name=f"thumb_0{segment}_{label}"
        head=rig.pose.bones[name].head.copy()
        point(rig,name,head,head+direction*rig.data.bones[name].length)


def arm(rig, label, target, pole, palm_forward=None, palm_normal=None, grip=False):
    rest = rig.data.bones
    shoulder = rig.pose.bones["upperarm_" + label].head.copy()
    elbow, wrist = two_bone(shoulder, Vector(target), rest["upperarm_" + label].length,
                            rest["lowerarm_" + label].length, Vector(pole))
    if (wrist-Vector(target)).length>.0001:
        raise ValueError("Arm contact target outside native reach")
    point(rig, "upperarm_" + label, shoulder, elbow)
    point(rig, "lowerarm_" + label, elbow, wrist)
    direction = Vector(palm_forward) if palm_forward else (wrist - elbow).normalized()
    normal = Vector(palm_normal) if palm_normal else Vector((0, -1, 0))
    return hand(rig, label, wrist, direction, normal, grip)


def pronated_forearm(rig, label, elbow, wrist, palm_normal):
    """Carry pronation through the forearm skin instead of twisting at wrist."""
    rest = rig.data.bones
    axis = (wrist - elbow).normalized()
    align = (rest["lowerarm_" + label].tail_local - rest["lowerarm_" + label].head_local).rotation_difference(axis)
    rest_forward = (rest["middle_01_" + label].head_local - rest["hand_" + label].head_local).normalized()
    rest_side = (rest["index_01_" + label].head_local - rest["pinky_01_" + label].head_local).normalized()
    normal = rest_forward.cross(rest_side).normalized()
    if label == "r":
        normal.negate()
    normal = align @ normal
    normal = (normal - axis * normal.dot(axis)).normalized()
    desired = Vector(palm_normal).normalized()
    twist = math.atan2(axis.dot(normal.cross(desired)), normal.dot(desired))
    bone_rotation(rig, "lowerarm_" + label, elbow, Quaternion(axis, twist) @ align)


def neutral_palm(rig, label, palm, pole):
    """Reach a horizontal handle with the forearm and hand axes aligned."""
    rest = rig.data.bones
    target = Vector(palm)
    shoulder = rig.pose.bones["upperarm_" + label].head.copy()
    lateral = target.x - shoulder.x
    upper = math.sqrt(rest["upperarm_" + label].length ** 2 - lateral ** 2)
    lower = rest["lowerarm_" + label].length + (rest["middle_01_" + label].head_local-rest["hand_" + label].head_local).length*.97
    effective = math.hypot(lower,.012)
    planar_pole=Vector(pole)
    planar_pole.x=target.x
    elbow, endpoint = two_bone(Vector((target.x,shoulder.y,shoulder.z)),target,upper,effective,planar_pole)
    if (endpoint-target).length>.00001:
        raise ValueError("Horizontal grip outside anatomical reach")
    combined=(target-elbow).normalized()
    n=Vector((0,-combined.z,combined.y))
    angle=math.atan2(.012,lower)
    forward=combined*math.cos(angle)-n*math.sin(angle)
    normal=Vector((0,-forward.z,forward.y))
    wrist=elbow+forward*rest["lowerarm_"+label].length
    point(rig,"upperarm_"+label,shoulder,elbow)
    pronated_forearm(rig,label,elbow,wrist,normal)
    return hand(rig,label,wrist,forward,normal,True)


def hanging_arm(rig, side, label, curl_amount=0):
    rest = rig.data.bones
    shoulder = rig.pose.bones["upperarm_" + label].head.copy()
    upper_direction = Vector((side * 0.20, -0.04, -0.98)).normalized()
    elbow = shoulder + upper_direction * rest["upperarm_" + label].length
    angle = math.radians(12 + 122 * curl_amount)
    lower_direction = Vector((side * 0.03, -math.sin(angle), -math.cos(angle))).normalized()
    wrist = elbow + lower_direction * rest["lowerarm_" + label].length
    point(rig, "upperarm_" + label, shoulder, elbow)
    point(rig, "lowerarm_" + label, elbow, wrist)
    normal = Vector((0, -math.cos(angle), math.sin(angle)))
    return hand(rig, label, wrist, lower_direction, normal, True)


def standing(rig, hip_shift=(0, 0, 0), lean=0):
    hip = hip_center(rig) + Vector(hip_shift)
    torso(rig, hip, Quaternion((1, 0, 0), math.radians(lean)))
    legs(rig)


def bent_over_row(rig, amount):
    """Overhand, abdominal-target row; bar position drives the whole grip chain.

    The torso and knees stay planted. A palm is not a wrist: solving only to
    the wrist and forcing the fingers downward caused the v1 bent wrist and
    misplaced bar. Here the forearm and metacarpals share a neutral axis.
    """
    rest = rig.data.bones
    lean = Quaternion((1, 0, 0), math.radians(65))
    ankle = rest["calf_l"].tail_local
    hip_y = 0.23
    lateral = rest["thigh_l"].head_local.x - ankle.x
    hip_z = ankle.z + math.sqrt(0.800 ** 2 - lateral ** 2 - (hip_y - ankle.y) ** 2)
    torso(rig, Vector((0, hip_y, hip_z)), lean)
    legs(rig)

    # The rig has clavicles rather than separate scapula bones. A small
    # symmetric protraction/retraction represents the shoulder girdle without
    # moving or extending the spine to throw the weight upward.
    for side, label in ((1, "l"), (-1, "r")):
        name = "clavicle_" + label
        head = rig.pose.bones[name].head.copy()
        girdle = Quaternion((0, 0, 1), math.radians(side * (-5 + 10 * amount)))
        bone_rotation(rig, name, head, lean @ girdle)

    # Shoulder-width hands keep the lowered arm chain almost fully extended;
    # a wide fixed grip with vertically constrained forearms bends the elbow.
    grip_x = 0.21
    shoulder = rig.pose.bones["upperarm_l"].head.copy()
    palm_length = (rest["middle_01_l"].head_local - rest["hand_l"].head_local).length * 0.97
    lower = rest["lowerarm_l"].length + palm_length
    grip_radius_offset = 0.012
    effective_lower = math.hypot(lower, grip_radius_offset)
    upper_yz = math.sqrt(rest["upperarm_l"].length ** 2 - (grip_x - shoulder.x) ** 2)
    # Start with genuinely extended elbows and a hanging bar below shoulders.
    hanging_length = math.sqrt((upper_yz + effective_lower - 0.000101) ** 2 - grip_radius_offset ** 2)
    start = Vector((grip_x, shoulder.y + grip_radius_offset,
                    shoulder.z - hanging_length))
    # Abdominal surface landmark is in the *rest* athlete's coordinates;
    # transform with the pelvis, not with moving shoulders or wrists.
    abdominal_landmark = Vector((0, -0.129, 1.055))
    surface = rig.pose.bones["pelvis"].matrix @ rest["pelvis"].matrix_local.inverted() @ abdominal_landmark
    anterior = lean @ Vector((0, -1, 0))
    # The large quadriceps extend ahead of the central abdominal depression.
    # Keep the shaft in front of the complete surface, not inside the thighs.
    finish = surface + anterior * 0.030 + Vector((0, -0.05 / rig.scale.x, 0.02 / rig.scale.x))
    bar = start.lerp(Vector((grip_x, finish.y, finish.z)), amount)
    contacts = {"feet": "foot", "row_bar_target": bar.copy()}
    for side, label in ((1, "l"), (-1, "r")):
        shoulder = rig.pose.bones["upperarm_" + label].head.copy()
        root_yz = Vector((side * grip_x, shoulder.y, shoulder.z))
        projected_upper = math.sqrt(rest["upperarm_" + label].length ** 2 - (root_yz.x - shoulder.x) ** 2)
        target = Vector((side * grip_x, bar.y, bar.z))
        pole = root_yz + lean @ Vector((0, 1, 0))
        elbow, endpoint = two_bone(root_yz, target, projected_upper, effective_lower, pole)
        if (endpoint - target).length > 0.00001:
            raise ValueError("Barbell row grip target is outside the athlete's reach")
        combined = (target - elbow).normalized()
        normal_axis = Vector((0, -combined.z, combined.y))
        angle = math.atan2(grip_radius_offset, lower)
        forward = combined * math.cos(angle) - normal_axis * math.sin(angle)
        normal = Vector((0, -forward.z, forward.y))
        wrist = elbow + forward * rest["lowerarm_" + label].length
        point(rig, "upperarm_" + label, shoulder, elbow)
        pronated_forearm(rig, label, elbow, wrist, normal)
        contacts[label] = hand(rig, label, wrist, forward, normal, True)
    return contacts


def pose(rig, exercise_id, amount):
    reset(rig)
    rest = rig.data.bones
    contacts = {}
    if exercise_id in ("curl", "lateral", "dumbbell_shoulder_press", "calf_raise"):
        if exercise_id == "calf_raise":
            # Rotate around the metatarsal joint: the ball of each foot stays
            # fixed while heels and the whole athlete rise together.
            angle = math.radians(26 * amount)
            rotation = Quaternion((1, 0, 0), angle)
            anchors = {}
            for label in ("l", "r"):
                ball = rest["foot_" + label].tail_local
                anchors[label] = ball + rotation @ (rest["foot_" + label].head_local - ball)
            shift = anchors["l"] - rest["foot_l"].head_local
            torso(rig, hip_center(rig) + shift, Quaternion((1, 0, 0), 0))
            legs(rig, anchors, foot_rotation=rotation)
            for label in ("l", "r"):
                bone_rotation(rig, "ball_" + label, rest["ball_" + label].head_local,
                              Quaternion((1, 0, 0), 0))
            contacts["feet"] = "ball"
        elif exercise_id == "dumbbell_shoulder_press":
            torso(rig,Vector((0,.10,.48)),Quaternion((1,0,0),0))
            anchors={label:Vector((side*.22,-.34,rest["foot_"+label].head_local.z)) for side,label in ((1,"l"),(-1,"r"))}
            legs(rig,anchors,pole_y=-.8,pole_z=.58)
            contacts["feet"]="foot"
        else:
            standing(rig)
            contacts["feet"] = "foot"
        for side, label in ((1, "l"), (-1, "r")):
            shoulder = rig.pose.bones["upperarm_" + label].head.copy()
            if exercise_id in ("curl", "calf_raise"):
                if exercise_id == "calf_raise":
                    target=Vector((side*.34,-.20,1.26))
                    contacts[label]=neutral_palm(rig,label,target,Vector((side*.34,.2,1.10)))
                else:
                    contacts[label] = hanging_arm(rig, side, label, amount)
            elif exercise_id == "lateral":
                angle = math.radians(9 + 73 * amount)
                upper_direction = Vector((side * math.sin(angle), -0.10, -math.cos(angle))).normalized()
                lower_direction = Vector((side * math.sin(angle + 0.10), -0.15, -math.cos(angle + 0.10))).normalized()
                elbow = shoulder + upper_direction * rest["upperarm_" + label].length
                wrist = elbow + lower_direction * rest["lowerarm_" + label].length
                point(rig, "upperarm_" + label, shoulder, elbow)
                point(rig, "lowerarm_" + label, elbow, wrist)
                neutral_normal = Vector((-side * math.cos(angle), 0, -math.sin(angle)))
                contacts[label] = hand(rig, label, wrist, lower_direction, neutral_normal, True)
            else:
                grip_x=.42-.14*amount
                upper=math.sqrt(rest["upperarm_"+label].length**2-(grip_x-abs(shoulder.x))**2)
                lower=rest["lowerarm_"+label].length+(rest["middle_01_"+label].head_local-rest["hand_"+label].head_local).length*.97
                extension=math.sqrt((upper+math.hypot(lower,.012)-.0002)**2-.05**2)
                target=Vector((side*grip_x,shoulder.y-.05,shoulder.z+.30*(1-amount)+extension*amount))
                contacts[label]=neutral_palm(rig,label,target,shoulder+Vector((side*.45,-.2,-.3)))
        if exercise_id == "calf_raise":
            contacts["shoulder_pads"] = (rig.pose.bones["upperarm_l"].head + rig.pose.bones["upperarm_r"].head) / 2
    elif exercise_id == "row":
        contacts = bent_over_row(rig, amount)
    elif exercise_id in ("deadlift", "romanian_deadlift"):
        depth = amount
        conventional = exercise_id == "deadlift"
        shift = (0, (0.225 if conventional else 0.18) * depth,
                 -(0.34271 if conventional else 0.13) * depth)
        lean = (50 if conventional else 65) * depth
        if exercise_id == "romanian_deadlift":
            # Preserve a slight knee bend throughout the hip hinge. The
            # ankle-to-hip distance is fixed, which fixes the included knee
            # angle in the fixed-length two-bone chain.
            ankle = rest["calf_l"].tail_local
            hip_y = 0.025 + 0.245 * depth
            lateral = rest["thigh_l"].head_local.x - ankle.x
            hip_z = ankle.z + math.sqrt(0.800 ** 2 - lateral ** 2 - (hip_y - ankle.y) ** 2)
            torso(rig, Vector((0, hip_y, hip_z)), Quaternion((1, 0, 0), math.radians(57 * depth)))
            legs(rig)
        else:
            # The IFBB thigh surface lies anterior to the rig's shoulder
            # joint. A directly vertical bone-only hanging bar ran through
            # the quadriceps. Keep the shaft on a fixed anterior path and
            # solve the extended arm chain to it.
            standing(rig,(0,.225,-.34271),50)
            bottom_shoulder=rig.pose.bones["upperarm_l"].head.copy()
            palm_length=(rest["middle_01_l"].head_local-rest["hand_l"].head_local).length*.97
            reach=math.sqrt(rest["upperarm_l"].length**2-(.30-bottom_shoulder.x)**2)+math.hypot(rest["lowerarm_l"].length+palm_length,.012)
            bottom_z=bottom_shoulder.z-math.sqrt(reach**2-(-.27-bottom_shoulder.y)**2)+.0002
            floor_adjust=bottom_z-.235/rig.scale.x
            shift=(shift[0],shift[1],shift[2]-floor_adjust*depth)
            standing(rig, shift, lean)
        contacts["feet"] = "foot"
        # Both grips have the same height and sagittal coordinate, keeping the
        # bar horizontal and close to the shins/thighs throughout the movement.
        shoulder = rig.pose.bones["upperarm_l"].head.copy()
        hand_y = -.27
        palm_length = (rest["middle_01_l"].head_local-rest["hand_l"].head_local).length*.97
        lateral = 0.30 - shoulder.x
        arm_length = math.sqrt(rest["upperarm_l"].length**2-lateral**2) + math.hypot(rest["lowerarm_l"].length+palm_length,.012)
        hand_z = shoulder.z - math.sqrt(arm_length ** 2 - (hand_y-shoulder.y) ** 2) + 0.0002
        for side, label in ((1, "l"), (-1, "r")):
            target = Vector((side * 0.30, hand_y, hand_z))
            pole = Vector((side * 0.40, hand_y + 0.23, hand_z + 0.20))
            contacts[label] = neutral_palm(rig, label, target, pole)
    elif exercise_id in ("bench", "dumbbell_bench"):
        # Torso lies on the bench with feet on the floor, rather than rotating
        # the whole standing pose and allowing the knees to float.
        torso(rig, Vector((0, 0.33, 0.50)), Quaternion((1, 0, 0), math.radians(-90)))
        anchors = {label: Vector((side * 0.29, -0.30, rest["calf_" + label].tail_local.z))
                   for side, label in ((1, "l"), (-1, "r"))}
        legs(rig, anchors, pole_y=-1.5)
        contacts["feet"] = "foot"
        for side, label in ((1, "l"), (-1, "r")):
            shoulder = rig.pose.bones["upperarm_" + label].head.copy()
            grip_x=.31 if exercise_id=="bench" else .30
            upper=math.sqrt(rest["upperarm_"+label].length**2-(grip_x-abs(shoulder.x))**2)
            lower=rest["lowerarm_"+label].length+(rest["middle_01_"+label].head_local-rest["hand_"+label].head_local).length*.97
            extension=math.sqrt((upper+math.hypot(lower,.012)-.0002)**2-.07**2)
            target=Vector((side*grip_x,shoulder.y-.07-.10*amount,shoulder.z+extension*(1-amount)+.20*amount))
            pole=shoulder+Vector((side*.40,-.3,-.4))
            contacts[label]=neutral_palm(rig,label,target,pole)
        contacts["bench"] = {"support_z": 0.365}
    elif exercise_id in ("pushup", "plank"):
        depth = amount if exercise_id == "pushup" else 0.98
        # Body stays straight. Chest and hips lower together while palm and
        # forefoot contacts remain fixed on the floor.
        lean = math.radians(73 + 11 * depth if exercise_id=="pushup" else 82.4)
        full_length = rest["thigh_l"].length + rest["calf_l"].length - 0.0005
        lateral = rest["calf_l"].tail_local.x - rest["thigh_l"].head_local.x
        leg_length = math.sqrt(full_length * full_length - lateral * lateral)
        hip_z = 0.145 + math.cos(lean) * leg_length
        hip_y = 0.84 - math.sin(lean) * leg_length
        torso(rig, Vector((0, hip_y, hip_z)), Quaternion((1, 0, 0), lean))
        anchors = {label: Vector((side * 0.18849, 0.84, 0.145))
                   for side, label in ((1, "l"), (-1, "r"))}
        legs(rig, anchors, pole_y=1.3, foot_rotation=Quaternion((1, 0, 0), math.radians(60)))
        for label in ("l", "r"):
            ball = rig.pose.bones["foot_" + label].tail.copy()
            bone_rotation(rig, "ball_" + label, ball, Quaternion((1, 0, 0), 0))
        contacts["feet"] = "foot"
        for side, label in ((1, "l"), (-1, "r")):
            if exercise_id == "pushup":
                target = Vector((side * 0.32, -0.40, 0.032))
                pole = Vector((side * 0.52, -0.15, 0.18))
                contacts[label] = arm(rig, label, target, pole, (0, -1, 0), (0, 0, -1), False)
                floor_hand(rig,label)
            else:
                shoulder = rig.pose.bones["upperarm_" + label].head.copy()
                elbow=shoulder+Vector((0,0,-rest["upperarm_"+label].length))
                # Elbows remain just below the shoulders. Use a fixed-length
                # upper arm and rest forearm horizontally on the mat.
                direction = (elbow - shoulder).normalized()
                elbow = shoulder + direction * rest["upperarm_" + label].length
                wrist = elbow + Vector((0, -1, 0)) * rest["lowerarm_" + label].length
                point(rig, "upperarm_" + label, shoulder, elbow)
                point(rig, "lowerarm_" + label, elbow, wrist)
                contacts[label] = hand(rig, label, wrist, (0, -1, 0), (0, 0, -1), False)
                floor_hand(rig,label)
        contacts["mat"] = True
    elif exercise_id == "crunch":
        torso(rig, Vector((0, 0.18, 0.14)), Quaternion((1, 0, 0), math.radians(-90)))
        # Flex at the lower and upper spine while leaving the pelvis planted.
        for name, portion in (("spine_01", 0.25), ("spine_02", 0.55), ("spine_03", 1.0)):
            head = rig.pose.bones[name].head.copy()
            bone_rotation(rig, name, head, Quaternion((1, 0, 0), math.radians(-90 + 25 * amount * portion)))
        anchors = {label: Vector((side * 0.17, -0.40, rest["calf_" + label].tail_local.z))
                   for side, label in ((1, "l"), (-1, "r"))}
        legs(rig, anchors, pole_y=-0.1, pole_z=0.80)
        contacts["feet"] = "foot"
        for side, label in ((1, "l"), (-1, "r")):
            shoulder = rig.pose.bones["upperarm_" + label].head.copy()
            target = Vector((side * 0.09, shoulder.y + 0.18, shoulder.z + 0.03))
            contacts[label] = arm(rig, label, target, shoulder + Vector((side * 0.40, 0.03, 0.2)),
                                   (0, 1, 0), (0, 0, -1), False)
        contacts["mat"] = True
    else:
        raise ValueError("No verified motion implementation for " + exercise_id)
    update()
    return contacts


def bone_audit(rig):
    return {name: {"head": list(rig.matrix_world @ bone.head),
                   "tail": list(rig.matrix_world @ bone.tail)}
            for name, bone in rig.pose.bones.items()}


def audit(rows,exercise_id):
    if exercise_id not in REFERENCES:
        return None
    import technique
    angles=[technique.angle_degrees(technique.subtract(technique.joint(row,"lowerarm_"+label,"tail"),technique.joint(row,"lowerarm_"+label)),technique.subtract(technique.joint(row,"middle_01_"+label),technique.joint(row,"hand_"+label))) for row in rows for label in ("l","r")]
    errors=[]
    if max(angles)>1:errors.append("Wrist is not aligned with forearm")
    return {"passed":not errors,"errors":errors,"max_wrist_axis_angle_deg":max(angles),"review_status":"trainer_pending","checks_are_geometry_only":True}
