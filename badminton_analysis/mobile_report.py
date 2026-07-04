"""Build mobile-app friendly summaries from Good-Badminton outputs."""

from __future__ import annotations

import json
import math
import os
from dataclasses import dataclass
from typing import Any


MAX_PLAUSIBLE_SPEED_MPS = 12.0
ROBUST_PEAK_PERCENTILE = 95


@dataclass
class PlayerStats:
    name: str
    detected_frames: int = 0
    first_time_sec: float | None = None
    last_time_sec: float | None = None
    last_position: tuple[float, float] | None = None
    last_time_for_position: float | None = None
    total_distance_m: float = 0.0
    raw_max_speed_mps: float = 0.0
    speed_samples_mps: list[float] | None = None

    def add_detection(
        self,
        time_sec: float | None,
        court_position: list[float] | tuple[float, float] | None,
        speed_mps: float | None,
    ) -> None:
        self.detected_frames += 1
        if time_sec is not None:
            if self.first_time_sec is None:
                self.first_time_sec = time_sec
            self.last_time_sec = time_sec

        if self.speed_samples_mps is None:
            self.speed_samples_mps = []

        if speed_mps is not None and math.isfinite(speed_mps) and speed_mps >= 0:
            self.raw_max_speed_mps = max(self.raw_max_speed_mps, float(speed_mps))
            if speed_mps <= MAX_PLAUSIBLE_SPEED_MPS:
                self.speed_samples_mps.append(float(speed_mps))

        if not court_position or len(court_position) < 2 or time_sec is None:
            return

        x, y = float(court_position[0]), float(court_position[1])
        position = (x, y)

        if self.last_position is not None and self.last_time_for_position is not None:
            dt = max(time_sec - self.last_time_for_position, 0.0)
            dist = math.dist(self.last_position, position)
            # Drop obvious tracking jumps while allowing short elite-level bursts.
            computed_speed = dist / dt if dt > 0 else 0.0
            self.raw_max_speed_mps = max(self.raw_max_speed_mps, computed_speed)
            if dt <= 1.0 and computed_speed <= MAX_PLAUSIBLE_SPEED_MPS:
                self.total_distance_m += dist
                self.speed_samples_mps.append(computed_speed)

        self.last_position = position
        self.last_time_for_position = time_sec

    def to_dict(self) -> dict[str, Any]:
        active_time = 0.0
        if self.first_time_sec is not None and self.last_time_sec is not None:
            active_time = max(self.last_time_sec - self.first_time_sec, 0.0)
        avg_speed = self.total_distance_m / active_time if active_time > 0 else 0.0
        peak_speed = percentile(self.speed_samples_mps or [], ROBUST_PEAK_PERCENTILE)
        return {
            "name": self.name,
            "detected_frames": self.detected_frames,
            "active_time_sec": round(active_time, 2),
            "total_distance_m": round(self.total_distance_m, 2),
            "max_speed_mps": round(peak_speed, 2),
            "raw_max_speed_mps": round(self.raw_max_speed_mps, 2),
            "avg_speed_mps": round(avg_speed, 2),
        }


def load_json(path: str | os.PathLike[str] | None) -> dict[str, Any]:
    if not path or not os.path.isfile(path):
        return {}
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


def summarize_detections(detections_path: str | os.PathLike[str] | None) -> dict[str, Any]:
    """Calculate lightweight movement metrics from detections.jsonl."""
    players: dict[str, PlayerStats] = {}
    frames = 0
    shuttlecock_frames = 0

    if not detections_path or not os.path.isfile(detections_path):
        return {
            "frames_with_detections": 0,
            "players": [],
            "primary_player": None,
            "match": _empty_match_summary(),
        }

    with open(detections_path, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                record = json.loads(line)
            except json.JSONDecodeError:
                continue

            frames += 1
            time_sec = record.get("time_sec")
            if record.get("shuttlecock", {}).get("image"):
                shuttlecock_frames += 1

            for name, payload in (record.get("players") or {}).items():
                if not isinstance(payload, dict):
                    continue
                player = players.setdefault(name, PlayerStats(name=name))
                player.add_detection(
                    time_sec=time_sec,
                    court_position=payload.get("court"),
                    speed_mps=payload.get("speed"),
                )

    player_summaries = [p.to_dict() for p in players.values()]
    player_summaries.sort(key=lambda item: item["total_distance_m"], reverse=True)
    primary = player_summaries[0] if player_summaries else None

    match = _empty_match_summary()
    if primary:
        match.update(
            {
                "total_distance_m": primary["total_distance_m"],
                "max_speed_mps": primary["max_speed_mps"],
                "avg_speed_mps": primary["avg_speed_mps"],
            }
        )
        match["intensity_score"] = calculate_intensity_score(
            total_distance_m=primary["total_distance_m"],
            max_speed_mps=primary["max_speed_mps"],
            active_time_sec=primary["active_time_sec"],
        )

    return {
        "frames_with_detections": frames,
        "frames_with_shuttlecock": shuttlecock_frames,
        "players": player_summaries,
        "primary_player": primary,
        "match": match,
    }


def calculate_intensity_score(
    *,
    total_distance_m: float,
    max_speed_mps: float,
    active_time_sec: float,
) -> int:
    distance_score = min(total_distance_m / 500.0 * 100.0, 100.0)
    speed_score = min(max_speed_mps / 5.0 * 100.0, 100.0)
    time_score = min(active_time_sec / 180.0 * 100.0, 100.0)
    score = 0.45 * distance_score + 0.35 * speed_score + 0.20 * time_score
    return int(round(max(0.0, min(score, 100.0))))


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


def build_mobile_report(
    *,
    result: dict[str, Any],
    metadata_path: str | os.PathLike[str] | None = None,
    detections_path: str | os.PathLike[str] | None = None,
) -> dict[str, Any]:
    metadata_path = str(metadata_path or result.get("metadata") or "")
    detections_path = str(detections_path or result.get("detections") or "")
    metadata = load_json(metadata_path)
    detection_summary = summarize_detections(detections_path)

    video = metadata.get("video") or {}
    match = detection_summary["match"]

    return {
        "schema_version": "mobile-report-v1",
        "video": {
            "name": video.get("name"),
            "duration_sec": round(float(video.get("duration_sec") or 0.0), 2),
            "fps": round(float(video.get("fps") or 0.0), 2),
            "width": video.get("width"),
            "height": video.get("height"),
        },
        "summary": {
            "total_distance_m": match["total_distance_m"],
            "max_speed_mps": match["max_speed_mps"],
            "avg_speed_mps": match["avg_speed_mps"],
            "intensity_score": match["intensity_score"],
            "detected_frames": detection_summary["frames_with_detections"],
            "shuttlecock_frames": detection_summary["frames_with_shuttlecock"],
        },
        "players": detection_summary["players"],
        "advice": generate_advice(match),
        "raw": {
            "metadata": metadata,
        },
    }


def generate_advice(match: dict[str, Any]) -> list[str]:
    advice = []
    distance = float(match.get("total_distance_m") or 0.0)
    max_speed = float(match.get("max_speed_mps") or 0.0)
    avg_speed = float(match.get("avg_speed_mps") or 0.0)

    if distance == 0:
        return ["未检测到足够的球员移动数据，建议检查拍摄角度和球场覆盖范围。"]
    if max_speed >= 4.0:
        advice.append("本次训练出现较高速度移动，爆发性回合较明显。")
    if avg_speed < 1.0:
        advice.append("平均移动速度偏低，可以加入前后场连续移动训练。")
    if distance >= 300:
        advice.append("本次跑动距离较高，适合作为高强度训练样例。")
    if not advice:
        advice.append("本次训练数据已生成，可结合热力图观察场地覆盖是否均衡。")
    return advice


def _empty_match_summary() -> dict[str, Any]:
    return {
        "total_distance_m": 0.0,
        "max_speed_mps": 0.0,
        "avg_speed_mps": 0.0,
        "intensity_score": 0,
    }
