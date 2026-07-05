import unittest

import numpy as np

from backend_api import _score_preview_frame


class PreviewFrameQualityTest(unittest.TestCase):
    def test_black_frame_is_rejected_as_preview_scene(self):
        frame = np.zeros((240, 320, 3), dtype=np.uint8)

        scored = _score_preview_frame(frame, frame_index=0, fps=30.0, detect_court=False)

        self.assertFalse(scored["usable"])
        self.assertEqual(scored["reason"], "rejected_dark_or_low_content")
        self.assertIn("重新提交视频", scored["scene_warning"])


if __name__ == "__main__":
    unittest.main()
