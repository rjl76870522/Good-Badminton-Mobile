import unittest

from badminton_analysis.mobile_report import generate_coaching


class MobileReportCoachingTest(unittest.TestCase):
    def test_high_intensity_short_clip_is_not_marked_low_intensity(self):
        coaching = generate_coaching(
            {
                "frames_with_detections": 538,
                "frames_with_shuttlecock": 408,
                "shuttlecock_ratio": 0.76,
                "match": {
                    "total_distance_m": 66.91,
                    "max_speed_mps": 6.6,
                    "raw_max_speed_mps": 18.62,
                    "avg_speed_mps": 1.87,
                    "active_time_sec": 17.9,
                    "distance_per_min": 112.14,
                    "combined_distance_per_min": 224.28,
                    "intensity_score": 92,
                    "coverage_area_m2": 15.96,
                    "court_span_x_m": 3.98,
                    "court_span_y_m": 4.04,
                    "front_court_ratio": 0.43,
                    "back_court_ratio": 0.57,
                    "left_court_ratio": 0.46,
                    "right_court_ratio": 0.54,
                    "high_intensity_moves": 146,
                    "dropped_jump_count": 44,
                    "tracking_quality_score": 94,
                },
            }
        )

        weakness_ids = {item["id"] for item in coaching["weaknesses"]}
        weakness_titles = {item["title"] for item in coaching["weaknesses"]}
        self.assertNotIn("low_intensity_weakness", weakness_ids)
        self.assertNotIn("训练强度偏低", weakness_titles)
        self.assertIn("short_sample_weakness", weakness_ids)
        self.assertIn("low_continuity_weakness", weakness_ids)
        self.assertIn("tracking_noise_weakness", weakness_ids)
        self.assertEqual(len(coaching["strengths"]), 3)
        self.assertEqual(len(coaching["weaknesses"]), 3)
        self.assertEqual(len(coaching["improvements"]), 3)


if __name__ == "__main__":
    unittest.main()
