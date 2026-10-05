"""Original rope attachment and cable column; no borrowed exercise media."""
import bpy
from mathutils import Vector
import equipment as e


def _path(name, material, radius):
    curve = bpy.data.curves.new(name, "CURVE")
    curve.dimensions = "3D"
    curve.bevel_depth = radius
    curve.bevel_resolution = 3
    spline = curve.splines.new("POLY")
    spline.points.add(1)
    obj = bpy.data.objects.new(name, curve)
    bpy.context.scene.collection.objects.link(obj)
    curve.materials.append(material)
    return obj


def create(exercise_id, rig):
    scale = rig.scale.x
    steel = e.material("Face pull machine steel", (.24, .24, .24), .65)
    rope = e.material("Face pull rope rubber", (.045, .045, .045))
    pulley = Vector((0, -1.00, 1.65)) * scale
    e.cube("Face pull cable column", (0, pulley.y + .12, 1.04), (.09, .09, 2.06), steel)
    e.cube("Face pull cable base", (0, pulley.y + .12, .035), (.78, .48, .07), steel)
    e.cube("Face pull weight stack", (.31, pulley.y + .12, .47), (.20, .25, .86), rope)
    wheel = e.cylinder("Eye-height cable pulley", .045, .04, steel)
    wheel.location = pulley
    props = {}
    for label in ("l", "r"):
        root = bpy.data.objects.new("Rope end grip " + label, None)
        bpy.context.scene.collection.objects.link(root)
        e.cylinder("Rope held section " + label, .018, .09, rope, root)
        e.cylinder("Rope end stop " + label, .033, .035, rope, root, -.062)
        props[label] = root
        props["branch_" + label] = _path("Rope branch " + label, rope, .018)
    cable = _path("Pulley to rope junction cable", e.material("Face pull cable", (.025, .025, .025)), .004)
    cable["pulley"] = list(pulley)
    props["cable"] = cable
    return props


def apply(props, contacts, rig, frame):
    e.apply(props, contacts, rig, frame)
    palms = {label: rig.matrix_world @ contacts[label]["palm"] for label in ("l", "r")}
    junction = (palms["l"] + palms["r"]) / 2 + Vector((0, -.16, .025))
    paths = [(props["cable"], Vector(props["cable"]["pulley"]), junction)]
    paths += [(props["branch_" + label], junction, palms[label]) for label in ("l", "r")]
    for obj, start, end in paths:
        for point, target in zip(obj.data.splines[0].points, (start, end)):
            point.co = (*target, 1)
            point.keyframe_insert("co", frame=frame)
