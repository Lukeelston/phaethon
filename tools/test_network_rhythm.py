"""Driving-time contracts: only a straight or actual steering reversal ends a turn."""
import math
import unittest
import numpy as np

import design_network as dn


def curved_runs(segs):
    runs, length = [], 0.0
    direction = None
    for kind, radius, angle, _ in segs:
        if kind == 'S' or kind != direction:
            if length:
                runs.append(length)
            length = 0.0
        if kind != 'S':
            length += radius * math.radians(angle)
        direction = kind
    if length:
        runs.append(length)
    return runs


class NetworkRhythm(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.roads, _, _, ew, ns, cls.jumps, _, _ = dn.build()
        dn.heights(cls.roads, ew, ns)

    def test_real_steering_reversals_in_long_sweeps(self):
        selected = [self.roads[self.jumps[k][1]] for k in dn.TRANSFER_JUMPS]
        selected += [r for r in self.roads if getattr(r, 'shape', '') in ('hairpin', 'crook')]
        for r in selected:
            # Integrate contiguous signed sampled curvature, ignoring actual straights.
            turns = []
            for delta in np.diff(np.unwrap(np.arctan2(r.t[:, 1], r.t[:, 0]))):
                if abs(delta) < 1e-9:
                    continue
                if not turns or delta * turns[-1] < 0:
                    turns.append(float(delta))
                else:
                    turns[-1] += float(delta)
            with self.subTest(road=r.name):
                self.assertGreaterEqual(len(turns), 10, 'must actually reverse steering through long sweeps')
                self.assertTrue(all(abs(t) > math.radians(1) for t in turns), 'reversals must have meaningful heading change')

    def test_hills_and_dips_are_real_and_keep_entry_clear(self):
        # v025 removes vertical waves from jump recovery roads; side-road hills remain.
        selected = [r for r in self.roads if r.kind == 'side']
        for r in selected:
            start = round((6000 if r.role == 'catch' else 12000) / dn.STEP)
            finish = r.N - round((35000 if r.role == 'catch' else 12000) / dn.STEP)
            heights = np.array([r.h(i) for i in range(start, finish, 20)])
            slope_sign = np.sign(np.diff(heights))
            signs = [int(v) for v in slope_sign if abs(v) > 0]
            changes = sum(a != b for a, b in zip(signs, signs[1:]))
            with self.subTest(road=r.name):
                self.assertGreaterEqual(changes, 3, 'needs several crests and dips, not one summit')
                self.assertGreater(float(np.ptp(heights)), 300.0)
                self.assertLess(float(np.max(np.abs(np.diff(heights)))) / (20 * dn.STEP), 0.10)
                self.assertGreaterEqual(float(heights.min()), 0.0)
                if r.kind == 'side':
                    self.assertAlmostEqual(r.h(0), r.h(start), places=6)
                    self.assertAlmostEqual(r.h(r.N-1), r.h(r.N-1-start), places=6)

    def test_reverse_bend_builder_preserves_endpoint_pose(self):
        self.assertTrue(hasattr(dn, 'varied_arc'))
        for kind, radius, angle, inner, count in [('L', 45000, 90, 25000, 4), ('R', 7000, 100, 6000, 2)]:
            segments = dn.varied_arc(kind, radius, angle, 'sp', inner, count)
            _, pose = dn.walk(segments, 0, 0, 0)
            sign = 1 if kind == 'L' else -1
            theta = math.radians(angle)
            self.assertAlmostEqual(pose[0], radius * math.sin(theta), places=5)
            self.assertAlmostEqual(pose[1], sign * radius * (1-math.cos(theta)), places=5)
            self.assertAlmostEqual(pose[2], sign * theta, places=8)

    def test_no_prolonged_central_turns(self):
        for k in dn.TRANSFER_JUMPS:
            _, catch, mph, *_ = self.jumps[k]
            road = self.roads[catch]
            longest = max(curved_runs(road.segs)) / (mph * dn.MPH)
            with self.subTest(road=road.name):
                self.assertLessEqual(longest, 12.0, f'{road.name}: {longest:.2f} seconds continuously turning')

    def test_several_real_acceleration_intervals(self):
        for k in dn.TRANSFER_JUMPS:
            _, catch, mph, *_ = self.jumps[k]
            road = self.roads[catch]
            intervals = 0
            sample = 0
            for j, (kind, radius, angle, _) in enumerate(road.segs):
                length = radius if kind == 'S' else radius * math.radians(angle)
                n = max(1, math.ceil(length / dn.STEP))
                if kind == 'S' and 0 < j < len(road.segs) - 1 and length / (mph * dn.MPH) >= 2.5:
                    intervals += 1
                    # Check the generated pavement, not just the segment labels.
                    for i in (sample + 1, sample + n // 2, sample + n - 2):
                        self.assertAlmostEqual(float(road.t[i] @ road.t[sample]), 1.0, places=9)
                sample += n
            with self.subTest(road=road.name):
                self.assertGreaterEqual(intervals, 4, 'needs multiple actual throttle windows between bends')


if __name__ == '__main__':
    unittest.main()
