import json
import subprocess
from pathlib import Path

from badminton_analysis.highlight import (
    DetectionFrame,
    HighlightSegment,
    _score_window,
    _render_highlight,
    _select_segments,
)


def _scoring_frames(*, speed: float, spike: bool = False) -> list[DetectionFrame]:
    frames = []
    for index in range(21):
        frames.append(
            DetectionFrame(
                time_sec=index * 0.1,
                shuttle_xy=(index * speed * 0.1, 100.0),
                player_positions={},
                player_speeds=[12.0 if spike and index == 10 else speed / 500.0],
            )
        )
    return frames


def test_highlight_score_ignores_one_frame_player_speed_spike():
    normal = _score_window(_scoring_frames(speed=500), 0, 2)
    with_spike = _score_window(_scoring_frames(speed=500, spike=True), 0, 2)
    assert normal is not None
    assert with_spike is not None
    assert with_spike.score - normal.score <= 3
    assert with_spike.metrics["player_peak_mps"] < 3


def test_highlight_score_rewards_sustained_activity():
    calm = _score_window(_scoring_frames(speed=250), 0, 2)
    active = _score_window(_scoring_frames(speed=1800), 0, 2)
    assert calm is not None
    assert active is not None
    assert active.score > calm.score + 20


def test_static_shuttle_positions_do_not_count_as_shuttle_activity():
    frames = [
        DetectionFrame(
            time_sec=index * 0.1,
            shuttle_xy=(100.0, 100.0),
            player_positions={"player": (index * 0.12, 0.0)},
            player_speeds=[1.2],
        )
        for index in range(21)
    ]
    segment = _score_window(frames, 0, 2)
    assert segment is not None
    assert segment.metrics["shuttle_detection_ratio"] == 1
    assert segment.metrics["shuttle_activity_ratio"] == 0
    assert segment.metrics["shuttle_score"] == 0

from badminton_analysis.media.video_audio import (
    encode_vscode_compatible_mp4,
    find_ffmpeg_executable,
)


def test_ffmpeg_executable_can_be_resolved():
    assert Path(find_ffmpeg_executable()).is_file()


def test_h264_export_uses_resolved_ffmpeg(tmp_path):
    import cv2
    import numpy as np

    source = tmp_path / "source.mp4"
    output = tmp_path / "output.mp4"
    writer = cv2.VideoWriter(
        str(source),
        cv2.VideoWriter_fourcc(*"mp4v"),
        10,
        (64, 48),
    )
    assert writer.isOpened()
    for value in range(10):
        writer.write(np.full((48, 64, 3), value * 20, dtype=np.uint8))
    writer.release()

    assert encode_vscode_compatible_mp4(str(source), str(output))
    assert output.is_file()
    assert output.stat().st_size > 0


def test_highlight_preserves_source_audio(tmp_path):
    source = tmp_path / "source-with-audio.mp4"
    highlight = tmp_path / "highlight.mp4"
    subprocess.run(
        [
            "ffmpeg",
            "-y",
            "-f",
            "lavfi",
            "-i",
            "color=c=green:s=160x90:r=15:d=3",
            "-f",
            "lavfi",
            "-i",
            "sine=frequency=440:duration=3",
            "-c:v",
            "libx264",
            "-pix_fmt",
            "yuv420p",
            "-c:a",
            "aac",
            "-shortest",
            str(source),
        ],
        check=True,
        capture_output=True,
    )
    _render_highlight(
        source,
        highlight,
        [
            HighlightSegment(
                start_sec=0.5,
                end_sec=2.5,
                score=80,
                reason="test",
                metrics={},
            ),
        ],
        duration_sec=3,
    )
    probe = subprocess.run(
        [
            "ffprobe",
            "-v",
            "error",
            "-show_entries",
            "stream=codec_type",
            "-of",
            "json",
            str(highlight),
        ],
        check=True,
        capture_output=True,
        text=True,
    )
    stream_types = {
        stream["codec_type"] for stream in json.loads(probe.stdout)["streams"]
    }
    assert stream_types == {"video", "audio"}


def test_highlight_segments_are_shorter_and_never_overlap():
    duration = 12.9
    frames = [
        DetectionFrame(
            time_sec=index / 10,
            shuttle_xy=(index * 8.0, index * 3.0),
            player_positions={"upper": (index / 20, 2.0)},
            player_speeds=[2.0],
        )
        for index in range(130)
    ]

    segments = _select_segments(
        frames=frames,
        duration_sec=duration,
        max_segments=3,
        window_sec=8,
        overlap_sec=4,
    )

    assert segments
    assert sum(item.end_sec - item.start_sec for item in segments) <= duration * 0.70
    assert all(0 <= item.start_sec < item.end_sec <= duration for item in segments)
    assert all(
        first.end_sec <= second.start_sec
        for first, second in zip(segments, segments[1:])
    )


def test_renderer_removes_overlapping_time_and_stays_shorter(tmp_path):
    source = tmp_path / "source.mp4"
    highlight = tmp_path / "highlight.mp4"
    subprocess.run(
        [
            "ffmpeg",
            "-y",
            "-f",
            "lavfi",
            "-i",
            "color=c=blue:s=160x90:r=15:d=12.9",
            "-c:v",
            "libx264",
            "-pix_fmt",
            "yuv420p",
            str(source),
        ],
        check=True,
        capture_output=True,
    )
    _render_highlight(
        source,
        highlight,
        [
            HighlightSegment(0, 9, 57, "first", {}),
            HighlightSegment(7, 13.9, 54, "overlap", {}),
        ],
        duration_sec=12.9,
    )

    duration = float(
        subprocess.run(
            [
                "ffprobe",
                "-v",
                "error",
                "-show_entries",
                "format=duration",
                "-of",
                "default=nw=1:nk=1",
                str(highlight),
            ],
            check=True,
            capture_output=True,
            text=True,
        ).stdout.strip()
    )
    assert duration < 12.9
    assert duration <= 12.9 * 0.70 + 0.2
