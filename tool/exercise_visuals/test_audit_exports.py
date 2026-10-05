"""Export-integrity regressions with real encoded media, in temporary folders."""
import json
import math
import shutil
import sys
import tempfile
import unittest
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

sys.path.insert(0, str(Path(__file__).resolve().parent))
import audit_exports as audit
from export_media import export_gif, export_mp4, locate_ffmpeg, sha256


class ExportIntegrity(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.fixture = tempfile.TemporaryDirectory()
        root = Path(cls.fixture.name)
        cls.fixture_visuals = root / "visuals"
        cls.fixture_frames = root / "frames"
        directory = cls.fixture_visuals / "pushup/v1"
        frames = cls.fixture_frames / "pushup/v1/frames"
        directory.mkdir(parents=True)
        frames.mkdir(parents=True)
        sequence = []
        for index in range(96):
            image = Image.new("RGB", (480, 480), (160, 160, 160))
            position = 32 + round(160 * math.sin(math.pi * index / 95) ** 2)
            ImageDraw.Draw(image).rectangle((position, 100, position + 64, 300), fill=(220, 220, 220))
            path = frames / f"frame_{index + 1:04d}.png"
            image.save(path)
            image.close()
            sequence.append(path)
        export_mp4(sequence, directory / "exercise.mp4", locate_ffmpeg(None), 480, 24)
        export_gif(sequence, directory / "exercise.gif", 64, 24, 1)
        for name in audit.MEDIA_FILES[2:]:
            shutil.copyfile(sequence[0], directory / name)
        (directory / "exercise.blend").write_bytes(b"BLENDER-test-native-integrity-fixture")
        bones = {"root": {"head": [0, 0, 0], "tail": [0, 0, 1]}}
        (directory / "motion-audit.json").write_text(json.dumps([
            {"frame": i + 1, "bones": bones} for i in range(96)]))
        (directory / "highlight-audit.json").write_text('{"regions": ["chest"]}')
        metadata = {"exerciseId": "pushup", "status": "rendered", "frameCount": 96,
                    "fps": 24, "durationSeconds": 4, "videoSize": 480, "gifSize": 64}
        (directory / "media.json").write_text(json.dumps(metadata))
        cls.rehash(directory)
        cls.catalog = root / "catalog.json"
        cls.catalog.write_text('{"exercises": [{"exerciseId": "pushup"}]}')

    @classmethod
    def tearDownClass(cls):
        cls.fixture.cleanup()

    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        root = Path(self.temporary.name)
        self.visuals, self.frames = root / "visuals", root / "frames"
        shutil.copytree(self.fixture_visuals, self.visuals)
        shutil.copytree(self.fixture_frames, self.frames)
        self.directory = self.visuals / "pushup/v1"

    def tearDown(self):
        self.temporary.cleanup()

    @staticmethod
    def rehash(directory):
        metadata = json.loads((directory / "media.json").read_text())
        metadata["files"] = {name: {"bytes": (directory / name).stat().st_size,
                                    "sha256": sha256(directory / name)} for name in audit.MEDIA_FILES}
        (directory / "media.json").write_text(json.dumps(metadata))
        names = [*audit.MEDIA_FILES, "media.json", "exercise.blend", "motion-audit.json", "highlight-audit.json"]
        (directory / "production-state.json").write_text(json.dumps({
            "exerciseId": "pushup", "status": "rendered",
            "files": {name: sha256(directory / name) for name in names}}))

    def inspect(self, ids=None):
        return audit.audit_exports(self.catalog, self.visuals, self.frames, ids or ["pushup"])

    def test_valid_media_decode_all_96_original_frames(self):
        report = self.inspect()
        self.assertTrue(report["passed"], report)
        self.assertEqual(report["results"][0]["video"]["decodedFrames"], 96)
        self.assertEqual(report["results"][0]["gif"]["durationMilliseconds"], 4000)

    def test_native_scene_drift_is_rejected_even_when_media_is_intact(self):
        with (self.directory / "exercise.blend").open("ab") as stream:
            stream.write(b"unreviewed native change")
        report = self.inspect()
        self.assertFalse(report["passed"])
        self.assertIn("Production-state hash drift: exercise.blend", report["results"][0]["error"])

    def test_missing_native_hash_is_rejected(self):
        path = self.directory / "production-state.json"
        state = json.loads(path.read_text())
        del state["files"]["exercise.blend"]
        path.write_text(json.dumps(state))
        self.assertIn("missing native/media/audit hashes", self.inspect()["results"][0]["error"])

    def test_corrupted_mp4_is_rejected_after_manifest_hashes_are_updated(self):
        (self.directory / "exercise.mp4").write_bytes(b"invalid video data with matching file hashes")
        self.rehash(self.directory)
        report = self.inspect()
        self.assertFalse(report["passed"])
        self.assertIn("MP4 cannot be opened/decoded", report["results"][0]["error"])

    def test_changed_middle_png_cannot_match_unrelated_video_frame(self):
        path = self.frames / "pushup/v1/frames/frame_0048.png"
        with Image.new("RGB", (480, 480), "black") as image:
            image.save(path)
        report = self.inspect()
        self.assertFalse(report["passed"])
        self.assertIn("pixel mean error", report["results"][0]["error"])

    def test_static_fake_gif_is_rejected_for_dynamic_exercise(self):
        with Image.new("RGB", (64, 64), "gray") as image:
            image.save(self.directory / "exercise.gif", save_all=True, duration=4000, loop=0)
        self.rehash(self.directory)
        report = self.inspect()
        self.assertFalse(report["passed"])
        self.assertIn(">=12 distinct decoded frames", report["results"][0]["error"])
        self.assertEqual(audit.audit_gif(self.directory / "exercise.gif", 64, True)["decodedFrames"], 1)

    def test_wrong_gif_duration_and_nonrepeating_loop_are_rejected(self):
        for duration, loop, expected in ((3900, 0, "duration"), (4000, 1, "loop=0")):
            with self.subTest(duration=duration, loop=loop):
                with Image.new("RGB", (64, 64), "gray") as image:
                    image.save(self.directory / "exercise.gif", save_all=True, duration=duration, loop=loop)
                self.rehash(self.directory)
                self.assertIn(expected, self.inspect()["results"][0]["error"])

    def test_requested_unfinished_id_is_failure_instead_of_substitution(self):
        report = self.inspect(["pushup", "not_authored"])
        self.assertFalse(report["passed"])
        self.assertEqual((report["passedCount"], report["failedCount"]), (1, 1))
        self.assertIn("No valid completed export", report["results"][1]["error"])

    def test_loop_noise_limits_reject_local_large_difference(self):
        first = np.zeros((100, 100, 3), dtype=np.uint8)
        last = first.copy()
        last[0, 0] = 1
        self.assertFalse(audit.loop_comparison(first, last, "small noise")["pixelsExactlyEqual"])
        last = first.copy()
        last[:1, :60] = 17  # Low global mean, but >0.5% significantly changed pixels.
        with self.assertRaisesRegex(ValueError, "loop mean/fraction"):
            audit.loop_comparison(first, last, "contact changed")


if __name__ == "__main__":
    unittest.main()
