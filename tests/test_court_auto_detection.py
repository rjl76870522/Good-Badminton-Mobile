import cv2
import numpy as np

from badminton_analysis.court.detector import (
    _build_green_court_mask,
    _detect_surface_court_corners,
    auto_detect_court_corners,
)
from badminton_analysis.court.reference import BadmintonCourtReference


def test_broadcast_style_green_court_returns_corners():
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
    assert detected is not None
    assert len(detected) == 4


def test_surface_fallback_does_not_use_generic_color_range():
    image = np.zeros((360, 640, 3), dtype=np.uint8)
    image[:] = (35, 35, 35)
    # HSV hue outside the supported court-color ranges, but with enough
    # brightness/saturation to be accepted by the very broad ROI fallback.
    generic_only_hsv = np.full((360, 640, 3), (150, 80, 150), dtype=np.uint8)
    generic_only_bgr = cv2.cvtColor(generic_only_hsv, cv2.COLOR_HSV2BGR)
    quad = np.array([[120, 160], [520, 155], [590, 330], [60, 330]], dtype=np.int32)
    cv2.fillConvexPoly(image, quad, tuple(int(v) for v in generic_only_bgr[0, 0]))

    roi_mask = _build_green_court_mask(image, fallback_bottom_roi=False)
    surface_mask = _build_green_court_mask(
        image,
        fallback_bottom_roi=False,
        include_generic_range=False,
    )

    assert cv2.countNonZero(roi_mask) > image.size // 20
    assert cv2.countNonZero(surface_mask) == 0


def test_surface_fallback_uses_the_prepared_support_mask():
    image = np.zeros((360, 640, 3), dtype=np.uint8)
    image[:] = (35, 35, 35)
    quad = np.array(
        [[150, 150], [490, 150], [570, 340], [70, 340]],
        dtype=np.int32,
    )
    cv2.fillConvexPoly(image, quad, (82, 170, 112))

    line_mask = np.zeros(image.shape[:2], dtype=np.uint8)
    cv2.polylines(line_mask, [quad], True, 255, 5, cv2.LINE_AA)
    reference = BadmintonCourtReference()
    line_support = reference.prepare_line_support(line_mask, image.shape)

    assert isinstance(line_support["support_mask"], np.ndarray)
    _detect_surface_court_corners(image, reference, line_support)
