import cv2
import numpy as np

from .reference import BadmintonCourtReference


def _line_angle(x1, y1, x2, y2):
    angle = np.degrees(np.arctan2(y2 - y1, x2 - x1))
    return angle % 180


def _line_intersection(line_a, line_b):
    x1, y1, x2, y2 = line_a
    x3, y3, x4, y4 = line_b
    denom = (x1 - x2) * (y3 - y4) - (y1 - y2) * (x3 - x4)
    if abs(denom) < 1e-6:
        return None

    px = ((x1 * y2 - y1 * x2) * (x3 - x4) - (x1 - x2) * (x3 * y4 - y3 * x4)) / denom
    py = ((x1 * y2 - y1 * x2) * (y3 - y4) - (y1 - y2) * (x3 * y4 - y3 * x4)) / denom
    return np.array([px, py], dtype=np.float32)


def _inside_image(point, width, height, margin=0):
    return margin <= point[0] <= width - 1 - margin and margin <= point[1] <= height - 1 - margin


def _polygon_area(points):
    return abs(cv2.contourArea(np.array(points, dtype=np.float32)))


def _is_convex_quad(points):
    pts = np.array(points, dtype=np.float32)
    return len(cv2.convexHull(pts)) == 4 and cv2.isContourConvex(pts.astype(np.int32))


def _project_court_points(matrix, points):
    pts = np.array(points, dtype=np.float32).reshape(-1, 1, 2)
    return cv2.perspectiveTransform(pts, matrix).reshape(-1, 2)


def _badminton_line_alignment_score(corners, line_mask):
    height, width = line_mask.shape[:2]
    image_points = np.array(corners, dtype=np.float32)
    court_points = np.array([[0, 0], [6.1, 0], [6.1, 13.4], [0, 13.4]], dtype=np.float32)
    matrix = cv2.getPerspectiveTransform(court_points, image_points)

    expected = np.zeros((height, width), dtype=np.uint8)
    horizontal_ys = [0, 0.76, 4.72, 6.7, 8.68, 12.64, 13.4]
    vertical_xs = [0, 0.46, 3.05, 5.64, 6.1]

    for y in horizontal_ys:
        p1, p2 = _project_court_points(matrix, [(0, y), (6.1, y)])
        cv2.line(expected, tuple(np.round(p1).astype(int)), tuple(np.round(p2).astype(int)), 255, 5)

    for x in vertical_xs:
        p1, p2 = _project_court_points(matrix, [(x, 0), (x, 13.4)])
        cv2.line(expected, tuple(np.round(p1).astype(int)), tuple(np.round(p2).astype(int)), 255, 5)

    center_segments = [((3.05, 0), (3.05, 4.72)), ((3.05, 8.68), (3.05, 13.4))]
    for p1_court, p2_court in center_segments:
        p1, p2 = _project_court_points(matrix, [p1_court, p2_court])
        cv2.line(expected, tuple(np.round(p1).astype(int)), tuple(np.round(p2).astype(int)), 255, 5)

    expected_pixels = cv2.countNonZero(expected)
    if expected_pixels == 0:
        return 0.0

    dilated_mask = cv2.dilate(line_mask, cv2.getStructuringElement(cv2.MORPH_RECT, (9, 9)), iterations=1)
    overlap = cv2.bitwise_and(expected, dilated_mask)
    return cv2.countNonZero(overlap) / expected_pixels


def _badminton_horizontal_pattern_score(corners, horizontal_lines, image_shape):
    if not horizontal_lines:
        return 0.0

    height, _width = image_shape[:2]
    image_points = np.array(corners, dtype=np.float32)
    court_points = np.array([[0, 0], [6.1, 0], [6.1, 13.4], [0, 13.4]], dtype=np.float32)
    matrix = cv2.getPerspectiveTransform(court_points, image_points)

    expected_court_y = [0, 0.76, 4.72, 6.7, 8.68, 12.64, 13.4]
    weights = [5.0, 4.0, 1.6, 0.8, 1.6, 4.0, 5.0]
    detected_y = [float(line["mid"][1]) for line in horizontal_lines]
    tolerance = max(12.0, height * 0.022)

    weighted_score = 0.0
    total_weight = 0.0
    for court_y, weight in zip(expected_court_y, weights):
        p1, p2 = _project_court_points(matrix, [(0, court_y), (6.1, court_y)])
        expected_y = float((p1[1] + p2[1]) / 2.0)
        nearest = min(abs(y - expected_y) for y in detected_y)
        weighted_score += max(0.0, 1.0 - nearest / tolerance) * weight
        total_weight += weight

    return weighted_score / total_weight


def _horizontal_segment_support(line, p_left, p_right, image_width):
    x1, _y1, x2, _y2 = line["points"]
    seg_min, seg_max = sorted((x1, x2))
    quad_min, quad_max = sorted((float(p_left[0]), float(p_right[0])))
    overshoot = max(0.0, seg_min - quad_min) + max(0.0, quad_max - seg_max)
    return max(0.0, 1.0 - overshoot / max(1.0, image_width * 0.20))


def _side_segment_support(line, p_top, p_bottom, image_height):
    _x1, y1, _x2, y2 = line["points"]
    seg_min, seg_max = sorted((y1, y2))
    quad_min, quad_max = sorted((float(p_top[1]), float(p_bottom[1])))
    overshoot = max(0.0, seg_min - quad_min) + max(0.0, quad_max - seg_max)
    return max(0.0, 1.0 - overshoot / max(1.0, image_height * 0.16))
def _reference_segment_support(line, line_support, image_shape):
    if line_support is None:
        return 0.0

    height, width = image_shape[:2]
    x1, y1, x2, y2 = line["points"]
    length = float(np.hypot(x2 - x1, y2 - y1))
    if length < 1.0:
        return 0.0

    sample_count = max(18, int(length / 4.0))
    xs = np.linspace(float(x1), float(x2), sample_count)
    ys = np.linspace(float(y1), float(y2), sample_count)
    valid = (xs >= 0) & (xs < width) & (ys >= 0) & (ys < height)
    if np.mean(valid) < 0.35:
        return 0.0

    xs = np.clip(np.rint(xs[valid]).astype(np.int32), 0, width - 1)
    ys = np.clip(np.rint(ys[valid]).astype(np.int32), 0, height - 1)
    distances = line_support["distance_map"][ys, xs]
    tolerance = line_support["tolerance"]
    line_scores = 1.0 - np.clip(distances / tolerance, 0.0, 1.0)
    coverage = np.mean(distances <= tolerance)
    return float(0.65 * np.mean(line_scores) + 0.35 * coverage)


def _promote_far_baseline(lines, horizontal_lines, image_shape):
    height, _width = image_shape[:2]
    top_line, bottom_line, left_line, right_line = lines
    top_y = float(top_line["mid"][1])
    candidates = []

    for line in horizontal_lines:
        candidate_y = float(line["mid"][1])
        gap = top_y - candidate_y
        if gap <= height * 0.04 or gap >= height * 0.09:
            continue
        if candidate_y < height * 0.28:
            continue
        if line["length"] < top_line["length"] * 0.65:
            continue
        next_gap = min(
            [float(other["mid"][1]) - top_y for other in horizontal_lines if float(other["mid"][1]) > top_y] or [height]
        )
        if gap > next_gap * 0.9:
            continue
        candidates.append(line)

    if not candidates:
        return lines

    promoted_top = max(candidates, key=lambda item: item["length"])
    return promoted_top, bottom_line, left_line, right_line


def _dedupe_lines(lines, orientation, max_count):
    selected = []
    for line in sorted(lines, key=lambda item: item["length"], reverse=True):
        duplicate = False
        for existing in selected:
            if orientation == "horizontal":
                same_band = abs(line["mid"][1] - existing["mid"][1]) < 18
                same_angle = abs(line["angle"] - existing["angle"]) < 8
            else:
                same_band = abs(line["mid"][0] - existing["mid"][0]) < 22
                same_angle = abs(line["angle"] - existing["angle"]) < 10
            if same_band and same_angle:
                duplicate = True
                break
        if not duplicate:
            selected.append(line)
        if len(selected) >= max_count:
            break
    return selected


def _order_quad_points(points):
    pts = np.array(points, dtype=np.float32).reshape(-1, 2)
    if pts.shape[0] != 4:
        return None
    sums = pts.sum(axis=1)
    diffs = pts[:, 1] - pts[:, 0]
    ordered = np.array(
        [
            pts[np.argmin(sums)],
            pts[np.argmin(diffs)],
            pts[np.argmax(sums)],
            pts[np.argmax(diffs)],
        ],
        dtype=np.float32,
    )
    if len(np.unique(ordered.astype(np.int32), axis=0)) != 4:
        return None
    return ordered


def _build_green_court_mask(image, *, fallback_bottom_roi=True):
    hsv = cv2.cvtColor(image, cv2.COLOR_BGR2HSV)
    h, s, v = cv2.split(hsv)
    median_v = float(np.median(v))
    image_area = image.shape[0] * image.shape[1]

    green_primary = ((h >= 35) & (h <= 95) & (s >= 25) & (v >= max(25, median_v * 0.45)))
    green_cool = ((h >= 90) & (h <= 120) & (s >= 20) & (v >= max(25, median_v * 0.45)))
    green_mask = (green_primary | green_cool).astype(np.uint8) * 255
    green_mask = cv2.morphologyEx(green_mask, cv2.MORPH_OPEN, np.ones((5, 5), np.uint8), iterations=1)
    green_mask = cv2.morphologyEx(green_mask, cv2.MORPH_CLOSE, np.ones((25, 25), np.uint8), iterations=2)

    count, labels, stats, _centroids = cv2.connectedComponentsWithStats(green_mask)
    candidates = [
        idx
        for idx in range(1, count)
        if stats[idx, cv2.CC_STAT_AREA] > image_area * 0.045
    ]
    if candidates:
        court_idx = max(candidates, key=lambda idx: stats[idx, cv2.CC_STAT_AREA])
        return ((labels == court_idx).astype(np.uint8)) * 255

    if not fallback_bottom_roi:
        return green_mask

    fallback = np.zeros_like(green_mask)
    fallback[int(image.shape[0] * 0.30):, :] = 255
    return fallback


def _enhance_for_detection(image):
    """Return a list of pre-processed image variants for robust detection."""
    variants = [image]  # original

    h, w = image.shape[:2]
    gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
    median = np.median(gray)

    # 1. CLAHE on LAB L-channel (handles dark courts)
    lab = cv2.cvtColor(image, cv2.COLOR_BGR2LAB)
    l, a, b = cv2.split(lab)
    clahe = cv2.createCLAHE(clipLimit=4.0, tileGridSize=(8, 8))
    l_eq = clahe.apply(l)
    variants.append(cv2.cvtColor(cv2.merge([l_eq, a, b]), cv2.COLOR_LAB2BGR))

    # 2. Auto-brightness: when median < 80, boost
    if median < 80:
        alpha = min(3.0, 120.0 / max(median, 1))
        beta = int((90 - median) * 0.6)
        variants.append(cv2.convertScaleAbs(image, alpha=alpha, beta=beta))

    # 3. Gamma correction for very dark frames
    if median < 60:
        gamma = 0.55
        lut = np.array([(i / 255.0) ** gamma * 255 for i in range(256)], dtype=np.uint8)
        variants.append(cv2.LUT(image, lut))

    return variants


def build_court_line_mask(image):
    hsv = cv2.cvtColor(image, cv2.COLOR_BGR2HSV)
    h, s, v = cv2.split(hsv)
    gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
    median_v = np.median(v)
    green_mask = _build_green_court_mask(image)

    court_roi = cv2.dilate(green_mask, cv2.getStructuringElement(cv2.MORPH_RECT, (17, 17)), iterations=1)

    # White court lines can be less bright than the global frame median on
    # broadcast footage. Keep saturation strict and cap the value threshold so
    # visible bottom lines are not lost.
    v_white = max(105, min(145, median_v * 0.85))
    white_mask = (((s <= 90) & (v >= v_white)).astype(np.uint8)) * 255
    white_mask = cv2.bitwise_and(white_mask, court_roi)

    # Adaptive Canny
    canny_low = max(20, int(median_v * 0.8))
    canny_high = min(250, int(median_v * 2.4))
    blurred = cv2.GaussianBlur(gray, (3, 3), 0)
    edges = cv2.Canny(blurred, canny_low, canny_high)
    edges = cv2.bitwise_and(edges, court_roi)

    merged = cv2.bitwise_or(white_mask, edges)
    merged = cv2.morphologyEx(merged, cv2.MORPH_CLOSE, cv2.getStructuringElement(cv2.MORPH_RECT, (7, 5)), iterations=1)
    merged = cv2.morphologyEx(merged, cv2.MORPH_OPEN, cv2.getStructuringElement(cv2.MORPH_RECT, (3, 3)), iterations=1)
    return merged

def build_reference_line_mask(image):
    hsv = cv2.cvtColor(image, cv2.COLOR_BGR2HSV)
    h, s, v = cv2.split(hsv)

    green_mask = _build_green_court_mask(image, fallback_bottom_roi=False)

    court_roi = cv2.dilate(green_mask, cv2.getStructuringElement(cv2.MORPH_RECT, (13, 13)), iterations=1)
    median_v = np.median(v)
    v_white = max(110, min(150, median_v * 0.90))
    white_mask = (((s <= 90) & (v >= v_white)).astype(np.uint8)) * 255
    yellow_mask = (((h >= 12) & (h <= 42) & (s >= 45) & (v >= 120)).astype(np.uint8)) * 255
    line_mask = cv2.bitwise_and(cv2.bitwise_or(white_mask, yellow_mask), court_roi)
    line_mask = cv2.morphologyEx(line_mask, cv2.MORPH_CLOSE, cv2.getStructuringElement(cv2.MORPH_RECT, (5, 3)), iterations=1)
    line_mask = cv2.morphologyEx(line_mask, cv2.MORPH_OPEN, cv2.getStructuringElement(cv2.MORPH_RECT, (3, 3)), iterations=1)
    return line_mask


def detect_court_line_segments(image):
    height, width = image.shape[:2]
    mask = build_court_line_mask(image)
    min_line_length = max(46, int(min(width, height) * 0.10))
    max_gap = max(14, int(min(width, height) * 0.045))
    raw_lines = cv2.HoughLinesP(
        mask,
        rho=1,
        theta=np.pi / 180,
        threshold=60,
        minLineLength=min_line_length,
        maxLineGap=max_gap,
    )
    if raw_lines is None:
        return [], [], mask

    edge_margin = max(10, int(min(width, height) * 0.02))
    horizontal = []
    side = []
    for raw_line in raw_lines[:, 0, :]:
        x1, y1, x2, y2 = [int(v) for v in raw_line]
        length = float(np.hypot(x2 - x1, y2 - y1))
        if length < min_line_length:
            continue

        if (
            min(x1, x2) <= edge_margin
            or max(x1, x2) >= width - 1 - edge_margin
            or min(y1, y2) <= edge_margin
            or max(y1, y2) >= height - 1 - edge_margin
        ):
            continue

        angle = _line_angle(x1, y1, x2, y2)
        segment = {
            "points": (x1, y1, x2, y2),
            "length": length,
            "mid": ((x1 + x2) / 2.0, (y1 + y2) / 2.0),
            "angle": angle,
        }
        if min(angle, 180 - angle) <= 16:
            horizontal.append(segment)
        elif 45 <= angle <= 135:
            side.append(segment)

    return _dedupe_lines(horizontal, "horizontal", 14), _dedupe_lines(side, "side", 18), mask


def _score_court_quad(corners, image_shape, lines, line_mask, horizontal_lines, court_reference=None, line_support=None):
    height, width = image_shape[:2]
    top_left, top_right, bottom_right, bottom_left = corners
    points = np.array(corners, dtype=np.float32)

    if not all(_inside_image(point, width, height, margin=8) for point in points):
        return None
    if not _is_convex_quad(points):
        return None

    area = _polygon_area(points)
    image_area = width * height
    if area < image_area * 0.08:
        return None

    top_width = float(np.linalg.norm(top_right - top_left))
    bottom_width = float(np.linalg.norm(bottom_right - bottom_left))
    left_height = float(np.linalg.norm(bottom_left - top_left))
    right_height = float(np.linalg.norm(bottom_right - top_right))
    avg_height = (left_height + right_height) / 2.0
    if min(top_width, bottom_width, avg_height) <= 1:
        return None
    if avg_height < height * 0.22:
        return None
    if bottom_width < top_width * 0.60:
        return None

    center = np.mean(points, axis=0)
    top_y = (top_left[1] + top_right[1]) / 2.0
    bottom_y = (bottom_left[1] + bottom_right[1]) / 2.0
    width_ratio = top_width / bottom_width
    if not (width * 0.30 <= center[0] <= width * 0.80 and height * 0.45 <= center[1] <= height * 0.90):
        return None
    if top_y < height * 0.18 or bottom_y < height * 0.68:
        return None
    if not (0.35 <= width_ratio <= 0.95):
        return None

    min_edge_distance = min(
        np.min(points[:, 0]),
        width - 1 - np.max(points[:, 0]),
        np.min(points[:, 1]),
        height - 1 - np.max(points[:, 1]),
    )
    edge_limit = max(10, min(width, height) * 0.02)
    if min_edge_distance < edge_limit:
        return None

    left_dx = bottom_left[0] - top_left[0]
    right_dx = bottom_right[0] - top_right[0]
    if left_dx > width * 0.16 or right_dx < -width * 0.16:
        return None

    top_line, bottom_line, left_line, right_line = lines
    area_score = min(area / (image_area * 0.42), 1.0) * 44
    height_score = min(avg_height / (height * 0.62), 1.0) * 22
    perspective_score = (1.0 - min(abs(width_ratio - 0.66) / 0.22, 1.0)) * 16
    center_x_score = (1.0 - min(abs(center[0] - width * 0.50) / (width * 0.24), 1.0)) * 18
    center_y_score = (1.0 - min(abs(center[1] - height * 0.70) / (height * 0.20), 1.0)) * 8
    bottom_score = min(max((bottom_y / height - 0.74) / 0.18, 0), 1.0) * 8
    edge_score = min(min_edge_distance / (min(width, height) * 0.08), 1.0) * 6
    line_score = min(
        (top_line["length"] + bottom_line["length"] + left_line["length"] + right_line["length"])
        / (width * 2.0 + height),
        1.0,
    ) * 6
    horizontal_support = (
        _horizontal_segment_support(top_line, top_left, top_right, width)
        + _horizontal_segment_support(bottom_line, bottom_left, bottom_right, width)
    ) / 2.0
    side_support = (
        _side_segment_support(left_line, top_left, bottom_left, height)
        + _side_segment_support(right_line, top_right, bottom_right, height)
    ) / 2.0
    support_score = (horizontal_support * 0.55 + side_support * 0.45) * 24
    top_span = sorted((float(top_line["points"][0]), float(top_line["points"][2])))
    bottom_span = sorted((float(bottom_line["points"][0]), float(bottom_line["points"][2])))
    top_endpoint_alignment = 1.0 - min(
        (abs(float(top_left[0]) - top_span[0]) + abs(float(top_right[0]) - top_span[1])) / max(width * 0.34, 1.0),
        1.0,
    )
    bottom_endpoint_alignment = 1.0 - min(
        (abs(float(bottom_left[0]) - bottom_span[0]) + abs(float(bottom_right[0]) - bottom_span[1])) / max(width * 0.34, 1.0),
        1.0,
    )
    endpoint_alignment_value = (top_endpoint_alignment + bottom_endpoint_alignment) / 2.0
    endpoint_alignment_score = endpoint_alignment_value * 44
    left_reference_support = _reference_segment_support(left_line, line_support, image_shape)
    right_reference_support = _reference_segment_support(right_line, line_support, image_shape)
    clean_side_support_value = min(left_reference_support, right_reference_support)
    clean_side_support_score = min(1.0, clean_side_support_value / 0.75) * 42

    alignment_value = _badminton_line_alignment_score(corners, line_mask)
    pattern_value = _badminton_horizontal_pattern_score(corners, horizontal_lines, image_shape)
    reference_value = 0.0
    reference_details = {}
    if court_reference is not None:
        reference_value, reference_details = court_reference.score_line_support(corners, line_support, image_shape)

    alignment_score = alignment_value * 10
    pattern_score = pattern_value * 110
    reference_score = reference_value * 18
    total_score = (
        area_score
        + height_score
        + perspective_score
        + center_x_score
        + center_y_score
        + bottom_score
        + edge_score
        + line_score
        + support_score
        + endpoint_alignment_score
        + clean_side_support_score
        + alignment_score
        + pattern_score
        + reference_score
    )
    details = {
        "alignment_score": round(float(alignment_value), 4),
        "horizontal_pattern_score": round(float(pattern_value), 4),
        "endpoint_alignment_score": round(float(endpoint_alignment_value), 4),
        "clean_side_support_score": round(float(clean_side_support_value), 4),
        **reference_details,
    }
    return total_score, details


def _detect_surface_court_corners(image, court_reference, line_support):
    height, width = image.shape[:2]
    mask = _build_green_court_mask(image, fallback_bottom_roi=False)
    contours, _hierarchy = cv2.findContours(mask, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
    if not contours:
        return None, None

    image_area = width * height
    candidates = []
    for contour in sorted(contours, key=cv2.contourArea, reverse=True)[:4]:
        contour_area = float(cv2.contourArea(contour))
        if contour_area < image_area * 0.10:
            continue

        perimeter = cv2.arcLength(contour, True)
        quad = None
        for epsilon_ratio in (0.018, 0.024, 0.032, 0.045):
            approx = cv2.approxPolyDP(contour, epsilon_ratio * perimeter, True)
            if len(approx) == 4:
                quad = approx.reshape(4, 2)
                break
        if quad is None:
            hull = cv2.convexHull(contour)
            rect = cv2.boxPoints(cv2.minAreaRect(hull))
            quad = rect.reshape(4, 2)

        ordered = _order_quad_points(quad)
        if ordered is None:
            continue

        area = _polygon_area(ordered)
        if not (image_area * 0.12 <= area <= image_area * 0.62):
            continue
        if not _is_convex_quad(ordered):
            continue

        top_left, top_right, bottom_right, bottom_left = ordered
        top_width = float(np.linalg.norm(top_right - top_left))
        bottom_width = float(np.linalg.norm(bottom_right - bottom_left))
        left_height = float(np.linalg.norm(bottom_left - top_left))
        right_height = float(np.linalg.norm(bottom_right - top_right))
        if min(top_width, bottom_width, left_height, right_height) < min(width, height) * 0.12:
            continue
        if bottom_width < top_width * 0.75:
            continue
        center = np.mean(ordered, axis=0)
        if not (width * 0.22 <= center[0] <= width * 0.78 and height * 0.42 <= center[1] <= height * 0.88):
            continue

        reference_score, reference_details = court_reference.score_line_support(
            ordered,
            line_support,
            image.shape,
        )
        if reference_score < 0.10:
            continue

        score = contour_area / image_area + reference_score
        candidates.append((score, ordered, reference_details))

    if not candidates:
        return None, None

    _score, corners, details = max(candidates, key=lambda item: item[0])
    return corners, details


def auto_detect_court_corners(image):
    """Auto-detect with multi-stage preprocessing for robustness."""
    court_reference = BadmintonCourtReference()

    # Try each enhanced variant
    variants = _enhance_for_detection(image)
    best_result = None
    best_score = 0

    for v_idx, variant in enumerate(variants):
        horizontal_lines, side_lines, mask = detect_court_line_segments(variant)
        if len(horizontal_lines) < 2 or len(side_lines) < 2:
            continue

        reference_mask = build_reference_line_mask(variant)
        line_support = court_reference.prepare_line_support(reference_mask, variant.shape)

        height, width = variant.shape[:2]
        horizontals = sorted(horizontal_lines, key=lambda x: x["mid"][1])
        sides = sorted(side_lines, key=lambda x: x["mid"][0])

        for top_idx, top_line in enumerate(horizontals):
            for bottom_line in horizontals[top_idx + 1:]:
                if bottom_line["mid"][1] - top_line["mid"][1] < height * 0.20:
                    continue
                for left_idx, left_line in enumerate(sides):
                    for right_line in sides[left_idx + 1:]:
                        if right_line["mid"][0] - left_line["mid"][0] < width * 0.15:
                            continue

                        intersections = [
                            _line_intersection(top_line["points"], left_line["points"]),
                            _line_intersection(top_line["points"], right_line["points"]),
                            _line_intersection(bottom_line["points"], right_line["points"]),
                            _line_intersection(bottom_line["points"], left_line["points"]),
                        ]
                        if any(p is None for p in intersections):
                            continue

                        scored = _score_court_quad(
                            intersections, variant.shape,
                            (top_line, bottom_line, left_line, right_line),
                            mask, horizontal_lines,
                            court_reference, line_support)
                        if scored is None:
                            continue
                        score, details = scored
                        if score > best_score:
                            best_score = score
                            best_result = {
                                "corners": intersections,
                                "score": score, "details": details,
                                "lines": (top_line, bottom_line, left_line, right_line),
                                "mask": mask,
                                "variant_scale": image.shape[0] / variant.shape[0]
                            }

    if best_result is None:
        mask = build_court_line_mask(image)
        reference_mask = build_reference_line_mask(image)
        line_support = court_reference.prepare_line_support(reference_mask, image.shape)
        surface_corners, surface_details = _detect_surface_court_corners(
            image,
            court_reference,
            line_support,
        )
        if surface_corners is not None:
            horizontal_lines, side_lines, _mask = detect_court_line_segments(image)
            debug = {
                "horizontal": horizontal_lines,
                "side": side_lines,
                "score": None,
                "details": {
                    "surface_fallback": True,
                    **(surface_details or {}),
                },
            }
            corners = [(int(round(p[0])), int(round(p[1]))) for p in surface_corners]
            return corners, mask, debug

        debug = {"horizontal": [], "side": [], "score": None, "details": None}
        return None, np.zeros(image.shape[:2], dtype=np.uint8), debug

    # Scale corners back to original resolution
    scale = image.shape[0] / best_result["corners"][0].shape[0] if False else 1.0
    # (variants don't change resolution, so scale=1. No scaling needed for CLAHE/brighten)

    horizontal_lines, side_lines, mask = detect_court_line_segments(image)
    debug = {"horizontal": horizontal_lines, "side": side_lines,
             "score": best_result["score"], "details": best_result["details"]}

    # Promote far baseline and refine
    selected_lines = _promote_far_baseline(best_result["lines"], horizontal_lines, image.shape)
    top_line, bottom_line, left_line, right_line = selected_lines
    corners_float = [
        _line_intersection(top_line["points"], left_line["points"]),
        _line_intersection(top_line["points"], right_line["points"]),
        _line_intersection(bottom_line["points"], right_line["points"]),
        _line_intersection(bottom_line["points"], left_line["points"]),
    ]
    if any(p is None for p in corners_float):
        corners_float = best_result["corners"]

    reference_mask = build_reference_line_mask(image)
    line_support = court_reference.prepare_line_support(reference_mask, image.shape)
    final_scored = _score_court_quad(
        corners_float, image.shape, selected_lines, mask,
        horizontal_lines, court_reference, line_support)
    if final_scored is not None:
        debug["score"], debug["details"] = final_scored

    corners = [(int(round(p[0])), int(round(p[1]))) for p in corners_float]
    return corners, mask, debug

def render_auto_court_preview(image, corners, roi_corners=None, debug=None):
    preview = image.copy()

    if corners:
        court_reference = BadmintonCourtReference()
        for start, end, weight in court_reference.project_lines(corners):
            p1 = tuple(np.round(start).astype(int))
            p2 = tuple(np.round(end).astype(int))
            color = (0, 255, 0) if weight >= 1.3 else (0, 220, 255)
            thickness = 3 if weight >= 1.3 else 2
            cv2.line(preview, p1, p2, color, thickness, cv2.LINE_AA)

        points = np.array(corners, dtype=np.int32)
        cv2.polylines(preview, [points], True, (0, 255, 0), 3, cv2.LINE_AA)
        for idx, point in enumerate(corners, start=1):
            cv2.circle(preview, point, 6, (0, 0, 255), -1, cv2.LINE_AA)
            cv2.putText(preview, str(idx), (point[0] + 8, point[1] - 8), cv2.FONT_HERSHEY_SIMPLEX, 0.75, (0, 0, 255), 2, cv2.LINE_AA)
    elif debug:
        for line in debug.get("horizontal", []):
            cv2.line(preview, line["points"][:2], line["points"][2:], (0, 220, 255), 2)
        for line in debug.get("side", []):
            cv2.line(preview, line["points"][:2], line["points"][2:], (255, 180, 0), 2)

    if roi_corners:
        cv2.rectangle(preview, roi_corners[0], roi_corners[1], (255, 0, 0), 3)

    cv2.rectangle(preview, (0, 0), (preview.shape[1], 44), (0, 0, 0), -1)
    detail = ""
    if debug and debug.get("details"):
        reference_score = debug["details"].get("reference_score")
        if isinstance(reference_score, (int, float)):
            detail = f" ref={reference_score:.2f}"
    cv2.putText(
        preview,
        f"Auto court detection{detail}: Enter/Y accept, M/R/Esc manual",
        (16, 29),
        cv2.FONT_HERSHEY_SIMPLEX,
        0.72,
        (255, 255, 255),
        2,
        cv2.LINE_AA,
    )
    return preview
