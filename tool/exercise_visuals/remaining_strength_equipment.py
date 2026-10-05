"""Original supports and rigid implement contracts for remaining strength."""
import math


def _api():
    import bpy
    import equipment
    from mathutils import Vector
    return bpy, equipment, Vector


def _root(name):
    bpy, _, _ = _api()
    root = bpy.data.objects.new(name, None)
    bpy.context.scene.collection.objects.link(root)
    return root


def _segment(name, start, finish, radius, mat, parent=None):
    _, e, V = _api()
    start, finish = V(start), V(finish)
    obj = e.cylinder(name, radius, (finish - start).length, mat)
    obj.location = (start + finish) / 2
    obj.rotation_mode = "QUATERNION"
    obj.rotation_quaternion = V((0, 0, 1)).rotation_difference((finish - start).normalized())
    if parent:
        obj.parent = parent
    return obj


def _rack(rig):
    from remaining_strength_motions import pose
    _, e, V = _api()
    contacts = pose(rig, "rack_pull", 0)
    centre = rig.matrix_world @ contacts["rack_bar_center"]
    steel = e.material("Remaining strength structural steel", (.22, .22, .22), .7)
    root = _root("Setflow original power rack")
    for x in (-.96, .96):
        for y in (-.52, .45):
            obj = e.cube("Rack upright", (x, y, .94), (.065, .065, 1.88), steel)
            obj.parent = root
        obj = e.cube("Rack base rail", (x, -.035, .03), (.14, 1.10, .06), steel)
        obj.parent = root
    for z in (.035, 1.85):
        obj = e.cube("Rack transverse support", (0, .45, z), (1.98, .065, .065), steel)
        obj.parent = root
    for x in (-.62, .62):
        _segment("Knee-height safety catch", (x, -.52, centre.z - .041), (x, .45, centre.z - .041), .025, steel, root)
    bar = e.barbell()
    bar["shaft_surface_half_width_m"] = .70
    bar["rack_pin_top_z"] = centre.z - .016
    return {"bar": bar, "rack": root}


def _landmine(rig):
    from remaining_strength_motions import LANDMINE_LENGTH, LANDMINE_PIVOT
    _, e, V = _api()
    steel = e.material("Remaining strength brushed steel", (.24, .24, .24), .75)
    rubber = e.material("Remaining strength rubber", (.042, .042, .042))
    root = _root("Setflow rigid landmine shaft")
    root["implement_kind"] = "fixed_pivot_landmine"
    root["shaft_half_length_m"] = LANDMINE_LENGTH / 2
    e.cylinder("Landmine full shaft", .016, LANDMINE_LENGTH, steel, root)
    for radius, depth, distance in ((.19, .065, .73), (.155, .035, .79), (.04, .035, .825)):
        e.cylinder("Landmine loaded sleeve plate", radius, depth, rubber if radius > .05 else steel, root, distance)
    handles = {}
    for side, label in ((1, "l"), (-1, "r")):
        grip = _root("Double-D parallel closed grip " + label)
        e.cylinder("Double-D hand segment " + label, .019, .18, steel, grip)
        handles[label] = grip
    attachment = _root("Rigid Double-D attachment frame")
    # This rectangular cross-frame has two separate parallel grip segments.
    scale = rig.scale.x
    for y in (-.09 * scale, .09 * scale):
        _segment("Double-D crosspiece", (-.195 * scale, y, 0), (.195 * scale, y, 0), .018, steel, attachment)
    _segment("Double-D shaft connection", (0, 0, 0), (0, 0, -.055 * scale), .023, steel, attachment)
    base = _root("Fixed landmine socket and base")
    pivot = rig.matrix_world @ V(LANDMINE_PIVOT)
    socket = e.cube("Landmine fixed floor anchor", (pivot.x, pivot.y, .025), (.35, .32, .05), steel)
    socket.parent = base
    _segment("Landmine pivot stem", (pivot.x, pivot.y, .025), pivot, .035, steel, base)
    return {"landmine": root, "attachment": attachment, "landmine_base": base, **handles}


def create(exercise_id, rig):
    _, e, _ = _api()
    if exercise_id == "rack_pull":
        return _rack(rig)
    if exercise_id == "tbar_row":
        return _landmine(rig)
    if exercise_id == "upright_row":
        bar = e.barbell()
        bar["shaft_surface_half_width_m"] = .70
        return {"bar": bar}
    raise ValueError("No exact remaining strength equipment: " + exercise_id)


def apply(props, contacts, rig, frame=None):
    bpy, e, V = _api()
    if "landmine" not in props:
        return e.apply(props, contacts, rig, frame)
    from remaining_strength_motions import LANDMINE_LENGTH, landmine_frame
    pivot, axis, centre = landmine_frame(contacts["motion_amount"])
    world = rig.matrix_world
    axis = (world.to_3x3() @ axis).normalized()
    pivot, centre = world @ pivot, world @ centre
    root = props["landmine"]
    root.location = pivot + axis * (LANDMINE_LENGTH / 2)
    root.rotation_mode = "QUATERNION"
    root.rotation_quaternion = V((1, 0, 0)).rotation_difference(axis)
    props["attachment"].location = centre
    props["attachment"].rotation_mode = "QUATERNION"
    # Attachment local Y is its parallel grip direction; local Z is the
    # upper normal. No part slides or changes length as the lever rises.
    from mathutils import Matrix
    up = V((0, axis.z, -axis.y))
    props["attachment"].rotation_quaternion = Matrix((V((1, 0, 0)), -axis, up)).transposed().to_quaternion()
    for label in ("l", "r"):
        grip = props[label]
        grip.location = world @ contacts[label]["palm"]
        grip.rotation_mode = "QUATERNION"
        grip.rotation_quaternion = V((1, 0, 0)).rotation_difference(axis)
    if frame is not None:
        for obj in props.values():
            obj.keyframe_insert("location", frame=frame)
            if obj.rotation_mode == "QUATERNION":
                obj.keyframe_insert("rotation_quaternion", frame=frame)
    bpy.context.view_layer.update()


def contacts_audit(props, contacts, rig):
    _, e, V = _api()
    if "landmine" not in props:
        result = e.contacts_audit(props, contacts, rig)
        if "rack" in props:
            result["rack_pin_hold_gap_m"] = abs(props["bar"].location.z - .016 - props["bar"]["rack_pin_top_z"]) if contacts["motion_amount"] < .0001 else 0.
        return result
    from remaining_strength_motions import LANDMINE_LENGTH, LANDMINE_PIVOT
    root = props["landmine"]
    axis = (root.matrix_world.to_3x3() @ V((1, 0, 0))).normalized()
    pivot = root.matrix_world.translation - axis * (LANDMINE_LENGTH / 2)
    result = {"landmine_pivot_drift_m": (pivot - rig.matrix_world @ V(LANDMINE_PIVOT)).length}
    for label in ("l", "r"):
        result["handle_" + label + "_contact_m"] = (props[label].matrix_world.translation - rig.matrix_world @ contacts[label]["palm"]).length
        hand_axis = (rig.matrix_world.to_3x3() @ contacts[label]["handle_axis"]).normalized()
        result["handle_" + label + "_axis_edge_error_m"] = .06 * axis.cross(hand_axis).length
    return result


def skin_sample(body, props, rig, frame, amount, topology_cache=None):
    """Complete real shaft sweep, including rotated landmine and full length."""
    import technique as t
    if "landmine" in props:
        half = props["landmine"]["shaft_half_length_m"]
        return t.bar_surface_sample(body, props["landmine"], frame, amount, rig=rig,
                                    half_width_m=half, sample_count=2 * math.ceil(half / .008) + 1,
                                    topology_cache=topology_cache)
    if "bar" in props:
        half = props["bar"].get("shaft_surface_half_width_m", .70)
        return t.bar_surface_sample(body, props["bar"], frame, amount, rig=rig,
                                    half_width_m=half, sample_count=2 * math.ceil(half / .008) + 1,
                                    topology_cache=topology_cache)
    return None


def surface_audit(exercise_id, props, rig, body, frame, amount, cache):
    if exercise_id == "upright_row":
        # The common renderer inspects this real bar's full .70 m shaft.
        return None
    if exercise_id == "rack_pull":
        knee = rig.matrix_world @ rig.pose.bones["calf_l"].head
        return {"frame": frame, "amount": amount,
                "rack_support": {"bar_center_z_m": props["bar"].location.z,
                                 "knee_z_m": knee.z,
                                 "start_bar_to_knee_height_difference_m": abs(props["bar"].location.z - knee.z) if amount < .0001 else None,
                                 "pin_hold_error_m": abs(props["bar"].location.z - .016 - props["bar"]["rack_pin_top_z"]) if amount < .0001 else 0.},
                "scope": "Actual pin hold and knee height; full shaft inspected independently by common bar-surface-audit"}
    sample = skin_sample(body, props, rig, frame, amount, cache)
    return {"frame": frame, "amount": amount, "full_shaft": sample,
            "scope": "Actual skinned body against complete straight or landmine shaft; source media not imported"}


def validate_surfaces(exercise_id, samples):
    failures = []
    if exercise_id == "rack_pull":
        starts = [row["rack_support"] for row in samples if row["amount"] < .0001]
        if not starts or any(row["start_bar_to_knee_height_difference_m"] > .04 or row["pin_hold_error_m"] > .002 for row in starts):
            failures.append("Knee-height bar support/pin hold is not maintained")
        return {"exercise_id": exercise_id, "sample_count": len(samples), "passed": not failures,
                "failures": failures, "trainerApproved": False,
                "scope": "Pin and knee-height guard; complete shaft skin proof is bar-surface-audit.json"}
    if not samples or any(not row.get("full_shaft") for row in samples):
        failures.append("Complete actual shaft samples missing")
    minimum = min((row["full_shaft"]["central_shaft_min_surface_clearance_m"] for row in samples if row.get("full_shaft")), default=None)
    if minimum is not None and minimum < -.001:
        failures.append("Actual complete shaft intersects skinned athlete")
    return {"exercise_id": exercise_id, "sample_count": len(samples), "minimum_complete_shaft_skin_clearance_m": minimum,
            "passed": not failures, "failures": failures, "trainerApproved": False,
            "scope": "Shaft collision guard; plates, fingers and support pressure additionally require visual review"}
