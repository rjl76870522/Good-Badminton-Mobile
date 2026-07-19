import json
import subprocess
from pathlib import Path

from badminton_analysis.highlight import HighlightSegment, _render_highlight

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
