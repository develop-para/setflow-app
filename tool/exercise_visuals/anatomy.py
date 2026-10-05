"""Original surface guide masks on the athlete's rest mesh.

Regions illustrate the primary muscle groups. They are intentionally labelled
as educational surface regions, not measured activation or anatomical layers.
"""
import math

REGIONS = {
    "pushup": ("chest", "triceps", "deltoids"),
    "bench": ("chest", "triceps", "deltoids"),
    "dumbbell_bench": ("chest", "triceps", "deltoids"),
    "deadlift": ("glutes", "hamstrings", "erectors", "quadriceps"),
    "romanian_deadlift": ("glutes", "hamstrings", "erectors"),
    "row": ("lats", "upper_back", "biceps"),
    "curl": ("biceps",),
    "dumbbell_shoulder_press": ("deltoids", "triceps"),
    "lateral": ("deltoids",),
    "calf_raise": ("calves",),
    "plank": ("abs",),
    "crunch": ("abs",),
}


def smooth(low, high, value):
    t = max(0.0, min(1.0, (value - low) / (high - low)))
    return t * t * (3 - 2 * t)


def ellipse(point, center, radii):
    distance = math.sqrt(sum(((point[index] - center[index]) / radii[index]) ** 2 for index in range(3)))
    return 1 - smooth(0.72, 1.10, distance)


def limb(point, normal, rig, bone_name, anterior=True, low=0.08, high=0.90):
    bone = rig.data.bones[bone_name]
    axis = bone.tail_local - bone.head_local
    relative = point - bone.head_local
    along = relative.dot(axis) / axis.length_squared
    if along <= low or along >= high:
        return 0.0
    radial = relative - axis * along
    boundary = smooth(low, low + 0.12, along) * (1 - smooth(high - 0.12, high, along))
    facing = smooth(-0.02, 0.06, -radial.y if anterior else radial.y)
    normal_fade = smooth(-0.25, 0.45, -normal.y if anterior else normal.y)
    radius = 0.105 if bone_name.startswith("upperarm") else (0.155 if bone_name.startswith("thigh") else 0.105)
    distance_fade = 1 - smooth(radius * 0.83, radius * 1.30, radial.length)
    return boundary * facing * normal_fade * distance_fade


def region(name, point, normal, rig, old_regions):
    if name == "triceps_r":
        # The rest rig's right side is negative X. Preserve the established
        # triceps region exactly while removing the non-working arm's mask.
        if point.x >= 0:
            return 0.0
        name = "triceps"
    side = "l" if point.x >= 0 else "r"
    sign = 1 if side == "l" else -1
    if name == "quadriceps":
        return old_regions.quadriceps(point, normal, rig)
    if name == "glutes":
        return old_regions.glutes(point, normal, rig)
    if name == "hamstrings":
        return limb(point, normal, rig, "thigh_" + side, False, 0.10, 0.95)
    if name == "adductors":
        bone = rig.data.bones["thigh_" + side]
        axis = bone.tail_local - bone.head_local
        relative = point - bone.head_local
        along = relative.dot(axis) / axis.length_squared
        radial = relative - axis * along
        return (smooth(.08, .22, along) * (1 - smooth(.72, .90, along))
                * smooth(-.005, .045, -sign * radial.x)
                * smooth(-.10, .45, -sign * normal.x)
                * (1 - smooth(.12, .19, radial.length)))
    if name == "biceps":
        return limb(point, normal, rig, "upperarm_" + side, True, 0.13, 0.90)
    if name == "triceps":
        return limb(point, normal, rig, "upperarm_" + side, False, 0.10, 0.94)
    if name == "forearms":
        return max(limb(point, normal, rig, "lowerarm_" + side, True, 0.08, 0.86),
                   limb(point, normal, rig, "lowerarm_" + side, False, 0.08, 0.86))
    if name == "calves":
        return limb(point, normal, rig, "calf_" + side, False, 0.06, 0.85)
    if name == "deltoids":
        shoulder = rig.data.bones["upperarm_" + side].head_local
        center = (shoulder.x + sign * 0.022, shoulder.y, shoulder.z - 0.025)
        return ellipse(point, center, (0.107, 0.122, 0.112))
    if name == "rear_deltoids":
        shoulder = rig.data.bones["upperarm_" + side].head_local
        center = (shoulder.x + sign * .016, shoulder.y + .05, shoulder.z - .025)
        return ellipse(point, center, (.098, .094, .102)) * smooth(-.08, .45, normal.y)
    if name == "chest":
        return ellipse(point, (sign * 0.105, -0.142, 1.240), (0.151, 0.190, 0.116)) * smooth(-0.05, 0.45, -normal.y)
    if name == "abs":
        return ellipse(point, (0, -0.114, 1.074), (0.161, 0.154, 0.182)) * smooth(-0.35, 0.35, -normal.y)
    if name == "lats":
        return ellipse(point, (sign * 0.130, 0.086, 1.174), (0.104, 0.134, 0.177)) * smooth(-0.1, 0.45, normal.y)
    if name == "upper_back":
        return ellipse(point, (sign * 0.075, 0.072, 1.318), (0.138, 0.136, 0.132)) * smooth(-0.1, 0.45, normal.y)
    if name == "traps":
        upper = ellipse(point, (sign * .09, .072, 1.403), (.150, .100, .083))
        middle = ellipse(point, (sign * .057, .080, 1.297), (.085, .100, .125))
        return max(upper, middle) * smooth(-.10, .45, normal.y)
    if name == "erectors":
        return ellipse(point, (sign * 0.038, 0.077, 1.051), (0.045, 0.110, 0.181)) * smooth(-0.1, 0.45, normal.y)
    raise ValueError("Unknown muscle region " + name)


def apply(obj, rig, selected, old_regions):
    names = ["setflow_" + name for name in selected] + ["setflow_muscle_focus"]
    for name in names:
        if obj.data.attributes.get(name) is None:
            obj.data.attributes.new(name=name, type="FLOAT", domain="POINT")
    attributes = {name: obj.data.attributes[name] for name in names}
    counts = {name: 0 for name in selected}
    counts["vertices"] = len(obj.data.vertices)
    for vertex in obj.data.vertices:
        focus = 0.0
        for name in selected:
            weight = region(name, vertex.co, vertex.normal, rig, old_regions)
            attributes["setflow_" + name].data[vertex.index].value = weight
            focus = max(focus, weight)
            counts[name] += int(weight > 0.35)
        attributes["setflow_muscle_focus"].data[vertex.index].value = focus
    return counts
