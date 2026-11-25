"""Use Basilisk's real rows to check both handed panel directions."""
import unittest
import numpy as np
from art_pilot_fleet import Surface, BASILISK_BODY, outboard_patch, sponson_rows

class HandedPanels(unittest.TestCase):
    def test_engine_panels_stay_on_their_host(self):
        for side in (-1,1):
            for start,end in ((2.15,2.85),(4.15,5.6)):
                with self.subTest(side=side,span=(start,end)):
                    mesh=Surface()
                    outboard_patch(mesh,BASILISK_BODY,start,end,side,32,.42,'stripe',.024)
                    p=np.asarray(mesh.pos)
                    self.assertLess(np.abs(p[:,0]).max(),1.14)
                    self.assertLess(np.abs(p[:,1]).max(),.7)
                    self.assertTrue(np.isfinite(p).all())
                    self.assertGreater((p[:,0]*side).min(),.7)

    def test_cabin_panels_stay_on_the_sponson(self):
        for side in (-1,1):
            mesh=Surface()
            outboard_patch(mesh,sponson_rows(side),2.15,2.95,side,42,.45,'access',.02)
            p=np.asarray(mesh.pos)
            self.assertLess(np.abs(p).max(),2.0)
            self.assertGreater((p[:,0]*side).min(),.9)

if __name__=='__main__': unittest.main()
