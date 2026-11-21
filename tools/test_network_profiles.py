"""Geometry contracts for visibly distinct ascents without changing ballistic capture."""
import math
import unittest
import numpy as np

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

    def test_launch_is_one_continuous_climb_without_terraces_or_dips(self):
        for launch, *_ in self.jumps:
            r = self.roads[launch]
            first = math.ceil(2700 / dn.STEP)
            samples = np.array([r.h(i) for i in np.arange(first, r.N-1, 0.5)])
            slopes = np.diff(samples) / (dn.STEP * 0.5)
            with self.subTest(road=r.name):
                self.assertTrue(np.all(slopes > 0), 'no downhill or level terraces after entry')
                # At most one broad slope maximum, never repeated pitch oscillation.
                peaks = np.sum((np.diff(slopes)[:-1] > 1e-8) & (np.diff(slopes)[1:] < -1e-8))
                self.assertLessEqual(peaks, 1)
                # Under 0.18 degrees of pitch change per 12 metres, including
                # the tallest existing launch's unavoidable entry curvature.
                self.assertLess(np.max(np.abs(np.diff(slopes))), 0.003)

    def test_recovery_descent_has_no_intermediate_stop_or_vertical_waves(self):
        for _, catch, *_ in self.jumps:
            r = self.roads[catch]
            flat = r.keys[2][0]
            end = r.keys[-2][0]
            z = np.array([r.h(i) for i in np.arange(flat+1, end, 2)])
            self.assertTrue(np.all(np.diff(z) < 0), r.name+' needs one smooth descent')

    def test_explicit_highway_overlap_for_every_launch(self):
        self.assertTrue(hasattr(dn, "surface_overlaps"), "shared pavement needs an explicit physical relation")
        overlaps = dn.surface_overlaps(self.roads, self.joins, self.jumps)
        self.assertEqual(len(overlaps), len(self.jumps))
        self.assertEqual(len(self.joins), 195, "physical overlap must not add route shortcuts")
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
            # Recovery rolls start on the landing straight; Needle Roll has two entry bends first.
            if r.role == 'catch':
                self.assertEqual(r.segs[0][0], 'S')
                self.assertGreater(r.segs[0][1], last * dn.STEP)
            np.testing.assert_allclose(r.t[first:last + 1], np.broadcast_to(r.t[first], (last - first + 1, 2)), atol=1e-8)
            self.assertAlmostEqual(r.h(first), r.h(last), places=6)
            self.assertGreater(r.h(first), r.width / 2.0 + 100.0)

    def test_central_transfers_use_short_open_bends(self):
        # A nearby merge previously made the broad-radius solver choose a 300+
        # degree circle. Retain broad corners and reject that long detour;
        # test_network_rhythm also limits continuous steering time between straights.
        for k in dn.TRANSFER_JUMPS:
            road = self.roads[self.jumps[k][1]]
            with self.subTest(road=road.name):
                self.assertLess(float(road.len[:-1].sum()), 210000.0)
                for kind, radius, angle, _ in road.segs:
                    if kind != 'S':
                        self.assertGreaterEqual(radius, 25000.0)
                        self.assertLess(angle, 180.0)

    def test_central_transfer_entry_and_destination_are_preserved(self):
        targets = [('N2', -1, 600.0), ('N2', 1, 600.0),
                   ('E2', 1, 0.0), ('E2', -1, 0.0)]
        for k, (name, direction, level) in enumerate(targets):
            launch, catch, speed, *_ = self.jumps[k]
            L, C = self.roads[launch], self.roads[catch]
            parent = next(p for c, end, p in self.joins if c == catch and end == 1)
            P = self.roads[parent]
            with self.subTest(road=C.name):
                self.assertEqual(P.name, name)
                self.assertEqual(C.segs[0][0], 'S')
                self.assertGreaterEqual(C.segs[0][1], 6000.0)
                self.assertAlmostEqual(C.hdeg, L.hdeg, places=8)
                expected_gap = [3218.7, 4693.9375, 4023.375, 4291.6][k]
                self.assertAlmostEqual(math.hypot(*(C.p[0] - L.p[-1])), expected_gap, places=5)
                self.assertEqual(speed, [3000.0, 3500.0, 2500.0, 4000.0][k])
                end_heading = C.end[2]
                along = math.cos(end_heading) * P.t[0, 0] + math.sin(end_heading) * P.t[0, 1]
                self.assertAlmostEqual(along, direction, places=8)
                self.assertAlmostEqual(C.h(C.N - 1), level, places=8)

    def test_central_transfers_overfly_then_merge_from_outside(self):
        # Dropping an open RSL curve onto the highway crosses opposing traffic.
        # An overflight must stay high; the real merge must stay on the outside
        # of its destination lane and coplanar throughout the shared pavement.
        for k in dn.TRANSFER_JUMPS:
            catch = self.jumps[k][1]
            C = self.roads[catch]
            parent = next(p for c, end, p in self.joins if c == catch and end == 1)
            P = self.roads[parent]
            j = dn.junction(self.roads, catch, 1, parent)
            lateral = (C.p[:, 0] - P.x0) * -P.t[0, 1] + (C.p[:, 1] - P.y0) * P.t[0, 0]
            side = 1 if lateral[-1] > 0 else -1
            level = C.h(C.N - 1)
            crossings = [i for i in range(j[4]) if abs(lateral[i]) < 400.0]
            with self.subTest(road=C.name):
                self.assertTrue(crossings, 'open transfer should overfly its destination before merging')
                self.assertGreater(min(C.h(i) - level for i in crossings), 100.0)
                for i in range(j[4], j[5] + 1):
                    self.assertGreaterEqual(lateral[i] * side, 99.9)
                    self.assertAlmostEqual(C.h(i), level, places=6)


if __name__ == "__main__":
    unittest.main()
