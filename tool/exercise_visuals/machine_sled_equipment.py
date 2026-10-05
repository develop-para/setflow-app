"""Original seated calf/sled hardware with actual evaluated surface guards."""
import math


def _skin(rig, cache=None, enable=False):
    import bpy
    import numpy as np
    body = bpy.data.objects["SetflowAthlete.body"]
    states = [(modifier, modifier.show_viewport) for modifier in body.modifiers]
    if enable:
        for modifier, _ in states:
            modifier.show_viewport = True
        bpy.context.view_layer.update()
    deps = bpy.context.evaluated_depsgraph_get()
    evaluated = body.evaluated_get(deps)
    mesh = evaluated.to_mesh(preserve_all_data_layers=True, depsgraph=deps)
    try:
        coordinates = np.empty(len(mesh.vertices) * 3, dtype=np.float32)
        mesh.vertices.foreach_get("co", coordinates)
        matrix = np.asarray(rig.matrix_world.inverted() @ evaluated.matrix_world)
        points = coordinates.reshape(-1, 3) @ matrix[:3, :3].T + matrix[:3, 3]
        key = (body.as_pointer(), len(mesh.vertices))
        groups = (cache or {}).get(key)
        if groups is None:
            groups = {}
            names = {"chest": ("spine_02", "spine_03"), "torso": ("pelvis", "spine_01", "spine_02", "spine_03"), "head": ("head",),
                     "knees": ("thigh_l", "thigh_r", "calf_l", "calf_r")}
            for label in ("l", "r"):
                names["hand_" + label] = tuple(g.name for g in body.vertex_groups if g.name.endswith("_" + label) and g.name.startswith(("hand_", "thumb_", "index_", "middle_", "ring_", "pinky_")))
                names["foot_" + label] = ("foot_" + label, "ball_" + label)
                names["thigh_" + label] = ("thigh_" + label,)
            for name, selected in names.items():
                indices = {g.index for g in body.vertex_groups if g.name in selected}
                groups[name] = np.asarray([v.index for v in mesh.vertices if sum(g.weight for g in v.groups if g.group in indices) >= .5], dtype=np.int32)
            if cache is not None:
                cache[key] = groups
        return points, groups
    finally:
        evaluated.to_mesh_clear()
        if enable:
            for modifier, state in states:
                modifier.show_viewport = state
            bpy.context.view_layer.update()


def _calf_frame(rig):
    from mathutils import Matrix, Vector
    thigh = rig.pose.bones["thigh_l"]
    y = (thigh.head - thigh.tail).normalized()
    x = Vector((1, 0, 0))
    x = (x - y * x.dot(y)).normalized()
    z = x.cross(y).normalized()
    return Matrix((x, y, z)).transposed().to_quaternion()


def _create_calf(rig):
    import bpy
    import numpy as np
    from mathutils import Vector
    import equipment as e
    import machine_sled_motions as m
    contacts = m.pose(rig, "seated_calf_raise", 0)
    points, groups = _skin(rig, enable=True)
    # Rigid plantar forefoot samples choose the rolling pressure point. This
    # is actual evaluated mesh calibration, not a metatarsal-bone floor proxy.
    for label in ("l", "r"):
        foot = points[groups["foot_" + label]]
        ankle = rig.pose.bones["foot_" + label].head
        offsets = foot - np.asarray(ankle)
        selected = (offsets[:, 1] > -.15) & (offsets[:, 1] < -.11) & (offsets[:, 2] < -.055)
        if not np.any(selected):
            raise ValueError("Calf raise has no actual plantar forefoot sample")
        rig["calf_forefoot_offsets_" + label] = offsets[selected].ravel().tolist()
    contacts = m.pose(rig, "seated_calf_raise", 0)
    points, groups = _skin(rig, enable=True)
    m.pose(rig, "seated_calf_raise", 1)
    peak_points, _ = _skin(rig, enable=True)
    peak_rotation = _calf_frame(rig)
    m.pose(rig, "seated_calf_raise", 0)
    rotation = _calf_frame(rig)
    root = bpy.data.objects.new("Setflow original seated calf machine", None)
    bpy.context.scene.collection.objects.link(root)
    root.matrix_world = rig.matrix_world.copy()
    root["exercise_id"] = "seated_calf_raise"
    props = {"fixed_machine": root}
    steel = e.material("Extra machine steel", (.27, .27, .27), .70)
    padding = e.material("Extra machine padding", (.048, .048, .048))
    rubber = e.material("Extra machine rubber", (.09, .09, .09))
    def cube(name, loc, size, mat=steel, parent=root, support=None, sign=1):
        obj = e.cube(name, loc, size, mat)
        obj.parent, obj.location = parent, loc
        if support:
            # Contact samples are >=3 mm inside each footprint, beyond this
            # 2 mm edge bevel, so their planar face is the actual mesh face.
            for modifier in obj.modifiers:
                if modifier.type == "BEVEL":
                    modifier.width = .002
            obj["support_family"], obj["face_axis"], obj["face_sign"] = support, 2, sign
        elif mat == steel:
            obj["hard_part"] = True
        return obj
    for side in (-1, 1):
        cube("Calf machine floor runner", (side * .45, -.15, .03), (.10, 1.05, .06))
        cube("Calf lever pivot upright", (side * .45, .08, .31), (.07, .07, .56))
    cube("Calf base crossmember", (0, .32, .03), (.98, .08, .06))
    for index in range(3):
        y = .07 + .06 * index
        minima = []
        for data in (points, peak_points):
            near = (np.abs(data[:, 0]) < .177) & (np.abs(data[:, 1] - y) < .028) & (data[:, 2] > .39)
            if np.any(near):
                minima.append(float(data[near, 2].min()))
        if minima:
            top = min(minima) - .001
            cube("Calf fitted seat " + str(index), (0, y, top - .035), (.36, .06, .07), padding, support="seat")
    cube("Calf seat upright", (0, .12, .235), (.07, .07, .47))
    cube("Calf forefoot platform", (0, -.475, .1025), (.38, .03, .035), rubber, support="forefeet")
    cube("Calf forefoot platform upright", (0, -.49, .04), (.075, .075, .08))
    lever = bpy.data.objects.new("Calf rigid thigh-pad lever", None)
    bpy.context.scene.collection.objects.link(lever)
    lever.parent = root
    props["calf_lever"] = lever
    hip = Vector((0, .08, .60))
    for side, label in ((1, "l"), (-1, "r")):
        center_y = -.80 * rig.data.bones["thigh_" + label].length
        maximum = []
        for data, q in ((points, rotation), (peak_points, peak_rotation)):
            local = (data - np.asarray(hip)) @ np.asarray(q.to_matrix())
            near = (np.abs(local[:, 0] - side * .105) < .065) & (np.abs(local[:, 1] - center_y) < .047)
            if not np.any(near):
                raise ValueError("Calf distal-thigh pad has no actual skin domain")
            maximum.append(float(local[near, 2].max()))
        bottom = max(maximum) + .001
        pad = cube("Calf padded distal thigh " + label, (side * .105, center_y, bottom + .03), (.14, .10, .06), padding, lever, "thighs", -1)
        pad["support_side"] = label
        cube("Calf upper cross lever " + label, (side * .275, center_y, bottom + .08), (.45, .055, .045), parent=lever)
        cube("Calf rigid side lever " + label, (side * .45, center_y / 2, bottom + .08), (.045, abs(center_y), .045), parent=lever)
        cube("Calf rear pivot link " + label, (side * .45, 0, (bottom + .08) / 2), (.045, .045, bottom + .08), parent=lever)
        pivot = e.cylinder("Calf actual transverse pivot " + label, .027, .085, steel, lever, side * .45)
        pivot.location = (side * .45, 0, 0)
        holder = e.cylinder("Calf weight horn " + label, .018, .22, steel, lever, side * .53)
        holder.location = (side * .53, center_y, bottom + .08)
        plate = e.cylinder("Calf original loaded plate " + label, .12, .06, rubber, lever, side * .54)
        plate.location = (side * .54, center_y, bottom + .08)
        handle = bpy.data.objects.new("Calf fixed side grip " + label, None)
        bpy.context.scene.collection.objects.link(handle)
        e.cylinder("Calf actual hand grip " + label, .017, .14, padding, handle)
        props[label] = handle
        cube("Calf fixed grip support " + label, (side * .39, .0, .60), (.13, .045, .045))
        cube("Calf fixed grip support upright " + label, (side * .45, .0, .32), (.045, .045, .60))
    apply(props, contacts, rig)
    return props


def _apply_calf(props, contacts, rig):
    from mathutils import Vector
    lever = props["calf_lever"]
    lever.location = (0, .08, .60)
    lever.rotation_mode = "QUATERNION"
    lever.rotation_quaternion = _calf_frame(rig)
    for label in ("l", "r"):
        props[label].location = rig.matrix_world @ contacts[label]["palm"]
        props[label].rotation_mode = "QUATERNION"
        axis = (rig.matrix_world.to_3x3() @ contacts[label]["handle_axis"]).normalized()
        props[label].rotation_quaternion = Vector((1, 0, 0)).rotation_difference(axis)

def create(exercise_id, rig):
    if exercise_id == "seated_calf_raise":
        return _create_calf(rig)
    if exercise_id in ("legpress", "hack_squat"):
        return _create_sled(exercise_id, rig)
    raise ValueError("No authored exact sled apparatus: " + exercise_id)


def apply(props, contacts, rig, frame=None):
    import bpy
    if props["fixed_machine"]["exercise_id"] == "seated_calf_raise":
        _apply_calf(props, contacts, rig)
    else:
        _apply_sled(props, contacts, rig)
    if frame is not None:
        for obj in props.values():
            for channel in ("location", "scale", "rotation_quaternion" if obj.rotation_mode == "QUATERNION" else "rotation_euler"):
                obj.keyframe_insert(channel, frame=frame)
    bpy.context.view_layer.update()


def contacts_audit(props, contacts, rig):
    import equipment
    from mathutils import Vector
    result = equipment.contacts_audit(props, contacts, rig)
    if props["fixed_machine"]["exercise_id"] != "seated_calf_raise":
        return _sled_contacts(props, contacts, rig, result)
    for label in ("l", "r"):
        point = contacts["forefoot_" + label]
        result["calf_" + label + "_plantar_contact_height_error_m"] = abs(point.z - .121) * rig.scale.x
        result["calf_" + label + "_plantar_contact_progress_error_m"] = abs(point.y + .49) * rig.scale.x
    result["calf_carriage_pivot_error_m"] = (props["calf_lever"].location - Vector((0, .08, .60))).length * rig.scale.x
    return result


def surface_audit(exercise_id, props, rig, body, frame, amount, cache):
    import numpy as np
    points, groups = _skin(rig, cache)
    root = props["fixed_machine"]
    report = {"frame": frame, "amount": amount, "body_floor_min_m": float(points[:, 2].min()) * rig.scale.x}
    families = {}
    hands = np.concatenate((groups["hand_l"], groups["hand_r"]))
    nonhand = np.ones(len(points), dtype=bool)
    nonhand[hands] = False
    hard_count = 0
    for obj in root.children_recursive:
        if obj.type != "MESH" or not (obj.get("support_family") or obj.get("hard_part")):
            continue
        matrix = np.asarray(obj.matrix_world.inverted() @ rig.matrix_world)
        local = points @ matrix[:3, :3].T + matrix[:3, 3]
        bounds = np.asarray(obj.bound_box)
        low, high = bounds.min(axis=0), bounds.max(axis=0)
        if obj.get("hard_part"):
            inside = np.all((local > low + .0015) & (local < high - .0015), axis=1) & nonhand
            hard_count += int(np.count_nonzero(inside))
            continue
        axis, sign = obj["face_axis"], obj["face_sign"]
        others = [i for i in range(3) if i != axis]
        within = np.all((local[:, others] > low[others] + .003) & (local[:, others] < high[others] - .003), axis=1)
        within &= local[:, axis] > low[axis] if sign == 1 else local[:, axis] < high[axis]
        if not np.any(within):
            continue
        face = high[axis] if sign == 1 else low[axis]
        gap = float(((local[within, axis] - face) * sign).min()) * rig.scale.x
        report[obj.name + "_penetration_gap_m"] = gap
        families.setdefault(obj["support_family"], []).append(gap)
        if obj.get("support_side"):
            families.setdefault("thigh_" + obj["support_side"], []).append(gap)
    report["nonhand_skin_inside_hard_frame_vertices"] = hard_count
    for family, values in families.items():
        report[family + "_support_gap_m"] = min(values)
    if exercise_id in ("legpress", "hack_squat"):
        _foot_surface_metrics(report, props, rig, points, groups)
    else:
        for label in ("l", "r"):
            data = points[groups["foot_" + label]]
            near = (np.abs(data[:, 0]) < .187) & (data[:, 1] > -.487) & (data[:, 1] < -.463)
            if not np.any(near):
                raise ValueError("Calf raise lacks actual " + label + " forefoot platform contact")
            report["forefoot_" + label + "_support_gap_m"] = float(data[near, 2].min() - .12) * rig.scale.x
    return report


def validate_surfaces(exercise_id, samples):
    if not samples:
        return {"passed": False, "failures": ["Missing extra machine actual surfaces"]}
    required = ["body_floor_min_m", "nonhand_skin_inside_hard_frame_vertices"]
    required += (["seat_support_gap_m", "thighs_support_gap_m", "forefeet_support_gap_m", "thigh_l_support_gap_m", "thigh_r_support_gap_m", "forefoot_l_support_gap_m", "forefoot_r_support_gap_m"] if exercise_id == "seated_calf_raise"
                 else ["back_support_gap_m", "feet_support_gap_m", "heel_l_support_gap_m", "heel_r_support_gap_m", "forefoot_l_support_gap_m", "forefoot_r_support_gap_m"])
    if exercise_id == "legpress":
        required.append("seat_support_gap_m")
    if exercise_id == "hack_squat":
        required.append("shoulders_support_gap_m")
    failures, metrics = [], {}
    if any(any(name not in row for name in required) for row in samples):
        return {"passed": False, "failures": ["Missing actual extra machine contacts"]}
    if any(not isinstance(value, (int, float)) or not math.isfinite(value) for row in samples for value in row.values()):
        return {"passed": False, "failures": ["Nonfinite actual extra machine surfaces"]}
    for name in samples[0]:
        if name in ("frame", "amount"):
            continue
        values = [row[name] for row in samples if name in row]
        metrics[name + "_min"], metrics[name + "_max"] = min(values), max(values)
        if name.endswith("vertices") and max(values):
            failures.append(name + " intersects real skin")
        if name.endswith("gap_m") and min(values) < -.001:
            failures.append(name + " penetrates skin by more than 1 mm")
        if name.endswith("support_gap_m") and max(values) > .004:
            failures.append(name + " misses support by more than 4 mm")
    if min(row["body_floor_min_m"] for row in samples) < -.001:
        failures.append("Real skin penetrates floor")
    return {"passed": not failures, "failures": failures, "metrics": metrics, "trainerReview": "pending"}



def _rod(obj, a, b):
    from mathutils import Vector
    obj.location = (a + b) / 2
    obj.rotation_mode = "QUATERNION"
    obj.rotation_quaternion = Vector((0, 0, 1)).rotation_difference(b - a)
    obj.scale.z = (b - a).length


def _create_sled(key, rig):
    import bpy
    import numpy as np
    from mathutils import Vector
    import equipment as e
    import machine_sled_motions as m
    contacts = m.pose(rig, key, 0)
    points, groups = _skin(rig, enable=True)
    base = contacts["machine"]
    m.pose(rig, key, 1)
    peak_points, _ = _skin(rig, enable=True)
    peak_contacts = m.pose(rig, key, 1)
    m.pose(rig, key, 0)
    hip, q = base["hip"], base["torso_rotation"]
    root = bpy.data.objects.new("Setflow original " + key + " sled station", None)
    bpy.context.scene.collection.objects.link(root)
    root.matrix_world = rig.matrix_world.copy()
    root["exercise_id"] = key
    props = {"fixed_machine": root}
    steel = e.material("Extra machine steel", (.27, .27, .27), .70)
    padding = e.material("Extra machine padding", (.048, .048, .048))
    rubber = e.material("Extra machine rubber", (.09, .09, .09))
    def empty(name, location, rotation):
        obj = bpy.data.objects.new(name, None)
        bpy.context.scene.collection.objects.link(obj)
        obj.parent = root
        obj.location = location
        obj.rotation_mode = "QUATERNION"
        obj.rotation_quaternion = rotation
        return obj
    def cube(name, loc, size, mat=steel, parent=root, support=None, axis=2, sign=1):
        obj = e.cube(name, loc, size, mat)
        obj.parent, obj.location = parent, loc
        if support:
            obj["support_family"], obj["face_axis"], obj["face_sign"] = support, axis, sign
        elif mat == steel:
            obj["hard_part"] = True
        return obj
    for side in (-1, 1):
        cube("Sled floor runner", (side * .65, .22, .03), (.10, 1.65, .06))
    cube("Sled base crossmember", (0, .95, .03), (1.40, .085, .06))
    body_frame = empty("Sled supported body frame", hip, q)
    props["body_carriage"] = body_frame
    foot_frame = empty("Sled actual footplate carriage", base["foot_center"], base["foot_rotation"])
    props["foot_carriage"] = foot_frame
    local_pair = [(data - np.asarray(c["machine"]["hip"])) @ np.asarray(q.to_matrix())
                  for data, c in ((points, contacts), (peak_points, peak_contacts))]
    if key == "legpress":
        for index in range(4):
            y = -.07 + .07 * index
            minima = []
            for data in local_pair:
                near = (np.abs(data[:, 0]) < .172) & (np.abs(data[:, 1] - y) < .032) & (data[:, 2] > -.24)
                if np.any(near):
                    minima.append(float(data[near, 2].min()))
            if minima:
                top = min(minima) - .00025
                cube("Leg press contoured hip seat " + str(index), (0, y, top - .035), (.35, .07, .07), padding, body_frame, "seat")
    for index in range(3):
        z = .18 + .135 * index
        maximum = []
        for data in local_pair:
            near = (np.abs(data[:, 0]) < .172) & (np.abs(data[:, 2] - z) < .062)
            domain = data[groups["torso"]]
            inside = (np.abs(domain[:, 0]) < .172) & (np.abs(domain[:, 2] - z) < .062)
            if not np.any(inside):
                raise ValueError("Sled back panel lacks actual torso contact")
            maximum.append(float(domain[inside, 1].max()))
        front = max(maximum) + .001
        cube("Sled fitted back panel " + str(index), (0, front + .035, z), (.35, .07, .13), padding, body_frame, "back", 1, -1)
    cube("Sled rear support spine", (0, .30, .24), (.075, .065, .70), parent=body_frame)
    cube("Sled rear carriage crossmember", (0, .32, .10), (1.28, .065, .065), parent=body_frame)
    if key == "hack_squat":
        for side, label in ((1, "l"), (-1, "r")):
            maximum = []
            for data in local_pair:
                near = (np.abs(data[:, 0] - side * .18) < .062) & (np.abs(data[:, 1] + .02) < .097) & (data[:, 2] > .35) & (data[:, 2] < .57)
                if not np.any(near):
                    raise ValueError("Hack shoulder support has no actual shoulder skin")
                maximum.append(float(data[near, 2].max()))
            bottom = max(maximum) + .001
            cube("Hack fitted shoulder cushion " + label, (side * .18, -.02, bottom + .04), (.13, .20, .08), padding, body_frame, "shoulders", 2, -1)
            cube("Hack overhead shoulder support " + label, (side * .18, .145, bottom + .10), (.055, .39, .045), parent=body_frame)
        cube("Hack upper rear crossmember", (0, .32, .64), (.78, .065, .06), parent=body_frame)
    local_feet = (points - np.asarray(base["foot_center"])) @ np.asarray(base["foot_rotation"].to_matrix())
    sole = np.concatenate((local_feet[groups["foot_l"]], local_feet[groups["foot_r"]]))
    top = float(sole[:, 2].min()) - .001
    root["footplate_top"] = top
    cube("Sled actual whole-foot platform", (0, -.07, top - .025), (.72, .42, .05), rubber, foot_frame, "feet")
    cube("Sled platform rear crossmember", (0, -.08, top - .12), (1.28, .07, .065), parent=foot_frame)
    for side, label in ((1, "l"), (-1, "r")):
        handle = bpy.data.objects.new("Sled actual side grip " + label, None)
        bpy.context.scene.collection.objects.link(handle)
        e.cylinder("Sled hand grip shaft " + label, .017, .17, padding, handle)
        props[label] = handle
        cube("Sled side grip support " + label, (side * .40, -.08, -.015), (.20, .045, .045), parent=body_frame)
        cube("Sled grip rear connection " + label, (side * .48, .12, -.015), (.045, .40, .045), parent=body_frame)
        rail_direction = Vector((0, -1 if key == "legpress" else 1, 1)).normalized()
        if key == "legpress":
            center = base["foot_center"] + base["foot_rotation"] @ Vector((side * .60, -.08, top - .12))
            a, b = center - rail_direction * .44, center + rail_direction * .18
            loaded_parent = foot_frame
            horn_position = (side * .73, -.08, top - .12)
        else:
            center = hip + q @ Vector((side * .60, .32, .10))
            a, b = center - rail_direction * .50, center + rail_direction * .85
            loaded_parent = body_frame
            horn_position = (side * .73, .32, .10)
        rail = cube("Sled straight fixed rail " + label, (0, 0, 0), (.055, .055, 1.0))
        _rod(rail, a, b)
        for end in (a, b):
            cube("Sled fixed rail floor upright " + label, (end.x, end.y, end.z / 2), (.065, .065, end.z))
        for amount in (0, 1):
            if key == "legpress":
                stop = center - rail_direction * .23 * amount
            else:
                stop = center - rail_direction * .35 * amount
            cube("Sled authored safety stop " + label, stop, (.09, .09, .09))
        holder = e.cylinder("Sled original plate horn " + label, .023, .25, steel, loaded_parent, side * .73)
        holder.location = horn_position
        plate = e.cylinder("Sled original load plate " + label, .14, .065, rubber, loaded_parent, side * .73)
        plate.location = horn_position
    if key == "legpress":
        # Ground support lies under the fixed seat, outside the feet track.
        cube("Leg press fixed seat base", (0, .18, .13), (.075, .075, .26))
    apply(props, contacts, rig)
    return props


def _apply_sled(props, contacts, rig):
    from mathutils import Vector
    machine = contacts["machine"]
    props["body_carriage"].location = machine["hip"]
    props["body_carriage"].rotation_quaternion = machine["torso_rotation"]
    props["foot_carriage"].location = machine["foot_center"]
    props["foot_carriage"].rotation_quaternion = machine["foot_rotation"]
    for label in ("l", "r"):
        props[label].location = rig.matrix_world @ contacts[label]["palm"]
        props[label].rotation_mode = "QUATERNION"
        props[label].rotation_quaternion = Vector((1, 0, 0)).rotation_difference((rig.matrix_world.to_3x3() @ contacts[label]["handle_axis"]).normalized())


def _sled_contacts(props, contacts, rig, result):
    from mathutils import Vector
    machine = contacts["machine"]
    result["sled_body_carriage_contact_error_m"] = (props["body_carriage"].location - machine["hip"]).length * rig.scale.x
    result["sled_footplate_carriage_contact_error_m"] = (props["foot_carriage"].location - machine["foot_center"]).length * rig.scale.x
    for side, label in ((1, "l"), (-1, "r")):
        actual = props["foot_carriage"].matrix_world @ Vector((side * .18, 0, 0))
        target = rig.matrix_world @ rig.pose.bones["foot_" + label].head
        result["sled_" + label + "_actual_ankle_anchor_error_m"] = (actual - target).length
    return result


def _foot_surface_metrics(report, props, rig, points, groups):
    import numpy as np
    foot_frame = props["foot_carriage"]
    matrix = np.asarray(foot_frame.matrix_world.inverted() @ rig.matrix_world)
    local = points @ matrix[:3, :3].T + matrix[:3, 3]
    top = props["fixed_machine"]["footplate_top"]
    for label in ("l", "r"):
        data = local[groups["foot_" + label]]
        for region, selection in (("heel", data[:, 1] > -.04), ("forefoot", (data[:, 1] < -.09) & (data[:, 1] > -.18))):
            if not np.any(selection):
                raise ValueError("Sled lacks actual " + region + " skin")
            report[region + "_" + label + "_support_gap_m"] = float((data[selection, 2] - top).min()) * rig.scale.x
