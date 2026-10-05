"""Resume deterministic exercise production using explicit, implemented motions.

An inventory entry is not an animation: only exact IDs in motion_registry have
authored implementations. Other catalog rows remain queued until authored.
No app assets are installed by this command; inspect them before registering.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import shutil
import subprocess
from pathlib import Path

from export_media import export, sha256
import motion_registry

PROJECT = Path(__file__).resolve().parents[2]
TOOLS = Path(__file__).resolve().parent
VISUALS = PROJECT / "output/exercise_visuals"
FIRST_BATCH = ("bodyweight_squat", "pushup", "bench", "dumbbell_bench", "deadlift",
               "romanian_deadlift", "row", "curl", "dumbbell_shoulder_press",
               "lateral", "calf_raise", "plank", "crunch")
OUTPUT_VERSIONS = {"bodyweight_squat": "v6", "row": "v2", "bench":"v2",
                   "dumbbell_bench":"v2", "dumbbell_shoulder_press":"v2",
                   "deadlift":"v2", "romanian_deadlift":"v2", "calf_raise":"v2", "pushup":"v2", "plank":"v2",
                   "close_grip_bench":"v2"}
BLENDER_FALLBACK = Path(r"C:\Program Files\Blender Foundation\Blender 4.4\blender.exe")


def select_jobs(catalog: dict, ids: list[str]) -> list[dict]:
    rows = {row["exerciseId"]: row for row in catalog["exercises"]}
    if len(rows) != len(catalog["exercises"]):
        raise ValueError("Duplicate catalog IDs")
    jobs = []
    for exercise_id in ids:
        if not re.fullmatch(r"[A-Za-z0-9_-]+", exercise_id):
            raise ValueError(f"Unsafe output ID: {exercise_id!r}")
        if exercise_id not in rows:
            raise ValueError(f"No such catalog exercise: {exercise_id}")
        if exercise_id != "bodyweight_squat" and exercise_id not in motion_registry.registrations():
            raise ValueError(f"Motion not authored yet: {exercise_id}. Catalog entry remains queued.")
        if exercise_id not in {job["exerciseId"] for job in jobs}:
            jobs.append(rows[exercise_id])
    return jobs


def output_directory(exercise_id: str) -> Path:
    return VISUALS / exercise_id / OUTPUT_VERSIONS.get(exercise_id, "v1")


def frames_directory(exercise_id: str) -> Path:
    # Squat v6 re-exports the established v5 render. All newly rendered motions
    # keep their intermediates under the same revision as their final output.
    version = "v5" if exercise_id == "bodyweight_squat" else OUTPUT_VERSIONS.get(exercise_id, "v1")
    return PROJECT / "artifacts/exercise_visuals" / exercise_id / version / "frames"


def production_sources(exercise_id: str) -> list[Path]:
    import ast
    source_files = [TOOLS / filename for filename in
                    ("render_exercise.py", "motions.py", "anatomy.py", "equipment.py", "export_media.py", "technique.py", "motion_registry.py")]
    if exercise_id != "bodyweight_squat":
        module = motion_registry.registrations()[exercise_id]
        if module != "motions":
            source_files += [TOOLS / (module + ".py"), TOOLS / (module.replace("_motions", "_equipment") + ".py")]
    # Include shared authoring helpers imported by an exact motion owner. This
    # does not pull in other registry owners merely because they are listed.
    seen = set(source_files)
    for source in source_files:
        tree = ast.parse(source.read_text(encoding="utf-8-sig"))
        for node in ast.walk(tree):
            names = [item.name for item in node.names] if isinstance(node, ast.Import) else (
                [node.module] if isinstance(node, ast.ImportFrom) and node.module else [])
            for name in names:
                dependency = TOOLS / (name + ".py")
                if re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", name) and dependency.is_file() and dependency not in seen:
                    seen.add(dependency)
                    source_files.append(dependency)
    source_files += [VISUALS / "bodyweight_squat/v5/squat.blend"]
    source_files += [VISUALS / "bodyweight_squat/v5/highlight_regions.py"]
    return source_files


def fingerprint(exercise_id: str, resolution: int, fps: int, count: int, gif_size: int) -> str:
    settings = {"exerciseId": exercise_id, "resolution": resolution, "fps": fps,
                "frameCount": count, "gifSize": gif_size}
    source_files = production_sources(exercise_id)
    settings["sourceHashes"] = {str(path.relative_to(PROJECT)): sha256(path) for path in source_files}
    return hashlib.sha256(json.dumps(settings, sort_keys=True).encode("utf-8")).hexdigest()


def snapshot_sources(exercise_id: str, signature: str, resolution: int, fps: int,
                     count: int, gif_size: int) -> Path:
    """Keep the exact authoring revision used by each independently reviewed clip."""
    if fingerprint(exercise_id, resolution, fps, count, gif_size) != signature:
        raise ValueError("Authoring sources changed before their snapshot: " + exercise_id)
    directory = VISUALS / "production/source-snapshots" / signature
    manifest_path = directory / "source-manifest.json"
    if manifest_path.is_file():
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        if manifest.get("exerciseId") != exercise_id or manifest.get("renderSourceFingerprint") != signature:
            raise ValueError("Source snapshot identity mismatch: " + exercise_id)
        for record in manifest["sourceFiles"].values():
            path = (PROJECT / record["snapshotPath"]).resolve()
            if not path.is_relative_to(directory.resolve()) or sha256(path) != record["sha256"]:
                raise ValueError("Frozen source snapshot was changed: " + exercise_id)
        for relative, digest in manifest["sharedBodyInputs"].items():
            path = (PROJECT / relative).resolve()
            if not path.is_relative_to(VISUALS.resolve()) or sha256(path) != digest:
                raise ValueError("Shared body input was changed: " + exercise_id)
        return manifest_path
    directory.mkdir(parents=True, exist_ok=True)
    manifest = {"exerciseId": exercise_id, "renderSourceFingerprint": signature,
                "settings": {"resolution": resolution, "fps": fps, "frameCount": count, "gifSize": gif_size},
                "trainerApproved": False, "sourceFiles": {}, "sharedBodyInputs": {}}
    for source in [*production_sources(exercise_id), TOOLS / "run_batch.py"]:
        relative = source.relative_to(PROJECT).as_posix()
        if source.parent != TOOLS:
            manifest["sharedBodyInputs"][relative] = sha256(source)
            continue
        target = directory / source.name
        shutil.copyfile(source, target)
        manifest["sourceFiles"][relative] = {
            "snapshotPath": target.relative_to(PROJECT).as_posix(), "sha256": sha256(target)}
    if fingerprint(exercise_id, resolution, fps, count, gif_size) != signature:
        raise ValueError("Authoring sources changed during their snapshot: " + exercise_id)
    temporary = manifest_path.with_suffix(".json.writing")
    temporary.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    temporary.replace(manifest_path)
    return manifest_path


def can_resume(directory: Path, signature: str) -> bool:
    path = directory / "production-state.json"
    if not path.is_file():
        return False
    try:
        state = json.loads(path.read_text(encoding="utf-8"))
        if not isinstance(state, dict) or state.get("fingerprint") != signature or state.get("status") != "rendered":
            return False
        files = state.get("files")
        if not isinstance(files, dict) or not files:
            return False
        return all(isinstance(name, str) and Path(name).name == name
                   and (directory / name).is_file() and sha256(directory / name) == value
                   for name, value in files.items())
    except (OSError, ValueError, TypeError):
        # A stopped write or corrupt state must cause a rerender, never prevent
        # recovery or skip a partially produced exercise.
        return False


def save_state(directory: Path, exercise_id: str, signature: str) -> None:
    names = ["exercise.mp4", "exercise.gif", "pose-start.png", "pose-middle.png", "pose-peak.png",
             "media.json", "contact-sheet.png"]
    if exercise_id != "bodyweight_squat":
        names += ["exercise.blend", "motion-audit.json", "motion-validation.json", "highlight-audit.json", "skin-floor-audit.json"]
        names += [name for name in ("technique-reference.json", "technique-validation.json",
                                   "equipment-surface-audit.json", "equipment-surface-validation.json")
                  if (directory / name).is_file() and exercise_id != "row"]
        if exercise_id != "row" and (directory / "bar-surface-audit.json").is_file():
            names.append("bar-surface-audit.json")
    if exercise_id == "row":
        names += ["technique-reference.json", "technique-validation.json", "bar-surface-audit.json"]
    state = {"exerciseId": exercise_id, "fingerprint": signature,
             "status": "rendered", "trainerReview": "pending",
             "files": {name: sha256(directory / name) for name in names}}
    temporary = directory / "production-state.json.writing"
    temporary.write_text(json.dumps(state, indent=2) + "\n", encoding="utf-8")
    temporary.replace(directory / "production-state.json")


def run_job(job: dict, blender: Path, mode: str, resolution: int, fps: int,
            frame_count: int, gif_size: int, resume: bool, ffmpeg: str | None) -> None:
    exercise_id = job["exerciseId"]
    directory = output_directory(exercise_id)
    signature = fingerprint(exercise_id, resolution, fps, frame_count, gif_size)
    snapshot_sources(exercise_id, signature, resolution, fps, frame_count, gif_size)
    if mode == "all" and resume and can_resume(directory, signature):
        print(f"Resume: verified existing export for {exercise_id}", flush=True)
        return
    if exercise_id == "bodyweight_squat":
        # Preserve the established v5 artwork and its native source. v1-v5 are
        # historical prototypes; v6 is just a smaller app export of v5 motion.
        frames = frames_directory(exercise_id)
        if mode == "all":
            export(frames, directory, exercise_id, job["name"], 96, 24, 640, gif_size, 2, ffmpeg)
            save_state(directory, exercise_id, signature)
        else:
            print(f"Existing source/poses: {VISUALS / 'bodyweight_squat/v5'}", flush=True)
        return
    if not blender.is_file():
        raise FileNotFoundError(f"Blender unavailable: {blender}")
    frames = frames_directory(exercise_id)
    command = [str(blender), "--background", "--factory-startup", "--threads", "8",
               "--python-exit-code", "1", "--python", str(TOOLS / "render_exercise.py"), "--",
               "--exercise", exercise_id, "--output", str(directory), "--frames", str(frames),
               "--mode", mode, "--resolution", str(resolution), "--fps", str(fps),
               "--frame-count", str(frame_count)]
    log = PROJECT / "artifacts/exercise_visuals/production" / f"{exercise_id}.log"
    log.parent.mkdir(parents=True, exist_ok=True)
    print(f"Render: {exercise_id} ({job['name']}); diagnostics: {log.relative_to(PROJECT)}", flush=True)
    with log.open("w", encoding="utf-8") as diagnostics:
        subprocess.run(command, cwd=PROJECT, stdout=diagnostics, stderr=subprocess.STDOUT, check=True)
    if mode == "all":
        export(frames, directory, exercise_id, job["name"], frame_count, fps, resolution, gif_size, 1, ffmpeg)
        if fingerprint(exercise_id, resolution, fps, frame_count, gif_size) != signature:
            raise ValueError("Authoring sources changed during production; export remains unverified: " + exercise_id)
        save_state(directory, exercise_id, signature)
    print(f"Complete: {exercise_id} ({mode}; trainer review pending)", flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--catalog", type=Path, default=VISUALS / "catalog.json")
    parser.add_argument("--ids", nargs="+", default=list(FIRST_BATCH))
    parser.add_argument("--all-authored", action="store_true", help="Render all exact IDs with authored motion implementations")
    parser.add_argument("--list", action="store_true", help="List jobs without rendering")
    parser.add_argument("--mode", choices=("all", "poses", "source"), default="all")
    parser.add_argument("--resume", action="store_true", help="Only skip exact sources/settings/media with matching hashes")
    parser.add_argument("--blender", type=Path, default=Path(shutil.which("blender") or BLENDER_FALLBACK))
    parser.add_argument("--resolution", type=int, default=480)
    parser.add_argument("--fps", type=int, default=12)
    parser.add_argument("--frame-count", type=int, default=48)
    parser.add_argument("--gif-size", type=int, default=384)
    parser.add_argument("--ffmpeg")
    args = parser.parse_args()
    if args.resolution < 64 or args.resolution % 2 or args.frame_count < 12 or args.fps < 3:
        parser.error("Use even resolution >=64, frame count >=12 and fps >=3 to include the return hold")
    if args.frame_count != args.fps * 4:
        parser.error("Motions use a four-second loop: --frame-count must equal --fps * 4")
    if args.gif_size < 32 or args.gif_size > args.resolution:
        parser.error("Use GIF dimensions between 32 and render resolution")
    catalog = json.loads(args.catalog.read_text(encoding="utf-8"))
    ids = ["bodyweight_squat", *motion_registry.registrations()] if args.all_authored else args.ids
    jobs = select_jobs(catalog, ids)
    if args.list:
        print(json.dumps([{"exerciseId": job["exerciseId"], "name": job["name"]} for job in jobs], ensure_ascii=False, indent=2))
        return
    for job in jobs:
        run_job(job, args.blender.resolve(), args.mode, args.resolution, args.fps,
                args.frame_count, args.gif_size, args.resume, args.ffmpeg)


if __name__ == "__main__":
    main()
