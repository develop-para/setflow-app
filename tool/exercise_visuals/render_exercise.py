"""Render native, deterministic exercise drafts with the v5 CC0 athlete.

Example: blender -b --python tool/exercise_visuals/render_exercise.py --
 --exercise curl --output output/exercise_visuals/curl/v1
 --frames artifacts/exercise_visuals/curl/v1/frames --mode poses
"""
import argparse
import json
import math
import sys
from pathlib import Path

import bpy
from mathutils import Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
import motions
import anatomy
import equipment
import technique
import motion_registry as registry

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "output/exercise_visuals/bodyweight_squat/v5"))
import highlight_regions as old_regions


def arguments():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--exercise", choices=tuple(registry.registrations()), required=True)
    parser.add_argument("--human", type=Path, default=ROOT / "output/exercise_visuals/bodyweight_squat/v5/squat.blend")
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--frames", type=Path, required=True)
    parser.add_argument("--mode", choices=("source", "poses", "animation", "all"), default="all")
    parser.add_argument("--resolution", type=int, default=480)
    parser.add_argument("--fps", type=int, default=12)
    parser.add_argument("--frame-count", type=int, default=48)
    return parser.parse_args(sys.argv[sys.argv.index("--") + 1:])


def aim(camera, exercise_id):
    low = exercise_id in ("pushup", "plank", "crunch", "bench", "dumbbell_bench")
    target = Vector((0, 0.07 if low else -0.02, 0.37 if low else 0.88))
    camera.location = Vector((3.8, -4.7, 2.1 if low else 2.4))
    camera.rotation_euler = (target - camera.location).to_track_quat("-Z", "Y").to_euler()
    camera.data.ortho_scale = 2.22 if low else 2.30
    if exercise_id in ("bench", "dumbbell_bench"):
        target = Vector((0, 0.30, 0.55))
        camera.location = (3.8, 4.7, 2.5)
        camera.rotation_euler = (target - camera.location).to_track_quat("-Z", "Y").to_euler()
        camera.data.ortho_scale = 2.70
    if exercise_id in ("row", "calf_raise", "deadlift", "romanian_deadlift"):
        camera.location = (4.8, 3.4, 2.3)
        camera.rotation_euler = (target - camera.location).to_track_quat("-Z", "Y").to_euler()
        camera.data.ortho_scale = 2.45 if exercise_id in ("row", "deadlift", "romanian_deadlift") else 2.30
    if exercise_id == "dumbbell_shoulder_press":
        target = Vector((0, -0.02, 1.02))
        camera.rotation_euler = (target - camera.location).to_track_quat("-Z", "Y").to_euler()
        camera.data.ortho_scale = 2.60
    if exercise_id == "calf_raise":
        target = Vector((0, 0.02, 1.03))
        camera.rotation_euler = (target - camera.location).to_track_quat("-Z", "Y").to_euler()
        camera.data.ortho_scale = 2.65
    if exercise_id == "plank":
        target = Vector((0, 0.10, 0.27))
        camera.location = (5.0, -2.0, 0.65)
        camera.rotation_euler = (target - camera.location).to_track_quat("-Z", "Y").to_euler()
        camera.data.ortho_scale = 2.15
    if exercise_id == "row":
        # Show the wrist and abdominal bar target instead of hiding both
        # behind the athlete's back. The separate review views show the back.
        target = Vector((0, -0.06, 0.75))
        camera.location = (4.8, -3.2, 1.95)
        camera.rotation_euler = (target - camera.location).to_track_quat("-Z", "Y").to_euler()
        camera.data.ortho_scale = 2.40
    custom = registry.view(exercise_id)
    if custom:
        target = Vector(custom["target"])
        camera.location = custom["location"]
        camera.rotation_euler = (target - camera.location).to_track_quat("-Z", "Y").to_euler()
        camera.data.ortho_scale = custom["ortho_scale"]


def validation(audit, rig, exercise_id):
    def distance(a, b):
        return (Vector(a) - Vector(b)).length
    loop, translation = technique.native_loop_delta(audit)
    length_ranges = []
    for name in rig.pose.bones.keys():
        lengths = [distance(row["bones"][name]["head"], row["bones"][name]["tail"]) for row in audit]
        length_ranges.append(max(lengths) - min(lengths))
    fixed = registry.fixed_contacts(exercise_id)
    foot_drift = max((distance(audit[0]["bones"][name]["head"],
                               row["bones"][name]["head"])
                      for row in audit for name in fixed), default=0)
    contact_errors = [value for row in audit for value in row["equipment_contacts"].values()]
    if any(not isinstance(value, (int, float)) or isinstance(value, bool)
           or not math.isfinite(value) or value < 0 for value in contact_errors):
        raise ValueError("Equipment contact errors must be finite nonnegative distances")
    grip = max(contact_errors, default=0)
    floor_heights = [row["equipment_floor_clearance_m"] for row in audit if row["equipment_floor_clearance_m"] is not None]
    clearance = min(floor_heights, default=None)
    joint_gap=technique.connected_joint_gap(audit)
    result = {"loop_joint_max_delta_m": loop, "root_motion_cycle_translation_m": translation,
              "bone_length_max_range_m": max(length_ranges),
              "fixed_contact_max_drift_m": foot_drift, "equipment_grip_max_error_m": grip,
              "fixed_contact_bones": fixed,
              "connected_joint_max_gap_m": joint_gap,
              "equipment_min_floor_clearance_m": clearance,
              "review_status": "Trainer review pending", "motion_capture": False}
    if loop > 0.00001 or max(length_ranges) > 0.00001 or foot_drift > 0.0001 or joint_gap > .0001 or grip > 0.002 or (clearance is not None and clearance < -0.001):
        raise ValueError("Motion geometry validation failed: " + json.dumps(result))
    return result


def main():
    args = arguments()
    if args.fps < 3 or args.frame_count != args.fps * 4:
        raise ValueError("Exercise cycles are exactly four seconds: frame-count must equal fps * 4")
    args.output, args.frames = args.output.resolve(), args.frames.resolve()
    args.output.mkdir(parents=True, exist_ok=True)
    args.frames.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.open_mainfile(filepath=str(args.human.resolve()))
    scene = bpy.context.scene
    bpy.context.preferences.filepaths.save_version = 0
    rig = bpy.data.objects["SetflowAthlete.rig"]
    for obj in scene.objects:
        obj.animation_data_clear()
    scene.timeline_markers.clear()
    modifiers = [(modifier, modifier.show_viewport) for obj in scene.objects if obj.type == "MESH" for modifier in obj.modifiers]
    for modifier, visibility in modifiers:
        modifier.show_viewport = False
    props = registry.create(args.exercise, rig)
    cycle_translation = rig.matrix_world.to_3x3() @ Vector(registry.cycle_translation(args.exercise))
    tracking = cycle_translation.length > 0
    aim(scene.camera, args.exercise)
    tracking_objects = [scene.camera, *(obj for obj in scene.objects if obj.type == "LIGHT")] if tracking else []
    tracking_locations = {obj: obj.location.copy() for obj in tracking_objects}
    if tracking and not (registry.view(args.exercise) or {}).get("track_root"):
        raise ValueError("A translating motion requires an explicitly selected tracking view")
    audit = []
    for frame in range(1, args.frame_count + 1):
        seconds = (frame - 1) / args.fps
        amount = registry.phase(args.exercise, seconds)
        contacts = registry.pose(rig, args.exercise, amount)
        registry.apply(args.exercise, props, contacts, rig, frame)
        progress = Vector((0, 0, 0))
        if tracking:
            if "root_translation" not in contacts:
                raise ValueError("A translating pose must record its armature root_translation")
            progress = rig.matrix_world.to_3x3() @ Vector(contacts["root_translation"])
            for obj in tracking_objects:
                obj.location = tracking_locations[obj] + progress
                obj.keyframe_insert("location", frame=frame)
        audit.append({"frame": frame, "seconds": seconds, "amount": amount,
                      "bones": motions.bone_audit(rig),
                      **({"root_motion_cycle_translation_m": list(cycle_translation),
                          "root_motion_translation_m": list(progress)} if tracking else {}),
                      "equipment_floor_clearance_m": equipment.floor_clearance(props),
                      "equipment_contacts": registry.contacts_audit(args.exercise, props, contacts, rig)})
        for bone in rig.pose.bones:
            bone.keyframe_insert("location", frame=frame)
            bone.keyframe_insert("rotation_quaternion", frame=frame)
            bone.keyframe_insert("scale", frame=frame)
    for obj in [rig, *props.values(), *tracking_objects]:
        if obj.animation_data and obj.animation_data.action:
            for curve in obj.animation_data.action.fcurves:
                for key in curve.keyframe_points:
                    key.interpolation = "LINEAR"
    for modifier, visibility in modifiers:
        modifier.show_viewport = visibility
    (args.output / "motion-audit.json").write_text(json.dumps(audit, indent=2), encoding="utf-8")
    body=bpy.data.objects["SetflowAthlete.body"]
    floor_samples=[]
    floor_cache={}
    for row in audit:
        scene.frame_set(row["frame"])
        floor_samples.append(technique.skin_floor_sample(body,row["frame"],floor_cache))
    (args.output/"skin-floor-audit.json").write_text(json.dumps(floor_samples,indent=2),encoding="utf-8")
    if min(sample["skin_min_floor_m"] for sample in floor_samples)<-.001:
        raise ValueError("Animated athlete skin intersects floor")
    if args.exercise in ("pushup","plank"):
        domain="hand" if args.exercise=="pushup" else "forearm"
        if max(sample[domain+"_"+label+"_min_floor_m"] for sample in floor_samples for label in ("l","r"))>.003:
            raise ValueError("Weight-bearing surface floats above floor")
    custom_surfaces = []
    surface_cache = {}
    for row in audit:
        scene.frame_set(row["frame"])
        sample = registry.surface_audit(args.exercise, props, rig, body, row["frame"], row["amount"], surface_cache)
        if sample is not None:
            if not isinstance(sample, dict) or sample.get("frame") != row["frame"]:
                raise ValueError("Equipment surface inspection must identify the actual frame")
            custom_surfaces.append(sample)
    if custom_surfaces:
        if len(custom_surfaces) != len(audit):
            raise ValueError("Equipment surface inspection must cover every native frame")
        (args.output / "equipment-surface-audit.json").write_text(json.dumps(custom_surfaces, indent=2), encoding="utf-8")
        surface_report = registry.validate_surfaces(args.exercise, custom_surfaces)
        (args.output / "equipment-surface-validation.json").write_text(json.dumps(surface_report, indent=2), encoding="utf-8")
    if "bar" in props and props["bar"].get("surface_check_shaft"):
        body = bpy.data.objects["SetflowAthlete.body"]
        surface_samples = []
        topology_cache={}
        shaft_half_width = max(.19, float(props["bar"].get("shaft_surface_half_width_m", .19)))
        shaft_samples = max(49, 2 * math.ceil(24 * shaft_half_width / .19) + 1)
        for row in audit:
            scene.frame_set(row["frame"])
            surface_samples.append(technique.bar_surface_sample(
                body, props["bar"], row["frame"], row["amount"], rig=rig,topology_cache=topology_cache,
                half_width_m=shaft_half_width, sample_count=shaft_samples))
            if row["frame"]%24==0:
                print(f"Skin clearance checked: {row['frame']}/{args.frame_count}",flush=True)
        (args.output / "bar-surface-audit.json").write_text(json.dumps(surface_samples, indent=2), encoding="utf-8")
        clearance=min(sample["central_shaft_min_surface_clearance_m"] for sample in surface_samples)
        if clearance < -.001:
            raise ValueError("Bar shaft enters athlete skin: " + str(clearance))
        if args.exercise=="row":
            technique_report = technique.validate_row(audit, surface_samples, raise_on_failure=False)
            (args.output / "technique-validation.json").write_text(json.dumps(technique_report, indent=2), encoding="utf-8")
            if not technique_report["passed"]:
                raise ValueError("Barbell row technique check failed: " + json.dumps(technique_report))
    report = registry.validate(args.exercise, audit)
    if report:
        (args.output / "technique-validation.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
    reference = registry.reference(args.exercise)
    if reference:
        (args.output / "technique-reference.json").write_text(json.dumps({**reference,
            "review_status": "Trainer review pending; numerical checks do not certify exercise technique"}, indent=2), encoding="utf-8")
    selected = registry.regions(args.exercise)
    highlight = {}
    for name in ("SetflowAthlete.body", "SetflowAthlete.training-briefs"):
        obj = bpy.data.objects[name]
        highlight[name] = anatomy.apply(obj, rig, selected, old_regions)
        for slot in obj.material_slots:
            if slot.material:
                slot.material = old_regions.highlight_material(slot.material)
    old_regions.soft_glow(scene)
    scene["Exercise ID"] = args.exercise
    scene["Review status"] = "Trainer review pending."
    scene["Muscle guide"] = ", ".join(selected) + "; educational surface guide, not measured activation."
    scene.frame_start, scene.frame_end = 1, args.frame_count
    scene.render.fps = args.fps
    scene.render.resolution_x = scene.render.resolution_y = args.resolution
    scene.render.resolution_percentage = 100
    scene.eevee.taa_render_samples = 32
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGB"
    if not tracking:
        aim(scene.camera, args.exercise)
    selected_poses = registry.pose_seconds(args.exercise)
    poses = tuple((name, min(args.frame_count, round(second * args.fps) + 1))
                  for name, second in selected_poses.items()) if selected_poses else (
                      ("start", 1), ("middle", round(args.fps * 1.1) + 1),
                      ("peak", round(args.fps * 1.9) + 1))
    for name, frame in poses:
        scene.timeline_markers.new(name.upper(), frame=frame)
    scene.frame_set(1)
    scene.render.filepath = str(args.frames / "frame_")
    bpy.ops.wm.save_as_mainfile(filepath=str(args.output / "exercise.blend"))
    (args.output / "motion-audit.json").write_text(json.dumps(audit, indent=2), encoding="utf-8")
    (args.output / "motion-validation.json").write_text(json.dumps(validation(audit, rig, args.exercise), indent=2), encoding="utf-8")
    (args.output / "highlight-audit.json").write_text(json.dumps({"regions": selected, "objects": highlight,
       "color_linear_rgba": old_regions.COLOR, "purpose": "Educational surface guide, not measured activation",
       "method": "Original rest-mesh point attributes deforming with the CC0 athlete skin weights"}, indent=2), encoding="utf-8")
    version = int(args.output.name[1:]) if args.output.name.startswith("v") and args.output.name[1:].isdigit() else 1
    (args.output / "metadata.json").write_text(json.dumps({"exercise_id": args.exercise, "version": version,
       "body_version": 5, "fps": args.fps, "frame_count": args.frame_count, "duration_seconds": args.frame_count / args.fps,
       "resolution": args.resolution, "regions": selected, "review_status": "trainer_pending",
       "asset_source": "CC0 MakeHuman body; Setflow original sculpt, animation and equipment",
       "source_body": "bodyweight_squat/v5/squat.blend"}, indent=2), encoding="utf-8")
    if args.exercise == "row":
        (args.output / "technique-reference.json").write_text(json.dumps({
            "variant": "Overhand bent-over barbell row toward the abdomen",
            "reference": "https://www.acefitness.org/resources/everyone/exercise-library/12/bent-over-row/",
            "reference_cues": ["Hip hinge", "Slight knee bend", "Extended elbows at start",
                               "Flat back maintained", "Pull toward belly button", "Controlled lowering"],
            "model_specific_values": {"pelvis_rotation_deg": 65, "grip_half_width_armature_m": 0.21},
            "values_are_not_universal_prescriptions": True,
            "scapula_representation": "Small clavicle rotations; this rig has no independent scapula bones",
            "review_status": "Trainer review pending; numerical checks do not certify exercise technique",
            "inspection_views": "Side view hides plates, collars and sleeves to expose wrist/bar; app video retains full equipment",
        }, indent=2), encoding="utf-8")
    if args.mode in ("poses", "all"):
        for name, frame in poses:
            scene.frame_set(frame)
            scene.render.filepath = str(args.output / ("pose-" + name + ".png"))
            bpy.ops.render.render(write_still=True)
        if args.exercise == "row":
            camera = scene.camera
            location, rotation, scale = camera.location.copy(), camera.rotation_euler.copy(), camera.data.ortho_scale
            target = Vector((0, -0.08, 0.74))
            for view, position in (("side", (5, 0, 0.90)), ("back", (4.8, 3.4, 2.0))):
                camera.location = position
                camera.rotation_euler = (target - camera.location).to_track_quat("-Z", "Y").to_euler()
                camera.data.ortho_scale = 2.40
                # Plates obscure the wrist and bar in an exact side view.
                # Hide only plates/collars for this labelled inspection view;
                # the actual app video retains every equipment part.
                hidden = []
                if view == "side":
                    hidden = [(obj, obj.hide_render) for obj in props["bar"].children_recursive
                              if "plate" in obj.name.lower() or "collar" in obj.name.lower() or "sleeve" in obj.name.lower()]
                    for obj, previous in hidden:
                        obj.hide_render = True
                for name, frame in poses:
                    scene.frame_set(frame)
                    scene.render.filepath = str(args.output / ("review-" + view + "-" + name + ".png"))
                    bpy.ops.render.render(write_still=True)
                for obj, previous in hidden:
                    obj.hide_render = previous
            camera.location, camera.rotation_euler, camera.data.ortho_scale = location, rotation, scale
    if args.mode in ("animation", "all"):
        scene.render.filepath = str(args.frames / "frame_")
        bpy.ops.render.render(animation=True)
    print("SETFLOW_RENDER_COMPLETE " + args.exercise)


if __name__ == "__main__":
    main()
