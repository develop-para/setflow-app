"""Direction, rigid linkage, source ordering and fail-closed draft evidence."""
import copy
import math
import unittest
import cardio_extra_motions as motion
import cardio_extra_equipment as equipment


class ExactCardioMechanicsTests(unittest.TestCase):
    def test_forward_pedal_descends_at_front(self):
        points = [motion.elliptical_linkage(index / 400, 1)[2] for index in range(401)]
        # Signed contour y dz distinguishes real forward from reverse; a
        # closed loop alone cannot detect the previous reversed animation.
        integral = sum((first[0] + second[0]) * (second[1] - first[1]) / 2 for first, second in zip(points, points[1:]))
        self.assertGreater(integral, 0)
        front = min(range(1, 199), key=lambda index: points[index][0])
        self.assertLess(points[front + 1][1], points[front][1])

    def test_both_rigid_linkages_close_every_sample(self):
        for index in range(201):
            for side in (-1, 1):
                rear, front, pedal, handle, _ = motion.elliptical_linkage(index / 200, side)
                self.assertAlmostEqual(math.dist(rear, motion.ELLIPTICAL_REAR), motion.ELLIPTICAL_RADIUS, places=10)
                self.assertAlmostEqual(math.dist(rear, front), motion.ELLIPTICAL_COUPLER, places=10)
                self.assertAlmostEqual(math.dist(front, motion.ELLIPTICAL_FRONT), motion.ELLIPTICAL_ROCKER, places=10)
                self.assertAlmostEqual(math.dist(handle, motion.ELLIPTICAL_FRONT), .55, places=10)

    def test_rowing_legs_body_arms_then_arms_body_legs(self):
        legs, body, arms = motion.rowing_sequence(.16)
        self.assertGreater(legs, 0)
        self.assertEqual((body, arms), (0, 0))
        self.assertEqual(motion.rowing_sequence(.24), (1, 1, 0))
        self.assertEqual(motion.rowing_sequence(.30), (1, 1, 1))
        self.assertEqual(motion.rowing_sequence(.46), (1, 1, 0))
        self.assertEqual(motion.rowing_sequence(.60), (1, 0, 0))
        self.assertEqual(motion.rowing_sequence(1), (0, 0, 0))
        self.assertGreater(1 - .30, .30)

    def test_incomplete_and_boolean_frame_coverage_fail(self):
        self.assertFalse(equipment.validate_surfaces('elliptical', [])['passed'])
        report = equipment.validate_surfaces('elliptical', [{'frame': True, 'amount': 0}])
        self.assertIn('Complete actual 96 distinct frame coverage required', report['failures'])

    def test_missing_nan_and_empty_actual_metrics_fail(self):
        for value in (None, math.nan, math.inf, -1, True):
            row = {'frame': 1, 'amount': 0, 'shoe_native_attachment_max_error_m': value}
            report = equipment.validate_surfaces('stationary_bike', [row])
            self.assertIn('Actual native shoe fit/attachment fails', report['failures'])
            self.assertIn('Actual positive skin-domain/body mesh counts required', report['failures'])

    def test_unknown_id_is_not_another_animation(self):
        with self.assertRaises(ValueError):
            motion.phase('unknown', 1)
        self.assertFalse(equipment.validate_surfaces('unknown', [])['passed'])

    def test_nan_infinite_boolean_and_float_sole_counts_rejected(self):
        for value in (math.nan, math.inf, True, 373.0, -1):
            row = {'frame': 1, 'amount': 0, 'soles': {'l': {'actual_sole_vertex_count': value}}}
            report = equipment.validate_surfaces('stationary_bike', [row])
            self.assertIn('Dense actual underside vertices required', report['failures'])

    def test_saddle_domain_and_penetration_are_required_measurements(self):
        for value in (math.nan, -0.1, None, True):
            row = {'frame': 1, 'amount': 0, 'saddle': {'domain': [], 'maximum_skin_penetration_m': value}}
            report = equipment.validate_surfaces('stationary_bike', [row])
            self.assertIn('Exact selected actual saddle support domain required', report['failures'])
            self.assertIn('Finite nonnegative actual saddle penetration/count evidence required', report['failures'])

    def test_float_overlap_and_invalid_rower_sequence_or_drift_rejected(self):
        row = {'frame': 1, 'amount': .3, 'rowing_sequence': [math.nan, True, 2], 'horizontal_seat_height_drift_m': -1,
               'actual_apparatus_meshes': [{'name': 'test', 'actual_vertex_count': 384, 'nonhand_skin_triangle_overlap_count': 0.0, 'actual_min_floor_m': .002}]}
        report = equipment.validate_surfaces('rowing_machine', [row])
        self.assertIn('Exact finite drive/recovery sequence record missing', report['failures'])
        self.assertIn('Fixed horizontal seat height and disclosed actual hip fit required', report['failures'])
        self.assertIn('Actual apparatus mesh intersects nonhand skin: test', report['failures'])

    def test_actual_frame_cannot_be_relabelled_to_another_phase(self):
        report = equipment.validate_surfaces('elliptical', [{'frame': 96, 'amount': 0}])
        self.assertIn('Actual frame and authored 24fps phase must agree', report['failures'])

    def test_one_frame_cannot_inspect_only_a_subset_of_unchanged_topology(self):
        rows = [{'frame': frame, 'amount': (frame - 1) / 95, 'l_actual_enclosure_skin_vertex_count': 16424,
                 'soles': {'l': {'actual_sole_vertex_count': 373}}} for frame in range(1, 97)]
        rows[0]['l_actual_enclosure_skin_vertex_count'] = 1
        rows[0]['soles']['l']['actual_sole_vertex_count'] = 30
        report = equipment.validate_surfaces('elliptical', rows)
        self.assertIn('Actual unchanged skin/body topology count must agree across all frames', report['failures'])
        self.assertIn('Actual unchanged sole topology count must agree across all frames', report['failures'])


if __name__ == '__main__':
    unittest.main()
