"""Build mobile-app friendly summaries from Good-Badminton outputs."""

from __future__ import annotations

import json
import math
import os
from dataclasses import dataclass
from functools import lru_cache
from pathlib import Path
from typing import Any


MAX_PLAUSIBLE_SPEED_MPS = 12.0
ROBUST_PEAK_PERCENTILE = 95
ADVICE_KNOWLEDGE_PATH = Path(__file__).with_name("advice_knowledge.json")


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
    positions_m: list[tuple[float, float]] | None = None

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
        if self.positions_m is None:
            self.positions_m = []

        if speed_mps is not None and math.isfinite(speed_mps) and speed_mps >= 0:
            self.raw_max_speed_mps = max(self.raw_max_speed_mps, float(speed_mps))
            if speed_mps <= MAX_PLAUSIBLE_SPEED_MPS:
                self.speed_samples_mps.append(float(speed_mps))

        if not court_position or len(court_position) < 2 or time_sec is None:
            return

        x, y = float(court_position[0]), float(court_position[1])
        if not math.isfinite(x) or not math.isfinite(y):
            return
        position = (x, y)
        self.positions_m.append(position)

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
        distance_per_min = self.total_distance_m / active_time * 60.0 if active_time > 0 else 0.0
        coverage = coverage_metrics(self.positions_m or [])
        zone = zone_metrics(self.positions_m or [], self.speed_samples_mps or [])
        return {
            "name": self.name,
            "detected_frames": self.detected_frames,
            "active_time_sec": round(active_time, 2),
            "total_distance_m": round(self.total_distance_m, 2),
            "max_speed_mps": round(peak_speed, 2),
            "raw_max_speed_mps": round(self.raw_max_speed_mps, 2),
            "avg_speed_mps": round(avg_speed, 2),
            "distance_per_min": round(distance_per_min, 2),
            **coverage,
            **zone,
        }


def load_json(path: str | os.PathLike[str] | None) -> dict[str, Any]:
    if not path or not os.path.isfile(path):
        return {}
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


@lru_cache(maxsize=1)
def load_advice_knowledge() -> dict[str, Any]:
    data = load_json(ADVICE_KNOWLEDGE_PATH)
    return {
        "sources": data.get("sources") or [],
        "entries": data.get("entries") or [],
    }


def summarize_detections(detections_path: str | os.PathLike[str] | None) -> dict[str, Any]:
    """Calculate lightweight movement metrics from detections.jsonl."""
    players: dict[str, PlayerStats] = {}
    frames = 0
    shuttlecock_frames = 0

    if not detections_path or not os.path.isfile(detections_path):
        return {
            "frames_with_detections": 0,
            "frames_with_shuttlecock": 0,
            "shuttlecock_ratio": 0.0,
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
    shuttlecock_ratio = shuttlecock_frames / frames if frames > 0 else 0.0
    if primary:
        match.update(
            {
                "total_distance_m": primary["total_distance_m"],
                "max_speed_mps": primary["max_speed_mps"],
                "avg_speed_mps": primary["avg_speed_mps"],
                "active_time_sec": primary["active_time_sec"],
                "distance_per_min": primary["distance_per_min"],
                "coverage_area_m2": primary["coverage_area_m2"],
                "court_span_x_m": primary["court_span_x_m"],
                "court_span_y_m": primary["court_span_y_m"],
                "front_court_ratio": primary["front_court_ratio"],
                "back_court_ratio": primary["back_court_ratio"],
                "left_court_ratio": primary["left_court_ratio"],
                "right_court_ratio": primary["right_court_ratio"],
                "high_intensity_moves": primary["high_intensity_moves"],
            }
        )
        match["intensity_score"] = calculate_intensity_score(
            total_distance_m=primary["total_distance_m"],
            max_speed_mps=primary["max_speed_mps"],
            active_time_sec=primary["active_time_sec"],
        )
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
    left_count = sum(1 for x, _ in positions if x < 3.05)
    front_count = sum(1 for _, y in positions if y < 6.7)
    high_intensity_moves = sum(1 for speed in speed_samples if speed >= 4.0)
    return {
        "front_court_ratio": round(front_count / total, 2),
        "back_court_ratio": round((total - front_count) / total, 2),
        "left_court_ratio": round(left_count / total, 2),
        "right_court_ratio": round((total - left_count) / total, 2),
        "high_intensity_moves": int(high_intensity_moves),
    }


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
    coaching = generate_coaching(detection_summary)
    report_summary = generate_report_summary(match)

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
            "active_time_sec": match["active_time_sec"],
            "distance_per_min": match["distance_per_min"],
            "coverage_area_m2": match["coverage_area_m2"],
            "court_span_x_m": match["court_span_x_m"],
            "court_span_y_m": match["court_span_y_m"],
            "front_court_ratio": match["front_court_ratio"],
            "back_court_ratio": match["back_court_ratio"],
            "left_court_ratio": match["left_court_ratio"],
            "right_court_ratio": match["right_court_ratio"],
            "high_intensity_moves": match["high_intensity_moves"],
            "shuttlecock_ratio": detection_summary["shuttlecock_ratio"],
        },
        "report_summary": report_summary,
        "players": detection_summary["players"],
        "coaching": coaching,
        "advice": flatten_coaching_advice(coaching),
        "advice_sources": load_advice_knowledge()["sources"],
        "raw": {
            "metadata": metadata,
        },
    }


def generate_report_summary(match: dict[str, Any]) -> str:
    distance = float(match.get("total_distance_m") or 0.0)
    max_speed = float(match.get("max_speed_mps") or 0.0)
    intensity = int(match.get("intensity_score") or 0)
    coverage = float(match.get("coverage_area_m2") or 0.0)
    active_time = float(match.get("active_time_sec") or 0.0)

    if distance <= 0:
        return "本次视频未检测到稳定移动数据，建议检查拍摄角度或手动校准球场角点。"

    intensity_text = "较高" if intensity >= 70 else "中等" if intensity >= 45 else "偏低"
    speed_text = "爆发移动明显" if max_speed >= 4.5 else "移动节奏较平稳"
    coverage_text = "场地覆盖较完整" if coverage >= 12 else "覆盖范围偏集中"
    if active_time < 25:
        return f"本次片段较短，训练强度{intensity_text}，{speed_text}，可作为快速复盘样例。"
    return f"本次训练强度{intensity_text}，{speed_text}，{coverage_text}。"


def generate_coaching(detection_summary: dict[str, Any]) -> dict[str, list[dict[str, Any]]]:
    knowledge = load_advice_knowledge()
    entries = {entry.get("id"): entry for entry in knowledge["entries"]}
    coaching: dict[str, list[dict[str, Any]]] = {
        "strengths": [],
        "weaknesses": [],
        "improvements": [],
    }

    match = detection_summary.get("match") or {}
    distance = float(match.get("total_distance_m") or 0.0)
    max_speed = float(match.get("max_speed_mps") or 0.0)
    avg_speed = float(match.get("avg_speed_mps") or 0.0)
    active_time = float(match.get("active_time_sec") or 0.0)
    distance_per_min = float(match.get("distance_per_min") or 0.0)
    intensity = int(match.get("intensity_score") or 0)
    coverage_area = float(match.get("coverage_area_m2") or 0.0)
    span_x = float(match.get("court_span_x_m") or 0.0)
    span_y = float(match.get("court_span_y_m") or 0.0)
    frames = int(detection_summary.get("frames_with_detections") or 0)
    shuttlecock_ratio = float(detection_summary.get("shuttlecock_ratio") or 0.0)

    if distance <= 0 or frames <= 0:
        add_coaching_item(
            coaching,
            "weaknesses",
            entries,
            "data_insufficient_weakness",
            "未检测到稳定的球员移动轨迹。",
        )
        add_coaching_item(
            coaching,
            "improvements",
            entries,
            "camera_setup_improvement",
            "优先解决拍摄视野或四角点，之后再评估训练表现。",
        )
        return coaching

    if max_speed >= 4.5:
        add_coaching_item(
            coaching,
            "strengths",
            entries,
            "fast_start_strength",
            f"检测最高移动速度 {format_metric(max_speed, 'm/s')}，具备明显爆发移动。",
        )
    if distance_per_min >= 110 or intensity >= 65:
        add_coaching_item(
            coaching,
            "strengths",
            entries,
            "work_rate_strength",
            f"单位时间移动约 {format_metric(distance_per_min, 'm/min')}，训练负荷较集中。",
        )
    if coverage_area >= 12 or span_x >= 3.5 or span_y >= 6.0:
        add_coaching_item(
            coaching,
            "strengths",
            entries,
            "court_coverage_strength",
            f"轨迹覆盖约 {format_metric(coverage_area, 'm²')}，横向 {format_metric(span_x, 'm')}、纵向 {format_metric(span_y, 'm')}。",
        )
    if frames >= 120 and shuttlecock_ratio >= 0.5:
        add_coaching_item(
            coaching,
            "strengths",
            entries,
            "stable_data_strength",
            f"有效检测 {frames} 帧，羽毛球识别占比约 {round(shuttlecock_ratio * 100)}%。",
        )

    if max_speed >= 4.5 and (avg_speed < 1.5 or distance_per_min < 95):
        add_coaching_item(
            coaching,
            "weaknesses",
            entries,
            "low_continuity_weakness",
            f"最高速度 {format_metric(max_speed, 'm/s')}，但平均速度 {format_metric(avg_speed, 'm/s')}，爆发后连续衔接还有提升空间。",
        )
    if coverage_area < 8 and active_time >= 8:
        add_coaching_item(
            coaching,
            "weaknesses",
            entries,
            "narrow_coverage_weakness",
            f"轨迹覆盖约 {format_metric(coverage_area, 'm²')}，可能集中在局部区域。",
        )
    if intensity < 45 or active_time < 25:
        add_coaching_item(
            coaching,
            "weaknesses",
            entries,
            "low_intensity_weakness",
            f"本次有效运动时长约 {format_metric(active_time, 's')}，强度分 {intensity}。",
        )
    if shuttlecock_ratio < 0.45 and frames >= 60:
        add_coaching_item(
            coaching,
            "weaknesses",
            entries,
            "low_shuttle_visibility_weakness",
            f"羽毛球识别占比约 {round(shuttlecock_ratio * 100)}%，球速和集锦判断会更不稳定。",
        )

    if not coaching["strengths"]:
        add_coaching_item(
            coaching,
            "strengths",
            entries,
            "stable_data_strength",
            f"已生成 {frames} 帧有效轨迹，可结合热力图做基础复盘。",
        )
    if not coaching["weaknesses"]:
        add_coaching_item(
            coaching,
            "weaknesses",
            entries,
            "low_continuity_weakness",
            "本次没有明显异常短板，下一阶段建议重点观察击球后回中是否稳定。",
        )

    if has_item(coaching["weaknesses"], "narrow_coverage_weakness"):
        add_coaching_item(
            coaching,
            "improvements",
            entries,
            "coverage_shadow_drill",
            "用于补齐前后场和左右两侧覆盖。",
        )
    if has_item(coaching["weaknesses"], "low_shuttle_visibility_weakness"):
        add_coaching_item(
            coaching,
            "improvements",
            entries,
            "camera_setup_improvement",
            "先提升视频质量，再对球速和击球片段做判断。",
        )
    if has_item(coaching["weaknesses"], "low_continuity_weakness") or max_speed >= 4.5:
        add_coaching_item(
            coaching,
            "improvements",
            entries,
            "split_step_recovery_drill",
            "把爆发速度转化成连续回合能力。",
        )
    if intensity < 60 or distance_per_min < 120:
        add_coaching_item(
            coaching,
            "improvements",
            entries,
            "multi_directional_drill",
            "提高连续多拍下的移动质量。",
        )
    if coverage_area >= 8 and max_speed >= 4.5:
        add_coaching_item(
            coaching,
            "improvements",
            entries,
            "rear_court_recovery_drill",
            "防止冲到后场后下一拍回位慢。",
        )
    if len(coaching["improvements"]) < 2:
        add_coaching_item(
            coaching,
            "improvements",
            entries,
            "net_lunge_drill",
            "补充网前低重心和回收能力。",
        )

    coaching["strengths"] = coaching["strengths"][:3]
    coaching["weaknesses"] = coaching["weaknesses"][:3]
    coaching["improvements"] = coaching["improvements"][:3]
    return coaching


def add_coaching_item(
    coaching: dict[str, list[dict[str, Any]]],
    group: str,
    entries: dict[str, dict[str, Any]],
    entry_id: str,
    basis: str,
) -> None:
    if has_item(coaching[group], entry_id):
        return
    entry = entries.get(entry_id)
    if not entry:
        return
    coaching[group].append(
        {
            "id": entry_id,
            "title": entry.get("title") or entry_id,
            "detail": entry.get("principle") or "",
            "basis": basis,
            "training_focus": entry.get("training_focus") or "",
            "source_ids": entry.get("source_ids") or [],
        }
    )


def has_item(items: list[dict[str, Any]], entry_id: str) -> bool:
    return any(item.get("id") == entry_id for item in items)


def flatten_coaching_advice(coaching: dict[str, list[dict[str, Any]]]) -> list[str]:
    labels = {
        "strengths": "当前优点",
        "weaknesses": "目前缺点",
        "improvements": "改进建议",
    }
    flattened: list[str] = []
    for group in ("strengths", "weaknesses", "improvements"):
        for item in coaching.get(group, []):
            pieces = [item.get("detail") or "", item.get("training_focus") or ""]
            text = " ".join(piece for piece in pieces if piece).strip()
            flattened.append(f"{labels[group]}：{item.get('title', '')}。{text}")
    return flattened


def format_metric(value: float, unit: str) -> str:
    if abs(value) >= 100:
        text = f"{value:.0f}"
    else:
        text = f"{value:.2f}".rstrip("0").rstrip(".")
    return f"{text} {unit}"


def _empty_match_summary() -> dict[str, Any]:
    return {
        "total_distance_m": 0.0,
        "max_speed_mps": 0.0,
        "avg_speed_mps": 0.0,
        "active_time_sec": 0.0,
        "distance_per_min": 0.0,
        "coverage_area_m2": 0.0,
        "court_span_x_m": 0.0,
        "court_span_y_m": 0.0,
        "front_court_ratio": 0.0,
        "back_court_ratio": 0.0,
        "left_court_ratio": 0.0,
        "right_court_ratio": 0.0,
        "high_intensity_moves": 0,
        "frames_with_detections": 0,
        "frames_with_shuttlecock": 0,
        "shuttlecock_ratio": 0.0,
        "intensity_score": 0,
    }
