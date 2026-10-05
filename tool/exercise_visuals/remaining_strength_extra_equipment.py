"""Original EZ bars and fitted supports; actual skinned-surface draft guards.

The EZ bar's every bent shaft segment is checked. Fitted padding is explicit
model support, not simulated pressure, a brand replica or trainer approval.
"""
import json
import math


def _api():
    import bpy
    import equipment
    from mathutils import Matrix, Quaternion, Vector
    return bpy, equipment, Matrix, Quaternion, Vector


def _skin(body, cache=None):
    bpy, _, _, _, _ = _api()
    from mathutils.bvhtree import BVHTree
    deps = bpy.context.evaluated_depsgraph_get()
    evaluated = body.evaluated_get(deps)
    mesh = evaluated.to_mesh(preserve_all_data_layers=True, depsgraph=deps)
    try:
        points = [evaluated.matrix_world @ vertex.co for vertex in mesh.vertices]
        key = (body.as_pointer(), len(mesh.vertices), len(mesh.polygons))
        topology = cache.get(key) if cache is not None else None
        if topology is None:
            hand_indices = {group.index for group in body.vertex_groups if group.name.startswith(("hand_", "thumb_", "index_", "middle_", "ring_", "pinky_"))}
            weights = [sum(g.weight for g in vertex.groups if g.group in hand_indices) for vertex in mesh.vertices]
            faces = [tuple(face.vertices) for face in mesh.polygons]
            hand = [sum(weights[index] for index in face) / len(face) >= .5 for face in faces]
            groups = {group.name: group.index for group in body.vertex_groups}
            memberships = [{g.group: g.weight for g in vertex.groups} for vertex in mesh.vertices]
            topology = (faces, hand, groups, memberships)
            if cache is not None:
                cache[key] = topology
        faces, hand, groups, memberships = topology
        return points, BVHTree.FromPolygons(points, faces, all_triangles=False), BVHTree.FromPolygons(points, [face for face, is_hand in zip(faces, hand) if not is_hand], all_triangles=False), hand, groups, memberships
    finally:
        evaluated.to_mesh_clear()


def _domain_indices(skin, prefixes):
    groups = {index for name, index in skin[4].items() if name.startswith(tuple(prefixes))}
    return [index for index, memberships in enumerate(skin[5]) if sum(memberships.get(group, 0) for group in groups) >= .45]


def _actual_skin(rig):
    bpy = _api()[0]
    body = bpy.data.objects["SetflowAthlete.body"]
    states = [(modifier, modifier.show_viewport) for modifier in body.modifiers]
    try:
        for modifier, _ in states:
            modifier.show_viewport = modifier.show_render
        bpy.context.view_layer.update()
        return _skin(body)
    finally:
        for modifier, state in states:
            modifier.show_viewport = state
        bpy.context.view_layer.update()


def _pad(name, center, long_axis, normal, width, length, domain, skin, parent, thickness=.065):
    _, e, M, _, V = _api()
    center, long_axis, normal = V(center), V(long_axis).normalized(), V(normal).normalized()
    indices = _domain_indices(skin, domain)
    candidates = [skin[0][index] for index in indices if abs((skin[0][index] - center).x) <= width / 2 - .007 and abs((skin[0][index] - center).dot(long_axis)) <= length / 2 - .007]
    if not candidates:
        raise ValueError("No actual skin points under selected support domain: " + name)
    level = min(point.dot(normal) for point in candidates) - .0008
    center += normal * (level - center.dot(normal) - thickness / 2)
    mat = e.material("Remaining fitted charcoal padding", (.047, .047, .047))
    pad = e.cube(name, center, (width, length, thickness), mat)
    pad.rotation_mode = "QUATERNION"
    pad.rotation_quaternion = M((long_axis.cross(normal), long_axis, normal)).transposed().to_quaternion()
    pad.parent = parent
    pad["support_normal"] = list(normal)
    pad["support_long_axis"] = list(long_axis)
    pad["support_width_m"], pad["support_length_m"], pad["support_thickness_m"] = width, length, thickness
    pad["support_domain_json"] = json.dumps(domain)
    pad["support_top_level_m"] = level
    return pad


def _support_frame():
    from remaining_strength_equipment import _root
    return _root("Setflow original fitted support frame")


def _legs_below_pads(props, pads, frame):
    _, e, _, _, V = _api()
    from remaining_strength_equipment import _segment
    steel = e.material("Remaining extra structural steel", (.26, .26, .26), .7)
    for index, pad in enumerate(pads):
        point = pad.location
        lower = V((point.x, point.y, .05))
        _segment("Fitted pad upright " + str(index), lower, point - V((0, 0, .06)), .035, steel, frame)
        foot = e.cube("Fitted pad base " + str(index), lower - V((0, 0, .025)), (.62, .12, .05), steel)
        foot.parent = frame


def _ez(rig, exercise_id, contacts):
    from remaining_strength_equipment import _root, _segment
    from remaining_strength_extra_motions import EZ_CANT_DEG
    _, e, _, _, V = _api()
    scale = rig.scale.x
    grip_x = abs(contacts["l"]["palm"].x) * scale
    inner, outer, shoulder = .065, .225, .36
    rise = math.tan(math.radians(-EZ_CANT_DEG))
    z_inner, z_outer = (grip_x - inner) * rise, (grip_x - outer) * rise
    points = [(-.60, 0, .015), (-shoulder, 0, .015), (-outer, 0, z_outer), (-inner, 0, z_inner),
              (inner, 0, z_inner), (outer, 0, z_outer), (shoulder, 0, .015), (.60, 0, .015)]
    root = _root("Setflow original bent EZ bar " + exercise_id)
    root["ez_points_json"] = json.dumps(points)
    root["ez_grip_x_m"] = grip_x
    steel = e.material("EZ bar brushed steel", (.24, .24, .24), .75)
    rubber = e.material("EZ bar graphite plates", (.042, .042, .042))
    for index, (start, finish) in enumerate(zip(points, points[1:])):
        _segment("EZ actual shaft segment " + str(index), start, finish, .014, steel, root)
    for side in (-1, 1):
        for radius, depth, offset in ((.110, .045, .50), (.035, .035, .548)):
            obj = e.cylinder("EZ loaded plate" if radius > .05 else "EZ collar", radius, depth, rubber if radius > .05 else steel, root, side * offset)
            obj.location.z = .015
    return root


def _supine_support(exercise_id, rig, skin, props, root):
    _, _, _, _, V = _api()
    angle = -105 if exercise_id == "decline_bench" else -90
    rad = math.radians(angle)
    long_axis = V((0, -math.sin(rad), math.cos(rad)))
    normal = V((0, -math.cos(rad), -math.sin(rad)))
    world = rig.matrix_world
    hip = world @ ((rig.pose.bones["thigh_l"].head + rig.pose.bones["thigh_r"].head) / 2)
    shoulders = world @ ((rig.pose.bones["upperarm_l"].head + rig.pose.bones["upperarm_r"].head) / 2)
    head = world @ rig.pose.bones["head"].head
    props["pad_seat"] = _pad("Fitted glute support", hip + long_axis * .06, long_axis, normal, .30, .26, ("pelvis", "thigh_l", "thigh_r"), skin, root)
    props["pad_back"] = _pad("Fitted upper-back support", shoulders - long_axis * .07, long_axis, normal, .27, .41, ("spine_02", "spine_03"), skin, root)
    props["pad_head"] = _pad("Fitted neutral-head bolster", head + long_axis * .06, long_axis, normal, .25, .20, ("head", "neck"), skin, root, .055)
    _legs_below_pads(props, [props["pad_seat"], props["pad_back"]], root)


def _anchor_rollers(rig, props, root, skin, decline=False):
    _, e, _, _, V = _api()
    from remaining_strength_equipment import _segment
    mat = e.material("Anchoring roller charcoal", (.055, .055, .055))
    steel = e.material("Anchoring support steel", (.26, .26, .26), .7)
    normal = V((0, 0, 1)) if decline else V((0, -math.sqrt(.5), math.sqrt(.5)))
    long_axis = V((0, 1, 0)) if decline else V((0, math.sqrt(.5), math.sqrt(.5)))
    for label in ("l", "r"):
        ankle = rig.matrix_world @ rig.pose.bones["foot_" + label].head
        props["pad_foot_" + label] = _pad("Secured foot platform " + label, ankle + V((0, -.075, -.05)), long_axis, normal, .17, .32, ("foot_" + label, "ball_" + label), skin, root, .045)
        direction = V((0, 1, 0)) if decline else V((0, math.sqrt(.5), math.sqrt(.5)))
        low, high = .045, .22
        for _ in range(23):
            distance = (low + high) / 2
            center = ankle + direction * distance
            gap = _line_clearance(center + V((-.095, 0, 0)), center + V((.095, 0, 0)), .055, skin)["minimum_nonhand_skin_clearance_m"]
            if gap < .0008:
                low = distance
            else:
                high = distance
        center = ankle + direction * high
        roller = _segment("Fixed ankle securing roller " + label, center + V((-.095, 0, 0)), center + V((.095, 0, 0)), .055, mat, root)
        roller["actual_contact_radius_m"] = .055
        roller["actual_contact_half_length_m"] = .095
        props["ankle_roller_" + label] = roller
        _segment("Securing roller stem " + label, center + V((0, 0, -.17)), center, .026, steel, root)


def create(exercise_id, rig):
    bpy, e, _, _, V = _api()
    import remaining_strength_extra_motions as m
    if exercise_id not in m.SUPPORTED:
        raise ValueError("No exact remaining extra equipment: " + exercise_id)
    contacts = m.pose(rig, exercise_id, 0)
    props = {}
    if exercise_id in ("preacher_curl", "skull_crusher"):
        props["ez"] = _ez(rig, exercise_id, contacts)
    elif exercise_id in ("decline_bench", "upright_row"):
        props["bar"] = e.barbell()
        props["bar"]["shaft_surface_half_width_m"] = .70
        # The custom hook below inspects all 1.75 m of the actual straight
        # shaft against the same full evaluated body on every native frame.
        props["bar"]["surface_check_shaft"] = False
    elif exercise_id == "chest_supported_row":
        props.update({"l": e.dumbbell("supported left"), "r": e.dumbbell("supported right")})
    elif exercise_id == "overhead_triceps_extension":
        props["r"] = e.dumbbell("single working right")
    if exercise_id in ("overhead_triceps_extension", "upright_row"):
        return props
    skin = _actual_skin(rig)
    root = _support_frame()
    props["support_frame"] = root
    if exercise_id in ("skull_crusher", "decline_bench"):
        _supine_support(exercise_id, rig, skin, props, root)
        if exercise_id == "decline_bench":
            _anchor_rollers(rig, props, root, skin, True)
    elif exercise_id == "preacher_curl":
        rad = math.radians(35)
        axis, normal = V((0, -math.sin(rad), -math.cos(rad))), V((0, -math.cos(rad), math.sin(rad)))
        mid = sum((rig.matrix_world @ ((rig.pose.bones["upperarm_" + label].head + rig.pose.bones["upperarm_" + label].tail) / 2) for label in ("l", "r")), V()) / 2
        # Split arm pads leave clearance for the enlarged thorax. The
        # separate chest face supports the sternum without embedding one
        # wide cushion through the sculpted pectorals.
        for side, label in ((1, "l"), (-1, "r")):
            center = mid + axis * .045
            center.x = side * .290
            props["pad_upperarm_" + label] = _pad("Preacher supported outer upper arm " + label, center, axis, normal, .09, .21, ("upperarm_" + label,), skin, root)
        chest = rig.matrix_world @ rig.pose.bones["spine_03"].head
        props["pad_chest"] = _pad("Preacher fitted chest face", chest, (0, 0, 1), (0, 1, 0), .17, .21, ("spine_02", "spine_03"), skin, root, .045)
        hip = rig.matrix_world @ ((rig.pose.bones["thigh_l"].head + rig.pose.bones["thigh_r"].head) / 2)
        props["pad_seat"] = _pad("Preacher seated glute support", hip + V((0, .08, 0)), (0, 1, 0), (0, 0, 1), .40, .24, ("pelvis", "thigh_l", "thigh_r"), skin, root)
        _legs_below_pads(props, [props["pad_upperarm_l"], props["pad_upperarm_r"], props["pad_seat"]], root)
    elif exercise_id == "chest_supported_row":
        rad = math.pi / 4
        axis, normal = V((0, -math.sin(rad), math.cos(rad))), V((0, math.cos(rad), math.sin(rad)))
        hip = rig.matrix_world @ ((rig.pose.bones["thigh_l"].head + rig.pose.bones["thigh_r"].head) / 2)
        props["pad_chest"] = _pad("45-degree prone chest support", hip + axis * .27, axis, normal, .27, .67, ("spine_01", "spine_02", "spine_03"), skin, root)
        _legs_below_pads(props, [props["pad_chest"]], root)
    elif exercise_id == "back_extension":
        axis, normal = V((0, math.sqrt(.5), -math.sqrt(.5))), V((0, math.sqrt(.5), math.sqrt(.5)))
        for label in ("l", "r"):
            thigh = rig.pose.bones["thigh_" + label]
            mid = rig.matrix_world @ ((thigh.head + thigh.tail) / 2)
            props["pad_thigh_" + label] = _pad("45-degree upper thigh pad " + label, mid + axis * .055, axis, normal, .19, .20, ("thigh_" + label,), skin, root)
            knee = rig.matrix_world @ rig.pose.bones["calf_" + label].head
            props["pad_knee_" + label] = _pad("45-degree knee support " + label, knee + axis * .015, axis, normal, .17, .13, ("thigh_" + label, "calf_" + label), skin, root, .055)
        _anchor_rollers(rig, props, root, skin)
        _legs_below_pads(props, [props["pad_thigh_l"], props["pad_thigh_r"]], root)
    return props


def apply(props, contacts, rig, frame=None):
    bpy, e, _, Q, V = _api()
    e.apply(props, contacts, rig, frame)
    if "ez" in props:
        ez = props["ez"]
        ez.location = rig.matrix_world @ ((contacts["l"]["palm"] + contacts["r"]["palm"]) / 2)
        ez.rotation_mode = "QUATERNION"
        ez.rotation_quaternion = rig.matrix_world.to_quaternion() @ Q((1, 0, 0), -contacts["ez_angle"])
        if frame is not None:
            ez.keyframe_insert("location", frame=frame)
            ez.keyframe_insert("rotation_quaternion", frame=frame)
    bpy.context.view_layer.update()


def contacts_audit(props, contacts, rig):
    _, e, _, _, V = _api()
    result = e.contacts_audit(props, contacts, rig)
    if "bar" in props:
        axis = (props["bar"].matrix_world.to_3x3() @ V((1, 0, 0))).normalized()
        result["custom_straight_bar_actual_axis_edge_error_m"] = max(.06 * axis.cross((rig.matrix_world.to_3x3() @ contacts[label]["handle_axis"]).normalized()).length for label in ("l", "r"))
    if "ez" in props:
        from remaining_strength_extra_motions import EZ_CANT_DEG
        ez = props["ez"]
        for side, label in ((1, "l"), (-1, "r")):
            point = ez.matrix_world @ V((side * ez["ez_grip_x_m"], 0, 0))
            result["ez_" + label + "_actual_palm_error_m"] = (point - rig.matrix_world @ contacts[label]["palm"]).length
            axis = (ez.matrix_world.to_3x3() @ V((math.cos(math.radians(EZ_CANT_DEG)), 0, side * math.sin(math.radians(EZ_CANT_DEG))))).normalized()
            hand_axis = (rig.matrix_world.to_3x3() @ contacts[label]["handle_axis"]).normalized()
            result["ez_" + label + "_actual_axis_edge_error_m"] = .06 * axis.cross(hand_axis).length
    return result


def _line_clearance(start, finish, radius, skin):
    import technique as t
    _, _, _, _, V = _api()
    start, finish = V(start), V(finish)
    count = max(3, math.ceil((finish - start).length / .006) + 1)
    minimum = math.inf
    for index in range(count):
        point = start + (finish - start) * index / (count - 1)
        hit, _, _, distance = skin[2].find_nearest(point)
        full_hit, normal, face, full_distance = skin[1].find_nearest(point)
        if hit is None or full_hit is None:
            raise ValueError("Actual skin mesh missing")
        signed = full_distance if (point - full_hit).dot(normal) >= 0 else -full_distance
        minimum = min(minimum, t.shaft_clearance(distance, signed, skin[3][face], radius))
    return {"sample_count": count, "actual_segment_start_world": list(start), "actual_segment_end_world": list(finish),
            "actual_radius_m": radius, "minimum_nonhand_skin_clearance_m": minimum}


def _pad_sample(pad, skin):
    _, _, _, _, V = _api()
    normal, axis = V(pad["support_normal"]), V(pad["support_long_axis"])
    level = pad["support_top_level_m"]
    domain = _domain_indices(skin, json.loads(pad["support_domain_json"]))
    width, length, thickness = pad["support_width_m"], pad["support_length_m"], pad["support_thickness_m"]
    def within(point):
        return abs((point - pad.location).x) <= width / 2 - .007 and abs((point - pad.location).dot(axis)) <= length / 2 - .007
    selected = [skin[0][index].dot(normal) - level for index in domain if within(skin[0][index])]
    inside = [point.dot(normal) - level for point in skin[0] if within(point) and -thickness + .006 < point.dot(normal) - level < -.001]
    return {"name": pad.name, "domain": json.loads(pad["support_domain_json"]),
            "domain_surface_gap_m": min(selected) if selected else None,
            "skin_vertices_inside_padding": len(inside), "maximum_skin_penetration_m": -min(inside) if inside else 0.,
            "scope": "Actual finite pad interior and selected skinned support domain; no pressure simulation"}


def surface_audit(exercise_id, props, rig, body, frame, amount, cache):
    _, _, _, _, V = _api()
    skin = _skin(body, cache)
    result = {"frame": frame, "amount": amount, "padding": [], "bent_shaft_segments": [],
              "scope": "Actual evaluated athlete skin, every real EZ shaft segment and fitted finite pads; trainer review pending"}
    if "ez" in props:
        points = json.loads(props["ez"]["ez_points_json"])
        result["bent_shaft_segments"] = [_line_clearance(props["ez"].matrix_world @ V(start), props["ez"].matrix_world @ V(finish), .014, skin)
                                           for start, finish in zip(points, points[1:])]
    if "bar" in props:
        center = props["bar"].matrix_world.translation
        axis = (props["bar"].matrix_world.to_3x3() @ V((1, 0, 0))).normalized()
        result["actual_complete_straight_shaft"] = _line_clearance(center - axis * .875, center + axis * .875, .016, skin)
        if exercise_id == "decline_bench":
            result["central_torso_endpoint_gap_m"] = _line_clearance(center - axis * .12, center + axis * .12, .016, skin)["minimum_nonhand_skin_clearance_m"]
    for key, pad in props.items():
        if key.startswith("pad_"):
            result["padding"].append(_pad_sample(pad, skin))
        elif key.startswith("ankle_roller_"):
            center = pad.matrix_world.translation
            axis = (pad.matrix_world.to_3x3() @ V((0, 0, 1))).normalized()
            result.setdefault("ankle_rollers", []).append(_line_clearance(center - axis * .095, center + axis * .095, .055, skin))
    # Plates/rollers are separately visible, not implied by a shaft-only test.
    result["moving_weight_mesh_min_nonhand_clearance_m"] = _weight_clearance(props, skin)
    return result


def _weight_clearance(props, skin):
    minimum = None
    for root in (props[key] for key in ("ez", "l", "r", "bar") if key in props):
        for obj in root.children_recursive:
            if obj.type != "MESH" or not any(word in obj.name.lower() for word in ("weight", "plate", "cap", "collar")):
                continue
            for vertex in obj.data.vertices:
                point = obj.matrix_world @ vertex.co
                hit, _, _, distance = skin[2].find_nearest(point)
                full_hit, normal, face, full_distance = skin[1].find_nearest(point)
                if hit is None or full_hit is None:
                    raise ValueError("Body surface unavailable")
                import technique as t
                full_signed = full_distance if (point - full_hit).dot(normal) >= 0 else -full_distance
                signed = t.shaft_clearance(distance, full_signed, skin[3][face], 0)
                minimum = signed if minimum is None else min(minimum, signed)
    return minimum


def validate_surfaces(exercise_id, samples):
    failures = []
    required_pads = {"preacher_curl": 4, "skull_crusher": 3, "chest_supported_row": 1,
                     "back_extension": 6, "decline_bench": 5,
                     "overhead_triceps_extension": 0, "upright_row": 0}
    if exercise_id not in required_pads:
        failures.append("Unknown exact remaining strength equipment ID")
    if not samples:
        failures.append("Missing actual equipment surface samples")
    frames = [row.get("frame") for row in samples]
    if any(not isinstance(frame, int) or frame < 1 for frame in frames) or len(set(frames)) != len(frames):
        failures.append("Actual surface frame numbers missing or duplicated")
    def finite(value):
        return isinstance(value, (int, float)) and not isinstance(value, bool) and math.isfinite(value)
    def clearance(segment):
        value = segment.get("minimum_nonhand_skin_clearance_m")
        return finite(value) and value >= -.001
    def line_is_complete(segment, radius, expected_length=None):
        points = [segment.get(key) for key in ("actual_segment_start_world", "actual_segment_end_world")]
        if not all(isinstance(point, (list, tuple)) and len(point) == 3 and all(finite(value) for value in point) for point in points):
            return False
        length = math.dist(*points)
        count, measured_radius = segment.get("sample_count"), segment.get("actual_radius_m")
        return (length > 0 and isinstance(count, int) and count >= 3 and length / (count - 1) <= .006001
                and finite(measured_radius) and abs(measured_radius - radius) <= .00001
                and (expected_length is None or abs(length - expected_length) <= .001))
    for row in samples:
        amount = row.get("amount")
        if not finite(amount) or not 0 <= amount <= 1:
            failures.append("Finite actual motion amount missing")
        pads = row.get("padding", [])
        if len(pads) != required_pads.get(exercise_id, -1) or len({pad.get("name") for pad in pads}) != len(pads):
            failures.append("Complete distinct required support pads missing")
        rollers = row.get("ankle_rollers", [])
        if len(rollers) != (2 if exercise_id in ("decline_bench", "back_extension") else 0):
            failures.append("Complete required ankle anchoring rollers missing")
        if exercise_id in ("preacher_curl", "skull_crusher") and len(row.get("bent_shaft_segments", [])) != 7:
            failures.append("Complete actual EZ shaft segment coverage missing")
        segments = row.get("bent_shaft_segments", [])
        if any(not clearance(segment) or not line_is_complete(segment, .014) for segment in segments):
            failures.append("Actual EZ shaft enters nonhand skin")
        if segments and any(math.dist(previous["actual_segment_end_world"], following["actual_segment_start_world"]) > .000001
                            for previous, following in zip(segments, segments[1:])
                            if all(previous.get(key) and following.get(key) for key in ("actual_segment_start_world", "actual_segment_end_world"))):
            failures.append("Actual EZ shaft segments are not contiguous")
        if exercise_id in ("decline_bench", "upright_row"):
            shaft = row.get("actual_complete_straight_shaft")
            if not shaft or not clearance(shaft) or not line_is_complete(shaft, .016, 1.75):
                failures.append("Complete actual straight shaft missing or intersects nonhand skin")
        if exercise_id == "decline_bench" and finite(amount) and amount > .999 and not -.001 <= row.get("central_torso_endpoint_gap_m", math.inf) <= .0035:
            failures.append("Decline source chest endpoint is not approached by actual central shaft")
        if any(not finite(pad.get("maximum_skin_penetration_m")) or pad["maximum_skin_penetration_m"] > .001 for pad in pads):
            failures.append("Actual skinned athlete enters finite support padding")
        if any(not pad.get("domain") or not finite(pad.get("domain_surface_gap_m")) or not -.001 <= pad["domain_surface_gap_m"] <= .004 for pad in pads):
            failures.append("Required selected support domain floats or penetrates padding")
        if any(not clearance(roller) or roller["minimum_nonhand_skin_clearance_m"] > .004 or not line_is_complete(roller, .055, .19) for roller in rollers):
            failures.append("Required ankle anchoring roller floats or penetrates actual skin")
        weight = row.get("moving_weight_mesh_min_nonhand_clearance_m")
        if exercise_id != "back_extension" and (not finite(weight) or weight < -.001):
            failures.append("Actual loaded plate/weight surface missing or enters nonhand skin")
    return {"exercise_id": exercise_id, "sample_count": len(samples), "passed": not failures,
            "failures": sorted(set(failures)), "trainerApproved": False, "humanTrainerApproval": False,
            "scope": "Geometry draft guards only; wrists, equipment contact, source scope and loaded technique require human review"}
