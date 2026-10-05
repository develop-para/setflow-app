"""Exact-ID motion ownership, shared by production and Blender dispatch.

Registrations describe authored movements, not name-based guesses. Importing
this index requires no Blender; modules are loaded only for a chosen motion.
"""
from importlib import import_module
from pathlib import Path
from functools import lru_cache

BASE = ("pushup", "bench", "dumbbell_bench", "deadlift", "romanian_deadlift",
        "row", "curl", "dumbbell_shoulder_press", "lateral", "calf_raise", "plank", "crunch")
MODULES = ("strength_motions", "bodyweight_motions", "accessory_motions",
           "bodyweight_extra_motions", "cable_extra_motions", "freeweight_extra_motions",
           "machine_motions", "machine_extra_motions", "machine_sled_motions",
           "cardio_motions", "cardio_extra_motions",
           "remaining_strength_motions", "remaining_strength_extra_motions",
           "remaining_bodyweight_motions", "remaining_cable_motions")
_ROOT = Path(__file__).resolve().parent


@lru_cache(maxsize=1)
def registrations():
    # Module declarations are JSON-compatible literals in each authored
    # source. Read them without importing bpy in the orchestration process.
    import ast
    result = {exercise_id: "motions" for exercise_id in BASE}
    for module in MODULES:
        source = _ROOT / (module + ".py")
        if not source.is_file():
            continue
        tree = ast.parse(source.read_text(encoding="utf-8-sig"))
        supported = None
        for node in tree.body:
            if isinstance(node, ast.Assign) and any(isinstance(target, ast.Name) and target.id == "SUPPORTED" for target in node.targets):
                supported = ast.literal_eval(node.value)
        if supported is None:
            raise ValueError(f"{module} must declare literal SUPPORTED exact IDs")
        for exercise_id in supported:
            if exercise_id in result:
                raise ValueError(f"Motion ownership collision: {exercise_id}")
            result[exercise_id] = module
    return result


def owner(exercise_id):
    owners = registrations()
    if exercise_id not in owners:
        raise ValueError("Motion not authored yet: " + exercise_id)
    return import_module(owners[exercise_id])


def pose(rig, exercise_id, amount):
    import motions
    module = owner(exercise_id)
    if module.__name__ != "motions":
        motions.reset(rig)
    return module.pose(rig, exercise_id, amount)


def create(exercise_id, rig):
    module = owner(exercise_id)
    equipment_module = "equipment" if module.__name__ == "motions" else module.__name__.replace("_motions", "_equipment")
    return import_module(equipment_module).create(exercise_id, rig)


def apply(exercise_id, props, contacts, rig, frame):
    import equipment
    module = owner(exercise_id)
    equipment_module = "equipment" if module.__name__ == "motions" else module.__name__.replace("_motions", "_equipment")
    custom = import_module(equipment_module)
    if custom is not equipment and hasattr(custom, "apply"):
        custom.apply(props, contacts, rig, frame)
    else:
        equipment.apply(props, contacts, rig, frame)


def phase(exercise_id, seconds):
    import motions
    module = owner(exercise_id)
    return module.phase(exercise_id, seconds) if hasattr(module, "phase") else motions.cycle(seconds)


def regions(exercise_id):
    module = owner(exercise_id)
    if module.__name__ == "motions":
        import anatomy
        return anatomy.REGIONS[exercise_id]
    return module.REGIONS[exercise_id]


def fixed_contacts(exercise_id):
    module = owner(exercise_id)
    if module.__name__ == "motions":
        prefix = "ball" if exercise_id == "calf_raise" else "foot"
        return (prefix + "_l", prefix + "_r")
    # Moving feet and aerial poses need explicitly selected contacts.
    return module.FIXED_CONTACTS[exercise_id]


def view(exercise_id):
    return getattr(owner(exercise_id), "VIEWS", {}).get(exercise_id)


def reference(exercise_id):
    return getattr(owner(exercise_id), "REFERENCES", {}).get(exercise_id)


def pose_seconds(exercise_id):
    """Read selected proof phases without importing Blender's bpy module."""
    import ast
    import math
    module = registrations().get(exercise_id)
    if module is None:
        return None
    tree = ast.parse((_ROOT / (module + ".py")).read_text(encoding="utf-8-sig"))
    declarations = [node for node in tree.body if isinstance(node, ast.Assign) and any(
        isinstance(target, ast.Name) and target.id == "POSE_SECONDS" for target in node.targets)]
    if len(declarations) > 1:
        raise ValueError("POSE_SECONDS must have one literal declaration: " + module)
    if not declarations:
        return None
    values = ast.literal_eval(declarations[0].value)
    if not isinstance(values, dict):
        raise ValueError("POSE_SECONDS must map exact IDs to proof phases: " + module)
    selected = values.get(exercise_id)
    if selected is None:
        return None
    if not isinstance(selected, dict) or set(selected) != {"start", "middle", "peak"} or any(
            isinstance(second, bool) or not isinstance(second, (int, float)) or
            not math.isfinite(second) or not 0 <= second < 4 for second in selected.values()):
        raise ValueError("Proof phases require start/middle/peak seconds within the four-second loop: " + exercise_id)
    return selected


def equipment_owner(exercise_id):
    module = owner(exercise_id)
    name = "equipment" if module.__name__ == "motions" else module.__name__.replace("_motions", "_equipment")
    return import_module(name)


def contacts_audit(exercise_id, props, contacts, rig):
    import equipment
    custom = equipment_owner(exercise_id)
    return getattr(custom, "contacts_audit", equipment.contacts_audit)(props, contacts, rig)


def surface_audit(exercise_id, props, rig, body, frame, amount, cache):
    inspect = getattr(equipment_owner(exercise_id), "surface_audit", None)
    return inspect(exercise_id, props, rig, body, frame, amount, cache) if inspect else None


def validate_surfaces(exercise_id, samples):
    inspect = getattr(equipment_owner(exercise_id), "validate_surfaces", None)
    if inspect is None:
        raise ValueError("Custom surface inspection requires an explicit validator: " + exercise_id)
    report = inspect(exercise_id, samples)
    if not isinstance(report, dict) or report.get("passed") is not True:
        raise ValueError("Equipment/skin surface validation failed: " + str(report))
    return report


def cycle_translation(exercise_id):
    import math
    value = getattr(owner(exercise_id), "CYCLE_TRANSLATION", {}).get(exercise_id, (0, 0, 0))
    if not isinstance(value, (tuple, list)) or len(value) != 3 or any(
            isinstance(part, bool) or not isinstance(part, (int, float)) or not math.isfinite(part)
            for part in value):
        raise ValueError("Cycle translation requires three finite armature coordinates: " + exercise_id)
    return tuple(value)


def validate(exercise_id, audit):
    module = owner(exercise_id)
    if hasattr(module, "audit"):
        report = module.audit(audit, exercise_id)
        if report is None:
            return None
        if not report.get("passed"):
            raise ValueError(f"{exercise_id} technique guard failed: {report}")
        return report
    return None
