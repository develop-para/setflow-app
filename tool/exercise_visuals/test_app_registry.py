import json
import tempfile
import unittest
from pathlib import Path

import register_app_assets as registry
from export_media import sha256


class AppRegistryTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.visuals = self.root / "output/exercise_visuals"
        self.directory = self.visuals / "plank/v2"
        self.directory.mkdir(parents=True)
        (self.directory / "highlight-audit.json").write_text(
            json.dumps({"regions": ["abs"]}), encoding="utf-8",
        )
        self.asset = self.root / "assets/exercise_visuals/plank.gif"
        self.asset.parent.mkdir(parents=True)
        self.asset.write_bytes(b"reviewed-gif-content")
        self.target = self.root / "exercise_visuals.dart"
        self.target.write_text("class ExerciseVisual {}\nconst exerciseVisuals = {};\n", encoding="utf-8")
        hashes = {"exercise.gif": {"sha256": sha256(self.asset)}}
        self.media = {"plank": {"directory": "plank/v2", "files": hashes}}
        self.row = {"exerciseId": "plank", "reviewStatus": "visual_checked_trainer_pending",
                    "reviewedExportHashes": {"exercise.gif": sha256(self.asset)}}

    def render(self):
        return registry.render({"exercises": [self.row]}, self.media, self.target,
                               self.visuals, self.root)

    def test_unreviewed_render_cannot_be_registered(self):
        self.row["reviewStatus"] = "visual_review_pending"
        with self.assertRaisesRegex(ValueError, "No explicitly reviewed"):
            self.render()

    def test_export_drift_invalidates_previous_visual_review(self):
        self.media["plank"]["files"]["exercise.gif"]["sha256"] = "new-render"
        with self.assertRaisesRegex(ValueError, "Reviewed export changed"):
            self.render()

    def test_wrong_installed_gif_cannot_be_shown_under_correct_exercise_id(self):
        self.asset.write_bytes(b"some-other-exercise")
        with self.assertRaisesRegex(ValueError, "Installed GIF does not match"):
            self.render()

    def test_verified_static_demo_keeps_exact_identity_and_muscle_label(self):
        content, ids = self.render()
        self.assertEqual(ids, ["plank"])
        self.assertIn("'plank': ExerciseVisual(", content)
        self.assertIn("assets/exercise_visuals/plank.gif", content)
        self.assertIn("highlightedMuscles: '복근'", content)
        self.assertIn("isStaticPose: true", content)


if __name__ == "__main__":
    unittest.main()
