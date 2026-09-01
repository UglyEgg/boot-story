# SPDX-License-Identifier: GPL-3.0-or-later

import math
import re
import unittest
import xml.etree.ElementTree as ElementTree
from pathlib import Path


ICON_PATH = (
    Path(__file__).parents[1]
    / "data"
    / "icons"
    / "hicolor"
    / "scalable"
    / "apps"
    / "quest.entropy.bootstory.svg"
)
SVG_NAMESPACE = {"svg": "http://www.w3.org/2000/svg"}


class IconGeometryTests(unittest.TestCase):
    def test_colored_segments_share_one_circle(self):
        root = ElementTree.parse(ICON_PATH).getroot()
        segment_group = root.find("svg:g", SVG_NAMESPACE)
        self.assertIsNotNone(segment_group)
        segments = segment_group.findall("svg:path", SVG_NAMESPACE)
        self.assertEqual(len(segments), 5)

        endpoints = []
        for segment in segments:
            numbers = [float(value) for value in re.findall(r"-?\d+(?:\.\d+)?", segment.attrib["d"])]
            start_x, start_y = numbers[0:2]
            radius_x, radius_y = numbers[2:4]
            end_x, end_y = numbers[-2:]
            self.assertEqual((radius_x, radius_y), (18.0, 18.0))
            self.assertAlmostEqual(math.hypot(start_x - 32, start_y - 32), 18.0, delta=0.001)
            self.assertAlmostEqual(math.hypot(end_x - 32, end_y - 32), 18.0, delta=0.001)
            endpoints.append(((start_x, start_y), (end_x, end_y)))

        stroke_width = float(segment_group.attrib["stroke-width"])
        for previous, following in zip(endpoints, endpoints[1:]):
            self.assertGreater(math.dist(previous[1], following[0]), stroke_width)

    def test_needle_is_centered_on_the_pip(self):
        root = ElementTree.parse(ICON_PATH).getroot()
        needle = root.findall("svg:path", SVG_NAMESPACE)[0]
        points = [float(value) for value in re.findall(r"-?\d+(?:\.\d+)?", needle.attrib["d"])]
        base_a = points[0:2]
        tip = points[2:4]
        base_b = points[4:6]

        self.assertEqual([(base_a[index] + base_b[index]) / 2 for index in range(2)], [32.0, 32.0])
        self.assertAlmostEqual(tip[0] - 32, -(tip[1] - 32), places=6)

        pip = root.find("svg:circle", SVG_NAMESPACE)
        self.assertIsNotNone(pip)
        self.assertEqual((float(pip.attrib["cx"]), float(pip.attrib["cy"])), (32.0, 32.0))


if __name__ == "__main__":
    unittest.main()
