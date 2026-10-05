"""Original coupled cardio machines, actual sole/skin and finite-support guards.

No manufacturer mesh or media is used. Fixed pivots, fitted saddles, strapped
pedals and handle contacts select this athlete; they do not certify technique.
"""
import json
import math


def _api():
    import bpy
    import equipment
    import cardio_extra_motions as m
    import cardio_footwear as shoes
    from mathutils import Vector, Quaternion, Matrix
    return bpy, equipment, m, shoes, Vector, Quaternion, Matrix


def _root(name):
    from remaining_strength_equipment import _root as root
    return root(name)


def _rod(name, start, end, radius, props):
    bpy, e, _, _, V, _, _ = _api()
    obj = e.cylinder(name, radius, 1., e.material("Original cardio structural steel", (.24, .24, .24), .7))
    obj["cardio_radius_m"] = radius
    props[name] = obj
    _line(obj, V(start), V(end))
    return obj


def _line(obj, start, end):
    V = _api()[4]
    obj.location = (start + end) / 2
    obj.rotation_mode = "QUATERNION"
    obj.rotation_quaternion = V((0, 0, 1)).rotation_difference((end - start).normalized())
    obj.scale = (1, 1, (end - start).length)
    obj["actual_start_world"] = list(start)
    obj["actual_end_world"] = list(end)


def _endpoints(obj):
    V = _api()[4]
    return obj.matrix_world @ V((0, 0, -.5)), obj.matrix_world @ V((0, 0, .5))


def _platform(name, center, pitch, width, length, height, props):
    _, e, _, _, _, Q, _ = _api()
    obj = e.cube(name, center, (width, length, height), e.material("Original cardio tread", (.066, .066, .066)))
    # Unbevelled flat top is the actual supported polygon, not an invisible plane.
    for modifier in list(obj.modifiers):
        obj.modifiers.remove(modifier)
    obj.rotation_mode = "QUATERNION"
    obj.rotation_quaternion = Q((1, 0, 0), pitch)
    obj["cardio_platform_json"] = json.dumps({"width": width, "length": length, "height": height})
    props[name] = obj
    return obj


def _strap(name, props, label):
    bpy, e, _, shoes, V, _, _ = _api()
    # The shoe's actual outer upper is followed by a curved strap over its
    # forefoot. It moves with the actual rigid foot platform on these machines.
    points = shoes._actual_vertices(props["shoe_" + label])
    target_y = shoes.contact_world(props, bpy.data.objects["SetflowAthlete.rig"], label, "forefoot").y + .018
    near = sorted(points, key=lambda point: abs(point.y - target_y))[:max(8, len(points) // 4)]
    roof = max(point.z for point in near)
    left, right = min(point.x for point in near), max(point.x for point in near)
    center = V(((left + right) / 2, target_y, roof + .003))
    strap = e.cube(name, center, (right - left + .006, .026, .005), e.material("Original fitted pedal strap", (.11, .11, .11)))
    strap["strap_label"] = label
    props[name] = strap
    platform = props["pedal_" + label]
    dims = json.loads(platform["cardio_platform_json"])
    local_y = (platform.matrix_world.inverted() @ center).y
    for side in (-1, 1):
        lower = platform.matrix_world @ V((side * dims["width"] / 2, local_y, dims["height"] / 2))
        upper = center.copy()
        upper.x = left - .003 if side < 0 else right + .003
        leg = _rod(name + "_anchor_" + str(side), lower, upper, .003, props)
        leg["strap_label"] = label
    return strap


def _fit_rower_seated_hip(rig, body, seat):
    """Seat height stays fixed; native hip rolls over its actual glute support.

    A model-specific few-mm hip-centre path is fitted to the real evaluated
    skin at all 96 authored amounts, without moving the horizontal rail or
    widening the support tolerance. It is exported as explicit native data.
    """
    bpy, _, m, shoes, V, _, _ = _api()
    from remaining_strength_extra_equipment import _actual_skin, _domain_indices
    indices = _domain_indices(_actual_skin(rig), ("pelvis", "thigh_l", "thigh_r"))
    level = seat["support_top_level_m"]
    width, length = seat["support_width_m"], seat["support_length_m"]
    rest_hip = rig.matrix_world @ ((rig.pose.bones["thigh_l"].head + rig.pose.bones["thigh_r"].head) / 2)
    offset_y = seat.location.y - rest_hip.y
    modifiers = [(modifier, modifier.show_viewport) for modifier in body.modifiers]
    rig["cardio_rower_fitting"] = True
    fit = []
    try:
        for frame in range(96):
            correction = 0.
            for _ in range(3):
                for modifier, _ in modifiers:
                    modifier.show_viewport = False
                rig["cardio_rower_fit_override"] = correction
                contacts = m.pose(rig, "rowing_machine", frame / 95)
                center_y = (rig.matrix_world @ contacts["rower_hip"]).y + offset_y
                for modifier, _ in modifiers:
                    modifier.show_viewport = modifier.show_render
                bpy.context.view_layer.update()
                points = shoes._actual_vertices(body)
                selected = [points[index].z for index in indices if abs(points[index].x) < width / 2 - .007 and abs(points[index].y - center_y) < length / 2 - .007]
                if not selected:
                    raise ValueError("Actual seated glute support missing during hip fit")
                correction += (level + .0008 - min(selected)) / rig.scale.x
            fit.append(correction)
            if frame % 24 == 0:
                print("ROWER_ACTUAL_SEAT_FIT", frame + 1, correction * rig.scale.x, flush=True)
        if max(abs(value) for value in fit) > .015:
            raise ValueError("Rower hip support correction exceeds disclosed model fit")
        rig["cardio_rower_hip_fit_json"] = json.dumps(fit)
        seat["model_hip_fit_min_m"] = min(fit) * rig.scale.x
        seat["model_hip_fit_max_m"] = max(fit) * rig.scale.x
    finally:
        rig["cardio_rower_fit_override"] = 0.
        rig["cardio_rower_fitting"] = False
        for modifier, visibility in modifiers:
            modifier.show_viewport = visibility
        bpy.context.view_layer.update()
        m.pose(rig, "rowing_machine", 0.)


def create(exercise_id, rig):
    bpy, e, m, shoes, V, Q, _ = _api()
    if exercise_id not in m.SUPPORTED:
        raise ValueError("Unknown exact cardio extra equipment")
    body = bpy.data.objects["SetflowAthlete.body"]
    props = shoes.create(rig, body)
    contacts = m.pose(rig, exercise_id, 0.)
    shoes.update(props, rig)
    world = rig.matrix_world
    scale = rig.scale.x
    props["machine"] = _root("Setflow original " + exercise_id)
    props["machine"]["exercise_id"] = exercise_id
    for side in (-1, 1):
        _rod("base_" + str(side), V((side * .46, -.95, .035)), V((side * .46, 1.15, .035)), .033, props)
    for y in (-.85, 1.05):
        _rod("base_cross_" + str(y), V((-.48, y, .035)), V((.48, y, .035)), .033, props)
    if exercise_id == "stationary_bike":
        crank = world @ V(m.BIKE_CRANK)
        _rod("bike_crank_axle", crank - V((.09, 0, 0)), crank + V((.09, 0, 0)), .014, props)
        housing = e.cylinder("Original enclosed stationary-bike resistance wheel", .13, .10, e.material("Cardio flywheel charcoal", (.06, .06, .06)))
        housing.location = crank
        props["housing"] = housing
        _rod("bike_main_frame", V((0, .43, .10)), crank, .052, props)
        _rod("bike_front_frame", crank, V((0, -.61, .25)), .052, props)
        _rod("bike_bar_support", V((0, -.61, .12)), V((0, -.46, 1.25)), .035, props)
        bar_center = world @ ((contacts["l"]["palm"] + contacts["r"]["palm"]) / 2)
        _rod("bike_handle_cross", world @ contacts["l"]["palm"], world @ contacts["r"]["palm"], .014, props)
        _rod("bike_handle_terminal", V((0, -.46, 1.25)), bar_center, .025, props)
        for label in ("l", "r"):
            side = 1 if label == "l" else -1
            _rod("grip_" + label, world @ contacts[label]["palm"] - V((.13, 0, 0)), world @ contacts[label]["palm"] + V((.13, 0, 0)), .014, props)
            hub = crank + V((side * .09, 0, 0))
            endpoint = world @ contacts["pedal_" + label]
            inner = V((side * .09, endpoint.y, endpoint.z))
            _rod("bike_crank_" + label, hub, inner, .014, props)
            _rod("bike_pedal_axle_" + label, inner, endpoint, .010, props)
            _platform("pedal_" + label, world @ contacts["pedal_" + label] + V((0, 0, .008)), 0, .16, .16, .016, props)
    elif exercise_id == "elliptical":
        _rod("elliptical_rear_axle", world @ V((-.21, *m.ELLIPTICAL_REAR)), world @ V((.21, *m.ELLIPTICAL_REAR)), .023, props)
        for label, side in (("l", 1), ("r", -1)):
            rear = world @ V((side * .21, *m.ELLIPTICAL_REAR))
            front = world @ V((side * .21, *m.ELLIPTICAL_FRONT))
            _rod("elliptical_rear_mount_" + label, V((rear.x, rear.y, .07)), rear, .03, props)
            _rod("elliptical_front_mount_" + label, V((front.x + side * .14, front.y, .07)), front + V((side * .14, 0, 0)), .033, props)
            _rod("elliptical_front_axle_" + label, front, front + V((side * .14, 0, 0)), .022, props)
            linkage = contacts["linkage"][label]
            for key, start, finish, radius in (("crank", rear, world @ linkage["rear"], .019),
                    ("coupler", world @ linkage["rear"], world @ linkage["front"], .022),
                    ("rocker", world @ linkage["front"], world @ V((side * .21, linkage["handle"].y, linkage["handle"].z)), .021)):
                _rod("elliptical_" + key + "_" + label, start, finish, radius, props)
            _rod("elliptical_handle_cross_" + label, world @ V((side * .21, linkage["handle"].y, linkage["handle"].z)), world @ linkage["handle"], .018, props)
            normal = Q((1, 0, 0), linkage["pitch_rad"]) @ V((0, 0, 1))
            _platform("pedal_" + label, world @ linkage["pedal"] + normal * .019, linkage["pitch_rad"], .20, .48, .022, props)
            _rod("grip_" + label, world @ contacts[label]["palm"] - (world.to_3x3() @ contacts[label]["handle_axis"]).normalized() * .11,
                 world @ contacts[label]["palm"] + (world.to_3x3() @ contacts[label]["handle_axis"]).normalized() * .11, .014, props)
        _rod("elliptical_front_cross", world @ V((-.48, *m.ELLIPTICAL_FRONT)), world @ V((.48, *m.ELLIPTICAL_FRONT)), .03, props)
    else:
        hip = world @ contacts["rower_hip"]
        _rod("rower_rail", V((0, -.34, .34)), V((0, 1.22, .34)), .047, props)
        _rod("rower_rail_rear_leg", V((0, 1.12, .035)), V((0, 1.12, .34)), .035, props)
        _rod("rower_front_leg", V((0, -.48, .035)), V((0, -.48, .34)), .035, props)
        # A compact flywheel is below the straight handle/chain path, clear of
        # the actual catch knees. It is original geometry, without a logo.
        wheel = e.cylinder("Original rower flywheel housing", .22, .29, e.material("Cardio flywheel charcoal", (.06, .06, .06)))
        wheel.location = (0, -1.08, .36)
        props["housing"] = wheel
        for label in ("l", "r"):
            ankle = world @ rig.pose.bones["foot_" + label].head
            normal = Q((1, 0, 0), math.radians(-40)) @ V((0, 0, 1))
            points = shoes.sole_vertices(props, label)
            center = sum(points, V()) / len(points)
            center += normal * (min(point.dot(normal) for point in points) - center.dot(normal) - .0108)
            _platform("pedal_" + label, center, math.radians(-40), .18, .39, .02, props)
            _rod("rower_footplate_support_" + label, V((center.x, center.y, .055)), center - V((0, 0, .045)), .022, props)
        _rod("grip_handle", world @ contacts["rower_handle"] - V((.31, 0, 0)), world @ contacts["rower_handle"] + V((.31, 0, 0)), .014, props)
        _rod("rower_chain", V((0, -1.02, contacts["rower_handle"].z * scale)), world @ contacts["rower_handle"], .003, props)
        _rod("rower_chain_guide_frame", V((0, -1.02, .055)), V((0, -1.02, contacts["rower_handle"].z * scale)), .024, props)
    if exercise_id in ("stationary_bike", "rowing_machine"):
        from remaining_strength_extra_equipment import _actual_skin, _pad
        hip = world @ ((rig.pose.bones["thigh_l"].head + rig.pose.bones["thigh_r"].head) / 2)
        bike = exercise_id == "stationary_bike"
        seat = _pad("Original fitted saddle", hip + V((0, .13 if bike else .015, 0)), (0, 1, 0), (0, 0, 1), .20 if bike else .34, .16 if bike else .28,
                    ("pelvis",) if bike else ("pelvis", "thigh_l", "thigh_r"), _actual_skin(rig), props["machine"], .045)
        if bike:
            seat.location.z -= .0015
            seat["support_top_level_m"] -= .0015
        props["pad_seat"] = seat
        seat["rest_hip_world_json"] = json.dumps(list(hip))
        seat["rest_center_world_json"] = json.dumps(list(seat.location))
        if not bike:
            _fit_rower_seated_hip(rig, body, seat)
            contacts = m.pose(rig, exercise_id, 0.)
        _rod("seat_support", V((0, seat.location.y, .10 if exercise_id == "stationary_bike" else .37)), seat.location - V((0, 0, .027)), .03, props)
    if exercise_id in ("stationary_bike", "rowing_machine"):
        for label in ("l", "r"):
            strap = _strap("strap_" + label, props, label)
            for obj in props.values():
                if obj.get("strap_label") == label:
                    obj["rest_foot_matrix_json"] = json.dumps([list(row) for row in rig.matrix_world @ rig.pose.bones["foot_" + label].matrix])
    apply(props, contacts, rig)
    return props


def apply(props, contacts, rig, frame=None):
    bpy, _, m, shoes, V, Q, M = _api()
    world = rig.matrix_world
    exercise_id = props["machine"]["exercise_id"]
    if exercise_id == "stationary_bike":
        for label in ("l", "r"):
            side = 1 if label == "l" else -1
            pedal = world @ contacts["pedal_" + label]
            props["pedal_" + label].location = pedal + V((0, 0, .008))
            hub = world @ V(m.BIKE_CRANK) + V((side * .09, 0, 0))
            inner = V((side * .09, pedal.y, pedal.z))
            _line(props["bike_crank_" + label], hub, inner)
            _line(props["bike_pedal_axle_" + label], inner, pedal)
    elif exercise_id == "elliptical":
        for label, side in (("l", 1), ("r", -1)):
            link = contacts["linkage"][label]
            _line(props["elliptical_crank_" + label], world @ V((side * .21, *m.ELLIPTICAL_REAR)), world @ link["rear"])
            _line(props["elliptical_coupler_" + label], world @ link["rear"], world @ link["front"])
            rocker_end = world @ V((side * .21, link["handle"].y, link["handle"].z))
            _line(props["elliptical_rocker_" + label], world @ link["front"], rocker_end)
            _line(props["elliptical_handle_cross_" + label], rocker_end, world @ link["handle"])
            rotation = Q((1, 0, 0), link["pitch_rad"])
            props["pedal_" + label].location = world @ link["pedal"] + rotation @ V((0, 0, .019))
            props["pedal_" + label].rotation_quaternion = rotation
            axis = (world.to_3x3() @ contacts[label]["handle_axis"]).normalized()
            center = world @ contacts[label]["palm"]
            _line(props["grip_" + label], center - axis * .11, center + axis * .11)
    else:
        handle = world @ contacts["rower_handle"]
        _line(props["grip_handle"], handle - V((.31, 0, 0)), handle + V((.31, 0, 0)))
        _line(props["rower_chain"], V((0, -1.02, handle.z)), handle)
        seat = props["pad_seat"]
        hip = world @ contacts["rower_hip"]
        delta = hip - V(json.loads(seat["rest_hip_world_json"]))
        delta.z = 0.
        seat.location = V(json.loads(seat["rest_center_world_json"])) + delta
        seat["support_top_level_m"] = seat.location.z + seat["support_thickness_m"] / 2
        _line(props["seat_support"], V((0, seat.location.y, .37)), seat.location - V((0, 0, .027)))
    shoes.update(props, rig, frame)
    for strap in props.values():
        label = strap.get("strap_label")
        if label:
            if not strap.get("rest_matrix_json"):
                strap["rest_matrix_json"] = json.dumps([list(row) for row in strap.matrix_world])
            current = world @ rig.pose.bones["foot_" + label].matrix
            strap.matrix_world = current @ M(json.loads(strap["rest_foot_matrix_json"])).inverted() @ M(json.loads(strap["rest_matrix_json"]))
    if frame is not None:
        for obj in props.values():
            obj.keyframe_insert("location", frame=frame)
            obj.keyframe_insert("scale", frame=frame)
            obj.keyframe_insert("rotation_quaternion" if obj.rotation_mode == "QUATERNION" else "rotation_euler", frame=frame)
    bpy.context.view_layer.update()


def contacts_audit(props, contacts, rig):
    _, _, _, shoes, V, _, _ = _api()
    result = shoes.attachment_audit(props, rig)
    exercise_id = props["machine"]["exercise_id"]
    for label in ("l", "r"):
        grip = props["grip_handle"] if exercise_id == "rowing_machine" else props["grip_" + label]
        center = rig.matrix_world @ contacts[label]["palm"]
        start, end = _endpoints(grip)
        axis = (end - start).normalized()
        result[label + "_actual_handle_axis_distance_m"] = ((center - start).cross(axis)).length
        target_axis = (rig.matrix_world.to_3x3() @ contacts[label]["handle_axis"]).normalized()
        result[label + "_actual_handle_axis_edge_error_m"] = .06 * axis.cross(target_axis).length
    return result


def _sole_support(props, label, whole_foot):
    _, _, _, shoes, V, _, _ = _api()
    platform = props["pedal_" + label]
    dims = json.loads(platform["cardio_platform_json"])
    inverse = platform.matrix_world.inverted()
    all_points = shoes.sole_vertices(props, label)
    values = [inverse @ point for point in all_points]
    domain = shoes.sole_vertices(props, label) if whole_foot else shoes.sole_vertices(props, label, "forefoot")
    selected = [inverse @ point for point in domain]
    inside = [point.z - dims["height"] / 2 for point in values if abs(point.x) <= dims["width"] / 2 and abs(point.y) <= dims["length"] / 2]
    result = {"actual_sole_vertex_count": len(values), "platform_top_surface_gap_m": min(point.z - dims["height"] / 2 for point in selected),
        "actual_sole_min_inside_platform_height_m": min(inside) if inside else None,
        "selected_sole_domain_edge_margin_m": min(min(dims["width"] / 2 - abs(point.x), dims["length"] / 2 - abs(point.y)) for point in selected)}
    if whole_foot:
        for kind in ("heel", "forefoot"):
            result[kind + "_top_gap_m"] = min((inverse @ point).z - dims["height"] / 2 for point in shoes.sole_vertices(props, label, kind))
    return result


def surface_audit(exercise_id, props, rig, body, frame, amount, cache):
    _, _, m, shoes, V, _, _ = _api()
    from remaining_strength_extra_equipment import _skin, _line_clearance, _pad_sample
    skin = _skin(body, cache)
    sample = {"frame": frame, "amount": amount, "soles": {}, "rods": [],
              **shoes.attachment_audit(props, rig), **shoes.foot_enclosure_audit(props, body),
              "scope": "Actual evaluated sole vertices, finite platforms, full actual rod axes/radii and skin domains; no pressure or trainer approval"}
    for label in ("l", "r"):
        sample["soles"][label] = _sole_support(props, label, exercise_id != "stationary_bike")
    for key, obj in props.items():
        if obj.get("cardio_radius_m"):
            segment = _line_clearance(*_endpoints(obj), obj["cardio_radius_m"], skin)
            segment["name"] = key
            sample["rods"].append(segment)
    from mathutils.bvhtree import BVHTree
    bpy = _api()[0]
    deps = bpy.context.evaluated_depsgraph_get()
    sample["actual_apparatus_meshes"] = []
    for key, obj in props.items():
        if obj.type != "MESH" or key.startswith(("shoe_", "sole_", "lace_")):
            continue
        evaluated = obj.evaluated_get(deps)
        mesh = evaluated.to_mesh()
        try:
            points = [evaluated.matrix_world @ vertex.co for vertex in mesh.vertices]
            shoes._finite_points(points)
            bvh = BVHTree.FromPolygons(points, [tuple(face.vertices) for face in mesh.polygons])
            sample["actual_apparatus_meshes"].append({"name": key, "actual_vertex_count": len(points),
                "nonhand_skin_triangle_overlap_count": len(bvh.overlap(skin[2])), "actual_min_floor_m": min(point.z for point in points)})
        finally:
            evaluated.to_mesh_clear()
    if "pad_seat" in props:
        from remaining_strength_extra_equipment import _domain_indices
        pad = props["pad_seat"]
        sample["saddle"] = _pad_sample(pad, skin)
        domain = _domain_indices(skin, json.loads(pad["support_domain_json"]))
        axis = V(pad["support_long_axis"])
        within = [index for index in domain if abs((skin[0][index] - pad.location).x) <= pad["support_width_m"] / 2 - .007 and abs((skin[0][index] - pad.location).dot(axis)) <= pad["support_length_m"] / 2 - .007]
        sample["saddle"].update({"actual_support_domain_vertex_count": len(domain), "actual_support_vertices_within_selected_pad_count": len(within), "actual_support_body_mesh_vertex_count": len(skin[0])})
    if exercise_id == "elliptical":
        sample["rigid_link_lengths_m"] = {key: (_endpoints(props[key])[1] - _endpoints(props[key])[0]).length for key in props if key.startswith(("elliptical_crank_", "elliptical_coupler_", "elliptical_rocker_"))}
    sample["rig_scale"] = rig.scale.x
    if exercise_id == "rowing_machine":
        sample["rowing_sequence"] = list(m.rowing_sequence(amount))
        sample["model_hip_center_world_z_m"] = (rig.matrix_world @ ((rig.pose.bones["thigh_l"].head + rig.pose.bones["thigh_r"].head) / 2)).z
        sample["horizontal_seat_height_drift_m"] = abs(props["pad_seat"].location.z - json.loads(props["pad_seat"]["rest_center_world_json"])[2])
    return sample


def validate_surfaces(exercise_id, samples):
    failures = []
    if exercise_id not in ("stationary_bike", "elliptical", "rowing_machine") or not samples:
        failures.append("Missing exact cardio surface evidence")
    frames = [row.get("frame") for row in samples]
    if len(samples) != 96 or set(frames) != set(range(1, 97)) or any(not isinstance(frame, int) or isinstance(frame, bool) for frame in frames):
        failures.append("Complete actual 96 distinct frame coverage required")
    def finite(value):
        return isinstance(value, (int, float)) and not isinstance(value, bool) and math.isfinite(value)
    expected_rods = {"base_-1", "base_1", "base_cross_-0.85", "base_cross_1.05"}
    if exercise_id == "stationary_bike":
        expected_rods.update(("bike_crank_axle", "bike_main_frame", "bike_front_frame", "bike_bar_support", "bike_handle_cross", "bike_handle_terminal", "seat_support"))
        expected_rods.update(prefix + label for prefix in ("grip_", "bike_crank_", "bike_pedal_axle_") for label in ("l", "r"))
    elif exercise_id == "elliptical":
        expected_rods.update(("elliptical_rear_axle", "elliptical_front_cross"))
        expected_rods.update(prefix + label for prefix in ("elliptical_rear_mount_", "elliptical_front_mount_", "elliptical_front_axle_", "elliptical_crank_", "elliptical_coupler_", "elliptical_rocker_", "elliptical_handle_cross_", "grip_") for label in ("l", "r"))
    elif exercise_id == "rowing_machine":
        expected_rods.update(("rower_rail", "rower_rail_rear_leg", "rower_front_leg", "grip_handle", "rower_chain", "rower_chain_guide_frame", "seat_support", "rower_footplate_support_l", "rower_footplate_support_r"))
    if exercise_id in ("stationary_bike", "rowing_machine"):
        expected_rods.update("strap_" + label + "_anchor_" + str(side) for label in ("l", "r") for side in (-1, 1))
    expected_meshes = expected_rods | {"pedal_l", "pedal_r"}
    if exercise_id in ("stationary_bike", "rowing_machine"):
        expected_meshes.update(("pad_seat", "strap_l", "strap_r", "housing"))
    invariant_keys = [label + suffix for label in ("l", "r") for suffix in ("_actual_enclosure_skin_vertex_count", "_actual_enclosure_body_mesh_vertex_count")]
    for key in invariant_keys:
        values = [sample.get(key) for sample in samples]
        if values and any(value != values[0] for value in values):
            failures.append("Actual unchanged skin/body topology count must agree across all frames")
    for label in ("l", "r"):
        values = [sample.get("soles", {}).get(label, {}).get("actual_sole_vertex_count") for sample in samples]
        if values and any(value != values[0] for value in values):
            failures.append("Actual unchanged sole topology count must agree across all frames")
    if exercise_id in ("stationary_bike", "rowing_machine"):
        for key in ("actual_support_domain_vertex_count", "actual_support_body_mesh_vertex_count"):
            values = [sample.get("saddle", {}).get(key) for sample in samples]
            if values and any(value != values[0] for value in values):
                failures.append("Actual unchanged saddle skin-domain/body topology count must agree across all frames")
    for sample in samples:
        if not finite(sample.get("amount")) or not 0 <= sample["amount"] <= 1:
            failures.append("Finite actual motion phase missing")
        elif isinstance(sample.get("frame"), int) and not isinstance(sample["frame"], bool) and abs(sample["amount"] - (sample["frame"] - 1) / 95) > .000000001:
            failures.append("Actual frame and authored 24fps phase must agree")
        for name in ("shoe_native_attachment_max_error_m", "l_foot_outside_shoe_max_m", "r_foot_outside_shoe_max_m"):
            if not finite(sample.get(name)) or not 0 <= sample[name] <= .0001:
                failures.append("Actual native shoe fit/attachment fails")
        for label in ("l", "r"):
            count, total = sample.get(label + "_actual_enclosure_skin_vertex_count"), sample.get(label + "_actual_enclosure_body_mesh_vertex_count")
            if not isinstance(count, int) or isinstance(count, bool) or not isinstance(total, int) or isinstance(total, bool) or not 0 < count <= total:
                failures.append("Actual positive skin-domain/body mesh counts required")
        if set(sample.get("soles", {})) != {"l", "r"}:
            failures.append("Both actual sole platform records required")
        for sole in sample.get("soles", {}).values():
            count = sole.get("actual_sole_vertex_count")
            if not isinstance(count, int) or isinstance(count, bool) or count < 30:
                failures.append("Dense actual underside vertices required")
            for name in ("platform_top_surface_gap_m", "actual_sole_min_inside_platform_height_m"):
                if not finite(sole.get(name)) or not -.001 <= sole[name] <= .003:
                    failures.append("Actual sole floats or penetrates finite platform")
            if not finite(sole.get("selected_sole_domain_edge_margin_m")) or sole["selected_sole_domain_edge_margin_m"] < .002:
                failures.append("Supported sole domain falls outside finite pedal")
            if exercise_id != "stationary_bike":
                if any(not finite(sole.get(kind + "_top_gap_m")) or not -.001 <= sole[kind + "_top_gap_m"] <= .003 for kind in ("heel", "forefoot")):
                    failures.append("Whole shoe heel/forefoot support missing")
        rods = sample.get("rods", [])
        if {rod.get("name") for rod in rods} != expected_rods or len({rod.get("name") for rod in rods}) != len(rods):
            failures.append("Complete distinct actual machine rod coverage missing")
        for rod in rods:
            value = rod.get("minimum_nonhand_skin_clearance_m")
            if not finite(value) or value < -.001:
                failures.append("Actual machine rod enters nonhand skin: " + str(rod.get("name")))
            ends = [rod.get("actual_segment_start_world"), rod.get("actual_segment_end_world")]
            valid_points = all(isinstance(point, (list, tuple)) and len(point) == 3 and all(finite(value) for value in point) for point in ends)
            count, radius = rod.get("sample_count"), rod.get("actual_radius_m")
            if not valid_points or not isinstance(count, int) or isinstance(count, bool) or count < 3 or not finite(radius) or radius <= 0 or (valid_points and math.dist(*ends) / (count - 1) > .006001):
                failures.append("Complete actual rod endpoint/radius/density evidence required")
        meshes = sample.get("actual_apparatus_meshes", [])
        if {item.get("name") for item in meshes} != expected_meshes or len({item.get("name") for item in meshes}) != len(meshes):
            failures.append("Actual distinct apparatus mesh coverage missing")
        for mesh in meshes:
            count, overlap = mesh.get("actual_vertex_count"), mesh.get("nonhand_skin_triangle_overlap_count")
            if not isinstance(count, int) or isinstance(count, bool) or count < 8 or not isinstance(overlap, int) or isinstance(overlap, bool) or overlap != 0:
                failures.append("Actual apparatus mesh intersects nonhand skin: " + str(mesh.get("name")))
            if not finite(mesh.get("actual_min_floor_m")) or mesh["actual_min_floor_m"] < -.001:
                failures.append("Actual apparatus mesh enters floor")
        if exercise_id != "elliptical":
            seat = sample.get("saddle", {})
            expected_domain = ["pelvis"] if exercise_id == "stationary_bike" else ["pelvis", "thigh_l", "thigh_r"]
            if seat.get("domain") != expected_domain:
                failures.append("Exact selected actual saddle support domain required")
            counts = [seat.get(key) for key in ("actual_support_domain_vertex_count", "actual_support_vertices_within_selected_pad_count", "actual_support_body_mesh_vertex_count")]
            if any(not isinstance(count, int) or isinstance(count, bool) or count <= 0 for count in counts) or (all(isinstance(count, int) and not isinstance(count, bool) for count in counts) and not counts[1] <= counts[0] <= counts[2]):
                failures.append("Complete actual selected saddle domain/pad/body vertex counts required")
            penetration, inside = seat.get("maximum_skin_penetration_m"), seat.get("skin_vertices_inside_padding")
            if not finite(penetration) or not 0 <= penetration <= .001 or not isinstance(inside, int) or isinstance(inside, bool) or inside < 0 or (finite(penetration) and isinstance(inside, int) and ((inside == 0) != (penetration == 0))):
                failures.append("Finite nonnegative actual saddle penetration/count evidence required")
            if not finite(seat.get("domain_surface_gap_m")) or not -.001 <= seat["domain_surface_gap_m"] <= .004:
                failures.append("Actual horizontal saddle contact missing or penetrating")
        if exercise_id == "elliptical":
            import cardio_extra_motions as m
            links = sample.get("rigid_link_lengths_m", {})
            scale = sample.get("rig_scale")
            expected = {kind + "_" + label: length for kind, length in (("elliptical_crank", m.ELLIPTICAL_RADIUS), ("elliptical_coupler", m.ELLIPTICAL_COUPLER), ("elliptical_rocker", m.ELLIPTICAL_ROCKER + .55)) for label in ("l", "r")}
            if set(links) != set(expected) or not finite(scale) or scale <= 0 or any(not finite(links.get(key)) or abs(links[key] - length * scale) > .00001 for key, length in expected.items()):
                failures.append("Both complete constant-length actual elliptical linkages required")
        if exercise_id == "rowing_machine":
            import cardio_extra_motions as m
            stages = sample.get("rowing_sequence", [])
            amount = sample.get("amount")
            if len(stages) != 3 or any(not finite(value) or not 0 <= value <= 1 for value in stages) or (finite(amount) and 0 <= amount <= 1 and len(stages) == 3 and any(not finite(value) or abs(value - expected) > .00000001 for value, expected in zip(stages, m.rowing_sequence(amount)))):
                failures.append("Exact finite drive/recovery sequence record missing")
            if not finite(sample.get("horizontal_seat_height_drift_m")) or not 0 <= sample["horizontal_seat_height_drift_m"] <= .000001 or not finite(sample.get("model_hip_center_world_z_m")):
                failures.append("Fixed horizontal seat height and disclosed actual hip fit required")
    return {"exercise_id": exercise_id, "sample_count": len(samples), "passed": not failures,
            "failures": sorted(set(failures)), "trainerApproved": False, "humanTrainerApproval": False,
            "scope": "Native geometry/contact draft guard; cadence, chosen fit and execution require trainer review"}
