"""Fail-closed declared actual mesh domain regression tests, no Blender needed."""
import math
import unittest
import cardio_footwear as footwear


class ActualFootwearCoverageTests(unittest.TestCase):
    def test_empty_domain_is_not_zero_penetration(self):
        with self.assertRaises(ValueError):
            footwear._validated_indices([], 100)

    def test_noninteger_bool_negative_and_out_of_bounds(self):
        for indices in ([True], [1.0], [-1], [100], [math.nan], [1, 1]):
            with self.subTest(indices=indices), self.assertRaises(ValueError):
                footwear._validated_indices(indices, 100)

    def test_partial_actual_domain_cannot_pass(self):
        with self.assertRaises(ValueError):
            footwear._validated_indices([1, 3], 100, [1, 2, 3])
        self.assertEqual(footwear._validated_indices([3, 2, 1], 100, [1, 2, 3]), [3, 2, 1])

    def test_missing_expected_domain_cannot_pass(self):
        with self.assertRaises(ValueError):
            footwear._validated_indices([1], 100, [])

    def test_nan_and_infinite_actual_mesh_are_rejected(self):
        for points in ([], [[0, 1]], [[0, math.nan, 1]], [[math.inf, 0, 0]]):
            with self.subTest(points=points), self.assertRaises(ValueError):
                footwear._finite_points(points)


if __name__ == '__main__':
    unittest.main()
