"""Geometry contracts for visibly distinct ascents without changing ballistic capture."""
import math
import unittest

import design_network as dn


class NetworkProfiles(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.roads, cls.joins, _, cls.ew, cls.ns, cls.jumps, _, _ = dn.build()
        dn.heights(cls.roads, cls.ew, cls.ns)

    def test_three_distinct_shaped_ascents(self):
        signatures = set()
        for launch, catch, speed, lip, _ in self.jumps:
            road = self.roads[launch]
            # Same-speed normalization reveals the shape rather than merely its height.
            signatures.add(tuple(round(road.h(road.N * f) / lip, 2) for f in (0.4, 0.5, 0.6, 0.7, 0.8)))
            self.assertGreaterEqual(len(road.keys), 5, road.name + " needs a shaped approach")
            self.assertGreaterEqual(len(self.roads[catch].keys), 6, road.name + " needs a shaped recovery")
        self.assertGreaterEqual(len(signatures), 3)

    def test_shared_pavement_stays_level_and_lips_remain_original(self):
        for launch, _, speed, lip, _ in self.jumps:
            road = self.roads[launch]
            self.assertAlmostEqual(road.h(2000.0 / dn.STEP), road.h(0), places=8)
            self.assertAlmostEqual(road.h(road.N - 1), lip, places=8)
            slope = (road.h(road.N - 1) - road.h(road.N - 1.01)) / (0.01 * dn.STEP)
            self.assertAlmostEqual(math.degrees(math.atan(slope)), dn.JUMP_ANGLES[speed], delta=0.05)

    def test_explicit_highway_overlap_for_every_launch(self):
        self.assertTrue(hasattr(dn, "surface_overlaps"), "shared pavement needs an explicit physical relation")
        overlaps = dn.surface_overlaps(self.roads, self.joins, self.jumps)
        self.assertEqual(len(overlaps), 20)
        self.assertEqual(len(self.joins), 175, "physical overlap must not add route shortcuts")
        self.assertEqual({j[3] for j in overlaps}, {j[0] for j in self.jumps})
        for j in overlaps:
            self.assertEqual(self.roads[j[0]].kind, "highway")
            self.assertEqual(j[4], 0)
            self.assertGreater(j[5] * dn.STEP, 2000.0)
            self.assertLess(j[5] * dn.STEP, 2600.0)

    def test_express_tier_meets_ground_ramps_and_flat_shaft_ends(self):
        for r in self.ns:
            road = self.roads[r]
            self.assertEqual(road.h(0), 0.0)
            self.assertEqual(road.h(road.N - 1), 0.0)
            for y in dn.LINES:
                i, _, _ = road.nearest((road.x0, y))
                self.assertAlmostEqual(road.h(i), 600.0, places=6)
        for r in self.roads:
            if r.kind == 'ramp':
                self.assertEqual(r.h(0), 0.0)
                self.assertEqual(r.h(r.N - 1), 600.0)

    def test_real_transfers_and_twist_capture_clearance(self):
        for k in dn.TRANSFER_JUMPS:
            launch, catch, *_ = self.jumps[k]
            ramp = next(p for c, end, p in self.joins if c == launch and end == 0)
            source = min((p for c, _, p in self.joins if c == ramp),
                         key=lambda p: self.roads[p].nearest(self.roads[launch].p[0])[2])
            target = next(p for c, end, p in self.joins if c == catch and end == 1)
            self.assertNotEqual(self.roads[source].name[0], self.roads[target].name[0])
        for road, first, last, turns in dn.twists(self.roads, self.jumps):
            r = self.roads[road]
            self.assertEqual(r.segs[0][0], 'S')
            self.assertGreater(r.segs[0][1], last * dn.STEP)
            self.assertAlmostEqual(r.h(first), r.h(last), places=6)
            self.assertGreater(r.h(first), r.width / 2.0 + 100.0)


if __name__ == "__main__":
    unittest.main()
