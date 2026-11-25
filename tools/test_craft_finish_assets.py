"""Physical material contracts on the shipped maps, not on generator constants."""
import unittest
from pathlib import Path

import numpy as np
from PIL import Image

ART = Path(__file__).resolve().parents[1] / 'godot/art'


class CraftFinishAssets(unittest.TestCase):
    def test_fleet_dielectrics_do_not_reflect_as_metal(self):
        data = np.asarray(Image.open(ART / 'pilot_fleet/finish_orm.png'))
        # Interior texels of enamel, accent, rubber, ceramic and cloth.
        for x, y in ((128,128),(384,128),(384,384),(640,384),(896,384)):
            with self.subTest(pixel=(x,y)):
                self.assertLessEqual(int(data[y,x,2]), 1)

    def test_fleet_coat_is_masked_off_fabric_and_metal(self):
        image = Image.open(ART / 'pilot_fleet/finish_orm.png')
        self.assertEqual(image.mode, 'RGBA', 'ORM alpha stores the painted-finish mask')
        data = np.asarray(image)
        self.assertGreater(int(data[128,128,3]), 240)
        for x,y in ((640,128),(384,384),(640,384),(896,384)):
            self.assertEqual(int(data[y,x,3]), 0)

    def test_shrike_paint_and_carbon_are_dielectrics(self):
        data = np.asarray(Image.open(ART / 'shrike/orm.png'))
        for x,y in ((600,500),(240,1270),(1260,1270),(1650,1650)):
            with self.subTest(pixel=(x,y)):
                self.assertLessEqual(int(data[y,x,2]), 1)

    def test_packed_maps_have_bounded_roughness_and_unit_normals(self):
        for relative in ('pilot_fleet/finish_normal.png','shrike/normal.png'):
            normal = np.asarray(Image.open(ART/relative)).astype(float)/127.5-1
            magnitude = np.linalg.norm(normal,axis=2)
            self.assertGreater(float(magnitude.min()), .98)
            self.assertLess(float(magnitude.max()), 1.02)
        for relative in ('pilot_fleet/finish_orm.png','shrike/orm.png'):
            data = np.asarray(Image.open(ART/relative))
            self.assertGreaterEqual(int(data[:,:,1].min()), 25)


if __name__ == '__main__':
    unittest.main()
