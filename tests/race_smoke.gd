extends SceneTree

## Competition-layer smoke test (docs/15_COMPETITION_AND_QUESTS.md §3): momentum
## ring buffer + persistence, overtake/overtaken events, and every event-trigger
## helper in `meta/race.gd`.
##   scripts/run_tests.sh race_smoke

const TestEnv := preload("res://tests/test_env.gd")

const PATH := "user://nocaps_race_test.json"

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	if not TestEnv.begin("race_smoke"):
		return
	_cleanup()
	_test_snapshots_and_persistence()
	_test_momentum_and_events()
	_test_triggers()
	_test_countdown()
	_cleanup()
	print("RACE_PASS: momentum, events, triggers, persistence verified")
	quit()

func _rows(mert: int, wif: int, bitsy: int = 100, mole: int = 50) -> Array:
	return [
		{"id": "mert", "name": "Mert", "score": mert},
		{"id": "wif", "name": "Wif", "score": wif},
		{"id": "bitsy", "name": "Bitsy", "score": bitsy},
		{"id": "mole", "name": "Mole", "score": mole},
	]

func _test_snapshots_and_persistence() -> void:
	var race := Race.new(PATH)
	var t0 := 1_700_000_000.0
	race.observe(_rows(1000, 900), t0)
	# Throttled: a snapshot inside SNAPSHOT_SECONDS is ignored.
	race.observe(_rows(1010, 900), t0 + 5.0)
	assert(race._snapshots.size() == 1, "snapshots are throttled to 10 s")
	race.observe(_rows(1100, 950), t0 + 60.0)
	assert(race._snapshots.size() == 2, "a later snapshot is recorded")
	race.note_run(60, t0)
	race.note_run(120, t0 + 10.0)
	assert(race.median_run_contribution() == 90, "median run contribution")

	# Reload from disk.
	var reloaded := Race.new(PATH)
	assert(reloaded._snapshots.size() == 0, "history loads lazily")
	assert(reloaded.median_run_contribution() == 90, "median persists across instances")
	assert(reloaded._snapshots.size() == 2, "snapshots persist across instances")

	# Ring buffer: old snapshots fall out of the 10-minute window.
	race.observe(_rows(1200, 900), t0 + 700.0)
	for snapshot in race._snapshots:
		assert(t0 + 700.0 - float(snapshot["t"]) <= Race.WINDOW_SECONDS, "snapshots stay in the window")
	race.clear()
	assert(not FileAccess.file_exists(PATH), "clear removes the history file")

func _test_momentum_and_events() -> void:
	var race := Race.new(PATH)
	var t0 := 1_700_000_000.0
	race.observe(_rows(1000, 900), t0)
	race.observe(_rows(1050, 900), t0 + 60.0)
	# Momentum needs a real span of at least 2 minutes.
	var early := race.momentum(t0 + 60.0)
	assert(early.is_empty(), "momentum is hidden before a 2-minute span")
	race.observe(_rows(1100, 900), t0 + 130.0)
	var gains := race.momentum(t0 + 130.0)
	assert(int(gains["mert"]["gain"]) == 100, "momentum is the gain across the window")
	assert(int(gains["mert"]["span_seconds"]) == 130, "momentum reports the real span")

	# wif overtakes mert between the last two snapshots.
	race.observe(_rows(1100, 1200), t0 + 200.0)
	var events := race.recent_events(t0 + 200.0)
	assert(events.size() == 1, "one overtake detected, got %s" % str(events))
	assert(events[0]["by"] == "wif" and events[0]["over"] == "mert", "overtake names the pair")
	assert(race.recent_events(t0 + 200.0, "wif").size() == 1, "events filter by crew")
	assert(race.recent_events(t0 + 200.0, "mole").is_empty(), "uninvolved crew has no events")
	# Events expire after 30 minutes.
	assert(race.recent_events(t0 + 200.0 + Race.EVENT_SECONDS + 1.0).is_empty(), "events expire after 30 min")

	# Momentum line shows only the top surging crews above the threshold.
	var line := race.momentum_line(t0 + 200.0)
	assert(line.size() <= Race.MAX_SURGING, "momentum line is capped")
	for entry in line:
		assert(int(entry["gain"]) >= Race.MOMENTUM_THRESHOLD, "only surging crews listed")
	race.clear()

func _test_triggers() -> void:
	var race := Race.new(PATH)
	var rows := _rows(1000, 900)  # my crew = wif, gap 100

	# Gap to pass: visible under max(150, 3 x median); hidden when the gap is big.
	var gap := race.gap_to_pass(rows, "wif", 20)
	assert(not gap.is_empty(), "gap to pass is visible within the threshold")
	assert(int(gap["gap"]) == 100 and gap["id"] == "mert", "gap reports the crew above")
	var far_rows := _rows(1000, 400)
	assert(race.gap_to_pass(far_rows, "wif", 50).is_empty(), "gap hides when it exceeds the threshold")
	assert(not race.gap_to_pass(far_rows, "wif", 300).is_empty(), "a large median widens the threshold")
	assert(race.gap_to_pass(rows, "mert", 0).is_empty(), "no crew above the leader")

	# Overtake: this run would flip the pair.
	assert(not race.run_overtake(rows, "wif", 200).is_empty(), "run overtake detected at the gap")
	assert(race.run_overtake(rows, "wif", 50).is_empty(), "small run does not overtake")

	# Crew rank up: pass the next player in the crew list.
	var players := [
		{"uid": "a", "name": "MVP", "score": 500, "rank": 1},
		{"uid": "b", "name": "Second", "score": 300, "rank": 2},
		{"uid": "me", "name": "You", "score": 200, "rank": 3},
	]
	var up := race.crew_rank_up(players, "me", 150)
	assert(up["rank"] == 2 and up["uid"] == "b", "crew rank-up target")
	assert(race.crew_rank_up(players, "me", 50).is_empty(), "no rank-up without passing")
	assert(race.crew_rank_up(players, "a", 500).is_empty(), "the MVP has nobody above")

	# Rank moved card.
	assert(race.rank_moved(3, 2, "Mert")["to"] == 2, "rank moved card")
	assert(race.rank_moved(2, 2, "Mert").is_empty(), "unchanged rank shows no card")
	assert(race.rank_moved(2, 3, "Mert").is_empty(), "a drop shows no card")

	# One-more CTA: reachable within two runs of the last one.
	var cta := race.catch_cta(rows, "wif", 60)
	assert(not cta.is_empty() and cta["text"].contains("CATCH"), "catch CTA when within reach")
	assert(race.catch_cta(rows, "wif", 10).is_empty(), "no catch CTA when out of reach")

	# Live ticker: a rival within 10% is surging.
	var t0 := 1_700_000_000.0
	race.observe(_rows(1000, 950), t0)
	race.observe(_rows(1250, 1200), t0 + 130.0)
	var ticker := race.live_ticker(_rows(1250, 1200), "wif", t0 + 130.0)
	assert(not ticker.is_empty() and ticker["type"] == "closing", "live ticker closing line")
	assert(int(ticker["gain"]) >= Race.MOMENTUM_THRESHOLD, "ticker reports the gain")
	race.clear()

	# Rank arrows: positive means the crew moved up since the window opened.
	race.observe(_rows(1000, 900), t0)
	race.observe(_rows(1100, 1200), t0 + 130.0)
	var arrows := race.rank_arrows(_rows(1100, 1200), t0 + 130.0)
	assert(int(arrows["wif"]) == 1 and int(arrows["mert"]) == -1, "rank arrows point both ways")
	race.clear()

func _test_countdown() -> void:
	var race := Race.new(PATH)
	var t := float(Time.get_unix_time_from_datetime_dict({
		"year": 2026, "month": 9, "day": 26, "hour": 23, "minute": 30, "second": 0,
	}))
	var ending := race.day_ending(t)
	assert(int(ending["seconds_left"]) == 1800, "seconds left until UTC midnight")
	assert(bool(ending["last_hour"]), "the last hour flags the countdown")
	assert(String(ending["clock"]) == "30:00", "countdown clock, got %s" % ending["clock"])
	var early := race.day_ending(t - 3600.0)
	assert(not bool(early["last_hour"]), "outside the last hour")

func _cleanup() -> void:
	if FileAccess.file_exists(PATH):
		DirAccess.remove_absolute(PATH)
