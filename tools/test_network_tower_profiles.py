"""End towers must differ in silhouette while preserving their grounded feet."""
import unittest
import numpy as np
import design_network as dn

class TowerProfiles(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.roads, *_, cls.shafts = dn.build()

    def test_varied_profiles(self):
        profiles = [(r, v) for _, _, _, r, v in self.shafts]
        self.assertEqual(len(set(profiles)), 12)
        heights = [2*r+v for r,v in profiles]
        self.assertGreater(max(heights)-min(heights), 6000)
        self.assertGreater(max(r for r,v in profiles)/min(r for r,v in profiles), 2)
        self.assertGreater(sum(v/r > 4 for r,v in profiles), 2)
        self.assertGreater(sum(v/r < 1.5 for r,v in profiles), 2)

    def test_feet_and_height_keys(self):
        for road, first, last, radius, vertical in self.shafts:
            with self.subTest(road=road):
                r = self.roads[road]
                length = np.cumsum(np.r_[0., r.len[:-1]])
                self.assertAlmostEqual(length[last]-length[first], 2*np.pi*radius+2*vertical, places=6)
                self.assertEqual(dn.shaft_z(0, radius, vertical), (0., 0.))
                self.assertLess(abs(dn.shaft_z(length[last]-length[first], radius, vertical)[0]), 1e-6)
                for i,z,slope in r.keys:
                    expected = dn.shaft_z(length[i]-length[first],radius,vertical)
                    self.assertAlmostEqual(z,expected[0],places=5)
                    self.assertAlmostEqual(slope,expected[1],places=5)

if __name__ == '__main__': unittest.main()
