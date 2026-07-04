import unittest

from badminton_analysis.tracking.player import PlayerTracker


class PlayerTrackerTest(unittest.TestCase):
    def test_realtime_stats_reject_tracking_jump(self):
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
        self.assertLessEqual(stats["current_speed"], 1.0)
        self.assertLess(stats["match_distance"], 0.1)
        self.assertLessEqual(stats["match_max_speed"], 8.0)


if __name__ == "__main__":
    unittest.main()
