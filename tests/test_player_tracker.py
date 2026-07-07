from badminton_analysis.tracking.player import PlayerTracker


def test_realtime_stats_reject_tracking_jump():
    tracker = PlayerTracker(
        corners=[(0, 0), (610, 0), (610, 1340), (0, 1340)],
        threshold=670,
        fps=30,
    )

    tracker.update(1, [(200, 300)], None, {}, {}, 1)
    tracker.update(2, [(202, 300)], None, {}, {}, 2)
    tracker.update(3, [(600, 300)], None, {}, {}, 3)
    tracker.update(4, [(204, 300)], None, {}, {}, 4)

    stats = tracker.get_player_movement_stats()["upper"]
    assert stats["current_speed"] <= 1.0
    assert stats["match_distance"] < 0.1
    assert stats["match_max_speed"] <= 8.0
