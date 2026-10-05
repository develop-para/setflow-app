"""Exact dispatch rejects unknown IDs and duplicate motion ownership."""
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch
import motion_registry as registry


class RegistryTests(unittest.TestCase):
    def setUp(self):
        registry.registrations.cache_clear()

    def tearDown(self):
        registry.registrations.cache_clear()

    def test_catalog_name_is_not_a_motion_registration(self):
        with self.assertRaisesRegex(ValueError,"not authored"):
            registry.owner("a-brand-machine-that-has-not-been-authored")

    def test_literal_exact_ids_are_read_without_importing_blender(self):
        with tempfile.TemporaryDirectory() as temporary:
            path=Path(temporary)
            (path/"strength_motions.py").write_text("import bpy\nSUPPORTED=('exact-uuid',)\n",encoding="utf-8")
            with patch.object(registry,"_ROOT",path):
                self.assertEqual(registry.registrations()["exact-uuid"],"strength_motions")
                self.assertNotIn("another-similar-uuid",registry.registrations())

    def test_duplicate_ownership_fails_instead_of_silently_replacing_motion(self):
        with tempfile.TemporaryDirectory() as temporary:
            path=Path(temporary)
            (path/"strength_motions.py").write_text("SUPPORTED=('curl',)\n",encoding="utf-8")
            with patch.object(registry,"_ROOT",path):
                with self.assertRaisesRegex(ValueError,"ownership collision"):
                    registry.registrations()

    def test_computed_name_mapping_is_not_an_authored_literal(self):
        with tempfile.TemporaryDirectory() as temporary:
            path=Path(temporary)
            (path/"strength_motions.py").write_text("SUPPORTED=guess_from_names()\n",encoding="utf-8")
            with patch.object(registry,"_ROOT",path):
                with self.assertRaises(ValueError):registry.registrations()


if __name__=="__main__":unittest.main()
