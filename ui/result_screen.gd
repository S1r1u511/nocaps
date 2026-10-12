extends UiScreen

## Result — v2 "arcade sticker" (docs/UI_V2_BRIEF.md §6, docs/mockups/result.html).
## Cause line → optional tilted NEW BEST sticker → huge GOLD outlined score with
## count-up → "Best {n}" → survived time → "+n coins" → contribution card (mascot
## tile + "+n for Crew" + rank + streak) → PLAY AGAIN → SHARE + BOARD. The shell
## hides the tab bar here, and no moment/toast UI ever overlaps this screen.

var _score_label: Label
var _retry_button: Button
var _coins_label: Label
var _page: VBoxContainer
## Viewport height available to the page content between the top/bottom margins.
var _content_height: float = 0.0

func setup(payload: Dictionary) -> void:
	var score := int(payload.get("score", 0))
	var best := int(payload.get("best", score))
	var new_best := bool(payload.get("new_best", false))
	var reason := String(payload.get("reason", ""))
	var community_id := StringName(payload.get("community_id", ""))
	var community_name := String(payload.get("community_name", ""))
	var contribution := int(payload.get("contribution", score))
	_run_id = String(payload.get("run_id", ""))
	var streak := int(payload.get("streak", 0))
	var streak_multiplier := float(payload.get("streak_multiplier", 1.0))
	var survival := float(payload.get("survival_seconds", 0.0))
	var coins := int(payload.get("coins", 0))
	var entry := CommunityRepository.by_id(CommunityRepository.load_roster(), community_id)
	# Short phones (720×1280) tighten the vertical rhythm so the whole result fits
	# without scrolling; 720×1560 keeps the full mockup spacing.
	var compact := get_viewport_rect().size.y < 1400.0
	var space := func(base: float) -> float: return px(base * (0.55 if compact else 1.0))

	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.scroll_deadzone = DRAG_DEADZONE
	add_child(scroll)
	_page_root = scroll

	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Fill the viewport so the expanding gap above PLAY AGAIN is what carries the
	# layout (docs/mockups/v2/live_result.html `flex-grow: 1`): added content
	# (e.g. the Survived line) then never moves the buttons.
	margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_theme_constant_override("margin_left", 40)
	margin.add_theme_constant_override("margin_right", 40)
	var margin_top := int(space.call(56) + maxf(ShellUI.safe_top, 0.0))
	var margin_bottom := int(space.call(34) + maxf(ShellUI.safe_bottom, 0.0))
	margin.add_theme_constant_override("margin_top", margin_top)
	margin.add_theme_constant_override("margin_bottom", margin_bottom)
	scroll.add_child(margin)
	_content_height = maxf(get_viewport_rect().size.y - float(margin_top + margin_bottom), 0.0)

	var page := VBoxContainer.new()
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.add_theme_constant_override("separation", 0)
	margin.add_child(page)
	_page = page

	if not reason.is_empty():
		page.add_child(_cause_label(reason))
		page.add_child(make_spacer(space.call(18)))
	if new_best:
		page.add_child(_new_best_sticker())
		page.add_child(make_spacer(space.call(6)))

	_score_label = outlined_title("0", GOLD, SIZE_SCORE_RESULT)
	_score_label.name = "ResultScore"
	_score_label.add_theme_constant_override("outline_size", 15)
	_score_label.add_theme_constant_override("shadow_offset_y", 15)
	_score_label.add_theme_constant_override("shadow_outline_size", 15)
	page.add_child(_score_label)
	page.add_child(make_spacer(space.call(4)))
	page.add_child(_best_label(best))
	if survival > 0.0:
		page.add_child(make_spacer(space.call(4)))
		page.add_child(_survived_label(survival))
	if coins > 0:
		page.add_child(make_spacer(space.call(12)))
		page.add_child(_coins_row(coins))
	page.add_child(make_spacer(space.call(26)))

	var crew := community_name
	if crew.is_empty() and entry != null:
		crew = entry.display_name
	if not crew.is_empty():
		_build_contribution_card(page, entry, crew, contribution, community_id, streak, streak_multiplier)

	if _should_ask_name():
		_build_onboard_card(page)

	# The expanding gap carries the layout (docs/mockups/v2/live_result.html
	# `flex-grow: 1`), so added lines never move the buttons.
	var gap := Control.new()
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	gap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(gap)

	_retry_button = primary_button("PLAY AGAIN", func() -> void: navigate.emit(&"run", {}), px(76), px(30))
	_retry_button.name = "ResultPlayAgain"
	# A long crew name must never overflow the button onto its edges.
	_retry_button.clip_text = true
	page.add_child(_retry_button)
	page.add_child(make_spacer(space.call(18)))

	var actions := HBoxContainer.new()
	actions.name = "ResultActions"
	actions.add_theme_constant_override("separation", int(px(12)))
	page.add_child(actions)
	var share := secondary_button("SHARE", func() -> void: _share_result(entry), px(54), px(18))
	share.name = "ResultShare"
	share.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(share)
	var board := secondary_button("BOARD", func() -> void: navigate.emit(&"leaderboard", {}), px(54), px(18))
	board.name = "ResultBoard"
	board.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(board)

	_count_up(score)

# ---------------------------------------------------------------------------
# Sections
# ---------------------------------------------------------------------------

func _cause_label(text: String) -> Label:
	var label := _make_base_label(text, 33, CORAL)
	label.add_theme_font_override("font", _bold())
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return label

func _new_best_sticker() -> CenterContainer:
	var center := CenterContainer.new()
	center.name = "ResultNewBest"
	var sticker := PanelContainer.new()
	sticker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = GOLD
	style.set_corner_radius_all(22)
	style.set_border_width_all(6)
	style.border_color = INK
	style.border_width_bottom = 13
	style.content_margin_left = 26.0
	style.content_margin_right = 26.0
	style.content_margin_top = 6.0
	style.content_margin_bottom = 14.0
	sticker.add_theme_stylebox_override("panel", style)
	var label := _make_base_label("NEW BEST!", 30, INK)
	label.add_theme_font_override("font", _bold())
	sticker.add_child(label)
	sticker.rotation = deg_to_rad(-5.0)
	sticker.resized.connect(func() -> void: sticker.pivot_offset = sticker.size * 0.5)
	center.add_child(sticker)
	return center

func _best_label(best: int) -> Label:
	var label := _make_base_label("Best %s" % fmt(best), 28, Color(CREAM.r, CREAM.g, CREAM.b, 0.8))
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return label

## Survival-time line under the best score. It sits above the expanding gap that
## precedes PLAY AGAIN, so adding it never moves the buttons.
func _survived_label(seconds: float) -> Label:
	var label := _make_base_label("Survived %s" % _time_text(seconds), 28,
		Color(CREAM.r, CREAM.g, CREAM.b, 0.8))
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return label

func _time_text(seconds: float) -> String:
	var total := int(maxf(seconds, 0.0))
	return "%d:%02d" % [total / 60, total % 60]

func _build_contribution_card(
	page: VBoxContainer,
	entry: CommunityDefinition,
	crew: String,
	contribution: int,
	community_id: StringName,
	streak: int,
	streak_multiplier: float
) -> void:
	var card := sticker_card(page, 18)
	card.name = "ResultContribution"
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", int(px(14)))
	card.add_child(row)
	if entry != null and entry.mascot != null and entry.mascot.idle_texture != null:
		var tile := avatar_tile(entry, px(84), true)
		tile.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(tile)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	column.add_theme_constant_override("separation", 6)
	row.add_child(column)
	var gain := _make_base_label("+%s for %s" % [fmt(contribution), crew], 48, YOURS)
	gain.add_theme_font_override("font", _bold())
	gain.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	# A long crew name wraps inside the card instead of widening the whole page.
	gain.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	gain.custom_minimum_size.x = 0.0
	column.add_child(gain)
	_board_status = _line("", 22, CREAM)
	_board_status.name = "ResultBoardStatus"
	column.add_child(_board_status)
	_update_board_status()
	var rank_text := _rank_line(community_id, crew)
	if not rank_text.is_empty():
		column.add_child(_line(rank_text, 28, CREAM))
	var streak_text := _streak_text(streak, streak_multiplier)
	if not streak_text.is_empty():
		column.add_child(_line(streak_text, 24, LILAC))
	# A live crew battle: say this run counts in it (same board as the web).
	# Otherwise, if this crew is in today's clash, say the run counts there.
	if not BattleService.board_for(String(community_id)).is_empty():
		var battle := _line("Counts in %s" % BattleService.title, 24, GOLD)
		battle.name = "ResultBattleLine"
		column.add_child(battle)
	elif Clash.has_crew(Clash.today(save_manager), community_id):
		var clash := _line("Counts in today's clash", 24, GOLD)
		clash.name = "ResultClashLine"
		column.add_child(clash)

# ---------------------------------------------------------------------------
# Board status (offline rule C, Oct 10): where this run's points went.
# ---------------------------------------------------------------------------

var _run_id := ""
var _board_status: Label
var _status_timer: Timer
var _status_checks := 0

## counted: the run left the queue on the same server day -> on today's board.
## pending: still queued (sending, or offline) -> counts if it syncs today.
## personal_only: played on an earlier server day -> personal score only.
func _update_board_status() -> void:
	if _board_status == null or not is_instance_valid(_board_status):
		return
	var queued := _queued_record()
	if _run_id.is_empty():
		_board_status.visible = false
		return
	if queued.is_empty():
		_board_status.text = "Counted on today's board"
		_board_status.add_theme_color_override("font_color", YOURS)
		_stop_status_timer()
		return
	if RunSubmission.queued_status(queued) == RunSubmission.STATUS_PERSONAL_ONLY:
		_board_status.text = "Played on an earlier day · saved as a personal score"
		_stop_status_timer()
		return
	var online := BackendClient.instance != null and BackendClient.instance.is_available() \
		and Standings.connection_state() != "offline"
	_board_status.text = "Sending to today's board…" if online and _status_checks < 20 \
		else "Saved offline · counts when you're back online today"
	_ensure_status_timer()

func _queued_record() -> Dictionary:
	if save_manager == null:
		return {}
	for entry in save_manager.pending_submissions:
		var record: Dictionary = entry.get("record", {})
		if String(record.get("run_id", "")) == _run_id:
			return record
	return {}

func _ensure_status_timer() -> void:
	if is_instance_valid(_status_timer):
		return
	_status_timer = Timer.new()
	_status_timer.wait_time = 0.5
	_status_timer.timeout.connect(func() -> void:
		_status_checks += 1
		_update_board_status())
	add_child(_status_timer)
	_status_timer.start()

func _stop_status_timer() -> void:
	if is_instance_valid(_status_timer):
		_status_timer.stop()

# ---------------------------------------------------------------------------
# First-run card: one dismissible card, name + wallet, shown once.
# ---------------------------------------------------------------------------

var _name_input: LineEdit
var _onboard_card: Control

func _should_ask_name() -> bool:
	return save_manager != null and save_manager.runs_played >= 1 \
		and not PlayerName.is_valid(save_manager.display_name) \
		and not save_manager.name_prompt_dismissed

## A single dismissible card inside the result page (not an overlay, so no
## keyboard pops over the score). It holds the one-time name field and, on
## Android with the wallet bridge, the prize-eligibility connect button. The
## name field is never auto-focused: the phone keyboard only opens on a tap.
func _build_onboard_card(page: VBoxContainer) -> void:
	var card := sticker_card(page, 16, GOLD)
	var panel := card.get_parent().get_parent() as Control
	panel.name = "ResultOnboardCard"
	_onboard_card = panel
	var title := _line("Put your name on the board", 34, CREAM)
	title.add_theme_font_override("font", _bold())
	card.add_child(title)
	card.add_child(_line(
		"Right now you show as %s. You can change it any time on Profile." % PlayerName.guest_name(save_manager.ensure_player_id()),
		22, LILAC))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", int(px(8)))
	card.add_child(row)
	_name_input = make_input("Your name", "", PlayerName.MAX_LENGTH)
	_name_input.name = "ResultNameInput"
	_name_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_input.text_submitted.connect(func(_t: String) -> void: _save_name())
	row.add_child(_name_input)
	var save := primary_button("SAVE", _save_name, px(54), px(20))
	save.name = "ResultNameSave"
	save.custom_minimum_size.x = px(150)
	row.add_child(save)
	if _wallet_available():
		var connect := secondary_button(
			"Connect wallet: be prize-eligible", _connect_wallet, px(54), px(16))
		connect.name = "ResultConnectWallet"
		card.add_child(connect)
	var dismiss := secondary_button("NOT NOW", _skip_name, px(46), px(16))
	dismiss.name = "ResultNameSkip"
	card.add_child(dismiss)

func _save_name() -> void:
	if save_manager == null or _name_input == null:
		return
	var name := PlayerName.sanitize(_name_input.text)
	var problem := PlayerName.problem(name)
	if not problem.is_empty():
		Toasts.show_message(problem)
		return
	save_manager.display_name = name
	save_manager.save_data()
	Toasts.show_message("You're on the board as %s" % name)
	_close_onboard_card()

## "Not now": remembers the dismissal so the card never shows again.
func _skip_name() -> void:
	if save_manager != null:
		save_manager.name_prompt_dismissed = true
		save_manager.save_data()
	_close_onboard_card()

func _close_onboard_card() -> void:
	if _onboard_card != null and is_instance_valid(_onboard_card):
		_onboard_card.queue_free()
	_onboard_card = null
	_name_input = null

## Android-only, and only when the wallet bridge is present.
func _wallet_available() -> bool:
	var wallet := get_node_or_null("/root/WalletService")
	return OS.has_feature("android") and wallet != null \
		and wallet.has_method("is_available") and bool(wallet.call("is_available"))

## Existing read-only sign-in flow: it only signs a message, never a transaction.
func _connect_wallet() -> void:
	var wallet := get_node_or_null("/root/WalletService")
	if wallet != null and wallet.has_method("connect_wallet"):
		wallet.call("connect_wallet")

func _line(text: String, size: int, color: Color) -> Label:
	var label := _make_base_label(text, size, color)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label

func _streak_text(streak: int, multiplier: float) -> String:
	if streak > 1:
		return "%d-day streak ×%.2f" % [streak, multiplier]
	if streak == 1:
		return "Day 1 of your streak"
	return ""

## Today's standing for the run's crew: lead gap or distance behind the crew above.
func _rank_line(community_id: StringName, crew_name: String) -> String:
	if community_id == &"":
		return ""
	var rows := Standings.communities_today(save_manager)
	var index := -1
	for i in range(rows.size()):
		if rows[i]["id"] == community_id:
			index = i
			break
	if index < 0:
		return ""
	var row: Dictionary = rows[index]
	var crew := crew_name if not crew_name.is_empty() else String(row["name"])
	var score := int(row["score"])
	if index == 0:
		var gap := score
		if rows.size() > 1:
			gap = score - int(rows[1]["score"])
		return "%s is #1 — leading by %s" % [crew, fmt(gap)]
	var above: Dictionary = rows[index - 1]
	return "%s is #%d — %s behind %s" % [
		crew, index + 1, fmt(int(above["score"]) - score), String(above["name"])
	]

## Count the run score up with a soft tick per step (skipped when muted).
func _count_up(score: int) -> void:
	if score <= 0:
		_score_label.text = "%d" % score
		return
	var last := {"value": -1}
	var duration := clampf(0.35 + float(score) * 0.02, 0.35, 1.0)
	var tween := create_tween()
	tween.tween_method(
		func(value: float) -> void:
			var shown := int(round(value))
			if shown != int(last["value"]):
				last["value"] = shown
				SoundService.play_count()
			_score_label.text = "%d" % shown,
		0.0, float(score), duration
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

## "+n coins" earned this run (gameplay supplies the `coins` result key; a
## missing key reads as 0 and the line stays out of the layout).
func _coins_row(coins: int) -> CenterContainer:
	var center := CenterContainer.new()
	center.name = "ResultCoins"
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", int(px(6)))
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var icon := Icon.new()
	icon.setup(&"coin", GOLD, 34.0)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(icon)
	_coins_label = _make_base_label("+%s coins" % fmt(coins), 34, GOLD)
	_coins_label.name = "ResultCoinsLabel"
	_coins_label.add_theme_font_override("font", _bold())
	_coins_label.add_theme_color_override("font_outline_color", INK)
	_coins_label.add_theme_constant_override("outline_size", 8)
	row.add_child(_coins_label)
	center.add_child(row)
	return center

## Shares the run's crew invite; falls back to the site link when the result has
## no resolvable crew, so the button always does something visible.
func _share_result(entry: CommunityDefinition) -> void:
	if entry != null:
		InviteService.share_crew(entry)
		return
	DisplayServer.clipboard_set(InviteService.SITE_URL)
	Toasts.show_message("Link copied")
