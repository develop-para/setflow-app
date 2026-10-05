"""Export any Setflow exercise PNG sequence; no third-party exercise images.

Keeps the full loop duration, a shared GIF palette and independent H.264 frames.
Blender and MPFB are not needed for this step. Pillow and FFmpeg are required.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import shutil
import subprocess
import tempfile
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

PROJECT = Path(__file__).resolve().parents[2]
FFMPEG_FALLBACK = Path(r"C:\Program Files\BlueStacks_nxt\ffmpeg.exe")


def sha256(path: Path) -> str:
    with path.open("rb") as handle:
        return hashlib.file_digest(handle, "sha256").hexdigest() if hasattr(hashlib, "file_digest") else hashlib.sha256(handle.read()).hexdigest()


def load_rgb(path: Path) -> Image.Image:
    with Image.open(path) as source:
        if source.mode == "RGBA":
            result = Image.new("RGB", source.size, "white")
            result.paste(source, mask=source.getchannel("A"))
            return result
        return source.convert("RGB")


def frame_paths(directory: Path, count: int, size: int) -> list[Path]:
    frames = [directory / f"frame_{number:04d}.png" for number in range(1, count + 1)]
    for path in frames:
        if not path.is_file():
            raise FileNotFoundError(f"Missing animation frame: {path}")
        with Image.open(path) as image:
            if image.size != (size, size):
                raise ValueError(f"Unexpected dimensions for {path}: {image.size}")
            image.verify()
    return frames


def locate_ffmpeg(requested: str | None) -> Path:
    path = Path(requested or shutil.which("ffmpeg") or FFMPEG_FALLBACK).resolve()
    if not path.is_file():
        raise FileNotFoundError("FFmpeg not found. Supply --ffmpeg.")
    return path


def export_mp4(frames: list[Path], output: Path, ffmpeg: Path, size: int, fps: int) -> None:
    temporary = output.with_name("exercise.encoding.mp4")
    command = [str(ffmpeg), "-hide_banner", "-loglevel", "error", "-y",
               "-f", "rawvideo", "-pix_fmt", "rgb24", "-s:v", f"{size}x{size}",
               "-r", str(fps), "-i", "pipe:0", "-an", "-c:v", "libopenh264",
               "-g", "1", "-rc_mode", "off", "-pix_fmt", "yuv420p",
               "-movflags", "+faststart", str(temporary)]
    with tempfile.TemporaryFile() as diagnostics:
        process = subprocess.Popen(command, stdin=subprocess.PIPE,
                                   stdout=subprocess.DEVNULL, stderr=diagnostics)
        failure = None
        try:
            for frame in frames:
                process.stdin.write(load_rgb(frame).tobytes())
        except (OSError, ValueError) as error:
            failure = error
        finally:
            try:
                process.stdin.close()
            except OSError as error:
                failure = failure or error
        code = process.wait()
        if code or failure:
            diagnostics.seek(0)
            raise RuntimeError(f"FFmpeg {code}: {diagnostics.read().decode('utf-8', errors='replace')}") from failure
    if not temporary.is_file() or not temporary.stat().st_size:
        raise RuntimeError("No MP4 produced")
    temporary.replace(output)


def gif_durations(count: int, fps: int, step: int) -> list[int]:
    boundaries = [round(number * step * 100 / fps) * 10 for number in range(count + 1)]
    return [boundaries[number + 1] - boundaries[number] for number in range(count)]


def export_gif(frames: list[Path], output: Path, size: int, fps: int, step: int) -> None:
    images = [load_rgb(path).resize((size, size), Image.Resampling.LANCZOS) for path in frames[::step]]
    indices = sorted({round(number * (len(images) - 1) / 11) for number in range(12)})
    sheet = Image.new("RGB", (128 * len(indices), 128), "white")
    for number, index in enumerate(indices):
        sheet.paste(images[index].resize((128, 128)), (number * 128, 0))
    palette = sheet.quantize(colors=192, method=Image.Quantize.MEDIANCUT)
    quantized = [image.quantize(palette=palette, dither=Image.Dither.NONE) for image in images]
    temporary = output.with_name("exercise.encoding.gif")
    quantized[0].save(temporary, format="GIF", save_all=True,
                      append_images=quantized[1:], duration=gif_durations(len(images), fps, step),
                      loop=0, disposal=2, optimize=False)
    temporary.replace(output)
    with Image.open(output) as image:
        duration = 0
        for frame in range(image.n_frames):
            image.seek(frame)
            duration += image.info.get("duration", 0)
        expected = round(len(frames) / fps * 1000)
        if image.info.get("loop") != 0 or abs(duration - expected) > 10:
            raise ValueError(f"GIF loop timing mismatch: {duration}ms vs {expected}ms")


def font(size: int):
    for path in (r"C:\Windows\Fonts\malgun.ttf", "NotoSansCJK-Regular.ttc", "DejaVuSans.ttf"):
        try:
            return ImageFont.truetype(path, size)
        except OSError:
            pass
    return ImageFont.load_default()


def export_stills(frames: list[Path], output: Path, size: int, fps: int, name: str,
                  pose_seconds: dict | None = None) -> None:
    seconds = pose_seconds or {"start": 0.3, "middle": 1.1, "peak": 2.0}
    indices = tuple(min(len(frames) - 1, round(seconds[key] * fps))
                    for key in ("start", "middle", "peak"))
    filenames = ("pose-start.png", "pose-middle.png", "pose-peak.png")
    for index, filename in zip(indices, filenames):
        shutil.copyfile(frames[index], output / filename)
    margin, header, label = 24, 72, 44
    sheet = Image.new("RGB", (size * 3 + margin * 2, header + size + label), "white")
    draw = ImageDraw.Draw(sheet)
    draw.text((margin, 18), name + " · 동작 시안", font=font(26), fill=(24, 24, 24))
    for number, (index, caption) in enumerate(zip(indices, ("시작", "중간", "주요 자세"))):
        sheet.paste(load_rgb(frames[index]), (margin + number * size, header))
        draw.text((margin + number * size + 12, header + size + 8), caption,
                  font=font(20), fill=(80, 80, 80))
    sheet.save(output / "contact-sheet.png")


def export(frames_dir: Path, output: Path, exercise_id: str, name: str,
           frame_count: int = 48, fps: int = 12, size: int = 480,
           gif_size: int = 384, gif_step: int = 1, ffmpeg: str | None = None) -> dict:
    if frame_count < 12 or fps < 3 or size < 2 or size % 2 or gif_size < 1 or gif_step < 1:
        raise ValueError("Positive dimensions and fps >=3 required; MP4 dimensions must be even")
    if frame_count != fps * 4:
        raise ValueError("These exercise motions require a four-second loop: frame_count == fps * 4")
    if frame_count % gif_step or 1000 * gif_step / fps < 10:
        raise ValueError("GIF sampling must divide frame count and use at least 10ms per frame")
    frames = frame_paths(frames_dir.resolve(), frame_count, size)
    output.mkdir(parents=True, exist_ok=True)
    export_mp4(frames, output / "exercise.mp4", locate_ffmpeg(ffmpeg), size, fps)
    export_gif(frames, output / "exercise.gif", gif_size, fps, gif_step)
    from motion_registry import pose_seconds
    selected_poses = pose_seconds(exercise_id)
    export_stills(frames, output, size, fps, name, selected_poses)
    metadata = {
        "schemaVersion": 1, "exerciseId": exercise_id, "name": name,
        "status": "rendered", "trainerReview": "pending", "bodyVersion": 5,
        "frameCount": frame_count, "fps": fps, "durationSeconds": frame_count / fps,
        "videoSize": size, "gifSize": gif_size,
        "provenance": "CC0 MakeHuman body + Setflow bodybuilder sculpt, motion and equipment",
        "humanSource": "../../bodyweight_squat/v5/source-manifest.json",
        "muscleGuide": "Educational regions; not measured muscle activation",
        "selectedPoseSeconds": selected_poses,
        "files": {filename: {"bytes": (output / filename).stat().st_size,
                             "sha256": sha256(output / filename)}
                  for filename in ("exercise.mp4", "exercise.gif", "pose-start.png",
                                   "pose-middle.png", "pose-peak.png", "contact-sheet.png")},
    }
    (output / "media.json").write_text(json.dumps(metadata, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return metadata


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--frames", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--exercise", required=True)
    parser.add_argument("--name", required=True)
    parser.add_argument("--frame-count", type=int, default=48)
    parser.add_argument("--fps", type=int, default=12)
    parser.add_argument("--size", type=int, default=480)
    parser.add_argument("--gif-size", type=int, default=384)
    parser.add_argument("--gif-step", type=int, default=1)
    parser.add_argument("--ffmpeg")
    args = parser.parse_args()
    result = export(args.frames, args.output, args.exercise, args.name,
                    args.frame_count, args.fps, args.size, args.gif_size, args.gif_step, args.ffmpeg)
    print(f"Exported {result['exerciseId']}: {result['durationSeconds']}s / {result['frameCount']} frames")


if __name__ == "__main__":
    main()
