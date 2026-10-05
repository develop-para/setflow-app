"""Original fixed training supports for exact bodyweight motion variants.

Static props are parented to an armature-space frame; only dumbbells follow
the hands. Fixed bars never use the l/r moving-equipment keys.
"""
import math


def _root(rig, name):
    import bpy
    obj = bpy.data.objects.new("Setflow " + name, None)
    bpy.context.scene.collection.objects.link(obj)
    obj.matrix_world = rig.matrix_world.copy()
    return obj


def _cube(parent, name, location, size, material):
    import equipment
    obj = equipment.cube("Setflow " + name, location, size, material)
    obj.parent = parent
    obj.location = location
    return obj


def _bar(parent, name, location, length, radius, material, axis="X"):
    import equipment
    obj = equipment.cylinder("Setflow " + name, radius, length, material, parent)
    obj.location = location
    if axis == "Y":
        obj.rotation_euler = (math.pi / 2, 0, 0)
    elif axis == "Z":
        obj.rotation_euler = (0, 0, 0)
    return obj


def _bench(rig, kind, props, materials):
    root = _root(rig, kind + " bench")
    props["fixed_bench"] = root
    if kind == "lying":
        center, width, depth, top = (0, 0.43), 0.42, 1.13, 0.329
    elif kind == "dip":
        center, width, depth, top = (0, 0.38), 0.75, 0.70, 0.45
    else:
        center, width, depth, top = (0, 0.50), 0.70, 0.36, 0.45
    _cube(root, kind + " bench pad", (*center, top - 0.04), (width, depth, 0.08), materials[1])
    for offset in (-1, 1):
        y = center[1] + offset * depth * 0.29
        _cube(root, "bench upright", (0, y, (top - 0.08) / 2), (0.075, 0.075, top - 0.08), materials[0])
        _cube(root, "bench foot", (0, y, 0.022), (width + 0.12, 0.12, 0.044), materials[0])


def create(exercise_id, rig):
    import bodyweight_motions as motion
    import equipment
    if exercise_id not in motion.SUPPORTED:
        raise ValueError("No exact bodyweight equipment: " + exercise_id)
    steel = equipment.material("Bodyweight support steel", (0.22, 0.22, 0.22), 0.72)
    pad = equipment.material("Bodyweight support upholstery", (0.055, 0.055, 0.055))
    props = {}
    if exercise_id in motion.LOADED:
        props["l"], props["r"] = equipment.dumbbell("l"), equipment.dumbbell("r")
    if exercise_id in ("pullup", motion.CHIN, "hanging_leg_raise"):
        root = _root(rig, "fixed pullup station")
        props["fixed_pullup_station"] = root
        _bar(root, "pullup bar", (0, -0.10, 2.10), 1.22, 0.019, steel)
        for side in (-1, 1):
            _bar(root, "pullup upright", (side * 0.72, 0.10, 1.09), 2.18, 0.025, steel, "Z")
            _cube(root, "pullup base", (side * 0.72, 0.08, 0.025), (0.14, 0.88, 0.05), steel)
            _bar(root, "pullup top connector", (side * 0.64, -0.10, 2.10), 0.16, 0.024, steel)
            _bar(root, "pullup forward reach", (side * 0.72, 0, 2.10), 0.20, 0.024, steel, "Y")
    if exercise_id in ("dips", motion.TRICEPS_DIP):
        root = _root(rig, "fixed parallel bars")
        props["fixed_dip_station"] = root
        for side in (-1, 1):
            _bar(root, "parallel grip", (side * 0.30, -0.08, 1.18), 0.72, 0.019, steel, "Y")
            for y in (-0.40, 0.24):
                _bar(root, "dip support", (side * 0.30, y, 0.585), 1.17, 0.025, steel, "Z")
            _cube(root, "dip base", (side * 0.30, -0.08, 0.025), (0.15, 1.0, 0.05), steel)
    if exercise_id in ("bulgarian_split_squat", motion.SPLIT, "bench_dip", "leg_raise"):
        kind = "rear foot" if exercise_id in ("bulgarian_split_squat", motion.SPLIT) else {"bench_dip": "dip", "leg_raise": "lying"}[exercise_id]
        _bench(rig, kind, props, (steel, pad))
    if exercise_id == motion.STEP:
        root = _root(rig, "fixed step platform")
        props["fixed_step"] = root
        _cube(root, "step box", (0, -0.275, 0.171), (0.70, 0.55, 0.342), steel)
        _cube(root, "step grip top", (0, -0.275, 0.346), (0.70, 0.55, 0.008), pad)
    if exercise_id in ("bird_dog", "dead_bug", "side_plank"):
        root = _root(rig, "fixed floor mat")
        _cube(root, "floor mat", (0, 0.12, -0.001), (0.95, 2.05, 0.012), pad)
    return props


def apply(props, contacts, rig, frame=None):
    import equipment
    # Base apply moves only the actual dumbbells. Its keyframing also records
    # fixed equipment roots so playback restores the authored station.
    equipment.apply(props, contacts, rig, frame)
