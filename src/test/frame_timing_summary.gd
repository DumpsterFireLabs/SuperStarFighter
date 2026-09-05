extends RefCounted


static func summarize(intervals: Array[int], expected_fps: float) -> Dictionary:
	var budget := 1000000.0 / maxf(expected_fps, 1.0)
	var sorted := intervals.duplicate()
	sorted.sort()
	var late := 0
	var severe := 0
	var streak := 0
	var longest_streak := 0
	for interval in intervals:
		# Keep nominal scheduling jitter separate from meaningful frame overruns.
		if interval > budget + 1000.0:
			late += 1
			streak += 1
			longest_streak = maxi(longest_streak, streak)
		else:
			streak = 0
		if interval > budget * 1.5:
			severe += 1
	return {"expected_fps": expected_fps, "budget_usec": budget,
		"late_threshold_usec": budget + 1000.0, "late_frames": late,
		"late_percent": 100.0 * late / maxi(intervals.size(), 1),
		"severe_threshold_usec": budget * 1.5, "severe_frames": severe,
		"longest_late_streak": longest_streak,
		"max_usec": sorted.back() if not sorted.is_empty() else 0}
