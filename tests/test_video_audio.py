from pathlib import Path

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
