"""Generate highlight clips from Good-Badminton detection output."""

from __future__ import annotations

import json
import math
import os
import shutil
import subprocess
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import imageio_ffmpeg

from .movement_metrics import load_stable_player_lookup


MAX_PLAYER_SPEED_MPS = 12.0
SHUTTLE_SCORE_REFERENCE_PX_PER_SEC = 3500.0


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
    max_segments: int = 3,
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
    segments = _select_segments(
        frames=frames,
        duration_sec=duration_sec,
        max_segments=max_segments,
        window_sec=window_sec,
        overlap_sec=overlap_sec,
    )
    if not segments:
        return {"video": None, "segments": [], "error": "No valid highlight segment found."}

    highlight_path = out_dir / "highlight.mp4"
    try:
        _render_highlight(video, highlight_path, segments, duration_sec)
    except Exception as exc:
        return {"video": None, "segments": [s.to_dict() for s in segments], "error": str(exc)}

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
    if duration_sec <= window_sec + 1.0:
        segment = _score_window(frames, 0.0, duration_sec)
        return [segment] if segment else []

    step = max(window_sec - overlap_sec, 1.0)
    candidates: list[HighlightSegment] = []
    start = 0.0
    while start < duration_sec:
        end = min(start + window_sec, duration_sec)
        segment = _score_window(frames, start, end)
        if segment:
            candidates.append(segment)
        if end >= duration_sec:
            break
        start += step

    candidates.sort(key=lambda item: item.score, reverse=True)
    selected: list[HighlightSegment] = []
    for segment in candidates:
        if all(_overlap_ratio(segment, existing) < 0.35 for existing in selected):
            selected.append(segment)
        if len(selected) >= max_segments:
            break

    selected.sort(key=lambda item: item.start_sec)
    return selected


def _score_window(
    frames: list[DetectionFrame],
    start_sec: float,
    end_sec: float,
) -> HighlightSegment | None:
    window = [frame for frame in frames if start_sec <= frame.time_sec <= end_sec]
    if len(window) < 3:
        return None

    shuttle_speeds: list[float] = []
    player_peak_speed = 0.0
    player_distance = 0.0
    previous_shuttle: tuple[float, tuple[float, float]] | None = None
    previous_players: dict[str, tuple[float, tuple[float, float]]] = {}

    for frame in window:
        if frame.player_speeds:
            player_peak_speed = max(player_peak_speed, max(frame.player_speeds))

        if frame.shuttle_xy is not None:
            if previous_shuttle is not None:
                prev_time, prev_xy = previous_shuttle
                dt = frame.time_sec - prev_time
                if 0 < dt <= 0.25:
                    speed = math.dist(prev_xy, frame.shuttle_xy) / dt
                    if math.isfinite(speed) and speed >= 0:
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
                    player_peak_speed = max(player_peak_speed, speed)
            previous_players[name] = (frame.time_sec, xy)

    if len(shuttle_speeds) < 3 and player_distance < 1.0:
        return None

    shuttle_peak = _percentile(shuttle_speeds, 90)
    shuttle_raw_peak = max(shuttle_speeds) if shuttle_speeds else 0.0
    shuttle_score = min(shuttle_peak / SHUTTLE_SCORE_REFERENCE_PX_PER_SEC * 100.0, 100.0)
    player_speed_score = min(player_peak_speed / 5.0 * 100.0, 100.0)
    player_distance_score = min(player_distance / 35.0 * 100.0, 100.0)
    detection_score = min((len(shuttle_speeds) + len(window)) / max(len(window) * 1.5, 1) * 100.0, 100.0)
    score = int(round(
        0.45 * shuttle_score
        + 0.35 * player_speed_score
        + 0.15 * player_distance_score
        + 0.05 * detection_score
    ))

    reason = _reason(
        shuttle_score=shuttle_score,
        player_speed_score=player_speed_score,
        player_distance_score=player_distance_score,
    )
    return HighlightSegment(
        start_sec=max(0.0, start_sec - 1.0),
        end_sec=end_sec + 1.0,
        score=score,
        reason=reason,
        metrics={
            "shuttle_peak_px_s": shuttle_peak,
            "shuttle_raw_peak_px_s": shuttle_raw_peak,
            "shuttle_samples": float(len(shuttle_speeds)),
            "player_peak_mps": player_peak_speed,
            "player_distance_m": player_distance,
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
                    "-vf",
                    "scale=trunc(iw/2)*2:trunc(ih/2)*2",
                    "-c:v",
                    "libx264",
                    "-preset",
                    "veryfast",
                    "-crf",
                    "23",
                    "-an",
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
                str(highlight_path),
            ],
            check=True,
            capture_output=True,
            timeout=180,
        )
    finally:
        shutil.rmtree(temp_dir, ignore_errors=True)
