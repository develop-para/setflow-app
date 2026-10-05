"""Own unbranded machine geometry with shared athlete/lever trajectories.

The neutral machines are original designs, not scanned or copied products.
Padding is fitted to the evaluated CC0 skin, not to bone centres.
"""
import math


def _skin(rig):
    import bpy
    import numpy as np
    body = bpy.data.objects["SetflowAthlete.body"]
    enabled = [(modifier, modifier.show_viewport) for modifier in body.modifiers]
    for modifier, _ in enabled:
        modifier.show_viewport = True
    bpy.context.view_layer.update()
    deps = bpy.context.evaluated_depsgraph_get()
    evaluated = body.evaluated_get(deps)
    mesh = evaluated.to_mesh(preserve_all_data_layers=True, depsgraph=deps)
    try:
        coordinates = np.empty(len(mesh.vertices) * 3, dtype=np.float32)
        mesh.vertices.foreach_get("co", coordinates)
        transform = np.asarray(rig.matrix_world.inverted() @ evaluated.matrix_world)
        points = coordinates.reshape(-1, 3) @ transform[:3, :3].T + transform[:3, 3]
        groups = {}
        for name in ("pelvis", "spine_02", "spine_03", "thigh_l", "thigh_r", "calf_l", "calf_r", "foot_l", "foot_r"):
            index = body.vertex_groups[name].index
            groups[name] = np.asarray([v.index for v in mesh.vertices if any(g.group == index and g.weight >= .5 for g in v.groups)], dtype=np.int32)
        return points, groups
    finally:
        evaluated.to_mesh_clear()
        for modifier, state in enabled:
            modifier.show_viewport = state
        bpy.context.view_layer.update()


def create(exercise_id, rig):
    import bpy
    import numpy as np
    from mathutils import Vector
    import equipment as e
    import machine_motions as m
    if exercise_id not in m.SUPPORTED:
        raise ValueError("No exact machine equipment: " + exercise_id)
    contacts = m.pose(rig, exercise_id, 0)
    points, groups = _skin(rig)
    root = bpy.data.objects.new("Setflow own generic " + exercise_id, None)
    bpy.context.scene.collection.objects.link(root)
    root.matrix_world = rig.matrix_world.copy()
    root["exercise_id"] = exercise_id
    props = {"fixed_machine": root}
    padding = e.material("Generic machine padding", (.048, .048, .048))
    steel = e.material("Generic machine steel", (.28, .28, .28), .70)
    rubber = e.material("Generic machine footrest", (.09, .09, .09))
    def cube(name, location, size, material=steel):
        obj = e.cube(name, location, size, material)
        obj.parent = root
        obj.location = location
        return obj
    def fitted_segments(name, center, length, rotation, count, samples):
        from mathutils import Quaternion
        orientation = Quaternion((1, 0, 0), rotation)
        center = Vector(center)
        transformed = [(data - np.asarray(center)) @ np.asarray(orientation.to_matrix()) for data in samples]
        for index in range(count):
            y = -length / 2 + length * (index + .5) / count
            contacts = []
            for local in transformed:
                select = (np.abs(local[:, 0]) < .184) & (np.abs(local[:, 1] - y) < length / count / 2 - .001) & (local[:, 2] > -.20)
                if np.any(select):
                    contacts.append(float(local[select, 2].min()))
            if not contacts:
                continue
            clearance = .0035 if name.startswith("Prone") else .0004 if exercise_id == "adductor_machine" else .001
            top = min(contacts) - clearance
            pad = cube(name + " " + str(index), center + orientation @ Vector((0, y, top - .035)), (.37, length / count, .070), padding)
            pad.rotation_euler[0] = rotation
            pad["support_domain"] = "body_contoured"
            pad["support_family"] = name
    for side in (-1, 1):
        cube("Machine base rail", (side * .57, .0, .028), (.09, 1.80, .056))
    cube("Machine base crossmember", (0, .50, .04), (1.20, .08, .08))
    # An original stack with visible guide rails and moving selected carriage.
    cube("Machine stack rear tower", (.67, .35, .75), (.07, .08, 1.50))
    stack = cube("Machine selected resistance stack", (.67, .20, .468), (.20, .18, .24), rubber)
    props["stack"] = stack
    for z in (-.09, -.06, -.03, 0, .03, .06, .09):
        groove = e.cube("Moving weight plate seam", (0, 0, z), (.204, .184, .002), steel)
        groove.parent = stack
        groove.location = (0, 0, z)
    cable = cube("Machine stack cable", (0, 0, 0), (.006, .006, 1.0), rubber)
    props["stack_cable"] = cable
    for z in (.19, .22, .25, .28, .31, .34):
        cube("Machine unselected weight plate", (.67, .20, z - .01), (.205, .185, .012), rubber)
    if exercise_id == "leg_curl":
        # Torso is pitched 70 degrees: support normal faces the athlete's front.
        angle = math.radians(70)
        axis = Vector((0, -math.sin(angle), math.cos(angle)))
        normal = Vector((0, -math.cos(angle), -math.sin(angle)))
        fitted_segments("Prone pelvis pad", (0, .20, .76), .30, angle - math.pi / 2, 3, [points])
        fitted_segments("Prone torso pad", (0, -.10, .87), .46, angle - math.pi / 2, 4, [points])
        fitted_segments("Prone upper-leg support", (0, .405, .705), .32, math.radians(-15), 3, [points])
        for label in ("l", "r"):
            knee = rig.pose.bones["calf_" + label].head
            cube("Prone knee frame " + label, (knee.x * 1.9, knee.y, knee.z * .5), (.045, .09, knee.z))
            cube("Prone knee pivot crosslink " + label, (.28 if label == "l" else -.28, knee.y, knee.z), (.20, .045, .045))
    else:
        contact_samples = [points]
        if exercise_id == "adductor_machine":
            m.pose(rig, exercise_id, 1)
            contact_samples.append(_skin(rig)[0])
            m.pose(rig, exercise_id, 0)
        fitted_segments("Machine seated cushion", (0, .17, .49), .28, 0, 4, contact_samples)
        top = min(float(data[(np.abs(data[:, 0]) < .18) & (np.abs(data[:, 1] - .17) < .137), 2].min()) for data in contact_samples) - .001
        back = np.concatenate((points[groups["spine_02"]], points[groups["spine_03"]]))
        front = float(back[:, 1].max()) + .001
        backrest = cube("Machine supported backrest", (0, front + .04, .93), (.35, .080, .82), padding)
        backrest["support_domain"] = "back"
        cube("Machine seat upright", (0, .21, top * .5), (.08, .08, top))
        cube("Machine back upright", (0, front + .11, .75), (.06, .06, 1.45))
    for label in ("l", "r"):
        handle = bpy.data.objects.new("Machine actual handle " + label, None)
        bpy.context.scene.collection.objects.link(handle)
        e.cylinder("Machine rubber grip " + label, .018, .18, padding, handle)
        props[label] = handle
        if exercise_id != "chest_press":
            palm = contacts[label]["palm"]
            cube("Fixed side handle brace " + label, (palm.x, palm.y + .11, palm.z - .018), (.040, .26, .036))
            cube("Fixed side handle upright " + label, (palm.x, palm.y + .22, palm.z / 2), (.045, .045, palm.z))
    if exercise_id == "chest_press":
        height = contacts["machine"]["pivot"][2]
        for side in (-1, 1):
            cube("Press fixed front upright", (side * .55, -.30, height / 2), (.060, .060, height))
        cube("Press fixed overhead crossmember", (0, -.30, height), (1.13, .060, .060))
        for label in ("l", "r"):
            lever = cube("Press rigid lever " + label, (0, 0, 0), (.043, .043, .65))
            props["press_lever_" + label] = lever
            pivot = cube("Press fixed pivot " + label, (0, 0, 0), (.13, .08, .08))
            props["press_pivot_" + label] = pivot
    elif exercise_id in ("leg_curl", "leg_extension"):
        offsets = []
        for label in ("l", "r"):
            bone = rig.pose.bones["calf_" + label]
            axis = (bone.tail - bone.head).normalized()
            center = bone.head + axis * bone.length * .84
            # Anterior extension pad / posterior curl pad; target the real
            # skinned lower-calf cross section, above the ankle.
            normal = Vector((0, -axis.z, axis.y))
            if exercise_id == "leg_extension":
                normal.negate()
            data = points[groups["calf_" + label]]
            along = (data - np.asarray(center)) @ np.asarray(axis)
            near = data[np.abs(along) < .025]
            surface = float(((near - np.asarray(center)) @ np.asarray(normal)).max())
            low_distance, high_distance = surface + .04, surface + .09
            for _ in range(40):
                distance = (low_distance + high_distance) / 2
                radial = np.linalg.norm(data[:, 1:] - np.asarray(center + normal * distance)[1:], axis=1).min()
                if radial < .057:
                    low_distance = distance
                else:
                    high_distance = distance
            offset = high_distance - .056 - .001
            offsets.append(offset)
            lever_length = math.hypot(bone.length * .84, max(offsets) + .001 + .056)
            lever = cube("Knee rigid lever " + label, (0, 0, 0), (.038, .038, lever_length))
            props["knee_lever_" + label] = lever
            pivot = cube("Machine knee pivot " + label, (0, 0, 0), (.12, .075, .075))
            props["knee_pivot_" + label] = pivot
            if exercise_id == "leg_extension":
                knee = bone.head
                cube("Extension knee pivot upright " + label, (.36 if label == "l" else -.36, knee.y, knee.z / 2), (.055, .055, knee.z))
        root["roller_skin_offset"] = max(offsets) + .001
        roller = bpy.data.objects.new("Machine shared lower-leg roller", None)
        bpy.context.scene.collection.objects.link(roller)
        e.cylinder("Machine cushioned lower-leg roller", .056, .51, padding, roller)
        props["roller"] = roller
        roller.scale = rig.scale.copy()
    elif exercise_id == "adductor_machine":
        for side, label in ((1, "l"), (-1, "r")):
            theta = contacts["machine"]["angle"]
            normal = Vector((side * math.cos(theta), math.sin(theta), 0))
            knee = rig.pose.bones["calf_" + label].head
            data = points[groups["thigh_" + label]]
            tangent = Vector((-math.sin(theta), side * math.cos(theta), 0))
            delta = data - np.asarray(knee)
            near = data[(np.abs(delta @ np.asarray(tangent)) < .079) & (np.abs(delta[:, 2]) < .079)]
            offset = float(((near - np.asarray(knee)) @ np.asarray(normal)).min())
            root["medial_offset_" + label] = offset - .001
            pad = cube("Adductor inner knee pad " + label, (0, 0, 0), (.060, .16, .16), padding)
            props["medial_pad_" + label] = pad
            lever = cube("Adductor hip lever " + label, (0, 0, 0), (.038, .038, rig.data.bones["thigh_" + label].length))
            props["adduction_lever_" + label] = lever
            brace = cube("Adductor footrest support " + label, (0, 0, 0), (.026, .026, .28))
            props["foot_brace_" + label] = brace
            pedal = cube("Adductor moving foot support " + label, (0, 0, 0), (.18, .30, .008), rubber)
            props["pedal_" + label] = pedal
        root["foot_support_top"] = min(float(points[groups["foot_" + label]][:, 2].min()) for label in ("l", "r")) - .001
    apply(props, contacts, rig)
    return props


def _rod(obj, a, b):
    from mathutils import Vector
    axis = b - a
    obj.location = (a + b) / 2
    obj.rotation_mode = "QUATERNION"
    obj.rotation_quaternion = Vector((0, 0, 1)).rotation_difference(axis)


def apply(props, contacts, rig, frame=None):
    import bpy
    from mathutils import Vector
    root = props["fixed_machine"]
    key = root["exercise_id"]
    machine = contacts["machine"]
    for label in ("l", "r"):
        contact = contacts[label]
        props[label].location = rig.matrix_world @ contact["palm"]
        props[label].rotation_mode = "QUATERNION"
        props[label].rotation_quaternion = Vector((1, 0, 0)).rotation_difference((rig.matrix_world.to_3x3() @ contact["handle_axis"]).normalized())
    if key == "chest_press":
        for label in ("l", "r"):
            palm = contacts[label]["palm"]
            pivot = Vector(machine["pivot"])
            pivot.x = palm.x
            props["press_pivot_" + label].location = pivot
            _rod(props["press_lever_" + label], pivot, palm)
        movement = (machine["angle"] - machine["start_angle"]) / (machine["end_angle"] - machine["start_angle"])
    elif key in ("leg_curl", "leg_extension"):
        centers = []
        for label in ("l", "r"):
            bone = rig.pose.bones["calf_" + label]
            axis = (bone.tail - bone.head).normalized()
            normal = Vector((0, -axis.z, axis.y))
            if key == "leg_extension":
                normal.negate()
            center = bone.head + axis * bone.length * machine["roller_fraction"]
            centers.append(center + normal * (root["roller_skin_offset"] + .056))
            pivot = bone.head.copy()
            pivot.x = .36 if label == "l" else -.36
            endpoint = centers[-1].copy()
            endpoint.x = pivot.x
            props["knee_pivot_" + label].location = pivot
            _rod(props["knee_lever_" + label], pivot, endpoint)
        props["roller"].location = rig.matrix_world @ ((centers[0] + centers[1]) / 2)
        movement = ((machine["angle"] - math.radians(70)) / math.radians(105) if key == "leg_curl" else -machine["angle"] / math.radians(82))
    else:
        for side, label in ((1, "l"), (-1, "r")):
            knee = rig.pose.bones["calf_" + label].head
            hip = rig.pose.bones["thigh_" + label].head
            normal = Vector((side * math.cos(machine["angle"]), math.sin(machine["angle"]), 0))
            pad = props["medial_pad_" + label]
            pad.location = knee + normal * (root["medial_offset_" + label] - .030)
            pad.rotation_euler[2] = side * machine["angle"]
            # Hip lever is a rigid rod below the thigh, with its fixed pivot
            # exactly under the anatomical hip joint.
            _rod(props["adduction_lever_" + label], hip - Vector((0, 0, .20)), knee - Vector((0, 0, .20)))
            foot = rig.pose.bones["foot_" + label].head
            props["pedal_" + label].location = (foot.x, foot.y - .06, root["foot_support_top"] - .004)
            top = Vector((knee.x + side * .08, knee.y + .06, knee.z - .20))
            bottom = Vector((foot.x + side * .08, foot.y + .06, root["foot_support_top"] - .004))
            _rod(props["foot_brace_" + label], bottom, top)
            props["foot_brace_" + label].scale.z = (top - bottom).length / .28
        movement = (math.radians(38) - machine["angle"]) / math.radians(32)
    props["stack"].location.z = .468 + .18 * movement
    cable_start = Vector((.67, .20, 1.50))
    cable_end = Vector((.67, .20, props["stack"].location.z + .12))
    _rod(props["stack_cable"], cable_start, cable_end)
    props["stack_cable"].scale.z = (cable_start - cable_end).length
    if frame is not None:
        for obj in props.values():
            obj.keyframe_insert("location", frame=frame)
            obj.keyframe_insert("rotation_quaternion" if obj.rotation_mode == "QUATERNION" else "rotation_euler", frame=frame)
            obj.keyframe_insert("scale", frame=frame)
    bpy.context.view_layer.update()


def contacts_audit(props, contacts, rig):
    """Errors only, in metres: compatible with the shared <=2 mm guard."""
    from mathutils import Vector
    import equipment
    result = equipment.contacts_audit(props, contacts, rig)
    key = props["fixed_machine"]["exercise_id"]
    machine = contacts["machine"]
    if key == "chest_press":
        errors = []
        for label in ("l", "r"):
            pivot = Vector(machine["pivot"])
            pivot.x = contacts[label]["palm"].x
            errors.append(abs((contacts[label]["palm"] - pivot).length - machine["radius"]))
            lever = props["press_lever_" + label]
            actual = lever.matrix_world @ Vector((0, 0, .325))
            result["press_" + label + "_actual_lever_endpoint_error_m"] = (actual - rig.matrix_world @ contacts[label]["palm"]).length
        result["press_constant_radius_error_m"] = max(errors) * rig.scale.x
    elif key in ("leg_curl", "leg_extension"):
        result["knee_pivot_alignment_error_m"] = max((props["knee_pivot_" + label].location.yz - rig.pose.bones["calf_" + label].head.yz).length for label in ("l", "r")) * rig.scale.x
    else:
        result["adduction_knee_flexion_plane_error_m"] = max(abs(rig.pose.bones["calf_" + label].head.z - rig.pose.bones["thigh_" + label].head.z) for label in ("l", "r")) * rig.scale.x
    return result


def surface_audit(exercise_id, props, rig, body, frame, amount, cache):
    """Measure actual evaluated skin against fixed/moving apparatus surfaces."""
    import bpy
    import numpy as np
    from mathutils import Vector
    deps = bpy.context.evaluated_depsgraph_get()
    evaluated = body.evaluated_get(deps)
    mesh = evaluated.to_mesh(preserve_all_data_layers=True, depsgraph=deps)
    try:
        coordinates = np.empty(len(mesh.vertices) * 3, dtype=np.float32)
        mesh.vertices.foreach_get("co", coordinates)
        transform = np.asarray(evaluated.matrix_world)
        points = coordinates.reshape(-1, 3) @ transform[:3, :3].T + transform[:3, 3]
        key = (body.as_pointer(), len(mesh.vertices))
        groups = cache.get(key)
        if groups is None:
            groups = {}
            for name, prefixes in {"pelvis": ("pelvis",), "back": ("spine_02", "spine_03"),
                                  "calf_l": ("calf_l",), "calf_r": ("calf_r",),
                                  "thigh_l": ("thigh_l",), "thigh_r": ("thigh_r",), "spine_03": ("spine_03",),
                                  "foot_l": ("foot_l", "ball_l"), "foot_r": ("foot_r", "ball_r")}.items():
                indices = {g.index for g in body.vertex_groups if g.name in prefixes}
                groups[name] = np.asarray([v.index for v in mesh.vertices if sum(g.weight for g in v.groups if g.group in indices) >= .5], dtype=np.int32)
            cache[key] = groups
        report = {"frame": frame, "amount": amount, "body_floor_min_m": float(points[:, 2].min())}
        root = props["fixed_machine"]
        family_gaps = {}
        for pad in root.children_recursive:
            if pad.type != "MESH" or not pad.get("support_domain"):
                continue
            inverse = np.asarray(pad.matrix_world.inverted())
            local = points @ inverse[:3, :3].T + inverse[:3, 3]
            bounds = np.asarray(pad.bound_box)
            low, high = bounds.min(axis=0), bounds.max(axis=0)
            # Each pad's local +Z is its contact surface, except the seated
            # vertical backrest, whose local -Y faces the athlete.
            backrest = pad["support_domain"] == "back"
            axis = 1 if backrest else 2
            others = [i for i in range(3) if i != axis]
            within = np.all((local[:, others] > low[others] + .003) & (local[:, others] < high[others] - .003), axis=1)
            within &= local[:, axis] < high[axis] if backrest else local[:, axis] > low[axis]
            if np.any(within):
                gap = low[axis] - local[within, axis].max() if backrest else local[within, axis].min() - high[axis]
                report[pad.name + "_penetration_gap_m"] = float(gap) * rig.scale.x
            if pad["support_domain"] == "body_contoured":
                if np.any(within):
                    family_gaps.setdefault(pad["support_family"], []).append(float(gap) * rig.scale.x)
                continue
            data = local[groups[pad["support_domain"]]]
            support = low[axis] - data[:, axis].max() if backrest else data[:, axis].min() - high[axis]
            report[pad.name + "_support_gap_m"] = float(support) * rig.scale.x
        for family, gaps in family_gaps.items():
            report[family + "_support_gap_m"] = min(gaps)
        if exercise_id in ("leg_curl", "leg_extension"):
            roller = props["roller"]
            center = np.asarray(roller.matrix_world.translation)
            radius = .056 * rig.scale.x
            for label in ("l", "r"):
                data = points[groups["calf_" + label]]
                radial = np.linalg.norm(data[:, 1:] - center[1:], axis=1)
                report["roller_" + label + "_skin_gap_m"] = float(radial.min()) - radius
        if exercise_id == "adductor_machine":
            for label in ("l", "r"):
                pad = props["medial_pad_" + label]
                inverse = np.asarray(pad.matrix_world.inverted())
                local = points @ inverse[:3, :3].T + inverse[:3, 3]
                data = local[groups["thigh_" + label]]
                near = (np.abs(data[:, 1]) < .079) & (np.abs(data[:, 2]) < .079)
                contact = data[near, 0].min() - .030 if label == "l" else -.030 - data[near, 0].max()
                report["medial_" + label + "_skin_gap_m"] = float(contact) * rig.scale.x
                inside = (np.abs(local[:, 0]) < .029) & (np.abs(local[:, 1]) < .079) & (np.abs(local[:, 2]) < .079)
                report["medial_" + label + "_body_inside_vertices"] = int(np.count_nonzero(inside))
                pedal = props["pedal_" + label]
                top = max((pedal.matrix_world @ Vector(corner)).z for corner in pedal.bound_box)
                report["pedal_" + label + "_skin_gap_m"] = float(points[groups["foot_" + label]][:, 2].min()) - top
        return report
    finally:
        evaluated.to_mesh_clear()


def validate_surfaces(exercise_id, samples):
    failures, metrics = [], {}
    if exercise_id not in ("chest_press", "leg_curl", "leg_extension", "adductor_machine") or not samples:
        return {"passed": False, "failures": ["Missing exact machine skin samples"]}
    required = ["frame", "amount", "body_floor_min_m"]
    if exercise_id == "leg_curl":
        required += [name + "_support_gap_m" for name in ("Prone pelvis pad", "Prone torso pad", "Prone upper-leg support")]
    else:
        required += ["Machine seated cushion_support_gap_m", "Machine supported backrest_support_gap_m"]
    if exercise_id in ("leg_curl", "leg_extension"):
        required += ["roller_" + label + "_skin_gap_m" for label in ("l", "r")]
    if exercise_id == "adductor_machine":
        required += [prefix + label + suffix for label in ("l", "r") for prefix, suffix in (
            ("medial_", "_skin_gap_m"), ("medial_", "_body_inside_vertices"), ("pedal_", "_skin_gap_m"))]
    if any(any(name not in row for name in required) for row in samples):
        return {"passed": False, "failures": ["Missing actual support/roller/pedal skin measurements"]}
    if any(not isinstance(value, (int, float)) or not math.isfinite(value) for row in samples for value in row.values()):
        return {"passed": False, "failures": ["Nonfinite or nonnumeric actual skin measurements"]}
    for key in samples[0]:
        if key in ("frame", "amount"):
            continue
        values = [row[key] for row in samples if key in row]
        metrics[key + "_min"] = min(values)
        metrics[key + "_max"] = max(values)
        if key.endswith("inside_vertices") and max(values):
            failures.append(key + " contains body skin")
        elif key.endswith("gap_m") and min(values) < -.001:
            failures.append(key + " penetrates skin by more than 1 mm")
        if key.endswith("support_gap_m") or key.startswith(("roller_", "medial_", "pedal_")) and key.endswith("skin_gap_m"):
            if max(values) > .004:
                failures.append(key + " misses actual support by more than 4 mm")
    if min(row["body_floor_min_m"] for row in samples) < -.001:
        failures.append("Body skin penetrates floor")
    return {"passed": not failures, "metrics": metrics, "failures": failures,
            "support_gap_allowed_m": [-.001, .004], "trainerReview": "pending"}
