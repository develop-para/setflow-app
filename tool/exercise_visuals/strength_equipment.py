"""Original neutral equipment geometry for the authored strength variants."""
import math


def _bench(rig, elevated=False):
    import equipment as e
    padding = e.material("Strength bench upholstery", (0.047, 0.047, 0.047))
    steel = e.material("Strength bench steel", (0.27, 0.27, 0.27), 0.70)
    scale = rig.scale.x
    if elevated:
        e.cube("Hip thrust bench cushion", (0, 0.62 * scale, 0.40 * scale - 0.04), (0.95, 0.38, 0.08), padding)
        for x in (-0.34, 0.34):
            e.cube("Hip thrust bench upright", (x, 0.62 * scale, 0.185), (0.07, 0.13, 0.37), steel)
            e.cube("Hip thrust bench foot", (x, 0.62 * scale, 0.025), (0.12, 0.62, 0.05), steel)
    else:
        # Pad's Y axis points toward the athlete's head, rising at 45 degrees.
        e.cube("Incline bench seat", (0, 0.12 * scale, 0.305 * scale), (0.35, 0.37, 0.08), padding)
        pad = e.cube("Incline bench back and head support", (0, 0.573 * scale, 0.683 * scale), (0.35, 1.00, 0.08), padding)
        pad.rotation_euler.x = math.radians(45)
        # This sculpt has a thick back; seat the cushion below the actual
        # posterior skin instead of through it.
        from mathutils import Vector
        pad.location -= Vector((0, -math.sqrt(0.5), math.sqrt(0.5))) * 0.020
        for y, z in ((0.12, 0.28), (0.61, 0.58)):
            e.cube("Incline bench upright", (0, y * scale, z * scale / 2), (0.075, 0.075, z * scale), steel)
            e.cube("Incline bench foot", (0, y * scale, 0.025), (0.65, 0.13, 0.05), steel)


def _hip_bar():
    import equipment as e
    root = e.barbell()
    padding = e.material("Hip bar protective foam", (0.065, 0.065, 0.065))
    e.cylinder("Hip bar protective foam pad", 0.050, 0.38, padding, root)
    return root


def _goblet():
    import bpy
    import equipment as e
    root = bpy.data.objects.new("Setflow kettlebell goblet load", None)
    bpy.context.scene.collection.objects.link(root)
    rubber = e.material("Equipment graphite rubber", (0.042, 0.042, 0.042))
    bpy.ops.mesh.primitive_uv_sphere_add(segments=48, ring_count=24, radius=0.115)
    body = bpy.context.object
    body.name = "Original kettlebell rounded iron body"
    body.parent = root
    body.location = (0, 0, -0.14)
    body.scale.z = 0.93
    body.data.materials.append(rubber)
    for face in body.data.polygons:
        face.use_smooth = True
    curve = bpy.data.curves.new("Original kettlebell upright horns", "CURVE")
    curve.dimensions = "3D"
    curve.resolution_u = 12
    curve.bevel_depth = 0.018
    curve.bevel_resolution = 4
    spline = curve.splines.new("BEZIER")
    positions = ((-0.07, 0, -0.10), (-0.10, 0, -0.05), (-0.07, 0, 0), (0.07, 0, 0), (0.10, 0, -0.05), (0.07, 0, -0.10))
    spline.bezier_points.add(len(positions) - 1)
    for point, position in zip(spline.bezier_points, positions):
        point.co = position
        point.handle_left_type = point.handle_right_type = "AUTO"
    handle = bpy.data.objects.new("Kettlebell rounded upright handle", curve)
    bpy.context.scene.collection.objects.link(handle)
    handle.parent = root
    curve.materials.append(rubber)
    return root


def create(exercise_id, rig):
    import equipment as e
    import strength_motions as m
    if exercise_id not in m.SUPPORTED:
        raise ValueError("Strength equipment not authored: " + exercise_id)
    props = {}
    if exercise_id == "incline":
        props["l"], props["r"] = e.dumbbell("l"), e.dumbbell("r")
    elif exercise_id == "goblet_squat":
        props["bar"] = _goblet()
    elif exercise_id in ("hip_thrust", "glute_bridge"):
        props["bar"] = _hip_bar()
    else:
        props["bar"] = e.barbell()
    if exercise_id == "front_squat":
        # Deltoid shelf lies outside the generic central-shaft sample span.
        props["bar"]["shaft_surface_half_width_m"] = 0.40
    if exercise_id in ("incline", "incline_barbell"):
        _bench(rig)
    if exercise_id == "hip_thrust":
        _bench(rig, elevated=True)
    if exercise_id == "glute_bridge":
        mat = e.material("Training mat", (0.125, 0.125, 0.125))
        e.cube("Barbell bridge training mat", (0, 0.1, -0.003), (1.00, 2.10, 0.014), mat)
    return props
