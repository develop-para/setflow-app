"""Independent, exercise-specific production checks for teaching drafts.

These guards reject obvious defects such as the original row's partly flexed
start, bent wrists, deep squat and shaft entering the abdomen. Passing them is
not trainer approval. Numeric limits describe this selected animation variant.
The core metrics use only Python's standard library, so unit tests need neither
Blender nor third-party math packages. Blender helpers import their dependencies
only when called, and inspect the actual evaluated, skinned body surface.
"""

import math


def subtract(a, b):
    return tuple(x - y for x, y in zip(a, b))


def length(value):
    return math.sqrt(sum(component * component for component in value))


def angle_degrees(a, b):
    denominator = length(a) * length(b)
    if denominator <= 1e-12:
        raise ValueError("Cannot measure an angle of a zero-length bone")
    cosine = sum(x * y for x, y in zip(a, b)) / denominator
    return math.degrees(math.acos(max(-1.0, min(1.0, cosine))))


def joint(row, name, part="head"):
    return row["bones"][name][part]


def bend_degrees(row, upper, lower):
    proximal = subtract(joint(row, upper), joint(row, upper, "tail"))
    distal = subtract(joint(row, lower, "tail"), joint(row, lower))
    return 180.0 - angle_degrees(proximal, distal)


def midpoint(a, b):
    return tuple((x + y) / 2 for x, y in zip(a, b))


def native_loop_delta(audit):
    """Compare periodic anatomy, with only an explicitly declared root cycle.

    Moving walks retain world-space stance contacts and translate their camera.
    The whole skeleton must repeat relative to the declared translation; a
    changed limb endpoint cannot be hidden by translating the pelvis alone.
    """
    if not audit:
        raise ValueError("No native loop frames")
    declared = [row.get("root_motion_cycle_translation_m", (0, 0, 0)) for row in audit]
    for value in declared:
        if not isinstance(value, (tuple, list)) or len(value) != 3 or any(
                isinstance(part, bool) or not isinstance(part, (int, float)) or not math.isfinite(part)
                for part in value):
            raise ValueError("Invalid native cycle translation")
    translation = tuple(declared[0])
    if any(tuple(value) != translation for value in declared):
        raise ValueError("Native cycle translation changes between frames")
    if any(translation):
        progress = [row.get("root_motion_translation_m") for row in audit]
        for value in progress:
            if not isinstance(value, (tuple, list)) or len(value) != 3 or any(
                    not isinstance(part, (int, float)) or isinstance(part, bool) or not math.isfinite(part)
                    for part in value):
                raise ValueError("Root motion requires recorded progress on every frame")
        if length(progress[0]) > 1e-5 or length(subtract(progress[-1], translation)) > 1e-5:
            raise ValueError("Root progress does not match the declared cycle endpoints")
    first, last = audit[0]["bones"], audit[-1]["bones"]
    if not first or set(first) != set(last):
        raise ValueError("Native loop bone sets differ")
    for row in audit:
        if set(row["bones"]) != set(first):
            raise ValueError("Native frame bone sets differ")
        for record in row["bones"].values():
            for part in ("head", "tail"):
                value = record[part]
                if not isinstance(value, (list, tuple)) or len(value) != 3 or any(
                        isinstance(coordinate, bool) or not isinstance(coordinate, (int, float))
                        or not math.isfinite(coordinate) for coordinate in value):
                    raise ValueError("Nonfinite or invalid native bone coordinates")
    delta = max(length(subtract(subtract(last[name][part], first[name][part]), translation))
                for name in first for part in ("head", "tail"))
    if not math.isfinite(delta):
        raise ValueError("Nonfinite native loop coordinates")
    return delta, translation


def connected_joint_gap(audit):
    """Bone lengths alone cannot catch a detached elbow from projected IK."""
    pairs=(("upperarm","lowerarm"),("lowerarm","hand"),("thigh","calf"),("calf","foot"))
    if not audit:
        raise ValueError("No motion frames")
    return max(length(subtract(joint(row,upper+"_"+label,"tail"),joint(row,lower+"_"+label)))
               for row in audit for upper,lower in pairs for label in ("l","r"))


def skin_floor_sample(body,frame,domain_cache):
    """Actual animated skin coordinates, including thumb and forearm surfaces."""
    import bpy
    import numpy as np
    deps=bpy.context.evaluated_depsgraph_get()
    evaluated=body.evaluated_get(deps)
    mesh=evaluated.to_mesh(preserve_all_data_layers=True,depsgraph=deps)
    try:
        coordinates=np.empty(len(mesh.vertices)*3,dtype=np.float32)
        mesh.vertices.foreach_get("co",coordinates)
        matrix=evaluated.matrix_world
        heights=coordinates.reshape(-1,3) @ np.asarray(matrix[2][:3])+matrix[2][3]
        key=(body.as_pointer(),len(mesh.vertices))
        domains=domain_cache.get(key)
        if domains is None:
            domains={}
            for label in ("l","r"):
                for domain,prefixes in (("hand",("hand_","thumb_","index_","middle_","ring_","pinky_")),("forearm",("lowerarm_",))):
                    indices={g.index for g in body.vertex_groups if g.name.startswith(prefixes) and g.name.endswith("_"+label)}
                    domains[domain+"_"+label]=np.asarray([v.index for v in mesh.vertices if sum(g.weight for g in v.groups if g.group in indices)>=.5],dtype=np.int32)
            domain_cache[key]=domains
        return {"frame":frame,"skin_min_floor_m":float(heights.min()),
                **{domain+"_min_floor_m":float(heights[indices].min()) for domain,indices in domains.items() if len(indices)}}
    finally:
        evaluated.to_mesh_clear()


def row_metrics(audit):
    if not audit:
        raise ValueError("No recorded frames to evaluate")
    starts = [row for row in audit if row.get("amount", 0) <= 0.001]
    peaks = [row for row in audit if row.get("amount", 0) >= 0.999]
    if not starts or not peaks:
        raise ValueError("Row audit must contain both fully lowered and fully raised poses")
    wrists, knees, torsos, elbow_x = [], [], [], []
    start_elbows, start_forearms, peak_elbows = [], [], []
    for row in audit:
        hips = midpoint(joint(row, "thigh_l"), joint(row, "thigh_r"))
        shoulders = midpoint(joint(row, "upperarm_l"), joint(row, "upperarm_r"))
        torsos.append(90 - angle_degrees(subtract(shoulders, hips), (0, 0, 1)))
        for label in ("l", "r"):
            upper = "upperarm_" + label
            lower = "lowerarm_" + label
            forearm = subtract(joint(row, lower, "tail"), joint(row, lower))
            palm_axis = subtract(joint(row, "middle_01_" + label), joint(row, "hand_" + label))
            wrists.append(angle_degrees(forearm, palm_axis))
            knees.append(bend_degrees(row, "thigh_" + label, "calf_" + label))
            elbow_x.append(abs(joint(row, lower)[0] - joint(row, "hand_" + label)[0]))
            if row.get("amount", 0) <= 0.001:
                start_elbows.append(bend_degrees(row, upper, lower))
                start_forearms.append(angle_degrees(forearm, (0, 0, -1)))
            if row.get("amount", 0) >= 0.999:
                peak_elbows.append(bend_degrees(row, upper, lower))
    stationary = ("pelvis", "spine_01", "spine_02", "spine_03", "neck_01", "head")
    fixed_drift = max(length(subtract(joint(row, name, part), joint(audit[0], name, part)))
                      for row in audit for name in stationary for part in ("head", "tail"))
    return {
        "wrist_axis_max_deviation_deg": max(wrists),
        "start_elbow_max_bend_deg": max(start_elbows),
        "start_forearm_max_angle_from_vertical_deg": max(start_forearms),
        "peak_elbow_min_bend_deg": min(peak_elbows),
        "peak_elbow_max_bend_deg": max(peak_elbows),
        "knee_min_bend_deg": min(knees),
        "knee_max_bend_deg": max(knees),
        "knee_bend_range_deg": max(knees) - min(knees),
        "torso_min_angle_from_horizontal_deg": min(torsos),
        "torso_max_angle_from_horizontal_deg": max(torsos),
        "fixed_trunk_and_head_max_drift_m": fixed_drift,
        "elbow_to_wrist_lateral_max_offset_m": max(elbow_x),
    }


def validate_row(audit, surface_samples=(), raise_on_failure=True):
    metrics = row_metrics(audit)
    failures = []
    checks = (
        (metrics["wrist_axis_max_deviation_deg"] <= 5, "Wrist bends more than five degrees from the forearm"),
        (metrics["start_elbow_max_bend_deg"] <= 6, "Lowered row starts with flexed elbows"),
        (metrics["start_forearm_max_angle_from_vertical_deg"] <= 8, "Lowered forearms do not hang beneath the shoulders"),
        (15 <= metrics["knee_min_bend_deg"] and metrics["knee_max_bend_deg"] <= 35, "This row variant needs a slight knee bend, not a deep squat"),
        (metrics["knee_bend_range_deg"] <= 0.1, "Knees change angle during the pull"),
        (15 <= metrics["torso_min_angle_from_horizontal_deg"] and metrics["torso_max_angle_from_horizontal_deg"] <= 40, "Torso hinge does not match the reviewed row variant"),
        (metrics["fixed_trunk_and_head_max_drift_m"] <= 0.0001, "Trunk or head moves to throw the weight"),
        (metrics["elbow_to_wrist_lateral_max_offset_m"] <= 0.025, "Elbows flare away from the vertical grip plane"),
        (75 <= metrics["peak_elbow_min_bend_deg"] and metrics["peak_elbow_max_bend_deg"] <= 140, "Raised row has implausibly little or excessive elbow flexion"),
    )
    failures.extend(reason for passed, reason in checks if not passed)
    if surface_samples:
        clearance = min(sample["central_shaft_min_surface_clearance_m"] for sample in surface_samples)
        metrics["central_shaft_min_surface_clearance_m"] = clearance
        metrics["surface_checked_frames"] = [sample["frame"] for sample in surface_samples]
        if clearance < -0.001:
            failures.append("Actual bar shaft intersects the skinned torso surface")
        palm_alignments = [sample["overhand_palmar_alignment_min"] for sample in surface_samples
                           if "overhand_palmar_alignment_min" in sample]
        if palm_alignments:
            metrics["overhand_palmar_alignment_min"] = min(palm_alignments)
            if min(palm_alignments) < 0.98:
                failures.append("Actual palm orientation does not match the overhand row grip")
        peak_gaps = [sample["abdominal_landmark_distance_m"] for sample in surface_samples
                     if sample.get("amount", 0) >= 0.999 and "abdominal_landmark_distance_m" in sample]
        if peak_gaps:
            metrics["peak_abdominal_landmark_max_distance_m"] = max(peak_gaps)
            if max(peak_gaps) > 0.10:
                failures.append("Peak bar position misses the abdominal target region")
    report = {"exercise_id": "row", "metrics": metrics, "passed": not failures,
              "failures": failures, "scope": "Animation production checks; trainer review pending"}
    if failures and raise_on_failure:
        raise ValueError("Barbell row technique check failed: " + "; ".join(failures))
    return report


def landmark_world(rig, point):
    """Rigid torso landmark; valid while all spinal bones share the hip hinge."""
    from mathutils import Vector
    deform = rig.pose.bones["pelvis"].matrix @ rig.data.bones["pelvis"].matrix_local.inverted()
    return rig.matrix_world @ (deform @ Vector(point))


def shaft_clearance(unsigned_body_distance_m, signed_full_mesh_distance_m,
                    nearest_full_face_is_hand, radius_m=0.016):
    """Keep full closed-surface sign; hand contact uses other skin proximity.

    Removing hand polygons opens a wrist boundary. Its remaining forearm
    normals cannot classify points near the omitted hand as inside/outside.
    The complete mesh supplies the sign only when its nearest surface is body
    skin. A nearest hand/finger surface denotes the intentional gripping area;
    there, the unsigned proximity to all remaining body skin still catches a
    shaft physically touching the torso, thighs or forearms.
    """
    distance = unsigned_body_distance_m if nearest_full_face_is_hand else signed_full_mesh_distance_m
    return distance - radius_m


def overhand_palmar_alignment(rig):
    """Read actual hand rotations; neutral hand axes alone cannot prove grip."""
    from mathutils import Vector
    scores = []
    for label in ("l", "r"):
        rest = rig.data.bones
        forward = (rest["middle_01_" + label].head_local - rest["hand_" + label].head_local).normalized()
        side = (rest["index_01_" + label].head_local - rest["pinky_01_" + label].head_local).normalized()
        normal = forward.cross(side).normalized()
        if label == "r":
            normal.negate()
        transform = rig.pose.bones["hand_" + label].matrix @ rest["hand_" + label].matrix_local.inverted()
        actual = (rig.matrix_world.to_3x3() @ transform.to_3x3() @ normal).normalized()
        forearm = rig.pose.bones["lowerarm_" + label]
        axis = (rig.matrix_world.to_3x3() @ (forearm.tail - forearm.head)).normalized()
        expected = Vector((1, 0, 0)).cross(axis).normalized()
        scores.append(actual.dot(expected))
    return min(scores)


def bar_surface_sample(body, bar, frame=None, amount=None, radius_m=0.016,
                       half_width_m=0.19, sample_count=49, rig=None,
                       rest_abdominal_landmark=(0, -0.1061723, 1.0554256), topology_cache=None):
    """Inspect the central shaft, excluding intentional contact inside the grips.

    Clearance is nearest signed skin distance minus the real shaft radius.
    A whole centre-line only check misses shallow intersections. The helper
    evaluates skin weights/subdivision first, then builds a world-space BVH.
    Faces predominantly skinned to hands/fingers are excluded by their real
    vertex weights: holding the bar is intentional contact. Torso, thighs and
    forearms remain in the collision mesh regardless of their X coordinate.
    The complete mesh supplies the local inside/outside sign. Removing hands
    leaves holes at the wrist, so the body-only mesh is used for unsigned
    proximity, never for an inside/outside classification. This is a local
    collision guard, not a universal inside-mesh classifier.
    """
    import bpy
    from mathutils import Vector
    from mathutils.bvhtree import BVHTree

    bpy.context.view_layer.update()
    evaluated = body.evaluated_get(bpy.context.evaluated_depsgraph_get())
    depsgraph = bpy.context.evaluated_depsgraph_get()
    mesh = evaluated.to_mesh(preserve_all_data_layers=True, depsgraph=depsgraph)
    try:
        coordinates = [evaluated.matrix_world @ vertex.co for vertex in mesh.vertices]
        # This athlete has fixed topology/skin weights: only coordinates
        # animate. Reuse classification, but rebuild both deformed BVHs for
        # every frame. Callers using changing topology must omit the cache.
        key=(body.as_pointer(),len(mesh.vertices),len(mesh.polygons))
        cached=topology_cache.get(key) if topology_cache is not None else None
        if cached is None:
            hand_indices = {group.index for group in body.vertex_groups
                            if group.name.startswith(("hand_", "index_", "middle_", "ring_", "pinky_", "thumb_"))}
            hand_weights = [sum(entry.weight for entry in vertex.groups if entry.group in hand_indices)
                            for vertex in mesh.vertices]
            polygons,full_polygons,full_face_is_hand=[],[],[]
            excluded_hand_faces=0
            for face in mesh.polygons:
                vertices=tuple(face.vertices)
                is_hand=sum(hand_weights[index] for index in vertices)/len(vertices)>=.5
                full_polygons.append(vertices)
                full_face_is_hand.append(is_hand)
                if is_hand: excluded_hand_faces+=1
                else: polygons.append(vertices)
            cached=(polygons,full_polygons,full_face_is_hand,excluded_hand_faces)
            if topology_cache is not None: topology_cache[key]=cached
        polygons,full_polygons,full_face_is_hand,excluded_hand_faces=cached
        bvh = BVHTree.FromPolygons(coordinates, polygons, all_triangles=False)
        full_bvh = BVHTree.FromPolygons(coordinates, full_polygons, all_triangles=False)
        center = bar.matrix_world.translation.copy()
        axis = (bar.matrix_world.to_3x3() @ Vector((1, 0, 0))).normalized()
        samples = []
        for index in range(sample_count):
            offset = -half_width_m + 2 * half_width_m * index / (sample_count - 1)
            point = center + axis * offset
            hit, normal, face, distance = bvh.find_nearest(point)
            if hit is None:
                raise ValueError("No body surface available for bar clearance check")
            full_hit, full_normal, full_face, full_distance = full_bvh.find_nearest(point)
            full_signed = full_distance if (point - full_hit).dot(full_normal) >= 0 else -full_distance
            closest_is_hand = full_face_is_hand[full_face]
            clearance = shaft_clearance(distance, full_signed, closest_is_hand, radius_m)
            samples.append({"axis_offset_m": offset,
                            "nearest_full_skin_domain": "hand_or_fingers" if closest_is_hand else "body",
                            "signed_full_skin_distance_m": full_signed,
                            "unsigned_body_skin_distance_m": distance,
                            "shaft_surface_clearance_m": clearance})
        result = {"frame": frame if frame is not None else bpy.context.scene.frame_current,
                  "bar_center_world": list(center), "shaft_radius_m": radius_m,
                  "checked_half_width_m": half_width_m,
                  "excluded_hand_and_finger_faces": excluded_hand_faces,
                  "checked_body_faces": len(polygons),
                  "central_shaft_min_surface_clearance_m": min(item["shaft_surface_clearance_m"] for item in samples),
                  "samples": samples}
        if amount is not None:
            result["amount"] = amount
        if rig is not None:
            landmark = landmark_world(rig, rest_abdominal_landmark)
            result["abdominal_landmark_world"] = list(landmark)
            result["abdominal_landmark_distance_m"] = (center - landmark).length
            result["overhand_palmar_alignment_min"] = overhand_palmar_alignment(rig)
        return result
    finally:
        evaluated.to_mesh_clear()
