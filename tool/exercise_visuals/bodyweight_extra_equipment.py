"""Original neutral wall panel and floor mats for three exact variants."""


def create(exercise_id, rig):
    import bpy
    import equipment
    import bodyweight_extra_motions as motion
    if exercise_id not in motion.SUPPORTED:
        raise ValueError("No exact extra bodyweight equipment: " + exercise_id)
    root = bpy.data.objects.new("Setflow extra fixed supports", None)
    bpy.context.scene.collection.objects.link(root)
    root.matrix_world = rig.matrix_world.copy()
    props = {"fixed_extra_supports": root}
    if exercise_id == "wall_sit":
        material = equipment.material("Wall sit neutral support", (.60, .60, .60))
        wall = equipment.cube("Setflow wall sit wall", (0, motion.WALL_FRONT_Y + .035, .80), (1.25, .07, 1.60), material)
        wall.parent = root
        wall.location = (0, motion.WALL_FRONT_Y + .035, .80)
        props["fixed_wall"] = wall
    else:
        material = equipment.material("Extra bodyweight charcoal mat", (.085, .085, .085))
        center = motion.TRAINING_SURFACE_Z - .002
        mat = equipment.cube("Setflow extra floor mat", (0, .10, center), (1.10, 2.15, .004), material)
        mat.parent = root
        mat.location = (0, .10, center)
    return props


def apply(props, contacts, rig, frame=None):
    import equipment
    equipment.apply(props, contacts, rig, frame)
