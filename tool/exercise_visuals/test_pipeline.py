"""Production invariants that need neither Blender nor external media.

Run: python -m unittest discover -s tool/exercise_visuals -p test_pipeline.py
"""

import copy
import hashlib
import io
import json
import tempfile
import unittest
from pathlib import Path
from contextlib import redirect_stderr
from unittest.mock import patch

from PIL import Image

import build_preview
import export_media
import run_batch
import motion_registry


class ProductionPipelineTests(unittest.TestCase):
    def test_selected_proof_phases_are_read_without_importing_blender(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / "proof_motions.py"
            source.write_text("import bpy\nraise RuntimeError('must not execute')\n"
                              "SUPPORTED = ('walking_lunge',)\n"
                              "POSE_SECONDS = {'walking_lunge': {'start': 0, 'middle': .65, 'peak': .912}}\n",
                              encoding="utf-8")
            with patch.object(motion_registry, "_ROOT", root), patch.object(motion_registry, "MODULES", ("proof_motions",)):
                motion_registry.registrations.cache_clear()
                try:
                    self.assertEqual(motion_registry.pose_seconds("walking_lunge"),
                                     {"start": 0, "middle": .65, "peak": .912})
                    self.assertIsNone(motion_registry.pose_seconds("unmade_specific_machine"))
                    for value in ("{'start': 0, 'middle': True, 'peak': 2}",
                                  "{'start': 0, 'middle': 1e309, 'peak': 2}",
                                  "{'start': 0, 'middle': 1, 'peak': 4}",
                                  "{'start': 0, 'peak': 2}"):
                        source.write_text("SUPPORTED = ('walking_lunge',)\nPOSE_SECONDS = {'walking_lunge': " + value + "}\n",
                                          encoding="utf-8")
                        with self.assertRaisesRegex(ValueError, "Proof phases"):
                            motion_registry.pose_seconds("walking_lunge")
                finally:
                    motion_registry.registrations.cache_clear()

    def test_selected_pose_exports_keep_the_floor_and_jump_phases(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            frames = []
            for index in range(96):
                path = root / f"frame_{index + 1:04d}.png"
                Image.new("RGB", (8, 8), (index, 0, 0)).save(path)
                frames.append(path)
            export_media.export_stills(frames, root, 8, 24, "버피",
                                      {"start": 0, "middle": 1.672, "peak": 3.116})
            for name, expected in (("start", 0), ("middle", 40), ("peak", 75)):
                with Image.open(root / ("pose-" + name + ".png")) as image:
                    self.assertEqual(image.getpixel((0, 0)), (expected, 0, 0))

    def test_production_snapshot_preserves_old_revision_and_rejects_tampering(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            tools = root / "tool/exercise_visuals"
            visuals = root / "output/exercise_visuals"
            tools.mkdir(parents=True)
            visuals.mkdir(parents=True)
            motion = tools / "proof_motions.py"
            motion.write_text("revision-one", encoding="utf-8")
            (tools / "run_batch.py").write_text("orchestration", encoding="utf-8")
            body = visuals / "body.blend"
            body.write_bytes(b"own-human-body")
            with patch.object(run_batch, "PROJECT", root), patch.object(run_batch, "TOOLS", tools), \
                    patch.object(run_batch, "VISUALS", visuals), \
                    patch.object(run_batch, "production_sources", return_value=[motion, body]):
                first = run_batch.fingerprint("proof", 480, 24, 96, 384)
                manifest = run_batch.snapshot_sources("proof", first, 480, 24, 96, 384)
                frozen = manifest.parent / motion.name
                motion.write_text("revision-two", encoding="utf-8")
                second = run_batch.fingerprint("proof", 480, 24, 96, 384)
                self.assertNotEqual(first, second)
                run_batch.snapshot_sources("proof", second, 480, 24, 96, 384)
                self.assertEqual(frozen.read_text(encoding="utf-8"), "revision-one")
                current_frozen = visuals / "production/source-snapshots" / second / motion.name
                current_frozen.write_text("tampered", encoding="utf-8")
                with self.assertRaisesRegex(ValueError, "snapshot was changed"):
                    run_batch.snapshot_sources("proof", second, 480, 24, 96, 384)

    def test_corrected_geometry_has_separate_outputs_and_frame_revisions(self):
        self.assertEqual(run_batch.output_directory("row"), run_batch.VISUALS / "row/v2")
        self.assertEqual(
            run_batch.frames_directory("row"),
            run_batch.PROJECT / "artifacts/exercise_visuals/row/v2/frames",
        )
        for exercise_id in run_batch.FIRST_BATCH:
            if exercise_id == "row":
                continue
            with self.subTest(exercise_id=exercise_id):
                revised={"bench","dumbbell_bench","dumbbell_shoulder_press","deadlift","romanian_deadlift","calf_raise","pushup","plank"}
                output_version = "v6" if exercise_id == "bodyweight_squat" else "v2" if exercise_id in revised else "v1"
                frame_version = "v5" if exercise_id == "bodyweight_squat" else "v2" if exercise_id in revised else "v1"
                self.assertEqual(
                    run_batch.output_directory(exercise_id),
                    run_batch.VISUALS / exercise_id / output_version,
                )
                self.assertEqual(
                    run_batch.frames_directory(exercise_id),
                    run_batch.PROJECT / "artifacts/exercise_visuals" / exercise_id / frame_version / "frames",
                )

    def test_latest_valid_row_export_replaces_v1_and_invalid_v2_does_not(self):
        with tempfile.TemporaryDirectory() as temporary:
            visuals = Path(temporary)
            rows = [{"exerciseId": "row"}, {"exerciseId": "curl"}]
            for relative, exercise_id in (("row/v1", "row"), ("row/v2", "row"), ("curl/v1", "curl")):
                directory = visuals / relative
                directory.mkdir(parents=True)
                self._media_manifest(directory, exercise_id)
            media, invalid = build_preview.load_exports(rows, visuals)
            self.assertEqual(media["row"]["directory"], "row/v2")
            self.assertEqual(media["curl"]["directory"], "curl/v1")
            self.assertEqual(invalid, [])
            (visuals / "row/v2/exercise.gif").write_bytes(b"incomplete new export")
            media, invalid = build_preview.load_exports(rows, visuals)
            self.assertEqual(media["row"]["directory"], "row/v1")
            self.assertEqual(media["curl"]["directory"], "curl/v1")
            self.assertEqual(invalid, ["row/v2/media.json"])

    def test_selection_rejects_unsafe_and_unauthored_ids_without_mutating_queue(self):
        catalog = {
            "exercises": [
                {"exerciseId": "curl", "name": "덤벨 컬", "status": "queued"},
                {"exerciseId": "unmade_specific_machine", "name": "아직 제작하지 않은 머신", "status": "queued"},
            ]
        }
        original = copy.deepcopy(catalog)
        for exercise_id in ("../curl", "curl/../../elsewhere", "C:\\curl", "curl.json"):
            with self.subTest(exercise_id=exercise_id):
                with self.assertRaisesRegex(ValueError, "Unsafe output ID"):
                    run_batch.select_jobs(catalog, [exercise_id])
        with self.assertRaisesRegex(ValueError, "Motion not authored yet.*remains queued"):
            run_batch.select_jobs(catalog, ["unmade_specific_machine"])
        self.assertEqual(catalog, original)
        self.assertEqual(
            [row["exerciseId"] for row in run_batch.select_jobs(catalog, ["curl", "curl"])],
            ["curl"],
        )

    def test_relabeling_another_exercise_folder_cannot_create_a_visual(self):
        with tempfile.TemporaryDirectory() as temporary:
            visuals = Path(temporary)
            directory = visuals / "row/v1"
            directory.mkdir(parents=True)
            self._media_manifest(directory, "curl")
            media, invalid = build_preview.load_exports(
                [{"exerciseId": "row"}, {"exerciseId": "curl"}], visuals,
            )
            self.assertEqual(media, {})
            self.assertEqual(invalid, ["row/v1/media.json"])

    def test_resume_requires_matching_source_and_unmodified_media(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            self._production_files(directory)
            run_batch.save_state(directory, "curl", "source-a")
            self.assertTrue(run_batch.can_resume(directory, "source-a"))
            self.assertFalse(run_batch.can_resume(directory, "source-b"))
            (directory / "exercise.gif").write_bytes(b"partially replaced GIF")
            self.assertFalse(run_batch.can_resume(directory, "source-a"))

    def test_resume_recovers_from_an_interrupted_state_write(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            (directory / "production-state.json").write_text(
                '{"fingerprint": "source-a", "status":', encoding="utf-8"
            )
            self.assertFalse(run_batch.can_resume(directory, "source-a"))

    def test_gif_duration_rounding_preserves_the_full_sampled_loop(self):
        for fps, count, step in ((12, 48, 1), (24, 96, 2), (24, 60, 2), (29, 116, 1)):
            with self.subTest(fps=fps, count=count, step=step):
                durations = export_media.gif_durations(count // step, fps, step)
                self.assertTrue(all(value >= 10 and value % 10 == 0 for value in durations))
                self.assertLessEqual(abs(sum(durations) - count / fps * 1000), 5)
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            frames = []
            for index in range(60):
                path = directory / f"frame_{index + 1:04d}.png"
                Image.new("RGB", (8, 8), (index * 4, 80, 120)).save(path)
                frames.append(path)
            output = directory / "exercise.gif"
            export_media.export_gif(frames, output, 8, 24, 2)
            with Image.open(output) as gif:
                duration = 0
                for index in range(gif.n_frames):
                    gif.seek(index)
                    duration += gif.info.get("duration", 0)
                self.assertEqual(duration, 2500)
                self.assertEqual(gif.info["loop"], 0)

    def test_runner_rejects_a_partial_cycle_before_reading_or_rendering(self):
        with patch("sys.argv", ["run_batch.py", "--list", "--fps", "24", "--frame-count", "48"]):
            with redirect_stderr(io.StringIO()):
                with self.assertRaises(SystemExit) as rejected:
                    run_batch.main()
        self.assertEqual(rejected.exception.code, 2)

    def test_export_rejects_a_partial_cycle_before_loading_frames(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            with self.assertRaises(ValueError):
                export_media.export(
                    directory / "missing-frames", directory / "output", "curl", "덤벨 컬",
                    frame_count=48, fps=24, size=8, gif_size=8,
                )

    def test_preview_keeps_unauthored_rows_queued_and_rejects_incomplete_exports(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            visuals = directory / "visuals"
            catalog = directory / "catalog.json"
            catalog.write_text(json.dumps({"exercises": [
                {"exerciseId": "curl", "name": "덤벨 컬", "status": "queued"},
                {"exerciseId": "squat", "name": "스쿼트", "status": "queued"},
            ]}), encoding="utf-8")
            export_directory = visuals / "curl/v1"
            export_directory.mkdir(parents=True)
            self._media_manifest(export_directory, "curl")
            with patch.object(build_preview, "VISUALS", visuals):
                summary = build_preview.build(catalog, visuals / "index.html")
                self._assert_coverage(summary, total=2, rendered=1, queued=1)
                (export_directory / "exercise.mp4").write_bytes(b"interrupted replacement")
                summary = build_preview.build(catalog, visuals / "index.html")
                self._assert_coverage(summary, total=2, rendered=0, queued=2)
                self.assertEqual(summary["invalidExports"], ["curl/v1/media.json"])

    def test_preview_does_not_call_a_queued_export_rendered(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            visuals = directory / "visuals"
            catalog = directory / "catalog.json"
            catalog.write_text(json.dumps({"exercises": [
                {"exerciseId": "curl", "name": "덤벨 컬"},
            ]}), encoding="utf-8")
            export_directory = visuals / "curl/v1"
            export_directory.mkdir(parents=True)
            self._media_manifest(export_directory, "curl", status="queued")
            with patch.object(build_preview, "VISUALS", visuals):
                summary = build_preview.build(catalog, visuals / "index.html")
                self._assert_coverage(summary, total=1, rendered=0, queued=1)

    def _assert_coverage(self, summary, *, total, rendered, queued):
        self.assertEqual(summary["total"], total)
        self.assertEqual(summary["renderedDemos"], rendered)
        self.assertEqual(summary["queued"], queued)

    @staticmethod
    def _production_files(directory):
        for name in (
            "exercise.mp4", "exercise.gif", "pose-start.png", "pose-middle.png",
            "pose-peak.png", "media.json", "contact-sheet.png", "exercise.blend",
            "motion-audit.json", "highlight-audit.json",
            "motion-validation.json",
            "skin-floor-audit.json",
        ):
            (directory / name).write_bytes(name.encode("ascii"))

    @staticmethod
    def _media_manifest(directory, exercise_id, status="rendered"):
        files = {}
        for name in (
            "exercise.mp4", "exercise.gif", "pose-start.png", "pose-middle.png",
            "pose-peak.png", "contact-sheet.png",
        ):
            contents = name.encode("ascii")
            (directory / name).write_bytes(contents)
            files[name] = {"bytes": len(contents), "sha256": hashlib.sha256(contents).hexdigest()}
        (directory / "media.json").write_text(json.dumps({
            "exerciseId": exercise_id, "status": status, "files": files,
        }), encoding="utf-8")


if __name__ == "__main__":
    unittest.main()
