"""Stable movement metrics built from detections.jsonl.

This module assumes the court corners are already correct. Its job is to make
player movement metrics less sensitive to single-frame pose jumps.
"""

from __future__ import annotations

import json
import math
import os
from dataclasses import dataclass
from pathlib import Path
from statistics import median
from typing import Any


COURT_WIDTH_M = 6.1
COURT_LENGTH_M = 13.4
COURT_FILTER_MARGIN_M = 0.85
MAX_STABLE_SPEED_MPS = 8.5
MAX_SEGMENT_DT_SEC = 0.75
ROBUST_PEAK_PERCENTILE = 95
SMOOTHING_WINDOW = 5
HIGH_INTENSITY_SPEED_MPS = 4.0


@dataclass(frozen=True)
class RawPoint:
    time_sec: float
    x: float
    y: float


@dataclass(frozen=True)
class StablePoint:
    time_sec: float
    x: float
    y: float
    speed_mps: float


@dataclass
class PlayerMetrics:
    name: str
    detected_frames: int
    raw_points: list[RawPoint]
    accepted_points: list[RawPoint]
    stable_points: list[StablePoint]
    dropped_jump_count: int
    raw_max_speed_mps: float

    def to_dict(self) -> dict[str, Any]:
        active_time = 0.0
        if self.stable_points:
            active_time = max(self.stable_points[-1].time_sec - self.stable_points[0].time_sec, 0.0)

        speeds = [point.speed_mps for point in self.stable_points if point.speed_mps > 0]
        total_distance = _total_distance(self.stable_points)
        avg_speed = total_distance / active_time if active_time > 0 else 0.0
        peak_speed = percentile(speeds, ROBUST_PEAK_PERCENTILE)
        distance_per_min = total_distance / active_time * 60.0 if active_time > 0 else 0.0
        positions = [(point.x, point.y) for point in self.stable_points]
        quality = _tracking_quality(
            raw_count=len(self.raw_points),
            accepted_count=len(self.accepted_points),
            dropped_count=self.dropped_jump_count,
        )

        return {
            "name": self.name,
            "detected_frames": len(self.raw_points),
            "active_time_sec": round(active_time, 2),
            "total_distance_m": round(total_distance, 2),
            "max_speed_mps": round(peak_speed, 2),
            "raw_max_speed_mps": round(self.raw_max_speed_mps, 2),
            "avg_speed_mps": round(avg_speed, 2),
            "distance_per_min": round(distance_per_min, 2),
            "stable_position_frames": len(self.stable_points),
            "dropped_jump_count": self.dropped_jump_count,
            "tracking_quality_score": quality,
            **coverage_metrics(positions),
            **zone_metrics(positions, speeds),
        }


def summarize_detections(detections_path: str | os.PathLike[str] | None) -> dict[str, Any]:
    """Summarize detections with smoothed tracks and jump rejection."""
    frames, shuttlecock_frames, raw_by_player, detected_by_player = load_detection_points(detections_path)
    if frames <= 0:
        return {
            "frames_with_detections": 0,
            "frames_with_shuttlecock": 0,
            "shuttlecock_ratio": 0.0,
            "players": [],
            "primary_player": None,
            "match": empty_match_summary(),
        }

    player_metrics = [
        build_player_metrics(name, points, detected_by_player.get(name, 0))
        for name, points in raw_by_player.items()
    ]
    player_summaries = [metrics.to_dict() for metrics in player_metrics]
    player_summaries.sort(key=lambda item: item["total_distance_m"], reverse=True)
    primary = player_summaries[0] if player_summaries else None

    match = empty_match_summary()
    shuttlecock_ratio = shuttlecock_frames / frames if frames > 0 else 0.0
    if player_summaries:
        match.update(build_match_summary(player_summaries, primary))

    match["frames_with_detections"] = frames
    match["frames_with_shuttlecock"] = shuttlecock_frames
    match["shuttlecock_ratio"] = round(shuttlecock_ratio, 2)

    return {
        "frames_with_detections": frames,
        "frames_with_shuttlecock": shuttlecock_frames,
        "shuttlecock_ratio": round(shuttlecock_ratio, 2),
        "players": player_summaries,
        "primary_player": primary,
        "match": match,
    }


def load_stable_player_lookup(detections_path: str | os.PathLike[str] | None) -> dict[float, dict[str, StablePoint]]:
    """Return stable player positions keyed by detection timestamp."""
    _frames, _shuttlecock_frames, raw_by_player, detected_by_player = load_detection_points(detections_path)
    lookup: dict[float, dict[str, StablePoint]] = {}
    for name, points in raw_by_player.items():
        metrics = build_player_metrics(name, points, detected_by_player.get(name, 0))
        for point in metrics.stable_points:
            lookup.setdefault(round(point.time_sec, 6), {})[name] = point
    return lookup


def build_match_summary(
    player_summaries: list[dict[str, Any]],
    primary: dict[str, Any] | None,
) -> dict[str, Any]:
    total_distance = sum(float(player.get("total_distance_m") or 0.0) for player in player_summaries)
    total_active_time = sum(float(player.get("active_time_sec") or 0.0) for player in player_summaries)
    match_active_time = max(float(player.get("active_time_sec") or 0.0) for player in player_summaries)
    avg_speed = total_distance / total_active_time if total_active_time > 0 else 0.0
    distance_per_min = avg_speed * 60.0
    combined_distance_per_min = total_distance / match_active_time * 60.0 if match_active_time > 0 else 0.0
    max_speed = max(float(player.get("max_speed_mps") or 0.0) for player in player_summaries)
    raw_max_speed = max(float(player.get("raw_max_speed_mps") or 0.0) for player in player_summaries)
    stable_frames = sum(int(player.get("stable_position_frames") or 0) for player in player_summaries)
    dropped_jumps = sum(int(player.get("dropped_jump_count") or 0) for player in player_summaries)
    high_intensity_moves = sum(int(player.get("high_intensity_moves") or 0) for player in player_summaries)
    tracking_quality = _weighted_average(
        player_summaries,
        "tracking_quality_score",
        "stable_position_frames",
    )
    coverage_area = max(float(player.get("coverage_area_m2") or 0.0) for player in player_summaries)
    span_x = max(float(player.get("court_span_x_m") or 0.0) for player in player_summaries)
    span_y = max(float(player.get("court_span_y_m") or 0.0) for player in player_summaries)

    summary = {
        "total_distance_m": round(total_distance, 2),
        "primary_player_distance_m": round(float((primary or {}).get("total_distance_m") or 0.0), 2),
        "max_speed_mps": round(max_speed, 2),
        "raw_max_speed_mps": round(raw_max_speed, 2),
        "avg_speed_mps": round(avg_speed, 2),
        "active_time_sec": round(match_active_time, 2),
        "distance_per_min": round(distance_per_min, 2),
        "combined_distance_per_min": round(combined_distance_per_min, 2),
        "coverage_area_m2": round(coverage_area, 2),
        "court_span_x_m": round(span_x, 2),
        "court_span_y_m": round(span_y, 2),
        "front_court_ratio": round(_weighted_average(player_summaries, "front_court_ratio", "stable_position_frames"), 2),
        "back_court_ratio": round(_weighted_average(player_summaries, "back_court_ratio", "stable_position_frames"), 2),
        "left_court_ratio": round(_weighted_average(player_summaries, "left_court_ratio", "stable_position_frames"), 2),
        "right_court_ratio": round(_weighted_average(player_summaries, "right_court_ratio", "stable_position_frames"), 2),
        "high_intensity_moves": high_intensity_moves,
        "stable_position_frames": stable_frames,
        "dropped_jump_count": dropped_jumps,
        "tracking_quality_score": int(round(tracking_quality)),
    }
    summary["intensity_score"] = calculate_intensity_score(
        distance_per_min=summary["distance_per_min"],
        max_speed_mps=summary["max_speed_mps"],
        active_time_sec=summary["active_time_sec"],
    )
    return summary


def load_detection_points(
    detections_path: str | os.PathLike[str] | None,
) -> tuple[int, int, dict[str, list[RawPoint]], dict[str, int]]:
    frames = 0
    shuttlecock_frames = 0
    raw_by_player: dict[str, list[RawPoint]] = {}
    detected_by_player: dict[str, int] = {}

    if not detections_path or not os.path.isfile(detections_path):
        return frames, shuttlecock_frames, raw_by_player, detected_by_player

    with Path(detections_path).open("r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                record = json.loads(line)
            except json.JSONDecodeError:
                continue

            frames += 1
            time_sec = _finite_float(record.get("time_sec"))
            if record.get("shuttlecock", {}).get("image"):
                shuttlecock_frames += 1

            for name, payload in (record.get("players") or {}).items():
                if not isinstance(payload, dict):
                    continue
                detected_by_player[name] = detected_by_player.get(name, 0) + 1
                point = _raw_point(time_sec, payload.get("court"))
                if point is not None:
                    raw_by_player.setdefault(name, []).append(point)

    for points in raw_by_player.values():
        points.sort(key=lambda point: point.time_sec)
    return frames, shuttlecock_frames, raw_by_player, detected_by_player


def build_player_metrics(name: str, raw_points: list[RawPoint], detected_frames: int) -> PlayerMetrics:
    accepted_points, dropped_jump_count, raw_max_speed = reject_tracking_jumps(raw_points)
    stable_points = smooth_and_score_points(accepted_points)
    return PlayerMetrics(
        name=name,
        detected_frames=detected_frames,
        raw_points=raw_points,
        accepted_points=accepted_points,
        stable_points=stable_points,
        dropped_jump_count=dropped_jump_count,
        raw_max_speed_mps=raw_max_speed,
    )


def reject_tracking_jumps(points: list[RawPoint]) -> tuple[list[RawPoint], int, float]:
    accepted: list[RawPoint] = []
    dropped = 0
    raw_max_speed = 0.0

    for point in points:
        if not _inside_court_margin(point):
            dropped += 1
            continue
        if not accepted:
            accepted.append(point)
            continue

        previous = accepted[-1]
        dt = point.time_sec - previous.time_sec
        if dt <= 0:
            dropped += 1
            continue
        if dt > MAX_SEGMENT_DT_SEC:
            accepted.append(point)
            continue

        dist = math.dist((previous.x, previous.y), (point.x, point.y))
        speed = dist / dt
        raw_max_speed = max(raw_max_speed, speed)
        if speed > MAX_STABLE_SPEED_MPS:
            dropped += 1
            continue
        accepted.append(point)

    return accepted, dropped, raw_max_speed


def smooth_and_score_points(points: list[RawPoint]) -> list[StablePoint]:
    if not points:
        return []

    smoothed_xy = _median_smooth(points, SMOOTHING_WINDOW)
    stable: list[StablePoint] = []
    previous: StablePoint | None = None
    for point, (x, y) in zip(points, smoothed_xy):
        speed = 0.0
        if previous is not None:
            dt = point.time_sec - previous.time_sec
            if 0 < dt <= MAX_SEGMENT_DT_SEC:
                dist = math.dist((previous.x, previous.y), (x, y))
                speed = min(dist / dt, MAX_STABLE_SPEED_MPS)
        stable.append(StablePoint(time_sec=point.time_sec, x=x, y=y, speed_mps=speed))
        previous = stable[-1]
    return stable


def percentile(values: list[float], pct: int) -> float:
    if not values:
        return 0.0
    ordered = sorted(values)
    if len(ordered) == 1:
        return ordered[0]
    rank = (len(ordered) - 1) * pct / 100.0
    lower = math.floor(rank)
    upper = math.ceil(rank)
    if lower == upper:
        return ordered[int(rank)]
    weight = rank - lower
    return ordered[lower] * (1.0 - weight) + ordered[upper] * weight


def calculate_intensity_score(
    *,
    distance_per_min: float,
    max_speed_mps: float,
    active_time_sec: float,
) -> int:
    work_rate_score = min(distance_per_min / 130.0 * 100.0, 100.0)
    speed_score = min(max_speed_mps / 6.0 * 100.0, 100.0)
    duration_score = min(active_time_sec / 20.0 * 100.0, 100.0)
    score = 0.50 * work_rate_score + 0.35 * speed_score + 0.15 * duration_score
    return int(round(max(0.0, min(score, 100.0))))


def coverage_metrics(positions: list[tuple[float, float]]) -> dict[str, float]:
    if not positions:
        return {
            "court_span_x_m": 0.0,
            "court_span_y_m": 0.0,
            "coverage_area_m2": 0.0,
        }
    xs = [point[0] for point in positions]
    ys = [point[1] for point in positions]
    span_x = max(xs) - min(xs)
    span_y = max(ys) - min(ys)
    return {
        "court_span_x_m": round(span_x, 2),
        "court_span_y_m": round(span_y, 2),
        "coverage_area_m2": round(span_x * span_y, 2),
    }


def zone_metrics(
    positions: list[tuple[float, float]],
    speed_samples: list[float],
) -> dict[str, float | int]:
    if not positions:
        return {
            "front_court_ratio": 0.0,
            "back_court_ratio": 0.0,
            "left_court_ratio": 0.0,
            "right_court_ratio": 0.0,
            "high_intensity_moves": 0,
        }

    total = len(positions)
    left_count = sum(1 for x, _ in positions if x < COURT_WIDTH_M / 2)
    front_count = sum(1 for _, y in positions if y < COURT_LENGTH_M / 2)
    high_intensity_moves = sum(1 for speed in speed_samples if speed >= HIGH_INTENSITY_SPEED_MPS)
    return {
        "front_court_ratio": round(front_count / total, 2),
        "back_court_ratio": round((total - front_count) / total, 2),
        "left_court_ratio": round(left_count / total, 2),
        "right_court_ratio": round((total - left_count) / total, 2),
        "high_intensity_moves": int(high_intensity_moves),
    }


def empty_match_summary() -> dict[str, Any]:
    return {
        "total_distance_m": 0.0,
        "primary_player_distance_m": 0.0,
        "max_speed_mps": 0.0,
        "raw_max_speed_mps": 0.0,
        "avg_speed_mps": 0.0,
        "active_time_sec": 0.0,
        "distance_per_min": 0.0,
        "combined_distance_per_min": 0.0,
        "coverage_area_m2": 0.0,
        "court_span_x_m": 0.0,
        "court_span_y_m": 0.0,
        "front_court_ratio": 0.0,
        "back_court_ratio": 0.0,
        "left_court_ratio": 0.0,
        "right_court_ratio": 0.0,
        "high_intensity_moves": 0,
        "stable_position_frames": 0,
        "dropped_jump_count": 0,
        "tracking_quality_score": 0,
        "frames_with_detections": 0,
        "frames_with_shuttlecock": 0,
        "shuttlecock_ratio": 0.0,
        "intensity_score": 0,
    }


def _raw_point(time_sec: float | None, court_position: Any) -> RawPoint | None:
    if time_sec is None or not isinstance(court_position, (list, tuple)) or len(court_position) < 2:
        return None
    x = _finite_float(court_position[0])
    y = _finite_float(court_position[1])
    if x is None or y is None:
        return None
    return RawPoint(time_sec=time_sec, x=x, y=y)


def _finite_float(value: Any) -> float | None:
    if not isinstance(value, (int, float)):
        return None
    value = float(value)
    return value if math.isfinite(value) else None


def _inside_court_margin(point: RawPoint) -> bool:
    margin = COURT_FILTER_MARGIN_M
    return (
        -margin <= point.x <= COURT_WIDTH_M + margin
        and -margin <= point.y <= COURT_LENGTH_M + margin
    )


def _median_smooth(points: list[RawPoint], window: int) -> list[tuple[float, float]]:
    if len(points) < 3:
        return [(point.x, point.y) for point in points]

    radius = max(window // 2, 1)
    smoothed: list[tuple[float, float]] = []
    for idx in range(len(points)):
        start = max(0, idx - radius)
        end = min(len(points), idx + radius + 1)
        chunk = points[start:end]
        smoothed.append((
            float(median(point.x for point in chunk)),
            float(median(point.y for point in chunk)),
        ))
    return smoothed


def _total_distance(points: list[StablePoint]) -> float:
    total = 0.0
    for previous, current in zip(points, points[1:]):
        dt = current.time_sec - previous.time_sec
        if 0 < dt <= MAX_SEGMENT_DT_SEC:
            total += math.dist((previous.x, previous.y), (current.x, current.y))
    return total


def _tracking_quality(raw_count: int, accepted_count: int, dropped_count: int) -> int:
    if raw_count <= 0:
        return 0
    accepted_ratio = accepted_count / raw_count
    dropped_ratio = dropped_count / max(raw_count + dropped_count, 1)
    score = accepted_ratio * 100.0 - dropped_ratio * 35.0
    return int(round(max(0.0, min(score, 100.0))))


def _weighted_average(items: list[dict[str, Any]], value_key: str, weight_key: str) -> float:
    numerator = 0.0
    denominator = 0.0
    for item in items:
        value = float(item.get(value_key) or 0.0)
        weight = float(item.get(weight_key) or 0.0)
        if weight <= 0:
            continue
        numerator += value * weight
        denominator += weight
    if denominator <= 0:
        return 0.0
    return numerator / denominator
