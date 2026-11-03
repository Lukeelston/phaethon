"""Driving-time contracts, counting adjoining curves as one continuous turn."""
import math
import unittest

import design_network as dn


def curved_runs(segs):
    runs, length = [], 0.0
    for kind, radius, angle, _ in segs:
        if kind == 'S':
            if length:
                runs.append(length)
            length = 0.0
        else:
            length += radius * math.radians(angle)
    if length:
        runs.append(length)
    return runs


class NetworkRhythm(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.roads, _, _, _, _, cls.jumps, _, _ = dn.build()

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
