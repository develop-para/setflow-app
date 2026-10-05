"""Original generic trainers fitted to the actual CC0 athlete's feet.

The sole and upper use foot/ball armature weights. Heel and forefoot therefore
follow their respective native bones during toe-off, rather than rigidly
sliding a shoe beneath an independently rotating bare foot. No source media,
logos, manufacturer geometry, pressure simulation or trainer approval.
"""
import json
import math
_WEIGHT_PROFILES = {}
_SPEC_CACHE = {}


def _validated_indices(raw, vertex_count, expected=None):
    """Fail closed before inspecting any declared actual mesh domain."""
    if not isinstance(raw, list) or not raw or not isinstance(vertex_count, int) or isinstance(vertex_count, bool) or vertex_count < 1:
        raise ValueError("Nonempty actual mesh domain required")
    if any(not isinstance(index, int) or isinstance(index, bool) or not 0 <= index < vertex_count for index in raw) or len(set(raw)) != len(raw):
        raise ValueError("Finite distinct in-bounds actual mesh indices required")
    if expected is not None:
        expected = _validated_indices(expected, vertex_count)
        if set(raw) != set(expected):
            raise ValueError("Complete original actual mesh domain coverage required")
    return raw


def _finite_points(points, minimum=1):
    if len(points) < minimum or any(len(point) != 3 or any(not math.isfinite(value) for value in point) for point in points):
        raise ValueError("Complete finite actual mesh vertices required")
    return points


def _api():
    import bpy
    from mathutils import Vector
    return bpy, Vector


def _hull(points):
    points = sorted(set(tuple(point) for point in points))
    def cross(origin, first, second):
        return (first[0] - origin[0]) * (second[1] - origin[1]) - (first[1] - origin[1]) * (second[0] - origin[0])
    lower, upper = [], []
    for point in points:
        while len(lower) >= 2 and cross(lower[-2], lower[-1], point) <= 0:
            lower.pop()
        lower.append(point)
    for point in reversed(points):
        while len(upper) >= 2 and cross(upper[-2], upper[-1], point) <= 0:
            upper.pop()
        upper.append(point)
    return lower[:-1] + upper[:-1]


def _offset(hull, margin):
    _, V = _api()
    result = []
    for index, point in enumerate(hull):
        previous, following = hull[index - 1], hull[(index + 1) % len(hull)]
        before, after = V((point[0] - previous[0], point[1] - previous[1])), V((following[0] - point[0], following[1] - point[1]))
        first, second = V((before.y, -before.x)).normalized(), V((after.y, -after.x)).normalized()
        outward = (first + second).normalized()
        shifted = V(point) + outward * margin / max(.2, outward.dot(first))
        result.append((shifted.x, shifted.y))
    return result


def _rest_feet(rig, body):
    bpy, _ = _api()
    import motions
    saved = [(bone, bone.matrix_basis.copy()) for bone in rig.pose.bones]
    modifiers = [(modifier, modifier.show_viewport) for modifier in body.modifiers]
    try:
        motions.reset(rig)
        for modifier, _ in modifiers:
            modifier.show_viewport = modifier.show_render
        bpy.context.view_layer.update()
        deps = bpy.context.evaluated_depsgraph_get()
        evaluated = body.evaluated_get(deps)
        mesh = evaluated.to_mesh(preserve_all_data_layers=True, depsgraph=deps)
        try:
            world_to_rig = rig.matrix_world.inverted()
            feet = {}
            profiles = {}
            for label in ("l", "r"):
                groups = {group.index for group in body.vertex_groups if group.name.startswith(("foot_" + label, "ball_" + label))}
                ankle = rig.data.bones["foot_" + label].head_local
                selected = [(index, world_to_rig @ evaluated.matrix_world @ vertex.co) for index, vertex in enumerate(mesh.vertices)
                            if sum(group.weight for group in vertex.groups if group.group in groups) >= .35]
                selected = [(index, point) for index, point in selected if point.z <= ankle.z + .045]
                if len(selected) < 30:
                    raise ValueError("Actual native foot domain missing: " + label)
                feet[label] = selected
                foot_index = body.vertex_groups["foot_" + label].index
                ball_index = body.vertex_groups["ball_" + label].index
                profiles[label] = []
                for index, point in selected:
                    native = {group.group: group.weight for group in mesh.vertices[index].groups}
                    total = native.get(foot_index, 0) + native.get(ball_index, 0)
                    if total > 0:
                        profiles[label].append([*point, native.get(ball_index, 0) / total])
            rig["setflow_trainer_weight_samples_json"] = json.dumps(profiles)
            return feet
        finally:
            evaluated.to_mesh_clear()
    finally:
        for bone, basis in saved:
            bone.matrix_basis = basis
        for modifier, visibility in modifiers:
            modifier.show_viewport = visibility
        bpy.context.view_layer.update()


def _weight(point, rig, label):
    from mathutils.kdtree import KDTree
    key = rig.as_pointer()
    if key not in _WEIGHT_PROFILES:
        profiles = json.loads(rig["setflow_trainer_weight_samples_json"])
        _WEIGHT_PROFILES[key] = {}
        for side, samples in profiles.items():
            tree = KDTree(len(samples))
            for index, sample in enumerate(samples):
                tree.insert(sample[:3], index)
            tree.balance()
            _WEIGHT_PROFILES[key][side] = (samples, tree)
    samples, tree = _WEIGHT_PROFILES[key][label]
    found = tree.find_n(point, 3)
    nearest = [samples[index] for _, index, _ in found]
    weights = [1 / max(.0000001, distance ** 2) for _, _, distance in found]
    amount = sum(sample[3] * weight for sample, weight in zip(nearest, weights)) / sum(weights)
    return 0. if amount < .00001 else 1. if amount > .99999 else amount


def _prepare_body(rig, body):
    """Correct the native foot/ball transition only in this cardio scene.

    The old sole had almost rigid-foot weights anterior to the metatarsal
    joint. A flat ball and lifted heel consequently drove skin below the
    support. Preserve combined foot+ball weight and every other bone weight.
    This does not edit the source blend or any existing exercise export.
    """
    if body.get("setflow_cardio_metatarsal_weights") == 1:
        return
    transform = rig.matrix_world.inverted() @ body.matrix_world
    for label in ("l", "r"):
        foot, ball = body.vertex_groups["foot_" + label], body.vertex_groups["ball_" + label]
        pivot_y = rig.data.bones["ball_" + label].head_local.y
        for vertex in body.data.vertices:
            native = {group.group: group.weight for group in vertex.groups}
            combined = native.get(foot.index, 0) + native.get(ball.index, 0)
            if combined <= .00001:
                continue
            point = transform @ vertex.co
            value = min(1., max(0., (pivot_y + .010 - point.y) / .020))
            amount = value * value * (3 - 2 * value)
            foot.add([vertex.index], combined * (1 - amount), "REPLACE")
            ball.add([vertex.index], combined * amount, "REPLACE")
    body["setflow_cardio_metatarsal_weights"] = 1
    body.data.update()
    body.update_tag(refresh={"DATA"})
    for key in ("setflow_trainer_specs_json", "setflow_trainer_weight_samples_json"):
        if rig.get(key):
            del rig[key]
    _WEIGHT_PROFILES.pop(rig.as_pointer(), None)
    _SPEC_CACHE.pop(rig.as_pointer(), None)
    _api()[0].context.view_layer.update()


def _mesh(name, vertices, faces, rig, label, material):
    bpy, _ = _api()
    data = bpy.data.meshes.new(name + " mesh")
    data.from_pydata(vertices, [], faces)
    data.update()
    obj = bpy.data.objects.new(name, data)
    bpy.context.scene.collection.objects.link(obj)
    obj.matrix_world = rig.matrix_world.copy()
    obj.data.materials.append(material)
    foot = obj.vertex_groups.new(name="foot_" + label)
    ball = obj.vertex_groups.new(name="ball_" + label)
    weights = []
    for index, point in enumerate(vertices):
        amount = _weight(point, rig, label)
        if amount < 1:
            foot.add([index], 1 - amount, "REPLACE")
        if amount > 0:
            ball.add([index], amount, "REPLACE")
        weights.append(amount)
    modifier = obj.modifiers.new("Native foot and forefoot attachment", "ARMATURE")
    modifier.object = rig
    modifier.use_deform_preserve_volume = True
    obj["forefoot_weights_json"] = json.dumps(weights)
    obj["rest_vertices_json"] = json.dumps([list(point) for point in vertices])
    for polygon in data.polygons:
        polygon.use_smooth = True
    return obj


def _specifications(rig, body=None):
    bpy, V = _api()
    body = body or bpy.data.objects["SetflowAthlete.body"]
    _prepare_body(rig, body)
    if rig.as_pointer() in _SPEC_CACHE:
        return _SPEC_CACHE[rig.as_pointer()]
    if rig.get("setflow_trainer_specs_json"):
        specs = json.loads(rig["setflow_trainer_specs_json"])
        _SPEC_CACHE[rig.as_pointer()] = specs
        return specs
    feet = _rest_feet(rig, body)
    specs = {}
    for label, selected in feet.items():
        points = [point for _, point in selected]
        ankle = rig.data.bones["foot_" + label].head_local
        hull = _offset(_hull([(point.x, point.y) for point in points]), .009)
        n = len(hull)
        if n < 6:
            raise ValueError("Actual foot outline is incomplete")
        top = min(point.z for point in points) - .004
        bottom = top - .018
        center_x = sum(point[0] for point in hull) / n
        center_y = sum(point[1] for point in hull) / n
        footprint = [(center_x + (x - center_x) * fraction, center_y + (y - center_y) * fraction)
                     for fraction in (1., .75, .50, .25) for x, y in hull]
        footprint.append((center_x, center_y))
        sole_vertices = []
        for z in (bottom, top):
            for x, y in footprint:
                weight = _weight((x, y, z), rig, label)
                crown = .0035 * math.sin(math.pi * weight) ** 2
                sole_vertices.append((x, y, z + crown))
        # Heel/forefoot anchors are real sole vertices with a single bone
        # influence, not points invented below a visual mesh.
        weights = [_weight(point, rig, label) for point in sole_vertices]
        heel_indices = [index for index in range(n) if weights[index] == 0]
        fore_indices = [index for index in range(n) if weights[index] == 1]
        if not heel_indices or not fore_indices:
            raise ValueError("Distinct attached heel and forefoot surfaces missing")
        heel = max(heel_indices, key=lambda index: (sole_vertices[index][1], -abs(sole_vertices[index][0] - ankle.x)))
        forefoot = min(fore_indices, key=lambda index: (abs(sole_vertices[index][1] - rig.data.bones["ball_" + label].head_local.y), abs(sole_vertices[index][0] - ankle.x)))
        specs[label] = {"hull": hull, "top": top, "sole_vertices": sole_vertices, "bottom_count": len(footprint),
                        "contacts": {"heel": heel, "forefoot": forefoot},
                        "points": [list(point) for point in points],
                        "all_body_indices": [index for index, _ in selected],
                        "body_foot_indices": [index for index, point in selected if point.z < ankle.z - .008]}
    rig["setflow_trainer_specs_json"] = json.dumps(specs)
    _SPEC_CACHE[rig.as_pointer()] = specs
    return specs


def rest_contact(rig, label, kind="heel"):
    """Calibrate lazily before equipment create; returns a real sole landmark."""
    _, V = _api()
    if label not in ("l", "r") or kind not in ("heel", "forefoot"):
        raise ValueError("Unknown native shoe contact")
    spec = _specifications(rig)[label]
    point = V(spec["sole_vertices"][spec["contacts"][kind]])
    bone = ("foot_" if kind == "heel" else "ball_") + label
    return bone, rig.data.bones[bone].matrix_local.inverted() @ point


def create(rig, body=None):
    _, V = _api()
    import equipment
    rubber = equipment.material("Original trainer textured grey sole", (.34, .34, .34))
    textile = equipment.material("Original trainer charcoal upper", (.075, .075, .075))
    props = {}
    for label, spec in _specifications(rig, body).items():
        hull, top, sole_vertices = spec["hull"], spec["top"], spec["sole_vertices"]
        points = [V(point) for point in spec["points"]]
        ankle = rig.data.bones["foot_" + label].head_local
        n = len(hull)
        bottom_count = spec["bottom_count"]
        triangles = []
        for ring in range(3):
            for index in range(n):
                a, b = ring * n + index, ring * n + (index + 1) % n
                c, d = (ring + 1) * n + (index + 1) % n, (ring + 1) * n + index
                triangles.extend(((a, b, c), (a, c, d)))
        triangles.extend((3 * n + index, 3 * n + (index + 1) % n, bottom_count - 1) for index in range(n))
        faces = [tuple(reversed(face)) for face in triangles]
        top_start = len(faces)
        faces.extend(tuple(index + bottom_count for index in face) for face in triangles)
        side_start = len(faces)
        faces.extend((index, (index + 1) % n, (index + 1) % n + bottom_count, index + bottom_count) for index in range(n))
        sole = _mesh("Setflow generic trainer sole " + label, sole_vertices, faces, rig, label, rubber)
        sole["sole_bottom_indices_json"] = json.dumps(list(range(bottom_count)))
        sole["sole_outer_face_indices_json"] = json.dumps(list(range(top_start)) + list(range(side_start, len(faces))))
        sole["contact_vertex_indices_json"] = json.dumps(spec["contacts"])
        sole["body_foot_indices_json"] = json.dumps(spec["body_foot_indices"])
        upper = list(sole_vertices[bottom_count:bottom_count + n])
        for x, y in hull:
            nearby = [point.z for point in points if abs(point.y - y) < .022]
            height = min(max(nearby or [top + .04]) + .010, ankle.z + .004)
            upper.append((x, y, height))
        collar_z = ankle.z + .010
        cuff_x = max(abs(point.x - ankle.x) for point in points if point.z > ankle.z + .005) + .009
        cuff_y = max(abs(point.y - ankle.y) for point in points if point.z > ankle.z + .005) + .009
        for x, y in hull:
            angle = math.atan2(y - ankle.y, x - ankle.x)
            upper.append((ankle.x + cuff_x * math.cos(angle), ankle.y + cuff_y * math.sin(angle), collar_z))
        upper_faces = []
        for band in (0, 1):
            upper_faces.extend((band * n + index, band * n + (index + 1) % n,
                                (band + 1) * n + (index + 1) % n, (band + 1) * n + index) for index in range(n))
        shoe = _mesh("Setflow generic trainer upper " + label, upper, upper_faces, rig, label, textile)
        props["shoe_" + label], props["sole_" + label] = shoe, sole
        from mathutils.bvhtree import BVHTree
        bvh = BVHTree.FromPolygons([V(point) for point in upper], upper_faces)
        lace_material = equipment.material("Original trainer tucked grey laces", (.56, .56, .56))
        for lace_index, offset in enumerate((-.12, -.15, -.18)):
            vertices, faces = [], []
            for edge in (-.002, .002):
                for point_index in range(9):
                    x = ankle.x - .025 + .050 * point_index / 8
                    y = ankle.y + offset + edge
                    hit, _, _, _ = bvh.ray_cast(V((x, y, ankle.z + .20)), V((0, 0, -1)))
                    if hit is None:
                        raise ValueError("Actual trainer upper missing below lace")
                    vertices.append((x, y, hit.z + .0015))
            faces.extend((index, index + 1, index + 10, index + 9) for index in range(8))
            props["lace_" + label + "_" + str(lace_index)] = _mesh("Setflow tucked shoelace " + label + str(lace_index), vertices, faces, rig, label, lace_material)
    update(props, rig)
    return props


def update(props, rig, frame=None):
    bpy, _ = _api()
    for obj in props.values():
        if not obj.get("forefoot_weights_json"):
            continue
        obj.matrix_world = rig.matrix_world.copy()
        if frame is not None:
            obj.keyframe_insert("location", frame=frame)
            obj.keyframe_insert("rotation_euler", frame=frame)
            obj.keyframe_insert("scale", frame=frame)
    bpy.context.view_layer.update()


def _actual_vertices(obj):
    bpy, _ = _api()
    evaluated = obj.evaluated_get(bpy.context.evaluated_depsgraph_get())
    mesh = evaluated.to_mesh()
    try:
        return [evaluated.matrix_world @ vertex.co for vertex in mesh.vertices]
    finally:
        evaluated.to_mesh_clear()


def sole_vertices(props, label, kind=None):
    sole = props["sole_" + label]
    actual = _actual_vertices(sole)
    _finite_points(actual, 30)
    indices = _validated_indices(json.loads(sole["sole_bottom_indices_json"]), len(actual))
    weights = json.loads(sole["forefoot_weights_json"])
    if kind == "heel":
        indices = [index for index in indices if weights[index] <= .1]
    elif kind == "forefoot":
        indices = [index for index in indices if weights[index] >= .9]
    elif kind is not None:
        raise ValueError("Unknown sole domain")
    _validated_indices(indices, len(actual))
    return [actual[index] for index in indices]


def contact_local(props, rig, label, kind="heel"):
    _, V = _api()
    if kind not in ("heel", "forefoot"):
        raise ValueError("Unknown exact sole contact kind")
    sole = props["sole_" + label]
    index = json.loads(sole["contact_vertex_indices_json"])[kind]
    point = V(json.loads(sole["rest_vertices_json"])[index])
    bone = ("foot_" if kind == "heel" else "ball_") + label
    return bone, rig.data.bones[bone].matrix_local.inverted() @ point


def contact_world(props, rig, label, kind="heel"):
    bone, local = contact_local(props, rig, label, kind)
    return rig.matrix_world @ rig.pose.bones[bone].matrix @ local


def attachment_audit(props, rig):
    _, V = _api()
    from mathutils import Quaternion
    def skin_point(point, first, second, amount):
        rotations = [matrix.to_quaternion().normalized() for matrix in (first, second)]
        dual = [Quaternion((0, *matrix.translation)) @ rotation for matrix, rotation in zip((first, second), rotations)]
        if rotations[0].dot(rotations[1]) < 0:
            rotations[1].negate()
            dual[1].negate()
        real = [rotations[0][axis] * (1 - amount) + rotations[1][axis] * amount for axis in range(4)]
        companion = [(dual[0][axis] * (1 - amount) + dual[1][axis] * amount) * .5 for axis in range(4)]
        norm = math.sqrt(sum(value * value for value in real))
        real, companion = [value / norm for value in real], [value / norm for value in companion]
        projection = sum(a * b for a, b in zip(real, companion))
        companion = Quaternion([value - real[axis] * projection for axis, value in enumerate(companion)])
        real = Quaternion(real)
        translation = companion @ real.conjugated()
        return real @ point + V((translation.x, translation.y, translation.z)) * 2
    maximum = 0.
    for label in ("l", "r"):
        for prefix in ("shoe_", "sole_"):
            obj = props[prefix + label]
            actual = _actual_vertices(obj)
            rest = [V(point) for point in json.loads(obj["rest_vertices_json"])]
            weights = json.loads(obj["forefoot_weights_json"])
            _finite_points(actual, 30)
            _finite_points(rest, 30)
            if len(actual) != len(rest) or len(weights) != len(rest) or any(not isinstance(weight, (int, float)) or isinstance(weight, bool) or not math.isfinite(weight) or not 0 <= weight <= 1 for weight in weights):
                raise ValueError("Complete finite native shoe attachment weights required")
            foot = rig.pose.bones["foot_" + label].matrix @ rig.data.bones["foot_" + label].matrix_local.inverted()
            ball = rig.pose.bones["ball_" + label].matrix @ rig.data.bones["ball_" + label].matrix_local.inverted()
            expected = [rig.matrix_world @ skin_point(point, foot, ball, weight) for point, weight in zip(rest, weights)]
            maximum = max(maximum, max((point - target).length for point, target in zip(actual, expected)))
        for kind in ("heel", "forefoot"):
            index = json.loads(props["sole_" + label]["contact_vertex_indices_json"])[kind]
            _validated_indices([index], len(_actual_vertices(props["sole_" + label])))
            maximum = max(maximum, (_actual_vertices(props["sole_" + label])[index] - contact_world(props, rig, label, kind)).length)
    if not math.isfinite(maximum) or maximum < 0:
        raise ValueError("Finite nonnegative actual shoe attachment metric required")
    return {"shoe_native_attachment_max_error_m": maximum}


def foot_enclosure_audit(props, body, details=False):
    bpy, _ = _api()
    from mathutils.bvhtree import BVHTree
    deps = bpy.context.evaluated_depsgraph_get()
    actual_body = _finite_points(_actual_vertices(body), 30)
    rig = bpy.data.objects["SetflowAthlete.rig"]
    specs = _specifications(rig, body)
    result = {}
    for label in ("l", "r"):
        upper = props["shoe_" + label].evaluated_get(deps)
        mesh = upper.to_mesh()
        try:
            points = [upper.matrix_world @ vertex.co for vertex in mesh.vertices]
            _finite_points(points, 30)
            if len(points) % 3:
                raise ValueError("Complete actual trainer upper rings required")
            faces = [tuple(face.vertices) for face in mesh.polygons]
            ring_count = len(points) // 3
            sole = props["sole_" + label]
            sole_points = _finite_points(_actual_vertices(sole), 30)
            offset = len(points)
            outer_indices = set(_validated_indices(json.loads(sole["sole_outer_face_indices_json"]), len(sole.data.polygons)))
            outer_faces = faces + [tuple(offset + index for index in face.vertices) for face in sole.data.polygons if face.index in outer_indices]
            # The upper joins the actual sole's side and underside. The only
            # audit cap closes the open ankle cuff; it is not shoe material.
            all_points = points + sole_points
            closed = BVHTree.FromPolygons(all_points, outer_faces + [tuple(range(2 * ring_count, 3 * ring_count))])
            bvh = BVHTree.FromPolygons(all_points, outer_faces)
            def inside(point):
                votes = 0
                for direction in ((1., .137, .231), (.193, 1., .271), (.171, .213, 1.)):
                    direction = __import__('mathutils').Vector(direction).normalized()
                    origin, crossings = point.copy(), 0
                    for _ in range(32):
                        hit, _, _, _ = closed.ray_cast(origin, direction)
                        if hit is None:
                            break
                        crossings += 1
                        origin = hit + direction * .000001
                    votes += crossings % 2
                return votes >= 2
            maximum = 0.
            worst = None
            spec = specs[label]
            originals = _validated_indices(spec["all_body_indices"], len(actual_body))
            if len(originals) != len(spec["points"]):
                raise ValueError("Actual original foot reference coverage required")
            _finite_points(spec["points"], 30)
            ankle_z = rig.data.bones["foot_" + label].head_local.z
            expected = [index for index, rest in zip(originals, spec["points"]) if rest[2] < ankle_z - .008]
            indices = _validated_indices(json.loads(props["sole_" + label]["body_foot_indices_json"]), len(actual_body), expected)
            for index in indices:
                point = actual_body[index]
                hit, normal, _, distance = bvh.find_nearest(point)
                if hit is None or distance is None or not math.isfinite(distance) or distance < 0:
                    raise ValueError("Actual shoe surface missing")
                if not inside(point):
                    if distance > maximum:
                        maximum = distance
                        worst = {"body_vertex": index, "actual_skin_point": list(point), "nearest_shoe_point": list(hit), "normal": list(normal)}
            result[label + "_foot_outside_shoe_max_m"] = maximum
            result[label + "_actual_enclosure_skin_vertex_count"] = len(indices)
            result[label + "_actual_enclosure_body_mesh_vertex_count"] = len(actual_body)
            if details:
                result[label + "_worst_foot_point"] = worst
        finally:
            upper.to_mesh_clear()
    return result
