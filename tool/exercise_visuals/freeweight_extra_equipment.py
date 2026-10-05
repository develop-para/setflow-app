"""Setflow-owned benches/weights for three exact freeweight variants."""


def create(exercise_id, rig):
    import bpy
    import equipment as e
    import freeweight_extra_motions as m
    if exercise_id not in m.SUPPORTED:
        raise ValueError("No exact extra freeweight equipment: " + exercise_id)
    props = ({"l": e.dumbbell("l"), "r": e.dumbbell("r")} if exercise_id == "arnold_press"
             else {"bar": e.barbell()} if exercise_id == "close_grip_bench"
             else {"r": e.dumbbell("working right")})
    bench = bpy.data.objects.new("Setflow extra fixed bench", None)
    bpy.context.scene.collection.objects.link(bench)
    props["fixed_bench"] = bench
    def cube(name, location, size, material):
        obj = e.cube(name, location, size, material)
        obj.parent = bench
        return obj
    padding = e.material("Extra row bench upholstery", (.047, .047, .047))
    steel = e.material("Extra row bench steel", (.27, .27, .27), .70)
    scale = rig.scale.x
    if exercise_id == "arnold_press":
        # Heights are measured against the actual sculpted butt/back skin,
        # rather than positioning the pad through the larger athlete mesh.
        cube("Arnold press seat", (0, .10 * scale, .3562), (.43, .44, .085), padding)
        cube("Arnold press backrest", (0, .2543, .88 * scale), (.43, .085, .95 * scale), padding)
        for side in (-1, 1):
            cube("Arnold bench support", (side * .18, .15, .16), (.06, .06, .32), steel)
            cube("Arnold bench foot", (side * .18, .15, .025), (.12, .60, .05), steel)
        return props
    if exercise_id == "close_grip_bench":
        # End below the hips: extending the cushion toward the knees put
        # the athlete's descending hamstrings through its front edge.
        # Keep the fully lowered upper arms beside the cushion: the prior
        # 33 cm width intersected their inner surfaces at full chest approach.
        cube("Close-grip flat bench padding", (0, .74, .385), (.27, .96, .080), padding)
        # The enlarged upper-back sculpt sits higher than the occiput on a
        # uniform flat pad. Support the unchanged neutral head pose with a
        # small original bolster, rather than making the athlete hold it up.
        cube("Close-grip fitted head bolster", (0, 1.103, .4553), (.25, .20, .0606), padding)
        for y in (.26, .98):
            cube("Close-grip bench upright", (0, y, .17), (.075, .075, .34), steel)
            cube("Close-grip bench foot", (0, y, .025), (.62, .12, .05), steel)
        return props
    cube("Single-arm row knee and palm support", (.16 * scale, .18 * scale, .330 * scale), (.34, 1.14, .080), padding)
    for y in (-.18, .58):
        cube("Single-arm row bench upright", (.16 * scale, y * scale, .17), (.075, .075, .34), steel)
        cube("Single-arm row bench foot", (.16 * scale, y * scale, .025), (.43, .13, .05), steel)
    return props


def apply(props, contacts, rig, frame=None):
    import equipment
    equipment.apply(props, contacts, rig, frame)
