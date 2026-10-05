"""Original wheel/axle and dumbbells, with actual posed support inspection."""
import math
import bpy
from mathutils import Quaternion, Vector
import equipment as e


def create(exercise_id, rig):
    props = {}
    if exercise_id == "walking_lunge":
        props["l"], props["r"] = e.dumbbell("l"), e.dumbbell("r")
        marks = bpy.data.objects.new("Original stationary walking floor marks", None)
        bpy.context.scene.collection.objects.link(marks)
        marks.matrix_world = rig.matrix_world.copy()
        paint = e.material("Walking floor reference paint", (.31, .31, .31))
        for index in range(-12, 13):
            bpy.ops.mesh.primitive_plane_add(size=1)
            line = bpy.context.object
            line.name = "Stationary walking stride reference " + str(index)
            line.parent = marks
            line.location = (0, .35 + .86 * index, .00002)
            line.scale = (1.04, .012, 1)
            line.data.materials.append(paint)
        props["floor_markers"] = marks
    elif exercise_id == "ab_wheel":
        rubber = e.material("Original rollout wheel graphite", (.04, .04, .04))
        steel = e.material("Original rollout axle steel", (.23, .23, .23), .7)
        bar = bpy.data.objects.new("Original ab wheel handle axle", None)
        bpy.context.scene.collection.objects.link(bar)
        bar["surface_check_shaft"] = True
        bar["shaft_surface_half_width_m"] = .25
        e.cylinder("Closed-grip rollout axle", .016, .60, steel, bar)
        for side in (-1, 1):
            e.cylinder("Rollout rubber hand grip " + str(side), .018, .16, rubber, bar, side * .215)
        props["bar"] = bar
        wheel = bpy.data.objects.new("Original rolling ab wheel", None)
        bpy.context.scene.collection.objects.link(wheel)
        e.cylinder("Original rollout tire", .13, .065, rubber, wheel)
        spokes = bpy.data.objects.new("Visible rolling wheel spokes", None)
        bpy.context.scene.collection.objects.link(spokes)
        spokes.parent = wheel
        for side in (-1, 1):
            for degrees in (0, 60, 120):
                spoke = e.cube("Original rollout wheel spoke", (side * .034, 0, 0), (.008, .195, .012), steel)
                spoke.parent = spokes
                spoke.rotation_euler.x = math.radians(degrees)
        wheel["radius_m"] = .13
        props["wheel"], props["spokes"] = wheel, spokes
        e.cube("Original supported-knee rollout mat", (0, .20, -.003), (.72, 1.12, .014), rubber)
        for side in (-1, 1):
            e.cube("Original fixed rollout knee pad " + str(side), (side * .112, -.012, .004), (.175, .235, .008), rubber)
    elif exercise_id != "burpee":
        raise ValueError("No remaining bodyweight equipment: " + exercise_id)
    return props


def apply(props, contacts, rig, frame=None):
    e.apply(props, contacts, rig, frame)
    if "wheel" in props:
        wheel = props["wheel"]
        wheel.location = props["bar"].location.copy()
        if "start_y" not in wheel:
            wheel["start_y"] = wheel.location.y
        # The tire is rotationally symmetric. Spokes record visible rolling
        # without treating a rotated square bounding box as tire penetration.
        props["spokes"].rotation_mode = "QUATERNION"
        props["spokes"].rotation_quaternion = Quaternion((1, 0, 0), (float(wheel["start_y"]) - wheel.location.y) / float(wheel["radius_m"]))
        if frame is not None:
            wheel.keyframe_insert("location", frame=frame)
            props["spokes"].keyframe_insert("rotation_quaternion", frame=frame)
    bpy.context.view_layer.update()


def contacts_audit(props, contacts, rig):
    report = e.contacts_audit(props, contacts, rig)
    if "wheel" in props:
        report["wheel_axle_alignment_error_m"] = (props["wheel"].location - props["bar"].location).length
        report["wheel_floor_contact_error_m"] = abs(props["wheel"].location.z - float(props["wheel"]["radius_m"]))
    return report


def surface_audit(exercise_id, props, rig, body, frame, amount, cache):
    import numpy as np
    deps = bpy.context.evaluated_depsgraph_get()
    evaluated = body.evaluated_get(deps)
    mesh = evaluated.to_mesh(preserve_all_data_layers=True, depsgraph=deps)
    try:
        raw = np.empty(len(mesh.vertices) * 3, dtype=np.float32)
        mesh.vertices.foreach_get("co", raw)
        matrix = np.array(evaluated.matrix_world)
        coords = raw.reshape(-1, 3) @ matrix[:3, :3].T + matrix[:3, 3]
        key = ("remaining_body_support", body.as_pointer(), len(mesh.vertices))
        domains = cache.get(key)
        if domains is None:
            domains = {}
            for label in ("l", "r"):
                for domain, prefixes in (("foot", ("foot_", "ball_")), ("shin", ("calf_",)), ("leg", ("thigh_", "calf_")),
                                         ("hand", ("hand_", "thumb_", "index_", "middle_", "ring_", "pinky_"))):
                    groups = {g.index for g in body.vertex_groups if g.name.startswith(prefixes) and g.name.endswith("_" + label)}
                    domains[domain + "_" + label] = np.array([v.index for v in mesh.vertices if sum(g.weight for g in v.groups if g.group in groups) >= .5], dtype=np.int32)
            cache[key] = domains
        support = {}
        if exercise_id == "ab_wheel":
            for label in ("l", "r"):
                knee = np.array(rig.matrix_world @ rig.pose.bones["calf_" + label].head)
                ankle = np.array(rig.matrix_world @ rig.pose.bones["calf_" + label].tail)
                axis = (ankle - knee) / np.linalg.norm(ankle - knee)
                leg = coords[domains["leg_" + label]]
                shin = coords[domains["shin_" + label]]
                knee_patch = leg[np.linalg.norm(leg - knee, axis=1) <= .13]
                distance = (shin - knee) @ axis
                shin_patch = shin[(distance >= .15) & (distance <= np.linalg.norm(ankle - knee) - .05)]
                support["knee_" + label + "_mat_clearance_m"] = float(knee_patch[:, 2].min()) - .008
                support["shin_" + label + "_mat_clearance_m"] = float(shin_patch[:, 2].min()) - .004
        elif exercise_id == "walking_lunge":
            index = min(1, int(amount * 2)); local = amount * 2 - index
            leading = "l" if index == 0 else "r"
            if local >= .22:
                support["planted_front_foot_floor_m"] = float(coords[domains["foot_" + leading], 2].min())
            if .22 <= local <= .60:
                rear = "r" if leading == "l" else "l"
                support["planted_rear_forefoot_floor_m"] = float(coords[domains["foot_" + rear], 2].min())
        else:
            if .24 <= amount <= .64:
                for label in ("l", "r"):
                    support["supporting_hand_" + label + "_floor_m"] = float(coords[domains["hand_" + label], 2].min())
            if .34 <= amount <= .54 or amount >= .88 or amount <= .24 or .64 <= amount <= .76:
                for label in ("l", "r"):
                    support["supporting_foot_" + label + "_floor_m"] = float(coords[domains["foot_" + label], 2].min())
        result = {"frame": frame, "amount": amount, "skin_min_floor_m": float(coords[:, 2].min()), "support": support}
        if exercise_id == "burpee" and .76 < amount < .88:
            result["airborne_foot_min_floor_m"] = min(float(coords[domains["foot_" + label], 2].min()) for label in ("l", "r"))
        if "wheel" in props:
            result["wheel_floor_contact_error_m"] = abs(props["wheel"].location.z - float(props["wheel"]["radius_m"]))
        return result
    finally:
        evaluated.to_mesh_clear()


def validate_surfaces(exercise_id, samples):
    floor = min(row["skin_min_floor_m"] for row in samples)
    support = max((abs(value) for row in samples for value in row["support"].values()), default=0)
    wheel = max((row.get("wheel_floor_contact_error_m", 0) for row in samples), default=0)
    jump = max((row.get("airborne_foot_min_floor_m", 0) for row in samples), default=0)
    return {"exercise_id": exercise_id, "passed": floor >= -.001 and support <= .003 and wheel <= .0001 and (exercise_id != "burpee" or jump >= .10),
            "minimum_skin_floor_m": floor, "maximum_support_surface_clearance_m": support, "wheel_floor_contact_error_m": wheel,
            "peak_actual_both_feet_airborne_clearance_m": jump,
            "trainerApproved": False, "scope": "Actual evaluated skin and weight-bearing knee/shin/hand/foot surface contacts"}
