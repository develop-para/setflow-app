"""Independently decode completed exports without changing production sources.

python tool/exercise_visuals/audit_exports.py --ids row bench plank
Without --ids, inspect only valid completed exports selected by build_preview.
All results go to JSON; a missing requested ID or any failed check exits 1.
OpenCV, NumPy and Pillow must already be installed. No assets are installed.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
import re
from datetime import datetime, timezone
from pathlib import Path

import cv2
import numpy as np
from PIL import Image

from build_preview import load_exports
from export_media import load_rgb, sha256
from technique import native_loop_delta

PROJECT = Path(__file__).resolve().parents[2]
MEDIA_FILES = ("exercise.mp4", "exercise.gif", "pose-start.png", "pose-middle.png",
               "pose-peak.png", "contact-sheet.png")
STATIC_IDS = frozenset(("plank", "side_plank", "wall_sit"))
LOOP_MEAN_LIMIT = 0.5  # Absolute RGB levels on a 0..255 scale, not normalized.
LOOP_LARGE_PIXEL_THRESHOLD = 16
LOOP_LARGE_PIXEL_FRACTION_LIMIT = 0.005
# v6 squat re-exports the unchanged, established v5 scene/96 PNG sequence.
# Its production-state contains export hashes only. Pin the original native
# source explicitly, rather than silently claiming native-state coverage.
ESTABLISHED_SQUAT_V5 = {
    "squat.blend": "d8c9c3283b7aeb20c3de46d744c28179fe8440a05c9bcddc5461f2554c0926cd",
    "motion-audit.json": "7bf31f0357dd7132779afb5b06299afeb3754bcf0ae2260406a1e78420e654a0",
    "highlight-audit.json": "c34704e5c814cd3e024c1b64eb144034704dde6d11c0f0e0f4ecc589de6a137d",
    "source-manifest.json": "f95840e49640396aa943ea29ec5aed31a76704acd439783090fc4a0bf5636bf3",
    "sculpt-audit.json": "6d6c7a1455c969506d2529770c78e594c53e1d86679cde1e05e1c3fd001d1b85",
}


def require(condition, message):
    if not condition:
        raise ValueError(message)


def read_object(path):
    value = json.loads(path.read_text(encoding="utf-8"))
    require(isinstance(value, dict), "JSON object required: " + str(path))
    return value


def integer(value, field):
    require(isinstance(value, int) and not isinstance(value, bool) and value > 0,
            "Positive integer required: " + field)
    return value


def selected_directory(visuals, exercise_id, relative):
    require(re.fullmatch(r"[A-Za-z0-9_-]+", exercise_id) is not None,
            "Unsafe exercise ID")
    parts = Path(relative).parts
    require(len(parts) == 2 and parts[0] == exercise_id
            and re.fullmatch(r"v[0-9]+", parts[1]) is not None,
            "Export directory must match its exact exercise ID/version")
    directory = (visuals / relative).resolve()
    require(directory.is_relative_to(visuals.resolve()), "Export outside visual root")
    return directory


def audit_hashes(directory, item, visuals):
    records = item.get("files")
    require(isinstance(records, dict), "Missing media file hash records")
    for name in MEDIA_FILES:
        record = records.get(name)
        path = directory / name
        require(isinstance(record, dict) and path.is_file(), "Missing media file: " + name)
        require(record.get("bytes") == path.stat().st_size
                and record.get("sha256") == sha256(path), "Media hash/bytes drift: " + name)
    state = read_object(directory / "production-state.json")
    require(state.get("status") == "rendered" and state.get("exerciseId") == item["exerciseId"],
            "Production state does not identify this completed exact ID")
    files = state.get("files")
    require(isinstance(files, dict), "Missing production-state file hashes")
    required = {*MEDIA_FILES, "media.json"}
    if item["exerciseId"] != "bodyweight_squat":
        required.update(("exercise.blend", "motion-audit.json", "highlight-audit.json"))
    require(required <= set(files), "Production state is missing native/media/audit hashes: "
            + ", ".join(sorted(required - set(files))))
    for name, expected in files.items():
        require(isinstance(name, str) and Path(name).name == name
                and not any(character in name for character in ("/", "\\", ":"))
                and name not in (".", ".."), "Unsafe production-state filename")
        path = directory / name
        require(path.is_file() and sha256(path) == expected,
                "Production-state hash drift: " + name)
    legacy = {}
    if item["exerciseId"] == "bodyweight_squat":
        original = visuals / "bodyweight_squat/v5"
        for name, expected in ESTABLISHED_SQUAT_V5.items():
            require((original / name).is_file() and sha256(original / name) == expected,
                    "Established squat v5 source hash drift: " + name)
            legacy[name] = expected
    return {"mediaFilesVerified": len(MEDIA_FILES), "productionStateFilesVerified": len(files),
            "nativeHashSource": "pinned_established_v5" if legacy else "production-state.json",
            "establishedV5Hashes": legacy}


def audit_native_loop(path, frame_count):
    rows = json.loads(path.read_text(encoding="utf-8"))
    require(isinstance(rows, list) and len(rows) == frame_count, "Native audit frame count mismatch")
    delta, _ = native_loop_delta(rows)
    require(math.isfinite(delta) and delta <= 1e-5, f"Native bone loop delta {delta}m exceeds 1e-5m")
    return delta


def loop_comparison(first, last, label):
    require(first.shape == last.shape, label + " loop dimensions differ")
    error = np.abs(first.astype(np.int16) - last.astype(np.int16))
    mean = float(error.mean())
    fraction = float(np.any(error > LOOP_LARGE_PIXEL_THRESHOLD, axis=2).mean())
    require(mean <= LOOP_MEAN_LIMIT and fraction <= LOOP_LARGE_PIXEL_FRACTION_LIMIT,
            f"{label} loop mean/fraction {mean:.6f}/{fraction:.6f} exceeds "
            f"{LOOP_MEAN_LIMIT}/{LOOP_LARGE_PIXEL_FRACTION_LIMIT}")
    return {"meanAbsoluteRgbError": mean, "largeErrorPixelFraction": fraction,
            "largePixelThreshold": LOOP_LARGE_PIXEL_THRESHOLD, "maxChannelError": int(error.max()),
            "pixelsExactlyEqual": bool(np.array_equal(first, last))}


def audit_video(path, frames, frame_count, size, fps, max_mean_error):
    require(set(p.name for p in frames.glob("frame_*.png"))
            == {f"frame_{n:04d}.png" for n in range(1, frame_count + 1)},
            "Original PNG sequence must contain exactly the expected numbered frames")
    capture = cv2.VideoCapture(str(path))
    require(capture.isOpened(), "MP4 cannot be opened/decoded")
    try:
        actual_fps = capture.get(cv2.CAP_PROP_FPS)
        require(math.isfinite(actual_fps) and abs(actual_fps - fps) <= 0.001,
                f"MP4 fps mismatch: {actual_fps} vs {fps}")
        errors = []
        source_hashes = []
        first_video = last_video = None
        first_source = last_source = None
        while True:
            readable, bgr = capture.read()
            if not readable:
                break
            index = len(errors) + 1
            require(index <= frame_count, "MP4 has more frames than the original sequence")
            require(bgr.shape == (size, size, 3), f"MP4 frame {index} dimensions mismatch")
            rgb = cv2.cvtColor(bgr, cv2.COLOR_BGR2RGB)
            with load_rgb(frames / f"frame_{index:04d}.png") as image:
                require(image.size == (size, size), f"Original PNG {index} dimensions mismatch")
                source = np.asarray(image)
                source_hashes.append(hashlib.sha256(source.tobytes()).hexdigest())
                error = float(np.abs(rgb.astype(np.int16) - source.astype(np.int16)).mean())
                errors.append(error)
                if index == 1:
                    first_video, first_source = rgb.copy(), source.copy()
                last_video, last_source = rgb.copy(), source.copy()
        require(len(errors) == frame_count, f"MP4 decoded frame count {len(errors)} vs {frame_count}")
        require(max(errors) <= max_mean_error,
                f"MP4 frame/PNG pixel mean error {max(errors):.6f} exceeds {max_mean_error}")
        source_loop = loop_comparison(first_source, last_source, "Original PNG")
        decoded_loop = loop_comparison(first_video, last_video, "Decoded MP4")
        sequence_digest = hashlib.sha256("\n".join(source_hashes).encode()).hexdigest()
        return {"decodedFrames": len(errors), "size": size, "fps": actual_fps,
                "maxFrameMeanError": max(errors), "meanFrameMeanError": float(np.mean(errors)),
                "worstFrame": int(np.argmax(errors)) + 1, "sourceSequencePixelSha256": sequence_digest,
                "sourceLoop": source_loop, "decodedLoop": decoded_loop}
    finally:
        capture.release()


def audit_gif(path, size, is_static):
    with Image.open(path) as animation:
        require(animation.format == "GIF", "GIF file has a different format")
        require(animation.info.get("loop") == 0, "GIF must repeat indefinitely (loop=0)")
        duration = 0
        unique = set()
        first = last = None
        for number in range(animation.n_frames):
            animation.seek(number)
            animation.load()
            require(animation.size == (size, size), f"GIF frame {number + 1} dimensions mismatch")
            milliseconds = animation.info.get("duration", 0)
            require(isinstance(milliseconds, (int, float)) and milliseconds > 0,
                    "GIF has missing/nonpositive frame duration")
            duration += milliseconds
            with animation.convert("RGB") as frame:
                digest = hashlib.sha256(frame.tobytes()).hexdigest()
                unique.add(digest)
                if number == 0:
                    first = np.asarray(frame).copy()
                last = np.asarray(frame).copy()
        require(abs(duration - 4000) <= 10, f"GIF duration {duration}ms vs 4000ms")
        decoded_loop = loop_comparison(first, last, "Decoded GIF")
        if not is_static:
            require(animation.n_frames >= 12 and len(unique) >= 12,
                    f"Dynamic GIF needs >=12 distinct decoded frames; got {animation.n_frames}/{len(unique)}")
        return {"decodedFrames": animation.n_frames, "distinctPixelFrames": len(unique),
                "durationMilliseconds": duration, "loop": 0, "decodedLoop": decoded_loop,
                "staticPoseException": is_static}


def audit_one(item, visuals, frames_root, expected_frames=96, max_mean_error=3.0):
    eid = item["exerciseId"]
    directory = selected_directory(visuals, eid, item["directory"])
    count = integer(item.get("frameCount"), "frameCount")
    fps = integer(item.get("fps"), "fps")
    size = integer(item.get("videoSize"), "videoSize")
    gif_size = integer(item.get("gifSize"), "gifSize")
    require(count == expected_frames, f"Export frameCount {count} vs requested {expected_frames}")
    require(count == fps * 4 and item.get("durationSeconds") == 4,
            "Export must have a four-second loop matching its original fps metadata")
    require(size in (480, 640), "Only original 480/established 640 pixel renders accepted")
    frames_version = "v5" if eid == "bodyweight_squat" else directory.name
    frames = frames_root / eid / frames_version / "frames"
    result = {"exerciseId": eid, "directory": item["directory"], "originalFrames": str(frames),
              "trainerReview": "pending", "approved": False}
    result["hashes"] = audit_hashes(directory, item, visuals)
    native_audit = (visuals / "bodyweight_squat/v5/motion-audit.json"
                    if eid == "bodyweight_squat" else directory / "motion-audit.json")
    result["nativeLoopMaxDeltaMeters"] = audit_native_loop(native_audit, count)
    native_samples = json.loads(native_audit.read_text(encoding="utf-8"))
    result["nativeCycleTranslationMeters"] = native_samples[0].get(
        "root_motion_cycle_translation_m", [0.0, 0.0, 0.0])
    result["video"] = audit_video(directory / "exercise.mp4", frames, count, size, fps, max_mean_error)
    result["gif"] = audit_gif(directory / "exercise.gif", gif_size, eid in STATIC_IDS)
    result["passed"] = True
    return result


def audit_exports(catalog_path, visuals, frames_root, ids=None, expected_frames=96,
                  max_mean_error=3.0, progress=False):
    catalog = read_object(catalog_path)
    media, invalid = load_exports(catalog["exercises"], visuals)
    selected = list(dict.fromkeys(ids)) if ids is not None else sorted(media)
    results = []
    for eid in selected:
        try:
            require(eid in media, "No valid completed export for requested exact ID")
            result = audit_one(media[eid], visuals, frames_root, expected_frames, max_mean_error)
        except (OSError, ValueError, TypeError, KeyError, cv2.error) as error:
            result = {"exerciseId": eid, "directory": media.get(eid, {}).get("directory"),
                      "passed": False, "error": str(error), "trainerReview": "pending", "approved": False}
        results.append(result)
        if progress:
            print(f"Audit {eid}: {'PASS' if result['passed'] else 'FAIL ' + result['error']}", flush=True)
    return {"schemaVersion": 1, "generatedAt": datetime.now(timezone.utc).isoformat(),
            "passed": bool(results) and all(row["passed"] for row in results),
            "selectedCount": len(selected), "passedCount": sum(row["passed"] for row in results),
            "failedCount": sum(not row["passed"] for row in results),
            "invalidExportsExcludedByPreview": invalid, "expectedFrameCount": expected_frames,
            "pixelMeanErrorLimit": max_mean_error, "results": results,
            "loopTolerance": {"maxMeanAbsoluteRgbErrorOn255Scale": LOOP_MEAN_LIMIT,
                              "largeErrorPixelThreshold": LOOP_LARGE_PIXEL_THRESHOLD,
                              "maxLargeErrorPixelFraction": LOOP_LARGE_PIXEL_FRACTION_LIMIT,
                              "pixelFractionUsesAnyRgbChannel": True,
                              "nativeBoneMaxDeltaMeters": 1e-5},
            "scope": "File integrity, complete media decoding and exact source PNG comparison; trainer review remains pending"}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--catalog", type=Path, default=PROJECT / "output/exercise_visuals/catalog.json")
    parser.add_argument("--visuals", type=Path, default=PROJECT / "output/exercise_visuals")
    parser.add_argument("--frames-root", type=Path, default=PROJECT / "artifacts/exercise_visuals")
    parser.add_argument("--ids", nargs="+")
    parser.add_argument("--expected-frames", type=int, default=96,
                        help="96 for current production; explicitly use 48 only to audit historical 12fps exports")
    parser.add_argument("--max-pixel-mean-error", type=float, default=3.0)
    parser.add_argument("--output", type=Path,
                        default=PROJECT / "artifacts/exercise_visuals/export-integrity-audit.json")
    args = parser.parse_args()
    if args.expected_frames < 12 or not math.isfinite(args.max_pixel_mean_error) or args.max_pixel_mean_error < 0:
        parser.error("Positive expected frame count >=12 and finite nonnegative error limit required")
    try:
        report = audit_exports(args.catalog, args.visuals.resolve(), args.frames_root.resolve(),
                               args.ids, args.expected_frames, args.max_pixel_mean_error, True)
    except (OSError, ValueError, TypeError, KeyError) as error:
        report = {"passed": False, "error": str(error), "trainerReview": "pending"}
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({key: value for key, value in report.items() if key not in ("results", "scope")},
                     ensure_ascii=False, indent=2))
    raise SystemExit(0 if report["passed"] else 1)


if __name__ == "__main__":
    main()
