import json
from pathlib import Path

from badminton_analysis.movement_metrics import (
    MAX_STABLE_SPEED_MPS,
    load_stable_player_lookup,
    summarize_detections,
)


def _write_jsonl(tmp_path: Path, records: list[dict]) -> Path:
    path = tmp_path / "detections.jsonl"
    path.write_text(
        "".join(json.dumps(record, ensure_ascii=False) + "\n" for record in records),
        encoding="utf-8",
    )
    return path


def _frame(index, time_sec, upper, lower=None):
    return {
        "schema_version": "1.0",
        "frame": index,
        "time_sec": round(time_sec, 6),
        "detect_frame": index + 1,
        "players": {
            "upper": {"image": [100, 100], "court": upper, "speed": 0.0, "hands": {}},
            "lower": {"image": None, "court": lower, "speed": 0.0, "hands": {}},
        },
        "shuttlecock": {"image": [300, 200]},
    }


def test_rejects_single_frame_tracking_jump(tmp_path):
    path = _write_jsonl(
        tmp_path,
        [
            _frame(0, 0.0, [2.0, 6.0]),
            _frame(1, 1 / 30, [2.02, 6.01]),
            _frame(2, 2 / 30, [6.0, 13.0]),
            _frame(3, 3 / 30, [2.05, 6.04]),
            _frame(4, 4 / 30, [2.08, 6.06]),
        ],
    )
    player = summarize_detections(path)["players"][0]
    assert player["dropped_jump_count"] >= 1
    assert player["max_speed_mps"] <= MAX_STABLE_SPEED_MPS
    assert player["total_distance_m"] < 1.0


def test_stable_lookup_keeps_player_identity(tmp_path):
    path = _write_jsonl(
        tmp_path,
        [
            _frame(0, 0.0, [2.0, 3.0], [3.0, 10.0]),
            _frame(1, 1 / 30, [2.03, 3.02], [3.04, 10.03]),
            _frame(2, 2 / 30, [2.06, 3.04], [3.08, 10.06]),
        ],
    )
    first = load_stable_player_lookup(path)[0.0]
    assert first["upper"].y < first["lower"].y
