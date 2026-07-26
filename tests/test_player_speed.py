from badminton_analysis.tracking.player import PlayerTracker


def test_peak_speed_uses_95th_percentile_not_fixed_cap():
    # A valid run with varied speeds must not turn into the old fixed 8.00 m/s.
    assert PlayerTracker._peak_speed([1.0, 2.0, 3.0, 4.0, 5.0]) == 4.8


def test_peak_speed_retains_single_sample():
    assert PlayerTracker._peak_speed([3.27]) == 3.27
