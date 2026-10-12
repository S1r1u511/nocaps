extends SceneTree

## Crew battles in the app (platform/battle_service.gd): parsing the live
## tournament and boards, the scoring window from the server clock, which board
## a run counts for, the embedded path, and offline behaviour.
##   scripts/run_tests.sh battle_smoke

const TestEnv := preload("res://tests/test_env.gd")

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	if not TestEnv.begin("battle_smoke"):
		return
	# Timestamps and the server clock.
	assert(BackendClient.timestamp_ms("2026-10-03T10:09:51.101Z") == 1791022191101, "RFC 3339 with millis (got %d)" % BackendClient.timestamp_ms("2026-10-03T10:09:51.101Z"))
	assert(BackendClient.timestamp_ms("2026-10-03T10:09:51Z") == 1791022191000, "RFC 3339 without millis")
	assert(BackendClient.timestamp_ms("") == 0, "empty timestamp")
	assert(BackendClient.server_ms_from(PackedStringArray(["Content-Type: x", "date: Sat, 03 Oct 2026 10:09:56 GMT"])) == 1791022196000, "Date header")
	assert(BackendClient.server_ms_from(PackedStringArray(["Content-Type: x"])) == 0, "no Date header")

	# The live tournament doc.
	var rows := [{"document": {"name": "projects/p/databases/(default)/documents/tournaments/cap-clash-2", "fields": {
		"status": {"stringValue": "live"}, "title": {"stringValue": "Cap Clash #2"},
		"crews": {"arrayValue": {"values": [{"stringValue": "mole"}, {"stringValue": "bitsy"}]}},
		"startAt": {"timestampValue": "2026-10-03T10:09:51.101Z"}, "durationSec": {"integerValue": "600"}}}}]
	var battle := BackendClient.parse_battle(rows)
	assert(battle["id"] == "cap-clash-2" and battle["title"] == "Cap Clash #2", "id and title")
	assert(battle["crews"] == PackedStringArray(["mole", "bitsy"]), "crews")
	assert(battle["duration_s"] == 600 and battle["start_ms"] == 1791022191101, "start and duration")
	assert(BackendClient.parse_battle([{"readTime": "x"}]).is_empty(), "no live tournament -> {}")

	# Window from the server clock: 60 s after startAt the battle is live.
	var start := int(battle["start_ms"])
	var t0 := 100000
	BattleService.clear()
	BattleService.absorb({"ok": true, "battle": battle, "server_ms": start + 60000}, t0)
	assert(BattleService.is_live(t0), "live 60 s in")
	assert(BattleService.board_for("mole", t0) == "cap-clash-2_mole", "a battle crew counts")
	assert(BattleService.board_for("mert", t0) == "", "a crew outside the battle never touches a board")
	assert(BattleService.seconds_left(t0) == 545, "600 s from startAt+5 s (got %d)" % BattleService.seconds_left(t0))
	assert(BattleService.board_for("mole", t0 + 545000 - 1000) == "", "too close to the end: skip the board, keep the run")
	assert(BattleService.board_for("mole", t0 + 545000 - 2000) == "cap-clash-2_mole", "still counts 2 s before the end")
	assert(BattleService.clock_text(t0) == "9:05", "clock text (got %s)" % BattleService.clock_text(t0))

	# During the 3-2-1: known, not live, nothing counts yet.
	BattleService.absorb({"ok": true, "battle": battle, "server_ms": start + 2000}, t0)
	assert(BattleService.in_countdown(t0) and not BattleService.is_live(t0), "countdown")
	assert(BattleService.board_for("mole", t0) == "", "nothing counts before the start")

	# Offline keeps what we knew; an ended or missing battle clears it.
	BattleService.absorb({"ok": true, "battle": battle, "server_ms": start + 60000}, t0)
	BattleService.absorb({"ok": false, "error": "offline"}, t0)
	assert(BattleService.board_for("mole", t0) == "cap-clash-2_mole", "offline: keep the window")
	BattleService.absorb({"ok": true, "battle": battle, "server_ms": start + 700000}, t0)
	assert(BattleService.tid.is_empty(), "an ended battle clears")
	BattleService.absorb({"ok": true, "battle": battle, "server_ms": start + 60000}, t0)
	BattleService.absorb({"ok": true, "battle": {}, "server_ms": start + 60000}, t0)
	assert(BattleService.tid.is_empty(), "no live battle clears")

	# The embedded path decides through the same helper, and the app query doesn't override it.
	EmbedService.set_battle({"board": "cap-clash-2_bitsy", "crew": "bitsy", "startsInMs": -10000, "endsInMs": 60000})
	assert(EmbedService.battle_board_for("bitsy") == "cap-clash-2_bitsy", "embed window")
	assert(BattleService.source == "embed", "embed source")
	BattleService.absorb({"ok": true, "battle": {}, "server_ms": start}, t0)
	assert(EmbedService.battle_board_for("bitsy") == "cap-clash-2_bitsy", "the app query never overrides the platform")
	EmbedService.set_battle({"board": "", "crew": ""})
	assert(BattleService.tid.is_empty(), "the platform ends it")

	# Boards: crew totals and this player's points.
	var boards := BackendClient.parse_boards([
		{"found": {"fields": {"crew": {"stringValue": "mole"}, "score": {"integerValue": "420"},
			"players": {"mapValue": {"fields": {"uidA": {"mapValue": {"fields": {"n": {"stringValue": "Dom"}, "s": {"integerValue": "283"}}}}}}}}}},
		{"missing": "x/boards/cap-clash-2_bitsy"}], "uidA")
	assert(boards["scores"] == {"mole": 420} and boards["mine"] == {"mole": 283}, "boards: %s" % boards)

	BattleService.clear()
	print("BATTLE_PASS: parsing, window, counting, embed, offline")
	quit()
