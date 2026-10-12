extends SceneTree

## Screens layout smoke test: every polished menu screen's key rects stay inside
## the 720-wide viewport, the important sibling blocks never overlap, and no
## moment/toast UI pops over a screen uninvited. Runs at 720x1280 and 720x1560.
##   scripts/run_tests.sh screens_layout_smoke

const TestEnv := preload("res://tests/test_env.gd")

const SIZES := [Vector2i(720, 1280), Vector2i(720, 1560)]
const RESULT_PAYLOAD := {
	"score": 1240,
	"best": 1240,
	"new_best": true,
	"reason": "BUMPED!",
	"community_id": "mert",
	"community_name": "Mert",
	"contribution": 1240,
	"streak": 3,
	"streak_multiplier": 1.1,
	"survival_seconds": 84.0,
	"coins": 12,
}

var _failures: PackedStringArray = PackedStringArray()

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	if not TestEnv.begin("screens_layout_smoke"):
		return
	var sound := root.get_node_or_null("SoundService")
	if sound != null:
		sound.is_sound_enabled = false
		sound.is_music_enabled = false
	Moments.set_enabled(false)

	for size in SIZES:
		root.size = size
		await process_frame
		_write_save({})
		await _check_home(size, false)
		_write_save(_seeded_save())
		await _check_home(size, true)
		await _check_home_battle(size, "mole")
		await _check_home_battle(size, "mert")
		await _check_home_clash(size, "in")
		await _check_home_clash(size, "out")
		await _check_home_clash(size, "none")
		await _check_crew(size)
		await _check_board(size)
		await _check_quests(size)
		await _check_explore(size)
		await _check_profile(size)
		await _check_result(size)
		await _check_shell(size)
	root.size = Vector2i(720, 1280)

	if not _failures.is_empty():
		for failure in _failures:
			printerr("SCREENS_LAYOUT_FAIL: %s" % failure)
		quit(1)
		return
	print("SCREENS_LAYOUT_PASS: result + shell rects are disjoint and in-bounds at 720x1280 and 720x1560")
	quit()

# ---------------------------------------------------------------------------
# Home
# ---------------------------------------------------------------------------

func _check_home(size: Vector2i, picked: bool) -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await _settle(3)
	var flow := main.get_node("AppFlow") as AppFlow
	flow.transitions_enabled = false
	var shell := main.get_node("Shell") as ShellUI
	var screen := flow.current_screen()
	_expect(screen != null and screen.name == "HomeScreen", "home screen did not load")

	var cta := _by_name(screen, "HomePrimaryCta")
	var race := _by_name(screen, "HomeRaceCard")
	var quests := _by_name(screen, "HomeQuestsRow")
	var strip := _by_name(screen, "HomeCrewStrip")
	for named in [["CTA", cta], ["live race", race], ["quests entry", quests], ["crew strip", strip]]:
		_expect(named[1] != null, "home is missing %s (%s)" % [named[0], "picked" if picked else "new"])

	# No beat/banner UI may mount itself on Home.
	_expect(_find_children(screen, "MomentPopup").is_empty(), "a MomentPopup is mounted on Home")

	if cta != null and race != null and quests != null and strip != null:
		var tab_top: float = (shell._tabs as Control).get_global_rect().position.y
		for named in [["CTA", cta], ["live race", race], ["quests entry", quests]]:
			var rect: Rect2 = (named[1] as Control).get_global_rect()
			_expect_in_horizontal(rect, size.x, "home %s" % named[0])
			_expect(rect.end.y <= tab_top + 1.0,
				"home %s sits under the tab bar (%s vs %s) at %dx%d" % [named[0], rect, tab_top, size.x, size.y])
		var cta_rect: Rect2 = (cta as Control).get_global_rect()
		var race_rect: Rect2 = (race as Control).get_global_rect()
		_expect(cta_rect.end.y <= race_rect.position.y + 1.0 or race_rect.end.y <= cta_rect.position.y + 1.0,
			"home CTA and live race card overlap at %dx%d" % [size.x, size.y])

	# New user: the strip is today's top 3 crews. After picking: their crew plus
	# others (top 3 + one extra, never fewer than the new-user strip).
	_expect((strip as Control).get_child_count() == 3 if not picked else (strip as Control).get_child_count() >= 3,
		"home crew strip has the wrong size for %s at %dx%d" % ["picked" if picked else "new", size.x, size.y])
	var hero: Control = screen._hero_holder
	_expect(hero != null and not _find_children(hero, "MascotPreview").is_empty(),
		"home hero mascot missing at %dx%d" % [size.x, size.y])
	_expect_all_labels_in_bounds(screen, size, "home")

	main.queue_free()
	await _settle(2)

## A live crew battle takes over the race card: battle title + clock, the two
## battle crews, and a note; everything stays on screen at both sizes.
func _check_home_battle(size: Vector2i, other: String) -> void:
	BattleService.clear()
	BattleService.set_window("cap-clash-2", PackedStringArray([other, "bitsy"]), -20000, 580000, "app", "Cap Clash #2")
	BattleService.scores = {other: 420, "bitsy": 310}
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await _settle(3)
	var flow := main.get_node("AppFlow") as AppFlow
	flow.transitions_enabled = false
	var shell := main.get_node("Shell") as ShellUI
	var screen := flow.current_screen()
	var title := _by_name(screen, "HomeRaceTitle") as Label
	var note := _by_name(screen, "HomeBattleNote") as Label
	var race := _by_name(screen, "HomeRaceCard") as Control
	var quests := _by_name(screen, "HomeQuestsRow") as Control
	_expect(title != null and title.text.begins_with("CAP CLASH #2 · "), "battle title on the race card (%s)" % [title.text if title else "none"])
	_expect(title != null and not title.text.begins_with("TODAY'S CLASH"), "a live battle overrides today's clash")
	_expect(note != null and note.visible, "battle note shows")
	if note != null:
		var mine := other == "mert"
		_expect(note.text.begins_with("Your runs count") if mine else note.text.begins_with("Rep "),
			"battle note for %s: %s" % ["a crew in the battle" if mine else "a crew outside it", note.text])
	_expect(screen._race_rows.get_child_count() == 2, "two battle crews on the race card (got %d)" % screen._race_rows.get_child_count())
	if race != null and quests != null:
		var tab_top: float = (shell._tabs as Control).get_global_rect().position.y
		for named in [["race", race], ["quests", quests]]:
			var rect: Rect2 = (named[1] as Control).get_global_rect()
			_expect_in_horizontal(rect, size.x, "battle home %s" % named[0])
			_expect(rect.end.y <= tab_top + 1.0, "battle home %s under the tab bar at %dx%d" % [named[0], size.x, size.y])
	_expect_all_labels_in_bounds(screen, size, "battle home")
	main.queue_free()
	await _settle(2)
	BattleService.clear()

# ---------------------------------------------------------------------------
# Home — Today's Clash (no live battle)
# ---------------------------------------------------------------------------
#
# Three states: my crew is in the clash, my crew is outside it, and no crew has
# scored yet. With a live battle set, `_check_home_battle` shows the battle takes
# the card instead. Every state must fit at both reference sizes.
func _check_home_clash(size: Vector2i, mode: String) -> void:
	BattleService.clear()
	_write_save(_clash_save(mode))
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await _settle(3)
	var flow := main.get_node("AppFlow") as AppFlow
	flow.transitions_enabled = false
	var shell := main.get_node("Shell") as ShellUI
	var screen := flow.current_screen()
	_expect(screen != null and screen.name == "HomeScreen", "home screen did not load for clash %s" % mode)

	var title := _by_name(screen, "HomeRaceTitle") as Label
	var note := _by_name(screen, "HomeBattleNote") as Label
	var reset := _by_name(screen, "HomeClashReset") as Label
	var race := _by_name(screen, "HomeRaceCard") as Control
	var quests := _by_name(screen, "HomeQuestsRow") as Control
	for named in [["race card", race], ["clash title", title], ["clash note", note], ["quests", quests]]:
		_expect(named[1] != null, "clash %s is missing %s at %dx%d" % [mode, named[0], size.x, size.y])
	if title == null or note == null or race == null:
		main.queue_free()
		await _settle(2)
		return

	if mode == "none":
		_expect(title.text == "TODAY'S CLASH", "no-clash title (got '%s')" % title.text)
		_expect(screen._race_rows.get_child_count() == 0, "no crews before the first runs")
		_expect(note.visible and note.text.begins_with("Starts with the first runs"),
			"no-clash note (got '%s')" % note.text)
		_expect(reset == null or not reset.visible, "the reset clock is hidden before the first runs")
	else:
		_expect(title.text.begins_with("TODAY'S CLASH · "), "clash title (got '%s')" % title.text)
		_expect(screen._race_rows.get_child_count() == 2, "two clash crews (got %d)" % screen._race_rows.get_child_count())
		_expect(reset != null and reset.visible and reset.text.begins_with("resets in "),
			"reset clock (%s)" % [reset.text if reset else "missing"])
		_expect(note.visible, "clash note shows")
		if mode == "in":
			_expect(note.text.begins_with("Your runs count for"), "my crew note (got '%s')" % note.text)
		else:
			_expect(note.text.begins_with("Bitsy is #3,"), "outside note (got '%s')" % note.text)
			_expect(note.text.contains("700 pts behind #2"), "outside note gap (got '%s')" % note.text)

	if race != null and quests != null:
		var tab_top: float = (shell._tabs as Control).get_global_rect().position.y
		for named in [["race", race], ["quests", quests]]:
			var rect: Rect2 = (named[1] as Control).get_global_rect()
			_expect_in_horizontal(rect, size.x, "clash %s %s" % [mode, named[0]])
			_expect(rect.end.y <= tab_top + 1.0,
				"clash %s %s under the tab bar at %dx%d" % [mode, named[0], size.x, size.y])
	_expect_all_labels_in_bounds(screen, size, "clash %s" % mode)
	main.queue_free()
	await _settle(2)

# ---------------------------------------------------------------------------
# Crew page
# ---------------------------------------------------------------------------

func _check_crew(size: Vector2i) -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await _settle(3)
	var flow := main.get_node("AppFlow") as AppFlow
	flow.transitions_enabled = false
	flow.go_to(&"community_detail", {"community_id": "mert"})
	await _settle(3)
	var screen := flow.current_screen()
	_expect(screen != null and screen.name == "CommunityDetailScreen", "crew screen did not load")

	var cta := _by_name(screen, "CrewPrimaryCta")
	var invite := _by_name(screen, "CrewInvite")
	var chips := _by_name(screen, "CrewChips")
	for named in [["CTA", cta], ["invite", invite], ["chips", chips]]:
		_expect(named[1] != null, "crew page is missing %s at %dx%d" % [named[0], size.x, size.y])
	if cta != null and invite != null and chips != null:
		_expect_in_horizontal((cta as Control).get_global_rect(), size.x, "crew CTA")
		_expect_in_horizontal((invite as Control).get_global_rect(), size.x, "crew invite")
		_expect_in_horizontal((chips as Control).get_global_rect(), size.x, "crew chips")
	# No unfinished placeholder copy may render anywhere on the page.
	for label in _find_children(screen, "Label"):
		var text := (label as Label).text
		_expect(not text.contains("— players"), "crew page still shows '— players'")
		_expect(not text.contains("[Reward]"), "crew page still shows the [Reward] placeholder")
		_expect(not text.contains("Demo data") and not text.contains("Demo night"),
			"crew page still shows demo placeholder copy: %s" % text)
	_expect_all_labels_in_bounds(screen, size, "crew")

	main.queue_free()
	await _settle(2)

# ---------------------------------------------------------------------------
# Board
# ---------------------------------------------------------------------------

func _check_board(size: Vector2i) -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await _settle(3)
	var flow := main.get_node("AppFlow") as AppFlow
	flow.transitions_enabled = false
	flow.go_to(&"leaderboard", {})
	await _settle(3)
	var screen := flow.current_screen()
	_expect(screen != null and screen.name == "LeaderboardScreen", "board screen did not load")

	var chip := _by_name(screen, "BoardLiveChip")
	var podium := _by_name(screen, "BoardPodium")
	var section := _by_name(screen, "BoardSection")
	var cta := _by_name(screen, "BoardPlayCta")
	for named in [["live chip", chip], ["podium", podium], ["section", section], ["CTA", cta]]:
		_expect(named[1] != null, "board is missing %s at %dx%d" % [named[0], size.x, size.y])
	if chip != null and podium != null and section != null and cta != null:
		var chip_rect: Rect2 = (chip as Control).get_global_rect()
		var podium_rect: Rect2 = (podium as Control).get_global_rect()
		var section_rect: Rect2 = (section as Control).get_global_rect()
		var cta_rect: Rect2 = (cta as Control).get_global_rect()
		for named in [["chip", chip_rect], ["podium", podium_rect], ["section", section_rect], ["CTA", cta_rect]]:
			_expect_in_horizontal(named[1], size.x, "board %s" % named[0])
		_expect(chip_rect.end.y <= podium_rect.position.y + 1.0,
			"board live chip overlaps the podium at %dx%d" % [size.x, size.y])
		_expect(podium_rect.end.y <= section_rect.position.y + 1.0,
			"board podium overlaps the all-crews section at %dx%d" % [size.x, size.y])
		_expect(section_rect.position.y < cta_rect.position.y,
			"board CTA is not inside the all-crews section at %dx%d" % [size.x, size.y])
	# The player's crew (mert, #1) is tagged; the label must be present and inside.
	var yours := _find_text(screen, "YOUR CREW")
	_expect(yours != null, "board is missing the YOUR CREW tag for the selected crew")
	if yours != null:
		_expect_in_horizontal(yours.get_global_rect(), size.x, "board YOUR CREW tag")
	_expect_all_labels_in_bounds(screen, size, "board")

	main.queue_free()
	await _settle(2)

# ---------------------------------------------------------------------------
# Quests
# ---------------------------------------------------------------------------

func _check_quests(size: Vector2i) -> void:
	_write_save(_quest_seed_save())
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await _settle(3)
	var flow := main.get_node("AppFlow") as AppFlow
	flow.transitions_enabled = false
	flow.go_to(&"quests", {})
	await _settle(3)
	var screen := flow.current_screen()
	_expect(screen != null and screen.name == "QuestsScreen", "quests screen did not load")

	var header := _by_name(screen, "QuestsDailyHeader")
	var card := _by_name(screen, "QuestCard")
	_expect(header != null, "quests is missing the DAILY QUESTS header")
	_expect(card != null, "quests is missing quest cards")
	if card != null:
		_expect_in_horizontal((card as Control).get_global_rect(), size.x, "quest card")

	# Seeded state: one completed claimable quest (CLAIM button) and one claimed
	# quest (CLAIMED chip). Both states must be reachable and in-bounds.
	var claim := _find_button(screen, "CLAIM")
	var claimed := _find_text(screen, "CLAIMED")
	_expect(claim != null, "quests is missing the CLAIM button for a completed quest")
	_expect(claimed != null, "quests is missing the CLAIMED state chip")
	if claim != null:
		_expect_in_horizontal(claim.get_global_rect(), size.x, "quest CLAIM button")
	# The rewards note is a full line of copy: it must be readable, not squeezed
	# into an ellipsis by a competing expander.
	var note := _find_label_prefix(screen, "Rewards = crew points")
	_expect(note != null, "quests is missing the rewards note")
	if note != null:
		var bold: Font = load("res://data/fonts/fredoka_bold.tres")
		var size_px := note.get_theme_font_size("font_size")
		var natural := bold.get_string_size(note.text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px).x
		_expect(natural <= note.get_global_rect().size.x + 2.0,
			"quests rewards note is truncated (%.0f px text in %.0f px box)" % [
				natural, note.get_global_rect().size.x])
	_expect_all_labels_in_bounds(screen, size, "quests")

	main.queue_free()
	await _settle(2)
	_write_save(_seeded_save())

# ---------------------------------------------------------------------------
# Explore
# ---------------------------------------------------------------------------

func _check_explore(size: Vector2i) -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await _settle(3)
	var flow := main.get_node("AppFlow") as AppFlow
	flow.transitions_enabled = false
	flow.go_to(&"community_select", {})
	await _settle(3)
	var screen := flow.current_screen()
	_expect(screen != null and screen.name == "CommunitySelectScreen", "explore screen did not load")

	var chips := _by_name(screen, "ExploreChips")
	var grid := _by_name(screen, "ExploreGrid")
	var empty := _by_name(screen, "ExploreEmpty")
	for named in [["filter chips", chips], ["crew grid", grid], ["empty state", empty]]:
		_expect(named[1] != null, "explore is missing %s at %dx%d" % [named[0], size.x, size.y])
	if chips != null and grid != null and empty != null:
		_expect_in_horizontal((chips as Control).get_global_rect(), size.x, "explore chips")
		_expect_in_horizontal((grid as Control).get_global_rect(), size.x, "explore grid")
		# Two columns: the first two tiles share a row without overlapping.
		var tiles: Array = []
		for child in grid.get_children():
			if child is Control and (child as Control).is_visible_in_tree():
				tiles.append(child)
		_expect(tiles.size() >= 2, "explore grid should show at least two crew tiles")
		if tiles.size() >= 2:
			var first: Rect2 = (tiles[0] as Control).get_global_rect()
			var second: Rect2 = (tiles[1] as Control).get_global_rect()
			_expect_in_horizontal(first, size.x, "explore tile 1")
			_expect_in_horizontal(second, size.x, "explore tile 2")
			_expect(not first.intersects(second, false), "explore grid tiles overlap at %dx%d" % [size.x, size.y])
		# A filter with no matching crews shows the empty state instead of an
		# unexplained gap.
		screen.call("_set_filter", &"token")
		await _settle(2)
		_expect((empty as Control).visible, "explore empty state did not show for an empty filter")
		_expect_all_labels_in_bounds(screen, size, "explore")
		screen.call("_set_filter", &"all")
		await _settle(2)

	main.queue_free()
	await _settle(2)

# ---------------------------------------------------------------------------
# Profile
# ---------------------------------------------------------------------------

func _check_profile(size: Vector2i) -> void:
	_write_save(_seeded_save())
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await _settle(3)
	var flow := main.get_node("AppFlow") as AppFlow
	flow.transitions_enabled = false
	flow.go_to(&"profile", {})
	await _settle(3)
	var screen := flow.current_screen()
	_expect(screen != null and screen.name == "ProfileScreen", "profile screen did not load")

	var wallet := _by_name(screen, "ProfileWallet")
	var stats := _by_name(screen, "ProfileStats")
	var version := _by_name(screen, "ProfileVersion")
	for named in [["wallet card", wallet], ["stats grid", stats], ["version footer", version]]:
		_expect(named[1] != null, "profile is missing %s at %dx%d" % [named[0], size.x, size.y])
	if wallet != null and stats != null and version != null:
		var guest_height: float = (wallet as Control).get_global_rect().size.y
		_expect((version as Label).text.begins_with("v"),
			"profile version footer should read v<x.y.z> (got '%s')" % (version as Label).text)
		_expect(_find_text(screen, "Best time") != null, "profile is missing the Best time stat")
		_expect(_find_text(screen, "Coins") != null, "profile is missing the Coins stat")
		_expect(_find_text(screen, "321") != null, "profile coins total did not read SaveManager.coins_total")
		_expect(_find_text(screen, "[Reward]") == null, "profile still shows the [Reward] placeholder")
		_expect((stats as Control).get_child_count() == 6,
			"profile stats grid should show 6 tiles")
		_expect_in_horizontal((wallet as Control).get_global_rect(), size.x, "profile wallet")
		_expect_in_horizontal((version as Control).get_global_rect(), size.x, "profile version")
		_expect_all_labels_in_bounds(screen, size, "profile")

		# Wallet connect collapses the card to one row; expanding brings the
		# Disconnect action back.
		var wallet_service := root.get_node_or_null("/root/WalletService")
		if wallet_service != null:
			wallet_service.call("connect_wallet")
			await _settle(3)
			var collapsed := _by_name(screen, "ProfileWallet")
			_expect(collapsed != null, "connected wallet card missing")
			if collapsed != null:
				var collapsed_height: float = (collapsed as Control).get_global_rect().size.y
				_expect(collapsed_height < guest_height,
					"connected wallet card did not collapse (%.1f vs guest %.1f)" % [collapsed_height, guest_height])
				_expect_in_horizontal((collapsed as Control).get_global_rect(), size.x, "profile wallet collapsed")
			screen.call("_expand_wallet")
			await _settle(2)
			_expect(_find_button(screen, "Disconnect") != null,
				"expanded wallet card is missing the Disconnect action")
			wallet_service.call("disconnect_wallet")
			await _settle(2)
			_expect(_find_button(screen, "CONNECT WALLET") != null,
				"disconnecting did not restore the connect wallet card")

	main.queue_free()
	await _settle(2)

# ---------------------------------------------------------------------------
# Result
# ---------------------------------------------------------------------------

func _check_result(size: Vector2i) -> void:
	# Re-seed: the profile wallet flow above can leave a bare save behind, and this
	# check needs mert's real day total to be in today's clash.
	_write_save(_seeded_save())
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await _settle(2)
	var flow := main.get_node("AppFlow") as AppFlow
	flow.transitions_enabled = false
	flow.go_to(&"result", RESULT_PAYLOAD)
	await _settle(3)
	var screen := flow.current_screen()
	_expect(screen != null and screen.name == "ResultScreen", "result screen did not load")

	var score := _by_name(screen, "ResultScore")
	var sticker := _by_name(screen, "ResultNewBest")
	var coins := _by_name(screen, "ResultCoinsLabel")
	var contribution := _by_name(screen, "ResultContribution")
	var play := _by_name(screen, "ResultPlayAgain")
	var share := _by_name(screen, "ResultShare")
	var board := _by_name(screen, "ResultBoard")
	for named in [["score", score], ["NEW BEST", sticker], ["coins", coins],
			["contribution", contribution], ["PLAY AGAIN", play], ["SHARE", share], ["BOARD", board]]:
		_expect(named[1] != null, "result is missing %s at %dx%d" % [named[0], size.x, size.y])

	# No battle is live here and the run's crew (mert) leads today's clash, so the
	# contribution card says the run counts there (docs B2).
	var clash_line := _by_name(screen, "ResultClashLine") as Label
	_expect(clash_line != null and clash_line.text == "Counts in today's clash",
		"result is missing the today's-clash line (got '%s')" % [clash_line.text if clash_line else "none"])

	if score == null or sticker == null or coins == null or contribution == null \
			or play == null or share == null or board == null:
		main.queue_free()
		await _settle(2)
		return

	_expect(_find_children(screen, "MomentPopup").is_empty(), "a MomentPopup is mounted on Result")
	var rects := {
		"score": (score as Control).get_global_rect(),
		"new_best": (sticker as Control).get_global_rect(),
		"coins": (coins as Control).get_global_rect(),
		"contribution": (contribution as Control).get_global_rect(),
		"play": (play as Control).get_global_rect(),
		"share": (share as Control).get_global_rect(),
		"board": (board as Control).get_global_rect(),
	}
	for key in rects:
		_expect_in_horizontal(rects[key], size.x, "result %s" % key)
	# Top-to-bottom order: score block, NEW BEST above it, contribution card, then
	# the button stack; adjacent blocks may touch but never overlap.
	_expect(rects["new_best"].end.y <= rects["score"].position.y + 1.0,
		"NEW BEST sticker overlaps the score at %dx%d" % [size.x, size.y])
	_expect(rects["score"].end.y <= rects["contribution"].position.y + 1.0,
		"score overlaps the contribution card at %dx%d" % [size.x, size.y])
	_expect(rects["contribution"].end.y <= rects["play"].position.y + 1.0,
		"contribution card overlaps PLAY AGAIN at %dx%d" % [size.x, size.y])
	_expect(rects["play"].end.y <= rects["share"].position.y + 1.0,
		"PLAY AGAIN overlaps the SHARE/BOARD row at %dx%d" % [size.x, size.y])
	_expect(not rects["share"].intersects(rects["board"], false),
		"SHARE and BOARD overlap at %dx%d" % [size.x, size.y])
	_expect(rects["play"].end.y <= float(size.y) + 1.0 and rects["share"].end.y <= float(size.y) + 1.0,
		"result buttons overflow the viewport bottom at %dx%d" % [size.x, size.y])

	var page: VBoxContainer = screen._page
	_expect(page.get_combined_minimum_size().y <= float(screen._content_height) + 1.0,
		"result page overflows its viewport at %dx%d" % [size.x, size.y])
	_expect_all_labels_in_bounds(screen, size, "result")

	main.queue_free()
	await _settle(2)

# ---------------------------------------------------------------------------
# Shell
# ---------------------------------------------------------------------------

func _check_shell(size: Vector2i) -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await _settle(2)
	var flow := main.get_node("AppFlow") as AppFlow
	flow.transitions_enabled = false
	var shell := main.get_node("Shell") as ShellUI
	_expect(shell != null, "ShellUI missing from the app shell")

	for screen_name in [&"home", &"community_select", &"leaderboard", &"profile", &"quests"]:
		flow.go_to(screen_name, {})
		await _settle(3)
		var tabs: PanelContainer = shell._tabs
		_expect(tabs != null and tabs.visible, "tab bar hidden on %s" % screen_name)
		if tabs == null:
			continue
		var buttons: Array = shell._tab_buttons.values()
		_expect(buttons.size() == 4, "tab bar should have 4 tabs on %s" % screen_name)
		var rects: Array = []
		for button in buttons:
			var rect: Rect2 = (button as Control).get_global_rect()
			rects.append(rect)
			_expect_in_horizontal(rect, size.x, "tab %s" % (button as Button).text)
			_expect(rect.position.y >= 0.0 and rect.end.y <= float(size.y) + 1.0,
				"tab bar row leaves the viewport on %s" % screen_name)
		for i in range(rects.size()):
			for j in range(i + 1, rects.size()):
				_expect(not rects[i].intersects(rects[j], false),
					"tab buttons overlap on %s at %dx%d: %s %s" % [screen_name, size.x, size.y, rects[i], rects[j]])
		if screen_name == &"quests":
			# A Home sub-page: the PLAY tab stays lit rather than no tab at all.
			var home_icon: Icon = shell._tab_icons.get(&"home")
			_expect(home_icon != null and home_icon.color == ShellUI.GOLD,
				"quests should keep the PLAY tab highlighted")
		# No moment popup may mount itself while browsing.
		_expect(_find_children(main, "MomentPopup").is_empty(),
			"a MomentPopup mounted on %s" % screen_name)

	# Toasts are user feedback and must stay above the tab bar, one at a time.
	var toasts := main.get_node_or_null("Toasts")
	_expect(toasts != null, "Toasts layer missing from the app shell")
	if toasts != null:
		Toasts.show_message("Crew switched")
		await _settle(2)
		var box: VBoxContainer = toasts._box
		_expect(box != null and box.get_child_count() == 1, "toast did not spawn exactly one panel")
		if box != null and box.get_child_count() == 1:
			var toast := box.get_child(0) as Control
			var tab_top: float = (shell._tabs as Control).get_global_rect().position.y
			_expect_in_horizontal(toast.get_global_rect(), size.x, "toast")
			_expect(toast.get_global_rect().end.y <= tab_top + 1.0,
				"toast overlaps the tab bar (%s vs %s)" % [toast.get_global_rect(), tab_top])
			# A short toast must stay one wide pill, not collapse into a column.
			_expect(toast.get_global_rect().size.y <= 160.0,
				"toast collapsed to a tall column (%s)" % toast.get_global_rect())
			_expect(toast.get_global_rect().size.x >= 200.0,
				"toast is too narrow to read (%s)" % toast.get_global_rect())
	main.queue_free()
	await _settle(2)

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)

func _expect_in_horizontal(rect: Rect2, width: int, label: String) -> void:
	_expect(rect.position.x >= -1.0 and rect.end.x <= float(width) + 1.0,
		"%s leaves the viewport horizontally (%s in %d wide)" % [label, rect, width])

## Every visible text label must stay inside the viewport horizontally: catches
## clipped/overflowing names and values on any screen.
func _expect_all_labels_in_bounds(screen: Node, size: Vector2i, tag: String) -> void:
	for label in _find_children(screen, "Label"):
		var control := label as Control
		if not control.is_visible_in_tree():
			continue
		var rect := control.get_global_rect()
		if rect.size.x <= 0.0:
			continue
		_expect(rect.position.x >= -1.0 and rect.end.x <= float(size.x) + 1.0,
			"%s label leaves the viewport horizontally: '%s' %s at %dx%d" % [
				tag, (label as Label).text, rect, size.x, size.y])

func _settle(frames: int) -> void:
	for _i in range(frames):
		await process_frame

func _by_name(node: Node, name: String) -> Node:
	var found := node.find_child(name, true, false)
	return found

## First visible Label with exactly `text`, or null.
func _find_text(node: Node, text: String) -> Label:
	for label in _find_children(node, "Label"):
		if (label as Label).text == text:
			return label as Label
	return null

## First visible Button whose text equals `text`, or null.
func _find_button(node: Node, text: String) -> Button:
	for button in _find_children(node, "Button"):
		var control := button as Button
		if control.text == text and control.is_visible_in_tree():
			return control
	return null

## First visible Label whose text begins with `prefix`, or null.
func _find_label_prefix(node: Node, prefix: String) -> Label:
	for label in _find_children(node, "Label"):
		var control := label as Label
		if control.is_visible_in_tree() and control.text.begins_with(prefix):
			return control
	return null

func _find_children(node: Node, type_name: String) -> Array:
	return node.find_children("*", type_name, true, false)

func _seeded_save() -> Dictionary:
	return {
		"schema_version": 2,
		"selected_community_id": "mert",
		"best_score": 1240,
		"best_time": 84.0,
		"display_name": "Guest 4821",
		"runs_played": 27,
		"name_prompt_dismissed": true,
		"games_played": 27,
		"streak_days": 3,
		"last_played_day_utc": _today(),
		"day_start_day_utc": _today(),
		"week_start_day_utc": _week_start(),
		"day_contribution": {"mert": 3200, "wif": 2500, "bitsy": 1800, "mole": 900},
		"week_contribution": {"mert": 9800, "wif": 7400, "bitsy": 5100, "mole": 2600},
		"contribution_by_community": {"mert": 18400, "wif": 15200, "bitsy": 9700, "mole": 5200},
		"tiers_reached": {"mert": 2},
		"unlocked_caps": ["mert", "wif"],
		"coins_total": 321,
	}

## Clash fixtures on top of `_seeded_save`: "in" (mert is #1), "out" (bitsy is #3)
## and "none" (nobody has scored today yet).
func _clash_save(mode: String) -> Dictionary:
	var data := _seeded_save()
	if mode == "none":
		data["day_contribution"] = {"mert": 0, "wif": 0, "bitsy": 0, "mole": 0}
	elif mode == "out":
		data["selected_community_id"] = "bitsy"
	return data

func _write_save(data: Dictionary) -> void:
	var file := FileAccess.open(SaveManager.DEFAULT_SAVE_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(data, "\t"))

func _today() -> int:
	return int(floor(Time.get_unix_time_from_system() / 86400.0))

func _week_start() -> int:
	var today := _today()
	var weekday := int(Time.get_datetime_dict_from_unix_time(today * 86400).get("weekday", 0))
	return today - (weekday + 6) % 7

## Same save as `_seeded_save`, plus a deterministic quest day: quest 1 complete
## and claimable, quest 2 already claimed.
func _quest_seed_save() -> Dictionary:
	var data := _seeded_save()
	var day := int(floor(Time.get_unix_time_from_system() / 86400.0))
	var picked := Quests.daily_selection(day)
	if picked.size() >= 1:
		data["quest_progress"] = {String(picked[0]["id"]): int(picked[0]["target"])}
	if picked.size() >= 2:
		data["quest_claimed"] = [String(picked[1]["id"])]
		data["quest_points_today"] = int(picked[1]["reward"])
	data["quest_day_utc"] = day
	return data
