"""Generate highlight clips from Good-Badminton detection output."""

from __future__ import annotations

import json
import math
import os
import shutil
import subprocess
from dataclasses import dataclass, replace
from pathlib import Path
from typing import Any

import imageio_ffmpeg

from .movement_metrics import load_stable_player_lookup

MAX_PLAYER_SPEED_MPS = 12.0
SHUTTLE_SCORE_REFERENCE_PX_PER_SEC = 3500.0
MIN_ACTIVE_SHUTTLE_SPEED_PX_PER_SEC = 20.0
MAX_HIGHLIGHT_SOURCE_RATIO = 0.70
MIN_HIGHLIGHT_SEGMENT_SEC = 2.0


@dataclass
class DetectionFrame:
    time_sec: float
    shuttle_xy: tuple[float, float] | None
    player_positions: dict[str, tuple[float, float]]
    player_speeds: list[float]


@dataclass
class HighlightSegment:
    start_sec: float
    end_sec: float
    score: int
    reason: str
    metrics: dict[str, float]

    def to_dict(self) -> dict[str, Any]:
        return {
            "start_sec": round(self.start_sec, 2),
            "end_sec": round(self.end_sec, 2),
            "score": self.score,
            "reason": self.reason,
            "metrics": {key: round(value, 2) for key, value in self.metrics.items()},
        }


def generate_highlight(
    *,
    video_path: str | os.PathLike[str],
    detections_path: str | os.PathLike[str],
    output_dir: str | os.PathLike[str],
    max_segments: int = 1,
    window_sec: float = 8.0,
    overlap_sec: float = 4.0,
) -> dict[str, Any]:
    """Create a highlight video and return clip metadata.

    The score is based on shuttle speed, player speed, and player movement. Shuttle
    speed is image-space px/s because detections only include image coordinates.
    """
    video = Path(video_path).resolve()
    detections = Path(detections_path).resolve()
    out_dir = Path(output_dir).resolve()
    if not video.is_file() or not detections.is_file():
        return {"video": None, "segments": [], "error": "Missing video or detections file."}

    frames = _load_frames(detections)
    if len(frames) < 2:
        return {"video": None, "segments": [], "error": "Not enough detections for highlights."}

    duration_sec = max(frame.time_sec for frame in frames)
    candidates = _candidate_segments(
        frames=frames,
        duration_sec=duration_sec,
        window_sec=window_sec,
        overlap_sec=overlap_sec,
    )
    segments = _select_from_candidates(
        frames=frames,
        candidates=candidates,
        duration_sec=duration_sec,
        max_segments=max_segments,
    )
    if not segments:
        return {
            "video": None,
            "segments": [],
            "error": "No valid highlight segment found.",
        }

    highlight_path = out_dir / "highlight.mp4"
    try:
        _render_highlight(video, highlight_path, segments, duration_sec)
    except Exception as exc:
        return {
            "video": None,
            "segments": [s.to_dict() for s in segments],
            "error": str(exc),
        }

    return {
        "video": str(highlight_path),
        "segments": [segment.to_dict() for segment in segments],
        "error": None,
    }


def _load_frames(path: Path) -> list[DetectionFrame]:
    frames: list[DetectionFrame] = []
    stable_lookup = load_stable_player_lookup(path)
    with path.open("r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                record = json.loads(line)
            except json.JSONDecodeError:
                continue

            time_sec = record.get("time_sec")
            if not isinstance(time_sec, (int, float)) or not math.isfinite(time_sec):
                continue

            shuttle_xy = _xy(record.get("shuttlecock", {}).get("image"))
            stable_players = stable_lookup.get(round(float(time_sec), 6), {})
            player_positions = {
                name: (point.x, point.y)
                for name, point in stable_players.items()
            }
            player_speeds = [
                point.speed_mps
                for point in stable_players.values()
                if 0 <= point.speed_mps <= MAX_PLAYER_SPEED_MPS
            ]

            frames.append(
                DetectionFrame(
                    time_sec=float(time_sec),
                    shuttle_xy=shuttle_xy,
                    player_positions=player_positions,
                    player_speeds=player_speeds,
                )
            )

    frames.sort(key=lambda frame: frame.time_sec)
    return frames


def _xy(value: Any) -> tuple[float, float] | None:
    if not isinstance(value, (list, tuple)) or len(value) < 2:
        return None
    x, y = value[0], value[1]
    if not isinstance(x, (int, float)) or not isinstance(y, (int, float)):
        return None
    if not math.isfinite(x) or not math.isfinite(y):
        return None
    return float(x), float(y)


def _select_segments(
    *,
    frames: list[DetectionFrame],
    duration_sec: float,
    max_segments: int,
    window_sec: float,
    overlap_sec: float,
) -> list[HighlightSegment]:
    candidates = _candidate_segments(
        frames=frames,
        duration_sec=duration_sec,
        window_sec=window_sec,
        overlap_sec=overlap_sec,
    )
    return _select_from_candidates(
        frames=frames,
        candidates=candidates,
        duration_sec=duration_sec,
        max_segments=max_segments,
    )


def _candidate_segments(
    *,
    frames: list[DetectionFrame],
    duration_sec: float,
    window_sec: float,
    overlap_sec: float,
) -> list[HighlightSegment]:
    effective_window = min(
        window_sec,
        max(MIN_HIGHLIGHT_SEGMENT_SEC, duration_sec * 0.60),
    )
    step = max(effective_window - overlap_sec, 1.0)
    candidates: list[HighlightSegment] = []
    start = 0.0
    while start < duration_sec:
        end = min(start + effective_window, duration_sec)
        if end - start < MIN_HIGHLIGHT_SEGMENT_SEC:
            break
        segment = _score_window(frames, start, end)
        if segment:
            candidates.append(segment)
        if end >= duration_sec:
            break
        start += step

    return candidates


def _select_from_candidates(
    *,
    frames: list[DetectionFrame],
    candidates: list[HighlightSegment],
    duration_sec: float,
    max_segments: int,
) -> list[HighlightSegment]:
    selected = _sanitize_segments(
        candidates,
        duration_sec=duration_sec,
        max_segments=max_segments,
    )
    rescored: list[HighlightSegment] = []
    for segment in selected:
        exact = _score_window(frames, segment.start_sec, segment.end_sec)
        rescored.append(exact or segment)
    return rescored


def _score_window(
    frames: list[DetectionFrame],
    start_sec: float,
    end_sec: float,
) -> HighlightSegment | None:
    window = [frame for frame in frames if start_sec <= frame.time_sec <= end_sec]
    if len(window) < 3:
        return None

    shuttle_speeds: list[float] = []
    shuttle_detection_frames = 0
    player_speeds: list[float] = []
    player_distance = 0.0
    player_detection_frames = 0
    previous_shuttle: tuple[float, tuple[float, float]] | None = None
    previous_players: dict[str, tuple[float, tuple[float, float]]] = {}

    for frame in window:
        if frame.player_speeds:
            player_speeds.extend(frame.player_speeds)
        if frame.player_positions:
            player_detection_frames += 1

        if frame.shuttle_xy is not None:
            shuttle_detection_frames += 1
            if previous_shuttle is not None:
                prev_time, prev_xy = previous_shuttle
                dt = frame.time_sec - prev_time
                if 0 < dt <= 0.25:
                    speed = math.dist(prev_xy, frame.shuttle_xy) / dt
                    if (
                        math.isfinite(speed)
                        and speed >= MIN_ACTIVE_SHUTTLE_SPEED_PX_PER_SEC
                    ):
                        shuttle_speeds.append(speed)
            previous_shuttle = (frame.time_sec, frame.shuttle_xy)

        for name, xy in frame.player_positions.items():
            previous = previous_players.get(name)
            if previous is not None:
                prev_time, prev_xy = previous
                dt = frame.time_sec - prev_time
                dist = math.dist(prev_xy, xy)
                speed = dist / dt if dt > 0 else 0.0
                if 0 < dt <= 0.5 and speed <= MAX_PLAYER_SPEED_MPS:
                    player_distance += dist
                    player_speeds.append(speed)
            previous_players[name] = (frame.time_sec, xy)

    if len(shuttle_speeds) < 3 and player_distance < 1.0:
        return None

    shuttle_peak = _percentile(shuttle_speeds, 90)
    shuttle_raw_peak = max(shuttle_speeds) if shuttle_speeds else 0.0
    player_peak_speed = _percentile(player_speeds, 90)
    window_duration = max(end_sec - start_sec, 0.01)
    player_movement_rate = player_distance / window_duration
    shuttle_activity_ratio = len(shuttle_speeds) / max(len(window) - 1, 1)
    shuttle_detection_ratio = shuttle_detection_frames / max(len(window), 1)
    player_detection_ratio = player_detection_frames / max(len(window), 1)
    shuttle_score = min(
        shuttle_peak / SHUTTLE_SCORE_REFERENCE_PX_PER_SEC * 100.0,
        100.0,
    )
    player_speed_score = min(player_peak_speed / 6.0 * 100.0, 100.0)
    player_distance_score = min(player_movement_rate / 4.5 * 100.0, 100.0)
    detection_score = min(
        shuttle_activity_ratio / 0.35 * 50.0
        + shuttle_detection_ratio / 0.75 * 20.0
        + player_detection_ratio / 0.75 * 30.0,
        100.0,
    )
    score = int(round(
        0.35 * shuttle_score
        + 0.30 * player_speed_score
        + 0.25 * player_distance_score
        + 0.10 * detection_score
    ))

    reason = _reason(
        shuttle_score=shuttle_score,
        player_speed_score=player_speed_score,
        player_distance_score=player_distance_score,
    )
    return HighlightSegment(
        start_sec=start_sec,
        end_sec=end_sec,
        score=score,
        reason=reason,
        metrics={
            "shuttle_peak_px_s": shuttle_peak,
            "shuttle_raw_peak_px_s": shuttle_raw_peak,
            "shuttle_samples": float(len(shuttle_speeds)),
            "player_peak_mps": player_peak_speed,
            "player_distance_m": player_distance,
            "player_movement_rate_mps": player_movement_rate,
            "shuttle_activity_ratio": shuttle_activity_ratio,
            "shuttle_detection_ratio": shuttle_detection_ratio,
            "player_detection_ratio": player_detection_ratio,
            "shuttle_score": shuttle_score,
            "player_speed_score": player_speed_score,
            "player_distance_score": player_distance_score,
        },
    )


def _percentile(values: list[float], pct: int) -> float:
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


def _reason(
    *,
    shuttle_score: float,
    player_speed_score: float,
    player_distance_score: float,
) -> str:
    parts = []
    if shuttle_score >= 60:
        parts.append("high-speed shuttle")
    if player_speed_score >= 65:
        parts.append("fast player movement")
    if player_distance_score >= 55:
        parts.append("high movement distance")
    if not parts:
        parts.append("active rally")
    return " + ".join(parts)


def _overlap_ratio(a: HighlightSegment, b: HighlightSegment) -> float:
    overlap = max(0.0, min(a.end_sec, b.end_sec) - max(a.start_sec, b.start_sec))
    shorter = max(min(a.end_sec - a.start_sec, b.end_sec - b.start_sec), 0.01)
    return overlap / shorter


def _sanitize_segments(
    segments: list[HighlightSegment],
    *,
    duration_sec: float,
    max_segments: int | None = None,
) -> list[HighlightSegment]:
    """Clamp, de-duplicate and budget highlight segments before rendering."""
    if duration_sec <= 0:
        return []

    duration_budget = min(
        duration_sec * MAX_HIGHLIGHT_SOURCE_RATIO,
        max(duration_sec - 1.0, 0.0),
    )
    if duration_budget < MIN_HIGHLIGHT_SEGMENT_SEC:
        return []

    selected: list[HighlightSegment] = []
    used_duration = 0.0
    for segment in sorted(segments, key=lambda item: item.score, reverse=True):
        start = max(0.0, min(float(segment.start_sec), duration_sec))
        end = max(start, min(float(segment.end_sec), duration_sec))
        if end - start < MIN_HIGHLIGHT_SEGMENT_SEC:
            continue
        if any(
            min(end, existing.end_sec) - max(start, existing.start_sec) > 0.001
            for existing in selected
        ):
            continue

        remaining = duration_budget - used_duration
        if remaining < MIN_HIGHLIGHT_SEGMENT_SEC:
            break
        if end - start > remaining:
            end = start + remaining
        if end - start < MIN_HIGHLIGHT_SEGMENT_SEC:
            continue

        selected.append(replace(segment, start_sec=start, end_sec=end))
        used_duration += end - start
        if max_segments is not None and len(selected) >= max_segments:
            break

    selected.sort(key=lambda item: item.start_sec)
    return selected


def _render_highlight(
    video_path: Path,
    highlight_path: Path,
    segments: list[HighlightSegment],
    duration_sec: float,
) -> None:
    ffmpeg = imageio_ffmpeg.get_ffmpeg_exe()
    video_path = video_path.resolve()
    highlight_path = highlight_path.resolve()
    temp_dir = highlight_path.parent / "_highlight_tmp"
    if temp_dir.exists():
        shutil.rmtree(temp_dir)
    temp_dir.mkdir(parents=True, exist_ok=True)

    segments = _sanitize_segments(segments, duration_sec=duration_sec)
    clip_paths: list[Path] = []
    try:
        for idx, segment in enumerate(segments, 1):
            start = max(0.0, segment.start_sec)
            end = min(segment.end_sec, duration_sec)
            if end - start < 1.0:
                continue
            clip = temp_dir / f"clip_{idx:02d}.mp4"
            subprocess.run(
                [
                    ffmpeg,
                    "-y",
                    "-ss",
                    f"{start:.3f}",
                    "-t",
                    f"{end - start:.3f}",
                    "-i",
                    str(video_path),
                    "-map",
                    "0:v:0",
                    "-map",
                    "0:a:0?",
                    "-vf",
                    "scale=trunc(iw/2)*2:trunc(ih/2)*2",
                    "-c:v",
                    "libx264",
                    "-preset",
                    "veryfast",
                    "-crf",
                    "23",
                    "-c:a",
                    "aac",
                    "-b:a",
                    "160k",
                    "-shortest",
                    str(clip),
                ],
                check=True,
                capture_output=True,
                timeout=180,
            )
            clip_paths.append(clip)

        if not clip_paths:
            raise RuntimeError("No highlight clips were rendered.")

        concat_file = temp_dir / "concat.txt"
        concat_file.write_text(
            "\n".join(f"file '{clip.resolve().as_posix()}'" for clip in clip_paths),
            encoding="utf-8",
        )
        joined_highlight = temp_dir / "joined_highlight.mp4"
        subprocess.run(
            [
                ffmpeg,
                "-y",
                "-f",
                "concat",
                "-safe",
                "0",
                "-i",
                str(concat_file),
                "-c",
                "copy",
                str(joined_highlight),
            ],
            check=True,
            capture_output=True,
            timeout=180,
        )
        os.replace(joined_highlight, highlight_path)
    finally:
        shutil.rmtree(temp_dir, ignore_errors=True)
