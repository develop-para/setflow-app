"""Original lever-fly and counterweighted kneeling pull-up apparatus."""
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


def _rod(obj, a, b):
    from mathutils import Vector
    obj.location = (a + b) / 2
    obj.rotation_mode = "QUATERNION"
    obj.rotation_quaternion = Vector((0, 0, 1)).rotation_difference(b - a)
    obj.scale.z = (b - a).length


def create(exercise_id, rig):
    import bpy
    import numpy as np
    from mathutils import Vector
    import equipment as e
    import machine_extra_motions as m
    if exercise_id not in m.SUPPORTED:
        raise ValueError("No exact extra machine equipment: " + exercise_id)
    contacts = m.pose(rig, exercise_id, 0)
    points, groups = _skin(rig, enable=True)
    root = bpy.data.objects.new("Setflow original " + exercise_id, None)
    bpy.context.scene.collection.objects.link(root)
    root.matrix_world = rig.matrix_world.copy()
    root["exercise_id"] = exercise_id
    props = {"fixed_machine": root}
    steel = e.material("Extra machine steel", (.27, .27, .27), .70)
    padding = e.material("Extra machine padding", (.048, .048, .048))
    rubber = e.material("Extra machine rubber", (.09, .09, .09))
    def cube(name, location, size, material=steel, parent=root, support=None, axis=2, sign=1):
        obj = e.cube(name, location, size, material)
        obj.parent = parent
        obj.location = location
        if support:
            obj["support_family"], obj["face_axis"], obj["face_sign"] = support, axis, sign
        elif material == steel:
            obj["hard_part"] = True
        return obj
    for side in (-1, 1):
        cube("Extra machine floor base", (side * .76, .20, .030), (.10, 1.90, .060))
    cube("Extra machine base crossmember", (0, .72, .030), (1.58, .08, .060))
    if exercise_id != "assisted_pullup":
        # One constant-radius rotating arm per shoulder, with a vertical
        # drop and vertical hand grip. The handles do not float separately.
        m.pose(rig, exercise_id, 1)
        peak_points, _ = _skin(rig, enable=True)
        m.pose(rig, exercise_id, 0)
        for index in range(4):
            y = .065 + .07 * index
            top_samples = []
            for data in (points, peak_points):
                near = (np.abs(data[:, 0]) < .182) & (np.abs(data[:, 1] - y) < .034) & (data[:, 2] > .29)
                if np.any(near):
                    top_samples.append(float(data[near, 2].min()))
            if top_samples:
                top = min(top_samples) - .001
                cube("Extra fitted seat " + str(index), (0, y, top - .035), (.37, .07, .070), padding, support="seat")
        cube("Extra seat upright", (0, .17, .19), (.075, .075, .38))
        chest = points[groups["chest"]]
        peak_chest = peak_points[groups["chest"]]
        if exercise_id == "pec_deck":
            front = max(float(data[:, 1].max()) for data in (chest, peak_chest)) + .001
            cube("Extra supported backrest", (0, front + .04, .93), (.35, .080, .82), padding, support="back", axis=1, sign=-1)
            cube("Extra backrest frame", (0, front + .10, .72), (.065, .065, 1.35))
        else:
            # Fit three original cushion panels to the actual chest, rather
            # than placing a large flat pad through the protruding abdomen.
            fronts = []
            for index in range(3):
                z = .78 + .055 * index
                nearest = []
                for data in (points[groups["torso"]], peak_points[groups["torso"]]):
                    near = (np.abs(data[:, 0]) < .117) & (np.abs(data[:, 2] - z) < .026)
                    if not np.any(near):
                        raise ValueError("Reverse-fly chest panel has no actual torso support")
                    nearest.append(float(data[near, 1].min()))
                back = min(nearest) - .001
                fronts.append(back)
                cube("Extra reverse-fly chest cushion " + str(index), (0, back - .04, z), (.24, .080, .055), padding, support="chest", axis=1, sign=1)
            upright_y = min(fronts) - .16
            cube("Extra chest support upright", (0, upright_y, .445), (.065, .065, .89))
            for index, back in enumerate(fronts):
                cube("Extra chest cushion support " + str(index), (0, (upright_y + back - .08) / 2, .78 + .055 * index), (.06, back - .08 - upright_y, .035))
        for side in (-1, 1):
            cube("Extra fly rear tower", (side * .76, .65, .80), (.060, .060, 1.60))
            cube("Extra fly overhead reach", (side * .76, .34, 1.60), (.060, .68, .060))
        cube("Extra fly overhead crossmember", (0, .075, 1.60), (1.58, .060, .060))
        for label in ("l", "r"):
            handle = bpy.data.objects.new("Extra fly actual grip " + label, None)
            bpy.context.scene.collection.objects.link(handle)
            e.cylinder("Extra fly vertical grip " + label, .018, .18, padding, handle)
            props[label] = handle
            props["fly_arm_" + label] = cube("Extra rigid horizontal arm " + label, (0, 0, 0), (.035, .035, 1.0))
            props["fly_drop_" + label] = cube("Extra rigid vertical drop " + label, (0, 0, 0), (.032, .032, 1.0))
            shoulder = rig.pose.bones["upperarm_" + label].head
            root["fly_radius_" + label] = (contacts[label]["palm"].xy - shoulder.xy).length
    else:
        for side in (-1, 1):
            cube("Assisted pull-up rear guide tower", (side * .76, .70, 1.13), (.070, .070, 2.26))
            cube("Assisted pull-up forward grip reach", (side * .76, .30, 2.10), (.065, .87, .065))
            cube("Assisted pull-up grip crosslink", (side * .67, -.10, 2.10), (.21, .055, .055))
        cube("Assisted cable top crossmember", (0, .70, 2.24), (1.59, .065, .065))
        bar = bpy.data.objects.new("Assisted fixed pronated grip bar", None)
        bpy.context.scene.collection.objects.link(bar)
        bar.location = rig.matrix_world @ Vector((0, -.10, 2.10))
        bar.scale = rig.scale.copy()
        e.cylinder("Assisted actual horizontal grip shaft", .019, 1.18, steel, bar)
        props["bar"] = bar
        carriage = bpy.data.objects.new("Assisted moving knee carriage", None)
        bpy.context.scene.collection.objects.link(carriage)
        carriage.parent = root
        props["knee_carriage"] = carriage
        knee = rig.pose.bones["calf_l"].head
        y = knee.y - .075
        near = (np.abs(points[:, 0]) < .217) & (np.abs(points[:, 1] - y) < .098) & (np.abs(points[:, 2] - knee.z) < .13)
        top = float(points[near, 2].min()) - .001
        root["knee_pad_top"] = top
        cube("Assisted fitted knee cushion", (0, y, top - .04), (.44, .20, .080), padding, carriage, "knees")
        cube("Assisted knee plate pedestal", (0, y, top - .14), (.085, .085, .20), parent=carriage)
        cube("Assisted under-knee carrier", (0, (y + .70) / 2, top - .20), (.065, .70 - y, .060), parent=carriage)
        cube("Assisted cable attachment upright", (0, .70, top), (.070, .070, .42), parent=carriage)
        stack = cube("Assisted selected counterweight", (.61, .70, 1.10), (.22, .20, .24), rubber)
        props["stack"] = stack
        for label in ("pad", "stack"):
            props["cable_" + label] = cube("Assisted counterweight cable " + label, (0, 0, 0), (.006, .006, 1.0), rubber)
        root["cable_total_length"] = (2.24 - top - .20) + (2.24 - 1.22)
    if exercise_id != "assisted_pullup":
        stack = cube("Extra fly selected weight stack", (.64, .68, .468), (.20, .18, .24), rubber)
        props["stack"] = stack
        props["stack_cable"] = cube("Extra fly cable", (0, 0, 0), (.006, .006, 1.0), rubber)
        for z in (.18, .21, .24, .27, .30, .33):
            cube("Extra fly unselected plate", (.64, .68, z), (.20, .18, .015), rubber)
    apply(props, contacts, rig)
    return props


def apply(props, contacts, rig, frame=None):
    import bpy
    from mathutils import Vector
    root = props["fixed_machine"]
    key = root["exercise_id"]
    if key != "assisted_pullup":
        for label in ("l", "r"):
            palm = contacts[label]["palm"]
            props[label].location = rig.matrix_world @ palm
            props[label].rotation_mode = "QUATERNION"
            props[label].rotation_quaternion = Vector((1, 0, 0)).rotation_difference((rig.matrix_world.to_3x3() @ contacts[label]["handle_axis"]).normalized())
            shoulder = rig.pose.bones["upperarm_" + label].head
            pivot = Vector((shoulder.x, shoulder.y, 1.60))
            outer = Vector((palm.x, palm.y, 1.60))
            _rod(props["fly_arm_" + label], pivot, outer)
            _rod(props["fly_drop_" + label], outer, palm + Vector((0, 0, .06)))
        angle = contacts["machine"]["angle"]
        movement = (math.radians(70) - angle) / math.radians(67) if key == "pec_deck" else (angle - math.radians(3)) / math.radians(87)
        props["stack"].location.z = .468 + .18 * movement
        _rod(props["stack_cable"], Vector((.64, .68, 1.60)), Vector((.64, .68, props["stack"].location.z + .12)))
    else:
        travel = contacts["machine"]["travel"]
        props["knee_carriage"].location = (0, 0, travel)
        props["stack"].location.z = 1.10 - travel
        _rod(props["cable_pad"], Vector((0, .70, 2.24)), Vector((0, .70, root["knee_pad_top"] + .20 + travel)))
        _rod(props["cable_stack"], Vector((.61, .70, 2.24)), Vector((.61, .70, 1.22 - travel)))
    if frame is not None:
        for obj in props.values():
            for channel in ("location", "scale", "rotation_quaternion" if obj.rotation_mode == "QUATERNION" else "rotation_euler"):
                obj.keyframe_insert(channel, frame=frame)
    bpy.context.view_layer.update()


def contacts_audit(props, contacts, rig):
    import equipment
    from mathutils import Vector
    result = equipment.contacts_audit(props, contacts, rig)
    root = props["fixed_machine"]
    if root["exercise_id"] != "assisted_pullup":
        for label in ("l", "r"):
            shoulder = rig.pose.bones["upperarm_" + label].head
            radius = (contacts[label]["palm"].xy - shoulder.xy).length
            result["fly_" + label + "_constant_radius_error_m"] = abs(radius - root["fly_radius_" + label]) * rig.scale.x
            endpoint = props["fly_drop_" + label].matrix_world @ Vector((0, 0, .5))
            result["fly_" + label + "_actual_drop_endpoint_error_m"] = (endpoint - rig.matrix_world @ (contacts[label]["palm"] + Vector((0, 0, .06)))).length
    else:
        for side, label in ((1, "l"), (-1, "r")):
            result["assisted_" + label + "_fixed_palm_error_m"] = (contacts[label]["palm"] - Vector((side * .29, -.10, 2.10))).length * rig.scale.x
        actual = props["cable_pad"].scale.z + props["cable_stack"].scale.z
        result["assisted_counterweight_cable_length_error_m"] = abs(actual - root["cable_total_length"]) * rig.scale.x
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
    report["nonhand_skin_inside_hard_frame_vertices"] = hard_count
    for family, values in families.items():
        report[family + "_support_gap_m"] = min(values)
    if exercise_id == "assisted_pullup":
        import technique
        sample = technique.bar_surface_sample(body, props["bar"], frame=frame, amount=amount, radius_m=.019 * rig.scale.x, half_width_m=.19, topology_cache=cache.setdefault("shaft_topology", {}))
        report["grip_bar_nonhand_skin_gap_m"] = sample["central_shaft_min_surface_clearance_m"]
    return report


def validate_surfaces(exercise_id, samples):
    if not samples:
        return {"passed": False, "failures": ["Missing extra machine actual surfaces"]}
    required = ["body_floor_min_m", "nonhand_skin_inside_hard_frame_vertices"]
    required += (["knees_support_gap_m", "grip_bar_nonhand_skin_gap_m"] if exercise_id == "assisted_pullup"
                 else ["seat_support_gap_m", "back_support_gap_m" if exercise_id == "pec_deck" else "chest_support_gap_m"])
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
