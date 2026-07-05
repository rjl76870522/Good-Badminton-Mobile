import unittest

import cv2
import numpy as np

from badminton_analysis.court.detector import auto_detect_court_corners
from badminton_analysis.court.reference import BadmintonCourtReference


class CourtAutoDetectionTest(unittest.TestCase):
    def test_broadcast_style_green_court_returns_corners(self):
        image = np.zeros((720, 1080, 3), dtype=np.uint8)
        image[:] = (60, 25, 20)
        corners = np.array(
            [[295, 300], [785, 320], [930, 650], [140, 650]],
            dtype=np.int32,
        )
        cv2.fillConvexPoly(image, corners, (82, 170, 112))

        reference = BadmintonCourtReference()
        for start, end, _weight in reference.project_lines(corners.astype(np.float32)):
            cv2.line(
                image,
                tuple(np.round(start).astype(int)),
                tuple(np.round(end).astype(int)),
                (235, 235, 230),
                6,
                cv2.LINE_AA,
            )

        detected, _mask, _debug = auto_detect_court_corners(image)

        self.assertIsNotNone(detected)
        self.assertEqual(len(detected), 4)


if __name__ == "__main__":
    unittest.main()
