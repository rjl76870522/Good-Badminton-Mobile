from __future__ import annotations

from pathlib import Path

import cv2
import numpy as np


def main() -> None:
    output = Path(__file__).resolve().parent / "videos" / "sample_match.mp4"
    output.parent.mkdir(parents=True, exist_ok=True)
    size = (640, 360)
    writer = cv2.VideoWriter(
        str(output), cv2.VideoWriter_fourcc(*"mp4v"), 24, size
    )
    if not writer.isOpened():
        raise RuntimeError("无法创建测试视频")
    for frame_number in range(48):
        frame = np.full((size[1], size[0], 3), (35, 100, 45), dtype=np.uint8)
        cv2.putText(
            frame,
            "Mock Venue Match Video",
            (130, 150),
            cv2.FONT_HERSHEY_SIMPLEX,
            0.8,
            (255, 255, 255),
            2,
        )
        cv2.putText(
            frame,
            f"frame {frame_number + 1}/48",
            (245, 205),
            cv2.FONT_HERSHEY_SIMPLEX,
            0.6,
            (230, 245, 230),
            1,
        )
        writer.write(frame)
    writer.release()
    print(f"Test video saved to: {output}")


if __name__ == "__main__":
    main()
