extends SceneTree

## Phase 1 moments smoke test (docs/15 §3): catalog priority order, per-event and
## home-banner cooldowns, dedupe, one-at-a-time popup surfaces, and surface
## routing. Detection is exercised from a result payload with race.gd skipped.
##   scripts/run_tests.sh moments_smoke

const TestEnv := preload("res://tests/test_env.gd")


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	if not TestEnv.begin("moments_smoke"):
		return
	_test_catalog_and_routing()
	_test_priority()
	_test_dedupe()
	_test_cooldowns()
	_test_home_banner_gap()
	_test_one_at_a_time()
	_test_detection()
	_test_popup_builds()
	await _test_popup_single_visible()
	await _test_popup_hold_alpha()
	print("MOMENTS_PASS: priority, cooldowns, dedupe, one-at-a-time, routing verified")
	quit()


func _test_catalog_and_routing() -> void:
	Moments.reset()
	assert(Moments.CATALOG.has("overtake") and Moments.CATALOG.has("new_best"), "catalog contains scoreboard + pride ids")
	assert(int(Moments.CATALOG["overtake"]["priority"]) < int(Moments.CATALOG["momentum"]["priority"]), "priority tracks §3 order")
	assert(Moments.push("live_ticker", &"home_banner", {"key": "t1"}), "owned surface accepts the moment")
	assert(not Moments.push("live_ticker", &"run_toast", {"key": "t2"}), "unowned surface rejects the moment")
	assert(Moments.next_for(&"run_toast").is_empty(), "routing keeps surfaces isolated")
	assert(not Moments.next_for(&"home_banner").is_empty(), "home banner is ready on its own surface")


func _test_priority() -> void:
	Moments.reset()
	Moments.push("momentum", &"board_row", {"key": "m", "crew": "Wif", "gain": 340, "min": 10})
	Moments.push("gap_to_pass", &"board_row", {"key": "g", "crew": "Wif", "gap": 12})
	var rows := Moments.peek_rows(&"board_row")
	assert(rows.size() == 2, "both board moments queued")
	assert(String(rows[0]["id"]) == "gap_to_pass", "lower priority number shows first")
	assert(String(rows[1]["id"]) == "momentum", "higher priority number follows")

	Moments.push("streak", &"home_banner", {"key": "s", "n": 3})
	Moments.push("live_ticker", &"home_banner", {"key": "t", "rival": "Wif", "gain": 340, "min": 10})
	var top := Moments.next_for(&"home_banner")
	assert(String(top["id"]) == "live_ticker", "priority 60 leads priority 120")


func _test_dedupe() -> void:
	Moments.reset()
	var ctx := {"key": "o1", "crew": "Mert", "rank": 2, "rival": "Wif"}
	assert(Moments.push("overtake", &"run_toast", ctx), "first enqueue succeeds")
	assert(not Moments.push("overtake", &"run_toast", ctx), "same key is deduped")
	assert(Moments.peek_rows(&"run_toast").size() == 1, "the event is queued exactly once")


func _test_cooldowns() -> void:
	Moments.reset()
	var t := 1000.0
	Moments.push("overtake", &"run_toast", {"key": "a", "crew": "Mert", "rank": 2, "rival": "Wif"}, t)
	var first := Moments.next_for(&"run_toast", t)
	assert(String(first["id"]) == "overtake", "overtake shown first")
	Moments.dismiss("overtake", t)

	assert(Moments.push("overtake", &"run_toast", {"key": "b", "crew": "Mert", "rank": 2, "rival": "Wif"}, t + 1.0), "a new key enqueues")
	assert(Moments.next_for(&"run_toast", t + 1.0).is_empty(), "per-event cooldown blocks an immediate re-show")
	assert(Moments.next_for(&"run_toast", t + 19.0).is_empty(), "still cooling down before the window")
	var cooled := Moments.next_for(&"run_toast", t + 21.0)
	assert(String(cooled.get("id", "")) == "overtake", "ready once the cooldown elapses")


func _test_home_banner_gap() -> void:
	Moments.reset()
	var t := 2000.0
	Moments.push("live_ticker", &"home_banner", {"key": "h1", "rival": "Wif", "gain": 340, "min": 10}, t)
	assert(not Moments.next_for(&"home_banner", t).is_empty(), "first non-critical banner shows")
	Moments.dismiss("live_ticker", t)

	Moments.push("streak", &"home_banner", {"key": "h2", "n": 3}, t + 1.0)
	assert(Moments.next_for(&"home_banner", t + 10.0).is_empty(), "non-critical banners keep the ≥20 s gap")
	var second := Moments.next_for(&"home_banner", t + 21.0)
	assert(String(second.get("id", "")) == "streak", "next banner after the gap")


func _test_one_at_a_time() -> void:
	Moments.reset()
	Moments.push("new_best", &"result_card", {"key": "nb", "score": 240})
	Moments.push("catch_cta", &"result_card", {"key": "cc", "crew": "Bitsy", "gap": 180})
	var first := Moments.next_for(&"result_card")
	assert(String(first["id"]) == "catch_cta", "priority 50 before 110")
	var again := Moments.next_for(&"result_card")
	assert(String(again["id"]) == "catch_cta", "only one result card is visible at a time")
	Moments.dismiss("catch_cta")
	var next := Moments.next_for(&"result_card")
	assert(String(next["id"]) == "new_best", "the next card shows after dismiss")


func _test_detection() -> void:
	var save := SaveManager.new()
	save.name = "SaveManager"
	save.save_path = "user://nocaps_moments_test.json"
	root.add_child(save)
	save.selected_community_id = &"mert"
	var dummy_race := RefCounted.new()  # no race methods -> race-derived events skip

	Moments.reset()
	var payload := {
		"community_id": "mert",
		"community_name": "Mert",
		"score": 240,
		"contribution": 248,
		"new_best": true,
		"streak": 3,
		"tier_crossed": true,
		"tier_after": 2,
	}
	Moments.observe_result(save, payload, dummy_race, _rows())
	var ids := _ids(Moments.peek_rows(&"result_card"))
	assert(ids.has("new_best"), "new best detected from the payload")
	assert(ids.has("streak"), "streak detected from the payload")
	assert(ids.has("tier_crossed"), "tier crossing detected from the payload")
	var top := Moments.next_for(&"result_card")
	assert(String(top["id"]) == "new_best", "new best leads the result queue")

	Moments.reset()
	Moments.observe_home(save, dummy_race, _rows())
	assert(Moments.next_for(&"home_banner").is_empty(), "no race module -> no home moment")
	save.free()


func _test_popup_builds() -> void:
	var popup := MomentPopup.new()
	root.add_child(popup)
	var moment := {
		"id": "overtake", "surface": &"run_toast", "emotion": "SCOREBOARD",
		"accent": "gold", "title": "MERT TAKES #2!", "detail": "Passed Wif",
	}
	var row: Control = popup.build_row(moment)
	assert(row != null, "a scoreboard moment builds into a kit row")
	var pride := moment.duplicate()
	pride["id"] = "new_best"
	pride["emotion"] = "PRIDE"
	pride["accent"] = "green"
	var pride_row: Control = popup.build_row(pride)
	assert(pride_row != null, "a pride moment builds too")
	popup.free()
	row.free()
	pride_row.free()


## One popup at a time: a toast, a result card and a banner requested together
## never stack. The later two wait in the queue and surface one after another.
func _test_popup_single_visible() -> void:
	Moments.reset()
	var popup := MomentPopup.new()
	root.add_child(popup)
	await process_frame
	popup.show_run_toast({
		"id": "overtake", "surface": &"run_toast", "emotion": "SCOREBOARD",
		"accent": "gold", "title": "MERT TAKES #2!", "detail": "Passed Wif",
	})
	popup.show_result_card({
		"id": "new_best", "surface": &"result_card", "emotion": "PRIDE",
		"accent": "green", "title": "NEW BEST!", "detail": "240",
	})
	popup.show_home_banner({
		"id": "live_ticker", "surface": &"home_banner", "emotion": "SCOREBOARD",
		"accent": "red", "title": "Wif +340 in the last 10 min", "detail": "closing in!",
	})
	assert(popup._live.size() == 1, "only one popup is visible at a time")
	assert(popup._queue.size() == 2, "later popups wait for their turn")

	await create_timer(MomentPopup.RUN_TOAST_SECONDS + 0.8).timeout
	assert(popup._live.size() == 1, "the second popup shows alone once the first is gone")
	assert(popup._queue.size() == 1, "the third still waits")

	await create_timer(MomentPopup.RESULT_CARD_SECONDS + 0.8).timeout
	assert(popup._live.size() == 1, "the third popup shows alone")
	assert(popup._queue.is_empty(), "queue is empty once every popup has shown")
	popup.queue_free()
	await process_frame


## The popup must hold the card fully visible through the middle of its hold
## (docs/15 §3: slide/fade in → hold → fade out), on all three surfaces.
func _test_popup_hold_alpha() -> void:
	await _check_hold_alpha(&"run_toast", MomentPopup.RUN_TOAST_SECONDS)
	await _check_hold_alpha(&"result_card", MomentPopup.RESULT_CARD_SECONDS)
	await _check_hold_alpha(&"home_banner", MomentPopup.HOME_BANNER_SECONDS)
	await _check_reduced_alpha()


func _check_hold_alpha(surface: StringName, hold: float) -> void:
	var popup := MomentPopup.new()
	root.add_child(popup)
	await process_frame
	var moment := {
		"id": "overtake", "surface": surface, "emotion": "SCOREBOARD",
		"accent": "gold", "title": "MERT TAKES #2!", "detail": "Passed Wif",
	}
	match surface:
		&"run_toast":
			popup.show_run_toast(moment)
		&"result_card":
			popup.show_result_card(moment)
		&"home_banner":
			popup.show_home_banner(moment)
	await create_timer(0.2 + hold * 0.5).timeout
	assert(popup._live.size() == 1, "%s stays live at mid-hold" % surface)
	var alpha := (popup._live[0] as Control).modulate.a
	assert(alpha >= 0.9, "%s stays visible at mid-hold (alpha %.2f)" % [surface, alpha])
	popup.queue_free()
	await process_frame


func _check_reduced_alpha() -> void:
	var popup := MomentPopup.new()
	root.add_child(popup)
	await process_frame
	popup.show_run_toast({
		"id": "overtake", "surface": &"run_toast", "emotion": "SCOREBOARD",
		"accent": "gold", "title": "MERT TAKES #2!", "detail": "Passed Wif",
	}, {"reduced_motion": true})
	await process_frame
	assert((popup._live[0] as Control).modulate.a >= 0.99, "reduced motion shows the toast instantly")
	popup.queue_free()
	await process_frame


func _ids(moments: Array) -> Array:
	var out: Array = []
	for moment in moments:
		out.append(String(moment.get("id", "")))
	return out


func _rows() -> Array:
	return [
		{"id": "bitsy", "name": "Bitsy", "score": 1600},
		{"id": "mert", "name": "Mert", "score": 1420},
		{"id": "wif", "name": "Wif", "score": 1408},
	]
