import tempfile
import unittest
import zipfile
from pathlib import Path

import numpy as np
from build_grid import clip_height, components, dilate, read_meshes


class GeometryTests(unittest.TestCase):
    def test_door_lintel_above_head_is_not_an_obstacle(self):
        triangle = [np.array(p, float) for p in [(0, 3, 0), (2, 3, 0), (2, 4, 0)]]
        self.assertEqual(clip_height(triangle, 1.9, False), [])

    def test_wall_crossing_body_height_is_preserved(self):
        triangle = [np.array(p, float) for p in [(0, 0, 0), (2, 0, 0), (2, 4, 0)]]
        clipped = clip_height(clip_height(triangle, .02, True), 1.9, False)
        self.assertGreaterEqual(len(clipped), 3)
        self.assertTrue(all(.02-1e-9 <= p[1] <= 1.9+1e-9 for p in clipped))

    def test_components_do_not_cut_diagonal_corners(self):
        _, sizes = components(np.array([[True, False], [False, True]]))
        self.assertEqual(sizes, [1, 1])

    def test_clearance_blocks_nearby_cells(self):
        mask = np.zeros((15, 15), bool)
        mask[7, 7] = True
        expanded = dilate(mask, .3)
        self.assertTrue(expanded[7, 8])
        self.assertTrue(expanded[7, 9])
        self.assertFalse(expanded[7, 10])

    def test_usd_transform_maps_xz_and_keeps_height_separate(self):
        scene = '''#usda 1.0
(
 metersPerUnit = 1
 upAxis = "Y"
)
def Xform "Museum"
{
 double3 xformOp:translate = (10, 2, 20)
 float xformOp:rotateY = 90
 def Mesh "Box"
 {
  int[] faceVertexCounts = [3]
  int[] faceVertexIndices = [0, 1, 2]
  point3f[] points = [(0, 0, 0), (1, 0, 0), (0, 0, 1)]
 }
}
'''
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "test.usdz"
            with zipfile.ZipFile(path, "w") as archive:
                archive.writestr("test.usda", scene)
            meshes = read_meshes(path)
        np.testing.assert_allclose(meshes[0][1], [[10, 2, 20], [10, 2, 19], [11, 2, 20]])


if __name__ == "__main__":
    unittest.main()
