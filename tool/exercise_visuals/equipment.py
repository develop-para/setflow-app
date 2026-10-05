"""Setflow-authored, neutral training equipment; no downloaded asset meshes."""
import math

import bpy
from mathutils import Vector


def material(name, color, metallic=0.0, roughness=0.48):
    mat = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    mat.diffuse_color = (*color, 1)
    mat.use_nodes = True
    shader = next(node for node in mat.node_tree.nodes if node.type == "BSDF_PRINCIPLED")
    shader.inputs["Base Color"].default_value = (*color, 1)
    shader.inputs["Metallic"].default_value = metallic
    shader.inputs["Roughness"].default_value = roughness
    return mat


def cylinder(name, radius, depth, mat, parent=None, offset=0):
    bpy.ops.mesh.primitive_cylinder_add(vertices=48, radius=radius, depth=depth)
    obj = bpy.context.object
    obj.name = name
    obj.data.materials.append(mat)
    if parent:
        obj.parent = parent
        obj.location = (offset, 0, 0)
    obj.rotation_euler[1] = math.pi / 2
    bevel = obj.modifiers.new("Rounded equipment edges", "BEVEL")
    bevel.width = 0.008
    bevel.segments = 3
    for polygon in obj.data.polygons:
        polygon.use_smooth = True
    return obj


def cube(name, location, scale, mat):
    bpy.ops.mesh.primitive_cube_add(size=1, location=location)
    obj = bpy.context.object
    obj.name = name
    obj.scale = scale
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    obj.data.materials.append(mat)
    bevel = obj.modifiers.new("Rounded padding", "BEVEL")
    bevel.width = 0.022
    bevel.segments = 4
    return obj


def dumbbell(label):
    root = bpy.data.objects.new("Setflow dumbbell " + label, None)
    bpy.context.scene.collection.objects.link(root)
    steel = material("Equipment brushed steel", (0.21, 0.21, 0.21), 0.75)
    rubber = material("Equipment graphite rubber", (0.042, 0.042, 0.042))
    cylinder("Dumbbell handle " + label, 0.020, 0.21, steel, root)
    for side in (-1, 1):
        cylinder("Dumbbell weight " + label + str(side), 0.091, 0.085, rubber, root, side * 0.139)
        cylinder("Dumbbell cap " + label + str(side), 0.045, 0.011, steel, root, side * 0.186)
    return root


def barbell():
    root = bpy.data.objects.new("Setflow barbell", None)
    bpy.context.scene.collection.objects.link(root)
    root["surface_check_shaft"] = True
    steel = material("Equipment brushed steel", (0.21, 0.21, 0.21), 0.75)
    rubber = material("Equipment graphite rubber", (0.042, 0.042, 0.042))
    cylinder("Barbell shaft", 0.016, 1.75, steel, root)
    for side in (-1, 1):
        cylinder("Barbell sleeve " + str(side), 0.027, 0.38, steel, root, side * 0.88)
        cylinder("Barbell full plate " + str(side), 0.235, 0.065, rubber, root, side * 0.775)
        cylinder("Barbell outer plate " + str(side), 0.192, 0.032, rubber, root, side * 0.825)
        cylinder("Barbell collar " + str(side), 0.044, 0.038, steel, root, side * 0.86)
    return root


def create(exercise_id, rig):
    props = {}
    if exercise_id in ("curl", "lateral", "dumbbell_shoulder_press", "dumbbell_bench"):
        props["l"], props["r"] = dumbbell("l"), dumbbell("r")
    if exercise_id in ("bench", "deadlift", "romanian_deadlift", "row"):
        props["bar"] = barbell()
    if exercise_id in ("bench", "dumbbell_bench"):
        scale = rig.scale.x
        padding = material("Bench charcoal upholstery", (0.047, 0.047, 0.047))
        frame = material("Bench steel frame", (0.27, 0.27, 0.27), 0.70)
        cube("Flat bench padding", (0, 0.63 * scale, 0.350 * scale), (0.33, 1.10, 0.080), padding)
        for y in (0.26, 0.98):
            cube("Bench support", (0, y, 0.17), (0.075, 0.075, 0.32), frame)
            cube("Bench foot", (0, y, 0.025), (0.62, 0.12, 0.05), frame)
    if exercise_id=="dumbbell_shoulder_press":
        scale=rig.scale.x
        padding=material("Bench charcoal upholstery",(.047,.047,.047))
        steel=material("Bench steel frame",(.27,.27,.27),.7)
        cube("Seated press seat",(0,.10*scale,.39*scale),(.43,.44,.085),padding)
        cube("Seated press backrest",(0,.245*scale,.88*scale),(.43,.085,.95*scale),padding)
        for side in (-1,1):
            cube("Seated press support "+str(side),(side*.18,.15,.2),(.06,.06,.4),steel)
            cube("Seated press foot "+str(side),(side*.18,.15,.025),(.12,.60,.05),steel)
    if exercise_id in ("pushup", "plank", "crunch"):
        mat = material("Training mat", (0.125, 0.125, 0.125))
        cube("Exercise mat", (0, 0.10, -0.003), (0.92, 2.1, 0.014), mat)
    if exercise_id == "calf_raise":
        steel = material("Machine brushed steel", (0.23, 0.23, 0.23), 0.65)
        padding = material("Machine shoulder pad", (0.035, 0.035, 0.035))
        for side in (-1, 1):
            cube("Calf machine vertical rail " + str(side), (side * 0.57, 0.25, 1.09), (0.062, 0.072, 2.17), steel)
            cube("Calf machine base " + str(side), (side * 0.57, 0.18, 0.024), (0.16, 0.86, 0.048), steel)
        cube("Calf machine top frame", (0, 0.25, 2.15), (1.20, 0.08, 0.09), steel)
        carriage = bpy.data.objects.new("Calf machine moving shoulder carriage", None)
        bpy.context.scene.collection.objects.link(carriage)
        props["carriage"] = carriage
        crossbar = cube("Calf machine shoulder crossbar", (0, 0.18, 0.03), (1.05, 0.07, 0.08), steel)
        crossbar.parent = carriage
        for side in (-1, 1):
            pad = cube("Calf machine shoulder pad " + str(side), (side * 0.245, 0, 0), (0.20, 0.30, 0.095), padding)
            pad.parent = carriage
        for label in ("l", "r"):
            handle = bpy.data.objects.new("Calf machine fixed handle " + label, None)
            bpy.context.scene.collection.objects.link(handle)
            cylinder("Calf machine hand grip " + label, 0.019, 0.25, padding, handle)
            props[label] = handle
        for side in (-1, 1):
            cube("Calf machine fixed handle stem " + str(side), (side * 0.57, 0.025, 1.26*rig.scale.x), (0.042, 0.45, 0.042), steel)
            cube("Calf machine fixed handle crosslink " + str(side), (side * 0.446, -0.20*rig.scale.x, 1.26*rig.scale.x), (0.25, 0.042, 0.042), steel)
    return props


def apply(props, contacts, rig, frame=None):
    world = rig.matrix_world
    for label in ("l", "r"):
        if label in props:
            contact = contacts[label]
            obj = props[label]
            obj.location = world @ contact["palm"]
            axis = (world.to_3x3() @ contact["handle_axis"]).normalized()
            obj.rotation_mode = "QUATERNION"
            obj.rotation_quaternion = Vector((1, 0, 0)).rotation_difference(axis)
    if "bar" in props:
        props["bar"].location = world @ ((contacts["l"]["palm"] + contacts["r"]["palm"]) / 2)
    if "carriage" in props:
        props["carriage"].location = world @ contacts["shoulder_pads"] + Vector((0, 0, 0.1075))
    if frame is not None:
        for obj in props.values():
            obj.keyframe_insert("location", frame=frame)
            if obj.rotation_mode == "QUATERNION":
                obj.keyframe_insert("rotation_quaternion", frame=frame)
    bpy.context.view_layer.update()


def contacts_audit(props, contacts, rig):
    result = {}
    world = rig.matrix_world
    if "bar" in props:
        center = props["bar"].location
        result["bar_grip_alignment_m"] = max(abs((world @ contacts[label]["palm"]).y - center.y)
                                                   + abs((world @ contacts[label]["palm"]).z - center.z)
                                                   for label in ("l", "r"))
        if props["bar"].get("surface_check_shaft"):
            shaft_axis=(props["bar"].matrix_world.to_3x3() @ Vector((1,0,0))).normalized()
            result["bar_axis_grip_edge_error_m"]=max((.06*shaft_axis.cross((world.to_3x3() @ contacts[label]["handle_axis"]).normalized()).length
                                                     for label in ("l","r") if contacts[label].get("shaft_axis_required",True)),default=0)
    for label in ("l", "r"):
        if label in props:
            result["dumbbell_" + label + "_contact_m"] = (props[label].location - world @ contacts[label]["palm"]).length
    return result


def floor_clearance(props):
    heights = [obj.matrix_world @ Vector(corner)
               for root in props.values() for obj in root.children_recursive
               if obj.type == "MESH" for corner in obj.bound_box]
    return min((point.z for point in heights), default=None)
