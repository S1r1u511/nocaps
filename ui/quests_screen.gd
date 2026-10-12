extends UiScreen

## Quests + crew hall of fame — v2 "arcade sticker" (docs/15_COMPETITION_AND_QUESTS.md
## §4–5, docs/mockups/v2/quests.html and pride_crew.html, docs/UI_V2_BRIEF.md §0–2).
## A scrollable page reached from Home (route id "quests"):
##
##   DAILY QUESTS   three deterministic quests with progress + CLAIM (Quests.claim)
##   EVENT QUESTS   rivalry (only when Race says the crew is within reach), the
##                  shared crew weekly goal, and a Sponsored "SOON" placeholder
##   CREW MILESTONES all-time, first week at #1, member count
##   TROPHY SHELF   four static mock slots, one dashed "next?"
##   TOP CARRIERS   weekly crew top 3 plus you
##   INVITE         shares this crew's invite link (native/web share)
##
## Every value comes from `Quests`, `Standings`, `Race` (via Standings), or the
## local save. Reward claiming goes through the documented quests claim path; the
## backend call is fired from there (backend/`claim_quest`) and the local reward is
## already authoritative. Nothing here changes gameplay rules.


const MEMBER_MILESTONE := 250
const ALL_TIME_MILESTONE := 100000

## TESTING placeholder: whole-crew weekly goal targets in crew points, keyed by
## community id. These are crew totals, not the per-player `weekly_tiers` — using
## the last tier (1,100) made every real crew total render as an already-full bar.
## Falls back to CREW_WEEKLY_TARGET_DEFAULT for crews without an entry; replace
## with authored crew-goal data when it exists.
const CREW_WEEKLY_TARGETS := {
	&"mert": 50000,
	&"wif": 50000,
	&"bitsy": 50000,
	&"mole": 50000,
}
const CREW_WEEKLY_TARGET_DEFAULT := 50000

## Top-of-page accent for the trophy shelf mock (one gold, one silver, one cap).
const TROPHY_LABELS := ["Champion", "Runner-up", "Gold cap"]

var _crew: CommunityDefinition
var _has_crew: bool = false
var _refresh_timer: Timer

var _week_bar: ProgressBar
var _week_label: Label
var _members_label: Label
var _carriers_box: VBoxContainer

func setup(_payload: Dictionary) -> void:
	_has_crew = save_manager != null and save_manager.selected_community_id != &""
	_crew = _resolve_crew()

	var page := build_page()
	page.add_child(_header())
	if not _has_crew:
		_build_no_crew(page)
	page.add_child(_daily_header())
	for quest in Quests.daily_quests(save_manager):
		page.add_child(_quest_card(quest))
	page.add_child(_events_header())
	_build_events(page)
	_build_milestones(page)
	_build_trophy(page)
	_build_carriers(page)
	_build_invite(page)
	page.add_child(_footer_note())

	_start_refresh_timer()

func _resolve_crew() -> CommunityDefinition:
	if not _has_crew or save_manager == null:
		return null
	return CommunityRepository.by_id(
		CommunityRepository.load_roster(), save_manager.selected_community_id)

func _crew_name() -> String:
	return _crew.display_name if _crew != null else "your crew"

# ---------------------------------------------------------------------------
# Header
# ---------------------------------------------------------------------------

func _header() -> Control:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", int(px(8)))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.add_child(_back_button(func() -> void: navigate.emit(&"home", {})))
	var note := _make_base_label(
		"Rewards = crew points for %s" % _crew_name(), SIZE_SMALL - 2,
		Color(CREAM.r, CREAM.g, CREAM.b, 0.8))
	note.add_theme_font_override("font", _bold())
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	note.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	note.clip_text = true
	note.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	note.custom_minimum_size.x = 0.0
	row.add_child(note)
	column.add_child(row)
	var title := outlined_title("QUESTS", CREAM, 64)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	column.add_child(title)
	column.add_child(_cap_note())
	return column

## Daily cap line: "Cap 300/day · N left" or a reached message (docs/15 §4).
func _cap_note() -> Label:
	var text := "Cap 300 quest points per day"
	if save_manager != null:
		var remaining := Quests.remaining_cap(save_manager)
		text = "Cap 300/day · %d left" % remaining
		if remaining <= 0:
			text = "Daily cap reached · back tomorrow"
	var label := _make_base_label(text, SIZE_SMALL, LILAC)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	return label

# ---------------------------------------------------------------------------
# No-crew placeholder
# ---------------------------------------------------------------------------

func _build_no_crew(page: VBoxContainer) -> void:
	var card := sticker_card(page, 12)
	card.add_child(make_h2("Pick a crew to earn quests"))
	card.add_child(make_sub("Quest points and crew milestones belong to the crew you represent."))
	card.add_child(secondary_button("EXPLORE CREWS",
		func() -> void: navigate.emit(&"community_select", {}), px(64), 30))

# ---------------------------------------------------------------------------
# Daily quests
# ---------------------------------------------------------------------------

func _daily_header() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var title := make_kicker("DAILY QUESTS")
	title.name = "QuestsDailyHeader"
	title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(title)
	row.add_child(_expander())
	var ending := Standings.race_state().day_ending()
	var reset := _make_base_label(
		"resets in %s" % String(ending.get("clock", "")), SIZE_SMALL - 2, LILAC)
	reset.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(reset)
	return row

func _quest_card(quest: Dictionary) -> PanelContainer:
	var target := maxi(int(quest.get("target", 1)), 1)
	var progress := clampi(int(quest.get("progress", 0)), 0, target)
	var completed := bool(quest.get("completed", false))
	var claimed := bool(quest.get("claimed", false))
	var claimable := bool(quest.get("claimable", false))
	var reward := int(quest.get("reward", 0))

	var panel := PanelContainer.new()
	panel.name = "QuestCard"
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", _row_style(CARD_INNER, CORAL if String(quest.get("source", "")) == "rivalry" else INK))

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	panel.add_child(column)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 12)
	column.add_child(top)
	var title := _plain_label(String(quest.get("title", "")), SIZE_SMALL + 4, CREAM, true)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(title)
	var reward_chip := chip("+%d crew pts" % reward, GOLD)
	reward_chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(reward_chip)

	var detail := String(quest.get("detail", ""))
	if not detail.is_empty():
		var detail_label := make_sub(detail, SIZE_SMALL - 2)
		column.add_child(detail_label)

	var bar := race_bar(float(progress) / float(target), YOURS if completed else GOLD, px(8))
	bar.custom_minimum_size = Vector2(0.0, px(8))
	column.add_child(bar)

	var state := "claimed" if claimed else ("complete" if completed else "active")
	column.add_child(_quest_action_row(quest, state, progress, target, claimable))
	return panel

## Right-aligned action: CLAIM button, "✓ CLAIMED" chip, or progress text.
func _quest_action_row(quest: Dictionary, state: String, progress: int, target: int, claimable: bool) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.add_child(_expander())
	if state == "claimed":
		var done := chip("CLAIMED", YOURS, &"check", SIZE_SMALL - 4)
		done.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(done)
	elif claimable:
		var button := primary_button("CLAIM", func() -> void: _claim_quest(quest), px(48), 30)
		button.custom_minimum_size = Vector2(px(110), px(48))
		row.add_child(button)
	else:
		var progress_label := _make_base_label(
			"%s / %s" % [fmt(progress), fmt(target)], SIZE_SMALL - 2, LILAC)
		progress_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(progress_label)
	return row

func _claim_quest(quest: Dictionary) -> void:
	var id := String(quest.get("id", ""))
	if save_manager == null:
		return
	if not _has_crew:
		Toasts.show_message("Pick a crew first")
		return
	if bool(quest.get("claimed", false)):
		Toasts.show_message("Already claimed")
		return
	var result := Quests.claim(save_manager, id, backend_client)
	if bool(result.get("ok", false)):
		Toasts.show_message("+%d for %s" % [int(result.get("points", 0)), _crew_name()])
		_rebuild()
		return
	match String(result.get("error", "")):
		"daily_cap":
			Toasts.show_message("Daily cap reached · back tomorrow")
		"not_complete":
			Toasts.show_message("Finish the quest first")
		"already_claimed":
			Toasts.show_message("Already claimed")
		_:
			Toasts.show_message("Couldn't claim — try again")

# ---------------------------------------------------------------------------
# Event quests: rivalry, crew weekly goal, sponsored placeholder
# ---------------------------------------------------------------------------

func _events_header() -> Control:
	return make_kicker("EVENT QUESTS")

func _build_events(page: VBoxContainer) -> void:
	var rivalry := Quests.rivalry_quest(save_manager)
	if not rivalry.is_empty():
		page.add_child(_quest_card(rivalry))
	if _has_crew:
		page.add_child(_crew_goal_card())
	page.add_child(_sponsored_card())

func _crew_goal_target() -> int:
	if _crew != null and CREW_WEEKLY_TARGETS.has(_crew.id):
		return int(CREW_WEEKLY_TARGETS[_crew.id])
	return CREW_WEEKLY_TARGET_DEFAULT

func _crew_goal_card() -> PanelContainer:
	var goal := _crew_goal_target()
	var week := _crew_week_score()
	var mine := save_manager.week_total(_crew.id) if save_manager != null else 0

	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", _row_style(CARD_INNER, INK))
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	panel.add_child(column)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 12)
	column.add_child(top)
	var title := _plain_label("%s weekly goal" % _crew_name(), SIZE_SMALL + 4, CREAM, true)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(title)
	var tier_chip := chip("GOAL", GOLD)
	tier_chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(tier_chip)

	_week_bar = race_bar(clampf(float(week) / float(maxi(goal, 1)), 0.0, 1.0), GOLD, px(12))
	_week_bar.custom_minimum_size = Vector2(0.0, px(12))
	column.add_child(_week_bar)

	_week_label = _make_base_label(
		"%s / %s · you added %s" % [fmt(week), fmt(goal), fmt(mine)], SIZE_SMALL - 2, LILAC)
	_week_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	column.add_child(_week_label)

	if _crew != null:
		var reward_text := _crew.campaign_value("reward_text")
		if not reward_text.is_empty():
			column.add_child(make_sub(reward_text, SIZE_SMALL - 2))
	return panel

func _crew_week_score() -> int:
	if _crew == null:
		return 0
	for row in Standings.communities_week(save_manager):
		if String(row.get("id", "")) == String(_crew.id):
			return int(row.get("score", 0))
	return 0

func _crew_week_rank() -> int:
	if _crew == null:
		return 0
	for row in Standings.communities_week(save_manager):
		if String(row.get("id", "")) == String(_crew.id):
			return int(row.get("rank", 0))
	return 0

func _sponsored_card() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", _dashed_style(CARD))
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	panel.add_child(column)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 12)
	column.add_child(top)
	var title := _plain_label("Sponsored quests", SIZE_SMALL + 4, CREAM, true)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(title)
	var soon := chip("EARLY BETA", LILAC)
	soon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(soon)
	column.add_child(make_sub("Crew-sponsored quests are an Early Beta idea; nothing is live yet.", SIZE_SMALL - 2))
	return panel

# ---------------------------------------------------------------------------
# Crew milestones
# ---------------------------------------------------------------------------

func _build_milestones(page: VBoxContainer) -> void:
	var card := sticker_card(page, 12)
	var header := _plain_label("CREW MILESTONES", SIZE_SMALL, Color(CREAM.r, CREAM.g, CREAM.b, 0.75), true)
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	card.add_child(header)
	if not _has_crew:
		card.add_child(make_sub("Milestones appear once you represent a crew.", SIZE_SMALL - 2))
		return

	var champion := Standings.last_champion(_crew.id)
	var members := Standings.members_count(_crew.id)
	var all_time := save_manager.total_contribution(_crew.id) if save_manager != null else 0

	var all_time_row := _milestone_row(
		all_time >= ALL_TIME_MILESTONE, "100k all-time points",
		"%s / %s" % [fmt(all_time), fmt(ALL_TIME_MILESTONE)], "")
	card.add_child(all_time_row)

	var won := not champion.is_empty()
	var champion_note := ""
	if won:
		champion_note = _period_label(String(champion.get("periodKey", "")))
	else:
		var rank := _crew_week_rank()
		champion_note = "#%d this week" % rank if rank > 0 else "not yet"
	card.add_child(_milestone_row(won, "First week at #1", champion_note, ""))

	# Keep a handle so a late member fetch can update the count in place.
	var member_row := _milestone_row(
		members >= MEMBER_MILESTONE, "%d members" % MEMBER_MILESTONE,
		_members_text(members), "")
	card.add_child(member_row)
	_members_label = _find_progress_label(member_row)

## "12 / 250", or "counting…" until the first member count arrives (never a fake 0).
func _members_text(members: int) -> String:
	if _crew == null or not Standings.members_known(_crew.id):
		return "counting…"
	return "%d / %d" % [members, MEMBER_MILESTONE]

func _milestone_row(done: bool, title: String, progress_text: String, done_label: String) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", int(px(10)))
	panel.add_child(row)

	var mark: Control
	if done:
		var icon := Icon.new()
		icon.setup(&"check", YOURS, SIZE_SMALL)
		mark = icon
	else:
		var dot := Icon.new()
		dot.setup(&"dot", LILAC, SIZE_SMALL - 6)
		mark = dot
	mark.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(mark)

	var title_label := _plain_label(title, SIZE_SMALL, CREAM, true)
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(title_label)

	var trailing := _plain_label(
		done_label if (done and not done_label.is_empty()) else progress_text,
		SIZE_SMALL - 2, LILAC, false)
	row.add_child(trailing)
	return panel

## The trailing label of a milestone row (stored so live refresh can rewrite it).
func _find_progress_label(row: PanelContainer) -> Label:
	var hbox := row.get_child(0)
	if hbox.get_child_count() >= 3:
		return hbox.get_child(2) as Label
	return null

func _period_label(period_key: String) -> String:
	var parts := period_key.split("-W")
	if parts.size() == 2 and not String(parts[1]).is_empty():
		return "Wk %s" % String(parts[1]).lstrip("0")
	return period_key

# ---------------------------------------------------------------------------
# Trophy shelf (static mock — four slots, one dashed "next?")
# ---------------------------------------------------------------------------

func _build_trophy(page: VBoxContainer) -> void:
	var card := sticker_card(page, 12)
	var header := _plain_label("TROPHY SHELF", SIZE_SMALL, Color(CREAM.r, CREAM.g, CREAM.b, 0.75), true)
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	card.add_child(header)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", int(px(8)))
	card.add_child(row)
	row.add_child(_trophy_slot_trophy())
	row.add_child(_trophy_slot_runner_up())
	row.add_child(_trophy_slot_cap())
	row.add_child(_trophy_slot_next())

func _trophy_slot(fill: Color, border: Color, content: Control, label_text: String) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.custom_minimum_size = Vector2(0.0, px(64))
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.set_corner_radius_all(int(px(14)))
	style.set_border_width_all(int(px(3)))
	style.border_color = border
	style.content_margin_left = px(4)
	style.content_margin_right = px(4)
	style.content_margin_top = px(4)
	style.content_margin_bottom = px(4)
	panel.add_theme_stylebox_override("panel", style)

	var column := VBoxContainer.new()
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 2)
	panel.add_child(column)
	column.add_child(make_center(content))
	var label := _make_base_label(label_text, SIZE_SMALL - 8, CREAM)
	label.add_theme_font_override("font", _bold())
	column.add_child(label)
	return panel

func _trophy_slot_trophy() -> PanelContainer:
	var icon := Icon.new()
	icon.setup(&"trophy", GOLD, px(26))
	return _trophy_slot(CARD_INNER, GOLD, icon, TROPHY_LABELS[0])

func _trophy_slot_runner_up() -> PanelContainer:
	var label := _make_base_label("2", px(18), SILVER)
	label.add_theme_font_override("font", _bold())
	return _trophy_slot(CARD_INNER, SILVER, label, TROPHY_LABELS[1])

func _trophy_slot_cap() -> PanelContainer:
	var content: Control
	var cap := CommunityRepository.resolve_cap(_crew)
	var texture: Texture2D = null
	if cap != null:
		texture = cap.side_texture if cap.side_texture != null else cap.center_texture
	if texture != null:
		var art := TextureRect.new()
		art.texture = texture
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		art.custom_minimum_size = Vector2(px(34), px(22))
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		content = art
	else:
		var icon := Icon.new()
		icon.setup(&"trophy", GOLD, px(24))
		content = icon
	return _trophy_slot(CARD_INNER, GOLD, content, TROPHY_LABELS[2])

func _trophy_slot_next() -> Control:
	var slot := DashedSlot.new()
	slot.custom_minimum_size = Vector2(0.0, px(64))
	slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(center)
	var label := _make_base_label("next?", SIZE_SMALL - 8, Color(CREAM.r, CREAM.g, CREAM.b, 0.7))
	label.add_theme_font_override("font", _bold())
	center.add_child(label)
	return slot

# ---------------------------------------------------------------------------
# Top carriers (weekly crew players, top 3 + you)
# ---------------------------------------------------------------------------

func _build_carriers(page: VBoxContainer) -> void:
	var card := sticker_card(page, 10)
	var header := _plain_label("TOP CARRIERS · THIS WEEK", SIZE_SMALL, Color(CREAM.r, CREAM.g, CREAM.b, 0.75), true)
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	card.add_child(header)
	_carriers_box = VBoxContainer.new()
	_carriers_box.add_theme_constant_override("separation", 6)
	card.add_child(_carriers_box)
	_refresh_carriers()

func _refresh_carriers() -> void:
	if _carriers_box == null:
		return
	for child in _carriers_box.get_children():
		_carriers_box.remove_child(child)
		child.queue_free()
	if not _has_crew:
		_carriers_box.add_child(make_sub("Carriers appear once you represent a crew.", SIZE_SMALL - 2))
		return
	var players := Standings.crew_players(save_manager, _crew.id, &"weekly")
	var rows: Array = []
	var me: Dictionary = {}
	for row in players:
		if bool(row.get("you", false)):
			if me.is_empty():
				me = row
		elif rows.size() < 3:
			rows.append(row)
	var rank := 0
	for row in rows:
		rank += 1
		_carriers_box.add_child(_carrier_row(rank, row, false))
	if not me.is_empty():
		_carriers_box.add_child(_carrier_row(int(me.get("rank", rank + 1)), me, true))
	if rows.is_empty() and me.is_empty():
		_carriers_box.add_child(make_sub("No carriers yet this week — play a run to appear here.", SIZE_SMALL - 2))

func _carrier_row(rank: int, row: Dictionary, mine: bool) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", int(px(10)))
	panel.add_child(line)

	var rank_label := _plain_label(str(maxi(rank, 1)), SIZE_SMALL + 2, GOLD if rank == 1 else (YOURS if mine else CREAM), true)
	rank_label.custom_minimum_size.x = px(24)
	rank_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	line.add_child(rank_label)

	var name_text := "You" if mine else _short_name(row)
	var name_label := _plain_label(name_text, SIZE_SMALL, YOURS if mine else CREAM, true)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(name_label)

	if rank == 1 and not mine:
		var mvp := chip("MVP", GOLD, &"", SIZE_SMALL - 8)
		mvp.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		line.add_child(mvp)

	var score_label := _plain_label(fmt(int(row.get("score", 0))), SIZE_SMALL, CREAM, true)
	score_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.add_child(score_label)
	return panel

## Short wallet address or name (mockups use "7xKp…3fQa").
func _short_name(row: Dictionary) -> String:
	var name := String(row.get("name", "")).strip_edges()
	var uid := String(row.get("uid", "")).strip_edges()
	if name.is_empty() or name == uid:
		return _short_address(uid if not uid.is_empty() else name)
	return name

func _short_address(value: String) -> String:
	if value.length() <= 8:
		return value if not value.is_empty() else "—"
	return "%s…%s" % [value.left(4), value.right(4)]

# ---------------------------------------------------------------------------
# Invite
# ---------------------------------------------------------------------------

func _build_invite(page: VBoxContainer) -> void:
	if _crew == null:
		return
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", _dashed_style(CARD, 22))
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	panel.add_child(column)

	var header := _plain_label("RECRUIT", SIZE_SMALL, Color(CREAM.r, CREAM.g, CREAM.b, 0.75), true)
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	column.add_child(header)
	column.add_child(make_sub(
		"Every new member makes the crew stronger. Share %s's invite link." % _crew_name(),
		SIZE_SMALL - 2))
	column.add_child(light_button("INVITE TO %s" % _crew_name().to_upper(), _on_invite, SIZE_SMALL, px(48)))
	page.add_child(panel)

func _on_invite() -> void:
	InviteService.share_crew(_crew)

func _footer_note() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = INK
	style.set_corner_radius_all(int(px(14)))
	style.content_margin_left = px(12)
	style.content_margin_right = px(12)
	style.content_margin_top = px(10)
	style.content_margin_bottom = px(10)
	panel.add_theme_stylebox_override("panel", style)
	var label := make_sub(
		"Quest points go straight into your crew's score — they count on the Board just like runs. Cap shards come later with the cap collection.",
		SIZE_SMALL - 2)
	label.add_theme_color_override("font_color", Color(CREAM.r, CREAM.g, CREAM.b, 0.85))
	panel.add_child(label)
	return panel

# ---------------------------------------------------------------------------
# Live refresh
# ---------------------------------------------------------------------------

func _start_refresh_timer() -> void:
	if is_instance_valid(_refresh_timer):
		return
	# No timed polling (Oct 10, E10): re-render only when Standings has new data.
	var seen := [Standings.version()]
	_refresh_timer = Timer.new()
	_refresh_timer.wait_time = 1.0
	_refresh_timer.timeout.connect(func() -> void:
		if Standings.version() != seen[0]:
			seen[0] = Standings.version()
			_refresh_live())
	add_child(_refresh_timer)
	_refresh_timer.start()

func _refresh_live() -> void:
	if not _has_crew or _crew == null:
		return
	if _week_bar != null and is_instance_valid(_week_bar):
		var goal := _crew_goal_target()
		var week := _crew_week_score()
		_week_bar.value = clampf(float(week) / float(maxi(goal, 1)), 0.0, 1.0)
		if _week_label != null and is_instance_valid(_week_label):
			var mine := save_manager.week_total(_crew.id) if save_manager != null else 0
			_week_label.text = "%s / %s · you added %s" % [fmt(week), fmt(goal), fmt(mine)]
	if _members_label != null and is_instance_valid(_members_label):
		_members_label.text = _members_text(Standings.members_count(_crew.id))
	_refresh_carriers()

func _rebuild() -> void:
	var pos := 0
	if _page_root != null and is_instance_valid(_page_root):
		pos = int(_page_root.scroll_vertical)
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_page_root = null
	_refresh_timer = null
	_week_bar = null
	_week_label = null
	_members_label = null
	_carriers_box = null
	setup({})
	if _page_root != null and is_instance_valid(_page_root):
		_page_root.scroll_vertical = pos
		call_deferred("_restore_scroll", pos)

func _restore_scroll(pos: int) -> void:
	if _page_root != null and is_instance_valid(_page_root):
		_page_root.scroll_vertical = pos

# ---------------------------------------------------------------------------
# Small shared pieces (composed from kit tokens; no §2 equivalent)
# ---------------------------------------------------------------------------

func _plain_label(text: String, size: int, color: Color, bold: bool) -> Label:
	var label := _make_base_label(text, size, color)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	if bold:
		label.add_theme_font_override("font", _bold())
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return label

func _row_style(fill: Color, border: Color) -> StyleBoxFlat:
	var style := _ledge(fill, int(px(3)), int(px(16)), 0, border)
	style.content_margin_left = px(12)
	style.content_margin_right = px(12)
	style.content_margin_top = px(10)
	style.content_margin_bottom = px(12)
	return style

func _dashed_style(fill: Color, radius: int = 16) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.set_corner_radius_all(int(px(radius)))
	style.set_border_width_all(int(px(3)))
	style.border_color = LILAC
	style.content_margin_left = px(14)
	style.content_margin_right = px(14)
	style.content_margin_top = px(14)
	style.content_margin_bottom = px(18)
	return style

func _back_button(action: Callable) -> Button:
	var button := Button.new()
	button.focus_mode = Control.FOCUS_NONE
	var size := px(46)
	button.custom_minimum_size = Vector2(size, size)
	button.add_theme_stylebox_override("normal", _icon_style(CARD, false))
	button.add_theme_stylebox_override("hover", _icon_style(CARD.lightened(0.06), false))
	button.add_theme_stylebox_override("pressed", _icon_style(CARD.darkened(0.06), true))
	button.add_theme_stylebox_override("focus", _icon_style(CARD, false))
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(center)
	var chevron := BackChevron.new()
	chevron.custom_minimum_size = Vector2(px(18), px(18))
	center.add_child(chevron)
	bind_press(button, action)
	return button

## Square CARD style for the back button (INK border + solid ledge).
func _icon_style(fill: Color, pressed: bool) -> StyleBoxFlat:
	var style := _ledge(fill, int(px(3)), int(px(14)), 0 if pressed else int(px(3)))
	style.content_margin_left = 0.0
	style.content_margin_right = 0.0
	style.content_margin_top = int(px(3)) if pressed else 0.0
	style.content_margin_bottom = 0.0
	return style

# ---------------------------------------------------------------------------
# Back chevron (kit `chevron` points right)
# ---------------------------------------------------------------------------

class BackChevron extends Control:
	const CREAM_INK := Color("fff4dc")

	func _draw() -> void:
		var w := size.x
		var h := size.y
		draw_polyline(PackedVector2Array([
			Vector2(w * 0.62, h * 0.24),
			Vector2(w * 0.36, h * 0.50),
			Vector2(w * 0.62, h * 0.76),
		]), CREAM_INK, w * 0.12, true)


## The empty trophy slot: INK rounded fill with a dashed LILAC outline.
class DashedSlot extends Control:
	const INK := Color("1d1033")
	const LILAC := Color("b9a8d6")
	const BORDER := 5.0

	func _draw() -> void:
		var w := size.x
		var h := size.y
		var bg := StyleBoxFlat.new()
		bg.bg_color = INK
		bg.set_corner_radius_all(int(BORDER * 5.0))
		draw_style_box(bg, Rect2(Vector2.ZERO, Vector2(w, h)))
		var dash := BORDER * 3.0
		var gap := BORDER * 2.0
		var half := BORDER * 0.5
		var x := 0.0
		while x < w:
			var x2 := minf(x + dash, w)
			draw_line(Vector2(x, half), Vector2(x2, half), LILAC, BORDER, true)
			draw_line(Vector2(x, h - half), Vector2(x2, h - half), LILAC, BORDER, true)
			x += dash + gap
		var y := 0.0
		while y < h:
			var y2 := minf(y + dash, h)
			draw_line(Vector2(half, y), Vector2(half, y2), LILAC, BORDER, true)
			draw_line(Vector2(w - half, y), Vector2(w - half, y2), LILAC, BORDER, true)
			y += dash + gap
