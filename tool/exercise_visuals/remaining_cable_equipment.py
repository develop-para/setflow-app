"""Original cable frames, D handles, rope and load-conserving pulley paths."""
import math
import bpy
from mathutils import Matrix, Vector
import equipment as e


def _polyline(name, points, material, radius):
    curve = bpy.data.curves.new(name, "CURVE")
    curve.dimensions = "3D"
    curve.bevel_depth = radius
    curve.bevel_resolution = 3
    spline = curve.splines.new("POLY")
    spline.points.add(len(points) - 1)
    for point, coordinate in zip(spline.points, points):
        point.co = (*coordinate, 1)
    obj = bpy.data.objects.new(name, curve)
    bpy.context.scene.collection.objects.link(obj)
    curve.materials.append(material)
    return obj


def _d_handle(label, rubber, steel):
    root = bpy.data.objects.new("Setflow closed D handle " + label, None)
    bpy.context.scene.collection.objects.link(root)
    e.cylinder("D handle actual palm shaft " + label, .016, .19, rubber, root)
    frame = _polyline("D handle closed frame " + label,
                     [(-.095, 0, 0), (-.095, 0, .095), (-.06, 0, .15), (.06, 0, .15), (.095, 0, .095), (.095, 0, 0)], steel, .009)
    frame.parent = root
    root["attachment_local"] = [0, 0, .15]
    return root


def _machine(props, label, pulley, scale, steel, rubber):
    position = Vector(pulley) * scale
    column_y = position.y + .12
    e.cube("Cable station column " + label, (position.x, column_y, 1.12), (.08, .08, 2.20), steel)
    e.cube("Cable station base " + label, (position.x, column_y, .026), (.48, .50, .052), steel)
    for dx in (-.11, .11):
        e.cube("Cable weight guide rail " + label, (position.x + dx, column_y, 1.0), (.018, .018, 1.95), steel)
    wheel = e.cylinder("Cable adjustable pulley " + label, .045, .034, steel)
    wheel.location = position
    upper = Vector((position.x, column_y, 2.10))
    top = e.cylinder("Cable return pulley " + label, .045, .034, steel)
    top.location = upper
    stack = e.cube("Moving cable resistance stack " + label, (position.x, column_y, .42), (.18, .21, .70), rubber)
    stack["rest_z"] = stack.location.z
    stack["top_offset"] = .35
    props["stack_" + label] = stack
    cable = _polyline("Taut cable from pulley " + label, [position, position], rubber, .0035)
    cable["pulley"] = list(position)
    props["cable_" + label] = cable
    returned = _polyline("Continuous return cable " + label, [position, upper, Vector((position.x, column_y, .77))], rubber, .0035)
    returned["upper"] = list(upper)
    props["return_" + label] = returned


def create(exercise_id, rig):
    steel = e.material("Remaining cable brushed steel", (.22, .22, .22), .7)
    rubber = e.material("Remaining cable graphite", (.04, .04, .04))
    props = {}
    scale = rig.scale.x
    if exercise_id == "cable_fly":
        for side, label in ((1, "l"), (-1, "r")):
            props[label] = _d_handle(label, rubber, steel)
            _machine(props, label, (side * 1.17, .23, 1.38), scale, steel, rubber)
    elif exercise_id == "cable_lateral_raise":
        props["l"] = _d_handle("l", rubber, steel)
        _machine(props, "l", (-.95, -.45, .115), scale, steel, rubber)
    elif exercise_id == "straight_arm_pulldown":
        from accessory_equipment import short_bar
        props["bar"] = short_bar(.78)
        _machine(props, "bar", (0, -1.02, 2.18), scale, steel, rubber)
    elif exercise_id == "cable_crunch":
        for label in ("l", "r"):
            root = bpy.data.objects.new("Kneeling crunch rope end " + label, None)
            bpy.context.scene.collection.objects.link(root)
            e.cylinder("Crunch rope held section " + label, .018, .095, rubber, root)
            e.cylinder("Crunch rope end stop " + label, .030, .030, rubber, root, -.06)
            props[label] = root
            props["branch_" + label] = _polyline("Kneeling rope branch " + label, [(0, 0, 0), (0, 0, 0)], rubber, .017)
        _machine(props, "rope", (0, -.98, 2.18), scale, steel, rubber)
        e.cube("Kneeling training mat", (0, .17, -.003), (.85, 1.22, .014), rubber)
    else:
        raise ValueError("Cable equipment not authored: " + exercise_id)
    return props


def _set_points(obj, values, frame):
    for point, value in zip(obj.data.splines[0].points, values):
        point.co = (*value, 1)
        if frame is not None:
            point.keyframe_insert("co", frame=frame)


def apply(props, contacts, rig, frame):
    e.apply(props, contacts, rig, frame)
    world = rig.matrix_world
    for label in ("l", "r"):
        if label not in props or "attachment_local" not in props[label]:
            continue
        obj = props[label]
        axis = (world.to_3x3() @ contacts[label]["handle_axis"]).normalized()
        direction = Vector(props["cable_" + label]["pulley"]) - obj.location
        up = (direction - axis * direction.dot(axis)).normalized()
        obj.rotation_mode = "QUATERNION"
        obj.rotation_quaternion = Matrix((axis, up.cross(axis), up)).transposed().to_quaternion()
        if frame is not None:
            obj.keyframe_insert("rotation_quaternion", frame=frame)
    bpy.context.view_layer.update()
    for key, cable in props.items():
        if not key.startswith("cable_"):
            continue
        label = key.removeprefix("cable_")
        start = Vector(cable["pulley"])
        if label == "rope":
            end = world @ contacts["rope_junction"]
            for hand in ("l", "r"):
                palm = world @ contacts[hand]["palm"]
                _set_points(props["branch_" + hand], [end, palm], frame)
            branch = max((end - world @ contacts[hand]["palm"]).length for hand in ("l", "r"))
        else:
            obj = props[label]
            end = obj.matrix_world @ Vector(obj.get("attachment_local", (0, 0, 0)))
            branch = 0
        length = (end - start).length + branch
        # During the first source pass determine min visible load length;
        # the custom verifier resets the baseline before authoring frames.
        if "rest_length" not in cable:
            cable["rest_length"] = length
        cable["minimum_length"] = min(float(cable.get("minimum_length", length)), length)
        _set_points(cable, [start, end], frame)
        stack = props["stack_" + label]
        stack.location.z = float(stack["rest_z"]) + length - float(cable["rest_length"])
        if frame is not None:
            stack.keyframe_insert("location", frame=frame)
        upper = Vector(props["return_" + label]["upper"])
        _set_points(props["return_" + label], [start, upper, stack.location + Vector((0, 0, stack["top_offset"]))], frame)
    bpy.context.view_layer.update()


def contacts_audit(props, contacts, rig):
    result = e.contacts_audit(props, contacts, rig)
    for key, cable in props.items():
        if key.startswith("cable_"):
            label = key.removeprefix("cable_")
            a, b = [Vector(point.co[:3]) for point in cable.data.splines[0].points]
            stack = props["stack_" + label]
            branch = max(((b - rig.matrix_world @ contacts[hand]["palm"]).length for hand in ("l", "r")), default=0) if label == "rope" else 0
            result[key + "_length_conservation_error_m"] = abs((b - a).length + branch - float(cable["rest_length"]) - (stack.location.z - float(stack["rest_z"])))
            result[key + "_pulley_endpoint_error_m"] = (a - Vector(cable["pulley"])).length
    return result


def surface_audit(exercise_id, props, rig, body, frame, amount, cache):
    """Sample actual cable radius against full posed skin, retaining hand grip contact."""
    from mathutils.bvhtree import BVHTree
    evaluated = body.evaluated_get(bpy.context.evaluated_depsgraph_get())
    mesh = evaluated.to_mesh(preserve_all_data_layers=True, depsgraph=bpy.context.evaluated_depsgraph_get())
    try:
        coords = [evaluated.matrix_world @ vertex.co for vertex in mesh.vertices]
        bvh = BVHTree.FromPolygons(coords, [tuple(p.vertices) for p in mesh.polygons], all_triangles=False)
        topology = ("cable_hand_faces", body.as_pointer(), len(mesh.vertices), len(mesh.polygons))
        domains = cache.get(topology)
        if domains is None:
            domains = {}
            for label in ("l", "r"):
                hand_groups = {group.index for group in body.vertex_groups if group.name.startswith(("hand_", "index_", "middle_", "ring_", "pinky_", "thumb_")) and group.name.endswith("_" + label)}
                weights = [sum(g.weight for g in vertex.groups if g.group in hand_groups) for vertex in mesh.vertices]
                domains["hand_" + label] = [sum(weights[index] for index in p.vertices) / len(p.vertices) >= .5 for p in mesh.polygons]
                for prefix in ("leg", "shin"):
                    groups = {group.index for group in body.vertex_groups if group.name in ("calf_" + label, "thigh_" + label) if prefix == "leg" or group.name == "calf_" + label}
                    domains[prefix + "_" + label] = [vertex.index for vertex in mesh.vertices if sum(g.weight for g in vertex.groups if g.group in groups) >= .5]
            cache[topology] = domains
        samples = []
        for key, obj in props.items():
            if not key.startswith(("cable_", "branch_")):
                continue
            start, end = [Vector(point.co[:3]) for point in obj.data.splines[0].points]
            radius = obj.data.bevel_depth
            steps = max(1, math.ceil((end - start).length / .005))
            label = key.removeprefix("branch_") if key.startswith("branch_") else key.removeprefix("cable_")
            for index in range(steps + 1):
                point = start.lerp(end, index / steps)
                hit, normal, face, distance = bvh.find_nearest(point)
                signed = distance if (point - hit).dot(normal) >= 0 else -distance
                # A held rope endpoint can touch its own palm. No torso,
                # forearm or distant hand intersection is exempted.
                intentional_grip = label in ("l", "r") and domains["hand_" + label][face] and (end - point).length <= .06
                clearance = abs(signed) - radius if intentional_grip else signed - radius
                if intentional_grip:
                    clearance = max(0, clearance)
                samples.append({"path": key, "index": index, "clearance_m": clearance, "intentional_hand_endpoint": intentional_grip,
                                "sample_interval_m": (end - start).length / steps})
        stack_clearance = min((obj.matrix_world @ Vector(corner)).z for key, obj in props.items() if key.startswith("stack_") for corner in obj.bound_box)
        support = {}
        if exercise_id == "cable_crunch":
            for label in ("l", "r"):
                knee = rig.matrix_world @ rig.pose.bones["calf_" + label].head
                ankle = rig.matrix_world @ rig.pose.bones["calf_" + label].tail
                axis = (ankle - knee).normalized()
                knee_vertices = [coords[index] for index in domains["leg_" + label] if (coords[index] - knee).length <= .13]
                shin_vertices = [coords[index] for index in domains["shin_" + label] if .15 <= (coords[index] - knee).dot(axis) <= (ankle - knee).length - .05]
                support["knee_" + label + "_mat_clearance_m"] = min(point.z for point in knee_vertices) - .004
                support["shin_" + label + "_mat_clearance_m"] = min(point.z for point in shin_vertices) - .004
        return {"frame": frame, "amount": amount, "minimum_cable_skin_clearance_m": min(s["clearance_m"] for s in samples),
                "moving_stack_min_floor_m": stack_clearance, "support": support, "samples": samples}
    finally:
        evaluated.to_mesh_clear()


def validate_surfaces(exercise_id, samples):
    clearance = min(sample["minimum_cable_skin_clearance_m"] for sample in samples)
    floor = min(sample["moving_stack_min_floor_m"] for sample in samples)
    support = [abs(value) for sample in samples for value in sample.get("support", {}).values()]
    support_max = max(support, default=0)
    return {"exercise_id": exercise_id, "passed": clearance >= -.001 and floor >= -.001 and support_max <= .003, "minimum_cable_skin_clearance_m": clearance,
            "moving_stack_min_floor_m": floor,
            "maximum_knee_shin_mat_clearance_m": support_max,
            "trainerApproved": False, "scope": "Actual posed cable/rope radius surface guard; hand endpoints permit intended grip contact only"}
