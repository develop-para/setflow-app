"""Original footwear, moving treadmill belt, rope and rotating stepmill.

No manufacturer meshes or third-party media are used. Actual evaluated sole
surfaces, cable radius and relative support paths are inspected every frame.
"""
import json
import math

import bpy
from mathutils import Vector
import equipment as e
import cardio_footwear as footwear


def _root(name):
    root = bpy.data.objects.new(name, None)
    bpy.context.scene.collection.objects.link(root)
    return root


def _line(name, points, mat, radius):
    from remaining_cable_equipment import _polyline
    return _polyline(name, points, mat, radius)


def _record_rest(props, rig):
    data = {}
    for label in ("l", "r"):
        sole = props["sole_" + label]
        vertices = json.loads(sole["rest_vertices_json"])
        indices = json.loads(sole["sole_bottom_indices_json"])
        contact = json.loads(sole["contact_vertex_indices_json"])
        data[label] = {kind: vertices[index] for kind, index in contact.items()}
        data[label]["bounds"] = {"min_y": min(vertices[index][1] for index in indices), "max_y": max(vertices[index][1] for index in indices)}
    rig["cardio_original_sole_rest_json"] = json.dumps(data)


def _tread_position(distance):
    """Continuous closed stair-chain path; the return is inside housing."""
    q = distance % 16
    if q <= 6:
        return Vector((0, .60 - .30 * q, .25 + .18 * q))
    if q <= 8:
        u = (q - 6) / 2
        return Vector((0, -1.20, 1.33 - .21 * u))
    if q <= 14:
        u = (q - 8) / 6
        return Vector((0, -1.20 + 1.80 * u, 1.12 - 1.08 * u))
    return Vector((0, .60, .04 + .21 * (q - 14) / 2))


def _clip_spec(rig):
    """A real waist-clothing vertex, with its actual native skin weights."""
    import motions as m
    clothing = bpy.data.objects["SetflowAthlete.training-briefs"]
    saved = [(bone, bone.matrix_basis.copy()) for bone in rig.pose.bones]
    modifiers = [(modifier, modifier.show_viewport) for modifier in clothing.modifiers]
    try:
        m.reset(rig)
        for modifier, _ in modifiers:
            modifier.show_viewport = modifier.show_render
        bpy.context.view_layer.update()
        deps = bpy.context.evaluated_depsgraph_get()
        evaluated = clothing.evaluated_get(deps)
        mesh = evaluated.to_mesh(preserve_all_data_layers=True, depsgraph=deps)
        try:
            target = rig.data.bones["pelvis"].head_local + Vector((.08, -.13, .075))
            transform = rig.matrix_world.inverted() @ evaluated.matrix_world
            groups = {group.index: group.name for group in clothing.vertex_groups}
            candidates = []
            for vertex in mesh.vertices:
                point = transform @ vertex.co
                torso = sum(group.weight for group in vertex.groups if groups[group.group].startswith(("pelvis", "spine_")))
                if torso < .98 or point.y >= -.04:
                    continue
                candidates.append(((point - target).length_squared, vertex.index, point, vertex.groups))
            if not candidates:
                raise ValueError("No actual front waist-clothing surface for emergency-stop clip")
            _, index, point, weights = min(candidates, key=lambda item: item[0])
            binding = [{"bone": groups[group.group], "weight": group.weight,
                        "local": list(rig.data.bones[groups[group.group]].matrix_local.inverted() @ point)}
                       for group in weights if group.weight > 0 and groups[group.group] in rig.data.bones]
            return {"vertex": index, "bindings": binding}
        finally:
            evaluated.to_mesh_clear()
    finally:
        for bone, matrix in saved:
            bone.matrix_basis = matrix
        for modifier, visibility in modifiers:
            modifier.show_viewport = visibility
        bpy.context.view_layer.update()


def create(exercise_id, rig):
    props = footwear.create(rig)
    _record_rest(props, rig)
    props["sole_l"]["cardio_variant"] = exercise_id
    steel = e.material("Original cardio neutral steel", (.22, .22, .22), .7)
    black = e.material("Original cardio graphite", (.04, .04, .04))
    stripe = e.material("Original cardio belt marking", (.36, .36, .36))
    scale = rig.scale.x
    if exercise_id == "brisk_walk":
        # Static lines make world travel visible while the camera follows.
        for index in range(-12, 16):
            y = -.58 * index * scale
            mesh = bpy.data.meshes.new("Walking route marking mesh " + str(index))
            mesh.from_pydata([(-1.0, y - .003, .00002), (1.0, y - .003, .00002), (1.0, y + .003, .00002), (-1.0, y + .003, .00002)], [], [(0, 1, 2, 3)])
            obj = bpy.data.objects.new("Original walking route marking " + str(index), mesh)
            bpy.context.scene.collection.objects.link(obj)
            mesh.materials.append(stripe)
    elif exercise_id == "run":
        deck = e.cube("Original treadmill deck", (0, -.04 * scale, .115 * scale), (.88 * scale, 1.96 * scale, .09 * scale), steel)
        props["deck"] = deck
        belt = e.cube("Original continuous treadmill belt", (0, -.04 * scale, .1575 * scale), (.66 * scale, 1.80 * scale, .005 * scale), black)
        props["belt"] = belt
        # Thin stripes follow a closed belt path. The surface portion moves
        # backward at exactly the same speed as a weight-bearing sole.
        for index in range(24):
            obj = e.cube("Moving treadmill belt stripe " + str(index), (0, 0, .16 * scale), (.64 * scale, .004, .0004), stripe)
            obj["belt_index"] = index
            props["belt_mark_" + str(index)] = obj
        for side in (-1, 1):
            e.cube("Original treadmill side platform " + str(side), (side * .39 * scale, -.04 * scale, .16 * scale), (.10 * scale, 1.90 * scale, .055 * scale), black)
            e.cube("Original treadmill upright " + str(side), (side * .45 * scale, -.91 * scale, .74 * scale), (.055, .08, 1.44 * scale), steel)
            e.cube("Original treadmill unheld rail " + str(side), (side * .43 * scale, -.58 * scale, 1.29 * scale), (.055, .69 * scale, .055), black)
        e.cube("Original treadmill console", (0, -.96 * scale, 1.45 * scale), (.84 * scale, .16 * scale, .16 * scale), black)
        stop = e.cube("Original treadmill emergency stop magnet", (0, -.855 * scale, 1.39 * scale), (.040, .025, .040), stripe)
        props["stop_magnet"] = stop
        clip = e.cube("Original treadmill clothing clip", (0, 0, 0), (.026, .020, .028), stripe)
        props["clothing_clip"] = clip
        clip["clothing_surface_binding_json"] = json.dumps(_clip_spec(rig))
        props["safety_cord"] = _line("Attached emergency-stop cord", [(0, 0, 0)] * 33, black, .0025)
    elif exercise_id == "jump_rope":
        for label in ("l", "r"):
            props[label] = _root("Original jump-rope handle " + label)
            e.cylinder("Closed jump-rope handle shaft " + label, .016, .16, black, props[label])
            props[label]["rope_attachment_local"] = [-.082, 0, 0]
        props["rope"] = _line("Original rotating jump rope", [(0, 0, 0)] * 129, stripe, .004)
    elif exercise_id == "stair_climber":
        for index in range(16):
            pos = _tread_position(index) * scale
            tread = e.cube("Original revolving stepmill tread " + str(index), pos - Vector((0, 0, .025 * scale)), (.71 * scale, .30 * scale, .05 * scale), black)
            tread["stair_index"] = index
            props["tread_" + str(index)] = tread
            riser = e.cube("Original revolving stepmill riser " + str(index), (0, -.15 * scale, .115 * scale), (.71 * scale, .012 * scale, .18 * scale), black)
            riser.parent = tread
        for side in (-1, 1):
            vertices = [(x * scale, y * scale, z * scale) for x in (side * .39, side * .49)
                        for y, z in ((.64, .015), (.64, .134), (-1.24, 1.262), (-1.24, .015))]
            data = bpy.data.meshes.new("Original sloping stepmill side housing mesh " + str(side))
            data.from_pydata(vertices, [], [(0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)])
            obj = bpy.data.objects.new("Original sloping stepmill side housing " + str(side), data)
            bpy.context.scene.collection.objects.link(obj)
            data.materials.append(steel)
            e.cube("Original stepmill upper column " + str(side), (side * .44 * scale, -1.06 * scale, 1.12 * scale), (.06, .08, 2.24 * scale), steel)
            e.cube("Original stepmill rail " + str(side), (side * .39 * scale, -.45 * scale, 1.59 * scale), (.05, .85 * scale, .05), black)
        e.cube("Original stepmill console", (0, -.98 * scale, 2.08 * scale), (.67 * scale, .15, .17), black)
        vertices = [(x * scale, y * scale, z * scale) for x in (-.375, .375)
                    for y, z in ((.64, .015), (.64, .079), (-1.24, 1.207), (-1.24, .015))]
        data = bpy.data.meshes.new("Original closed stepmill return housing mesh")
        data.from_pydata(vertices, [], [(0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)])
        housing = bpy.data.objects.new("Original closed stepmill return housing", data)
        bpy.context.scene.collection.objects.link(housing)
        data.materials.append(steel)
        for label in ("l", "r"):
            props[label] = _root("Original fixed stepmill held rail " + label)
            e.cylinder("Actual stepmill closed grip shaft " + label, .019, .19, black, props[label])
    else:
        raise ValueError("No exact cardio equipment: " + exercise_id)
    return props


def _set_points(obj, values, frame):
    for point, value in zip(obj.data.splines[0].points, values):
        point.co = (*value, 1)
        if frame is not None:
            point.keyframe_insert("co", frame=frame)


def _belt_point(distance):
    radius = .03
    arc = math.pi * radius
    length = (3.72 - 2 * arc) / 2
    front, rear = -.04 - length / 2, -.04 + length / 2
    q = distance % 3.72
    if q <= length:
        return front + q, .1602, 0.
    if q <= length + arc:
        angle = math.pi / 2 - (q - length) / radius
        return rear + radius * math.cos(angle), .1302 + radius * math.sin(angle), angle - math.pi / 2
    if q <= 2 * length + arc:
        return rear - (q - length - arc), .1002, -math.pi
    angle = -math.pi / 2 - (q - 2 * length - arc) / radius
    return front + radius * math.cos(angle), .1302 + radius * math.sin(angle), angle - math.pi / 2


def apply(props, contacts, rig, frame):
    e.apply(props, contacts, rig, frame)
    footwear.update(props, rig, frame)
    state = contacts["cardio"]
    states = json.loads(props["sole_l"].get("cardio_source_states_json", "{}"))
    states[str(frame)] = state
    props["sole_l"]["cardio_source_states_json"] = json.dumps(states)
    scale = rig.scale.x
    for key, obj in props.items():
        if key.startswith("belt_mark_"):
            y, z, angle = _belt_point(float(obj["belt_index"]) * .155 + state["belt_progress_native"])
            obj.location = (0, y * scale, z * scale)
            obj.rotation_euler = (angle, 0, 0)
        elif key.startswith("tread_"):
            obj.location = _tread_position(float(obj["stair_index"]) - state["stair_progress"]) * scale - Vector((0, 0, .025 * scale))
        if key.startswith(("belt_mark_", "tread_")) and frame is not None:
            obj.keyframe_insert("location", frame=frame)
            obj.keyframe_insert("rotation_euler", frame=frame)
    if "safety_cord" in props:
        bindings = json.loads(props["clothing_clip"]["clothing_surface_binding_json"])["bindings"]
        point = sum((rig.pose.bones[item["bone"]].matrix @ Vector(item["local"]) * item["weight"] for item in bindings), Vector())
        clip = rig.matrix_world @ point + rig.matrix_world.to_3x3() @ Vector((0, -.006, 0))
        props["clothing_clip"].location = clip
        start = props["stop_magnet"].location
        _set_points(props["safety_cord"], [start.lerp(clip, index / 32) - Vector((0, 0, .12 * math.sin(math.pi * index / 32))) for index in range(33)], frame)
        if frame is not None:
            props["clothing_clip"].keyframe_insert("location", frame=frame)
    if "rope" in props:
        bpy.context.view_layer.update()
        endpoints = [props[label].matrix_world @ Vector(props[label]["rope_attachment_local"]) for label in ("l", "r")]
        radius = 1.03 * scale - .008
        angle = state["rope_angle"]
        def path(radius):
            values = []
            for index in range(129):
                u = index / 128
                sag = radius * math.sin(math.pi * u)
                # The rope bows outside the arms before crossing the body
                # at its distant apex. A straight inward U cuts the torso.
                lateral = .25 * scale * math.sin(2 * math.pi * u)
                values.append(endpoints[0].lerp(endpoints[1], u) + Vector((lateral, sag * math.sin(angle), -sag * math.cos(angle))))
            return values
        values = path(radius)
        length = sum((b - a).length for a, b in zip(values, values[1:]))
        reference = float(props["rope"].get("rope_reference_length_m", length))
        props["rope"]["rope_reference_length_m"] = reference
        low, high = radius - .15, radius + .15
        for _ in range(25):
            radius = (low + high) / 2
            values = path(radius)
            current = sum((b - a).length for a, b in zip(values, values[1:]))
            if current < reference:
                low = radius
            else:
                high = radius
        _set_points(props["rope"], values, frame)
    bpy.context.view_layer.update()


def contacts_audit(props, contacts, rig):
    result = e.contacts_audit(props, contacts, rig)
    result.update(footwear.attachment_audit(props, rig))
    for label, state in contacts["cardio"]["feet"].items():
        if state["stance"]:
            actual = footwear.contact_world(props, rig, label, state["contact"])
            result[label + "_actual_sole_pivot_target_error_m"] = (actual - rig.matrix_world @ Vector(state["anchor"])).length
    return result


def _curve_clearance(obj, body, cache, hands=None):
    from mathutils.bvhtree import BVHTree
    deps = bpy.context.evaluated_depsgraph_get()
    evaluated = body.evaluated_get(deps)
    mesh = evaluated.to_mesh(preserve_all_data_layers=True, depsgraph=deps)
    try:
        points = [evaluated.matrix_world @ vertex.co for vertex in mesh.vertices]
        bvh = BVHTree.FromPolygons(points, [tuple(face.vertices) for face in mesh.polygons])
        key = ("cardio_hand_faces", body.as_pointer(), len(mesh.vertices), len(mesh.polygons))
        domains = cache.get(key)
        if domains is None:
            domains = {}
            for label in ("l", "r"):
                groups = {group.index for group in body.vertex_groups if group.name.startswith(("hand_", "index_", "middle_", "ring_", "pinky_", "thumb_")) and group.name.endswith("_" + label)}
                weights = [sum(group.weight for group in vertex.groups if group.group in groups) for vertex in mesh.vertices]
                domains[label] = [sum(weights[index] for index in face.vertices) / len(face.vertices) >= .5 for face in mesh.polygons]
            cache[key] = domains
        curve = [obj.matrix_world @ Vector(point.co[:3]) for point in obj.data.splines[0].points]
        minimum = float("inf")
        lowest = float("inf")
        spacing = 0.
        for a, b in zip(curve, curve[1:]):
            count = max(1, math.ceil((b - a).length / .005))
            spacing = max(spacing, (b - a).length / count)
            for index in range(count + 1):
                point = a.lerp(b, index / count)
                hit, normal, face, distance = bvh.find_nearest(point)
                signed = distance if (point - hit).dot(normal) >= 0 else -distance
                own_hand = hands is not None and any(domains[label][face] and (point - hands[label]).length <= .07 for label in ("l", "r"))
                clearance = max(0., distance - obj.data.bevel_depth) if own_hand else signed - obj.data.bevel_depth
                minimum = min(minimum, clearance)
                lowest = min(lowest, point.z - obj.data.bevel_depth)
        return minimum, lowest, spacing
    finally:
        evaluated.to_mesh_clear()


def _actual_bvh(obj):
    from mathutils.bvhtree import BVHTree
    deps = bpy.context.evaluated_depsgraph_get()
    evaluated = obj.evaluated_get(deps)
    mesh = evaluated.to_mesh()
    try:
        points = [evaluated.matrix_world @ vertex.co for vertex in mesh.vertices]
        return BVHTree.FromPolygons(points, [tuple(face.vertices) for face in mesh.polygons])
    finally:
        evaluated.to_mesh_clear()


def _stair_collisions(props, body):
    """Actual mesh triangle overlap, including swing shoes and body shins."""
    body_bvh = _actual_bvh(body)
    shoes = [_actual_bvh(props[key]) for key in ("shoe_l", "sole_l", "shoe_r", "sole_r")]
    body_count, shoe_count = 0, 0
    for key, tread in props.items():
        if not key.startswith("tread_"):
            continue
        for obj in (tread, *tread.children_recursive):
            if obj.type != "MESH":
                continue
            bvh = _actual_bvh(obj)
            body_count += len(body_bvh.overlap(bvh))
            shoe_count += sum(len(shoe.overlap(bvh)) for shoe in shoes)
    return {"stair_body_surface_intersection_pairs": body_count, "stair_shoe_surface_intersection_pairs": shoe_count}


def _rope_shoe_clearance(props):
    shoe_bvhs = [_actual_bvh(props[key]) for key in ("shoe_l", "sole_l", "shoe_r", "sole_r")]
    curve = [Vector(point.co[:3]) for point in props["rope"].data.splines[0].points]
    minimum = float("inf")
    intersections = 0
    for a, b in zip(curve, curve[1:]):
        for bvh in shoe_bvhs:
            if bvh.ray_cast(a, (b - a).normalized(), (b - a).length)[0] is not None:
                intersections += 1
        count = max(1, math.ceil((b - a).length / .005))
        for index in range(count + 1):
            point = a.lerp(b, index / count)
            for bvh in shoe_bvhs:
                _, _, _, distance = bvh.find_nearest(point)
                # A shoe upper has an open ankle cuff. Its nearest-face
                # normal cannot classify distant points as inside/outside.
                # Check actual surface radius and all centerline crossings.
                # At <=5mm spacing an 8mm rope cannot cross a surface
                # between samples without the radius test detecting it.
                minimum = min(minimum, distance - props["rope"].data.bevel_depth)
    return minimum, intersections


def surface_audit(exercise_id, props, rig, body, frame, amount, cache):
    state = json.loads(props["sole_l"]["cardio_source_states_json"])[str(frame)]
    support = {}
    min_floor = float("inf")
    for label, foot in state["feet"].items():
        actual = footwear.sole_vertices(props, label)
        floor = .16 * rig.scale.x if exercise_id == "run" else 0.
        if exercise_id == "stair_climber" and foot["stance"]:
            tread = props["tread_" + str(foot["tread"] % 16)]
            floor = tread.location.z + .025 * rig.scale.x
            minx, maxx = -.355 * rig.scale.x, .355 * rig.scale.x
            miny, maxy = tread.location.y - .15 * rig.scale.x, tread.location.y + .15 * rig.scale.x
            support[label + "_sole_tread_edge_clearance_m"] = min(min(point.x - minx, maxx - point.x, point.y - miny, maxy - point.y) for point in actual)
        clearance = min(point.z for point in actual) - floor
        support[label + "_sole_surface_clearance_m"] = clearance
        support[label + "_expected_stance"] = foot["stance"]
        support[label + "_contact_kind"] = foot["contact"]
        support[label + "_phase"] = foot["q"]
        support[label + "_step_index"] = foot.get("index", 0)
        min_floor = min(min_floor, min(point.z for point in actual))
        if foot["stance"]:
            marker = footwear.contact_world(props, rig, label, foot["contact"])
            support[label + "_actual_pivot_world"] = list(marker)
            support[label + "_anchor_world"] = list(rig.matrix_world @ Vector(foot["anchor"]))
            if exercise_id == "stair_climber":
                support[label + "_moving_surface_world"] = list(tread.location)
            elif exercise_id == "run":
                support[label + "_moving_surface_world"] = [0, state["belt_progress_native"] * rig.scale.x, 0]
            else:
                support[label + "_moving_surface_world"] = [0, 0, 0]
    extra = {}
    if "rope" in props:
        palms = {label: props[label].location.copy() for label in ("l", "r")}
        clearance, lowest, interval = _curve_clearance(props["rope"], body, cache, palms)
        vertices = [Vector(point.co[:3]) for point in props["rope"].data.splines[0].points]
        length = sum((b - a).length for a, b in zip(vertices, vertices[1:]))
        shoe_clearance, shoe_crossings = _rope_shoe_clearance(props)
        extra = {"rope_skin_clearance_m": clearance, "rope_floor_clearance_m": lowest, "rope_sample_interval_m": interval,
                 "rope_shoe_clearance_m": shoe_clearance, "rope_shoe_centerline_crossings": shoe_crossings, "rope_length_m": length,
                 "rope_length_conservation_error_m": abs(length - float(props["rope"]["rope_reference_length_m"]))}
    if exercise_id == "stair_climber":
        extra.update(_stair_collisions(props, body))
    if "safety_cord" in props:
        # The cord deliberately terminates at the clothing clip. Its open
        # approach is reviewed separately from a load cable/rope grip.
        binding = json.loads(props["clothing_clip"]["clothing_surface_binding_json"])
        vertex = footwear._actual_vertices(bpy.data.objects["SetflowAthlete.training-briefs"])[binding["vertex"]]
        offset = rig.matrix_world.to_3x3() @ Vector((0, -.006, 0))
        extra["clip_actual_clothing_vertex_error_m"] = (props["clothing_clip"].location - offset - vertex).length
    return {"frame": frame, "amount": amount, "support": support, "sole_min_world_floor_m": min_floor,
            "enclosure": footwear.foot_enclosure_audit(props, body),
            "attachment": footwear.attachment_audit(props, rig), **extra}


def validate_surfaces(exercise_id, samples):
    # These are measured production samples, not optional annotations.
    # Reject missing/invalid evidence before any default can look like zero.
    schema_failures = []
    def number(value, nonnegative=False):
        return isinstance(value, (int, float)) and not isinstance(value, bool) and math.isfinite(value) and (not nonnegative or value >= 0)
    def vector(value):
        return isinstance(value, (list, tuple)) and len(value) == 3 and all(number(component) for component in value)
    if exercise_id not in ("brisk_walk", "run", "jump_rope", "stair_climber"):
        schema_failures.append("Unknown exact cardio ID")
    if not isinstance(samples, list) or len(samples) != 96:
        schema_failures.append("Actual production surface evidence requires all96 samples")
    else:
        frames = [sample.get("frame") if isinstance(sample, dict) else None for sample in samples]
        if frames != list(range(1, 97)) or not all(isinstance(frame, int) and not isinstance(frame, bool) for frame in frames):
            schema_failures.append("Actual production surface frames must cover1 through96 exactly once")
        for sample in samples:
            if not isinstance(sample, dict):
                schema_failures.append("Actual surface sample must be a measured object")
                continue
            if not number(sample.get("amount")) or not 0 <= sample["amount"] <= 1 or not number(sample.get("sole_min_world_floor_m")):
                schema_failures.append("Actual surface amount/floor evidence must be finite")
            enclosure, attachment = sample.get("enclosure"), sample.get("attachment")
            if not isinstance(enclosure, dict) or not all(number(enclosure.get(label + "_foot_outside_shoe_max_m"), True) for label in ("l", "r")) or not all(number(value, True) for value in enclosure.values()):
                schema_failures.append("Bilateral actual foot enclosure evidence must be present finite and nonnegative")
            if isinstance(enclosure, dict):
                for label in ("l", "r"):
                    domain_count = enclosure.get(label + "_actual_enclosure_skin_vertex_count")
                    body_count = enclosure.get(label + "_actual_enclosure_body_mesh_vertex_count")
                    if not isinstance(domain_count, int) or isinstance(domain_count, bool) or not isinstance(body_count, int) or isinstance(body_count, bool) or not 0 < domain_count <= body_count:
                        schema_failures.append("Actual bilateral enclosure domains require positive integer counts within the body mesh")
            if not isinstance(attachment, dict) or not number(attachment.get("shoe_native_attachment_max_error_m"), True) or not all(number(value, True) for value in attachment.values()):
                schema_failures.append("Actual footwear attachment evidence must be present finite and nonnegative")
            support = sample.get("support")
            if not isinstance(support, dict):
                schema_failures.append("Actual bilateral sole support evidence is required")
                continue
            for label in ("l", "r"):
                if not number(support.get(label + "_sole_surface_clearance_m")) or not isinstance(support.get(label + "_expected_stance"), bool):
                    schema_failures.append("Actual bilateral sole clearance and stance must be finite and explicit")
                    continue
                if not number(support.get(label + "_phase")) or not 0 <= support[label + "_phase"] <= 1:
                    schema_failures.append("Actual foot phase must be finite and normalized")
                step_index = support.get(label + "_step_index")
                if not isinstance(step_index, int) or isinstance(step_index, bool) or step_index < 0:
                    schema_failures.append("Actual foot step index must be a nonnegative integer")
                contact = support.get(label + "_contact_kind")
                if contact not in ("heel", "forefoot", "air") or (support[label + "_expected_stance"] and contact == "air"):
                    schema_failures.append("Actual stance requires a physical heel/forefoot contact")
                if support[label + "_expected_stance"]:
                    if not all(vector(support.get(label + suffix)) for suffix in ("_actual_pivot_world", "_anchor_world", "_moving_surface_world")):
                        schema_failures.append("Actual supporting pivot/anchor/surface vectors must be present and finite")
                    if exercise_id == "stair_climber" and not number(support.get(label + "_sole_tread_edge_clearance_m")):
                        schema_failures.append("Actual whole-sole tread edge evidence is required")
            if exercise_id == "jump_rope":
                signed = ("rope_skin_clearance_m", "rope_floor_clearance_m", "rope_shoe_clearance_m")
                positive = ("rope_sample_interval_m", "rope_length_m", "rope_length_conservation_error_m")
                if not all(number(sample.get(key)) for key in signed) or not all(number(sample.get(key), True) for key in positive):
                    schema_failures.append("Actual rope skin/shoe/floor/length evidence must be present and finite")
                elif sample["rope_sample_interval_m"] <= 0 or sample["rope_sample_interval_m"] > .005001 or sample["rope_length_m"] <= 0:
                    schema_failures.append("Actual rope samples require positive length and at most5mm spacing")
            if exercise_id in ("jump_rope", "stair_climber"):
                keys = ("rope_shoe_centerline_crossings",) if exercise_id == "jump_rope" else ("stair_body_surface_intersection_pairs", "stair_shoe_surface_intersection_pairs")
                if not all(isinstance(sample.get(key), int) and not isinstance(sample[key], bool) and sample[key] >= 0 for key in keys):
                    schema_failures.append("Actual surface intersection counts must be present nonnegative integers")
            if exercise_id == "run" and not number(sample.get("clip_actual_clothing_vertex_error_m"), True):
                schema_failures.append("Actual emergency clip clothing evidence must be present finite and nonnegative")
    if schema_failures:
        return {"exercise_id": exercise_id, "passed": False, "failures": sorted(set(schema_failures)), "trainerApproved": False,
                "scope": "Invalid or missing measured evidence is never accepted as zero"}
    failures = []
    contacts, penetrations, tread_edges, pivot_errors = [], [], [], []
    both_air = 0
    flight_clearances = []
    planted = {}
    drifts = []
    for sample in samples:
        support = sample["support"]
        count = 0
        for label in ("l", "r"):
            clearance = support[label + "_sole_surface_clearance_m"]
            if support[label + "_expected_stance"]:
                contacts.append(abs(clearance))
                pivot_errors.append(math.dist(support[label + "_actual_pivot_world"], support[label + "_anchor_world"]))
                count += 1
                key = (label, support[label + "_step_index"], support[label + "_contact_kind"])
                relative = [point - shift for point, shift in zip(support[label + "_actual_pivot_world"], support[label + "_moving_surface_world"])]
                planted.setdefault(key, relative)
                drifts.append(math.dist(relative, planted[key]))
            if exercise_id != "stair_climber" or support[label + "_expected_stance"]:
                penetrations.append(clearance)
            if label + "_sole_tread_edge_clearance_m" in support:
                tread_edges.append(support[label + "_sole_tread_edge_clearance_m"])
        if count == 0:
            actual_clearances = [support[label + "_sole_surface_clearance_m"] for label in ("l", "r")]
            if exercise_id in ("run", "jump_rope"):
                flight_clearances.extend(actual_clearances)
                if min(actual_clearances) <= .001:
                    failures.append("Claimed flight phase lacks actual bilateral sole clearance")
                else:
                    both_air += 1
            else:
                both_air += 1
        if exercise_id in ("brisk_walk", "stair_climber") and count == 0:
            failures.append("Continuous stepping loses all expected support")
    if min(penetrations, default=0) < -.001:
        failures.append("Actual sole enters the weight-bearing surface")
    if max(contacts, default=0) > .003:
        failures.append("Expected weight-bearing sole floats above its surface")
    if max(pivot_errors, default=0) > .0001:
        failures.append("Actual sole pivot misses the planted target")
    if max(drifts, default=0) > .0001:
        failures.append("Actual supporting sole slides relative to its floor, belt or tread")
    if min(tread_edges, default=0) < -.001:
        failures.append("Whole sole does not fit its actual stair tread")
    if exercise_id in ("run", "jump_rope") and both_air == 0:
        failures.append("Running/jumping lacks an actual unsupported flight phase")
    rope_clear = min((sample["rope_skin_clearance_m"] for sample in samples if "rope_skin_clearance_m" in sample), default=None)
    rope_floor = min((sample["rope_floor_clearance_m"] for sample in samples if "rope_floor_clearance_m" in sample), default=None)
    if rope_clear is not None and rope_clear < -.001:
        failures.append("Rotating rope intersects non-grip skin")
    if rope_floor is not None and rope_floor < -.001:
        failures.append("Rotating rope passes beneath the floor")
    if max((sample.get("rope_length_conservation_error_m", 0) for sample in samples), default=0) > .00001:
        failures.append("Rotating rope changes its material length")
    if min((sample.get("rope_shoe_clearance_m", 1) for sample in samples), default=1) < -.001:
        failures.append("Rotating rope enters an actual shoe or sole")
    if max((sample.get("rope_shoe_centerline_crossings", 0) for sample in samples), default=0) > 0:
        failures.append("Rotating rope centerline crosses an actual shoe surface")
    if max((sample.get("stair_body_surface_intersection_pairs", 0) for sample in samples), default=0) > 0:
        failures.append("Actual body intersects a moving stair tread or riser")
    if max((sample.get("stair_shoe_surface_intersection_pairs", 0) for sample in samples), default=0) > 0:
        failures.append("Actual shoe intersects a moving stair tread or riser")
    if max((sample.get("clip_actual_clothing_vertex_error_m", 0) for sample in samples), default=0) > .002:
        failures.append("Emergency-stop clip does not follow its actual clothing surface")
    if max(sample["enclosure"][label + "_foot_outside_shoe_max_m"] for sample in samples for label in ("l", "r")) > .001:
        failures.append("Actual native foot skin protrudes through its shoe or sole")
    if max(sample["attachment"]["shoe_native_attachment_max_error_m"] for sample in samples) > .0001:
        failures.append("Actual original footwear loses its native foot/ball attachment")
    return {"exercise_id": exercise_id, "passed": not failures, "failures": sorted(set(failures)),
            "maximum_stance_surface_gap_m": max(contacts, default=0), "minimum_sole_surface_clearance_m": min(penetrations, default=0),
            "maximum_actual_pivot_error_m": max(pivot_errors, default=0), "minimum_tread_edge_clearance_m": min(tread_edges, default=None),
            "maximum_planted_surface_relative_drift_m": max(drifts, default=0),
            "maximum_foot_skin_outside_shoe_distance_m": max(sample["enclosure"][label + "_foot_outside_shoe_max_m"] for sample in samples for label in ("l", "r")),
            "minimum_bilateral_actual_enclosure_skin_vertex_count": min(sample["enclosure"][label + "_actual_enclosure_skin_vertex_count"] for sample in samples for label in ("l", "r")),
            "maximum_footwear_attachment_error_m": max((value for sample in samples for value in sample.get("attachment", {}).values()), default=0),
            "rope_min_shoe_clearance_m": min((sample["rope_shoe_clearance_m"] for sample in samples if "rope_shoe_clearance_m" in sample), default=None),
            "rope_max_centerline_shoe_crossings": max((sample.get("rope_shoe_centerline_crossings", 0) for sample in samples), default=0),
            "rope_max_material_length_error_m": max((sample.get("rope_length_conservation_error_m", 0) for sample in samples), default=0),
            "stair_max_body_intersection_pairs": max((sample.get("stair_body_surface_intersection_pairs", 0) for sample in samples), default=0),
            "stair_max_shoe_intersection_pairs": max((sample.get("stair_shoe_surface_intersection_pairs", 0) for sample in samples), default=0),
            "maximum_emergency_clip_clothing_error_m": max((sample.get("clip_actual_clothing_vertex_error_m", 0) for sample in samples), default=0),
            "both_feet_air_frames": both_air, "rope_min_skin_clearance_m": rope_clear, "rope_min_floor_clearance_m": rope_floor,
            "minimum_actual_flight_sole_clearance_m": min(flight_clearances, default=None),
            "trainerApproved": False, "scope": "Actual evaluated original footwear and original equipment; selected model guards are not trainer certification"}
