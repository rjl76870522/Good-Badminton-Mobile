import json
import tempfile
import unittest
from pathlib import Path

from badminton_analysis.movement_metrics import (
    MAX_STABLE_SPEED_MPS,
    load_stable_player_lookup,
    summarize_detections,
)


def write_jsonl(records):
    handle = tempfile.NamedTemporaryFile("w", suffix=".jsonl", delete=False, encoding="utf-8")
    with handle:
        for record in records:
            handle.write(json.dumps(record, ensure_ascii=False) + "\n")
    return Path(handle.name)


class MovementMetricsTest(unittest.TestCase):
    def test_rejects_single_frame_tracking_jump(self):
        path = write_jsonl(
            [
                frame(0, 0.0, [2.0, 6.0]),
                frame(1, 1 / 30, [2.02, 6.01]),
                frame(2, 2 / 30, [6.0, 13.0]),
                frame(3, 3 / 30, [2.05, 6.04]),
                frame(4, 4 / 30, [2.08, 6.06]),
            ]
        )
        try:
            summary = summarize_detections(path)
        finally:
            path.unlink(missing_ok=True)

        player = summary["players"][0]
        self.assertGreaterEqual(player["dropped_jump_count"], 1)
        self.assertLessEqual(player["max_speed_mps"], MAX_STABLE_SPEED_MPS)
        self.assertLess(player["total_distance_m"], 1.0)

    def test_stable_lookup_keeps_player_identity(self):
        path = write_jsonl(
            [
                frame(0, 0.0, [2.0, 3.0], lower=[3.0, 10.0]),
                frame(1, 1 / 30, [2.03, 3.02], lower=[3.04, 10.03]),
                frame(2, 2 / 30, [2.06, 3.04], lower=[3.08, 10.06]),
            ]
        )
        try:
            lookup = load_stable_player_lookup(path)
        finally:
            path.unlink(missing_ok=True)

        first = lookup[0.0]
        self.assertIn("upper", first)
        self.assertIn("lower", first)
        self.assertLess(first["upper"].y, first["lower"].y)


def frame(index, time_sec, upper, lower=None):
    players = {
        "upper": {
            "image": [100, 100],
            "court": upper,
            "speed": 0.0,
            "hands": {"left": None, "right": None},
        },
        "lower": {
            "image": None,
            "court": lower,
            "speed": 0.0,
            "hands": {"left": None, "right": None},
        },
    }
    if lower is None:
        players["lower"]["court"] = None
    return {
        "schema_version": "1.0",
        "frame": index,
        "time_sec": round(time_sec, 6),
        "detect_frame": index + 1,
        "players": players,
        "shuttlecock": {"image": [300, 200]},
    }


if __name__ == "__main__":
    unittest.main()
