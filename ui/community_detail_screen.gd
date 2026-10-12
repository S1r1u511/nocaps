extends UiScreen

## Community page — v2 "arcade sticker" (docs/UI_V2_BRIEF.md §5–6, docs/mockups/community.html).
## Back + "#n THIS WEEK" chip, mascot hero with the crew's cap on a CREAM sticker,
## name/description/chips/socials, the main CTA + INVITE, then collapsible To join /
## token / rewards / top players sections. Community standings come from `Standings`;
## weekly rewards and the "You" row come from local progress.

## TODO(ui-v2 kit): pieces with no §2 component are composed locally from kit
## tokens: `icon_button` (back), pill color variants, `row_panel`, `status_dot`,
## `cap_sticker`, and the demo sparkline. Fold them into `ui/ui_screen.gd` later.

class ChevronLeft:
	extends Control
	const CREAM_INK := Color("fff4dc")

	func _draw() -> void:
		var w := size.x
		var h := size.y
		draw_polyline(PackedVector2Array([
			Vector2(w * 0.62, h * 0.24),
			Vector2(w * 0.36, h * 0.50),
			Vector2(w * 0.62, h * 0.76),
		]), CREAM_INK, w * 0.12, true)


var _community: CommunityDefinition
var _representing: bool = false
var _followed: bool = false
var _holds: bool = false
var _players_box: VBoxContainer
var _players_timer: Timer
var _seen_version: int = -1

func setup(payload: Dictionary) -> void:
	var community_id := StringName(payload.get("community_id", ""))
	_community = CommunityRepository.by_id(CommunityRepository.load_roster(), community_id)
	if _community == null:
		_build_not_found()
		return
	_representing = save_manager != null and save_manager.selected_community_id == _community.id
	if not _wallet_address().is_empty():
		_holds = true

	var page := build_page()
	page.add_child(_top_bar())
	page.add_child(_hero())
	page.add_child(_cta_block())
	if _representing:
		page.add_child(_ready_card())
	else:
		_build_join(page)
	if not _community.token_ca.is_empty():
		_build_token(page)
	_build_rewards(page)
	_build_players(page)
	_start_players_timer()

func _build_not_found() -> void:
	var page := build_page()
	page.add_child(make_kicker("COMMUNITY", &"crew"))
	page.add_child(make_h1("Community not found"))
	page.add_child(secondary_button("BACK", func() -> void: navigate.emit(&"community_select", {})))

# ---------------------------------------------------------------------------
# Top bar + hero
# ---------------------------------------------------------------------------

func _top_bar() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 0)
	row.add_child(_icon_button(&"chevron", func() -> void: navigate.emit(&"community_select", {}), px(46), px(18)))
	row.add_child(_expander())
	row.add_child(_pill("#%d THIS WEEK" % _week_rank(), CARD, CREAM, px(14), 14, 4, 3, 3))
	return row

func _hero() -> VBoxContainer:
	var column := VBoxContainer.new()
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 0)
	column.add_child(_hero_stage())
	column.add_child(make_spacer(px(6)))
	var name_label := outlined_title(_community.display_name.to_upper(), CREAM, SIZE_DISPLAY)
	column.add_child(name_label)
	if not _community.short_description.is_empty():
		column.add_child(make_spacer(px(8)))
		var description := _make_base_label(_community.short_description, px(15), Color(CREAM.r, CREAM.g, CREAM.b, 0.9))
		description.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		column.add_child(description)
	column.add_child(make_spacer(px(12)))
	column.add_child(_chips())
	var socials := _socials()
	if socials != null:
		column.add_child(make_spacer(px(12)))
		column.add_child(socials)
	return column

func _hero_stage() -> Control:
	var stage := Control.new()
	stage.custom_minimum_size = Vector2(px(230), px(210))
	stage.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var preview := MascotPreview.new()
	preview.setup(_community, px(200))
	preview.anchor_left = 0.5
	preview.anchor_right = 0.5
	preview.anchor_top = 1.0
	preview.anchor_bottom = 1.0
	preview.offset_left = -px(100)
	preview.offset_right = px(100)
	preview.offset_top = -px(200)
	preview.offset_bottom = 0.0
	stage.add_child(preview)

	var cap: CapDefinition = CommunityRepository.resolve_cap(_community)
	var texture: Texture2D = null
	if cap != null:
		texture = cap.center_texture if cap.center_texture != null else cap.side_texture
	if texture != null:
		var sticker := PanelContainer.new()
		sticker.mouse_filter = Control.MOUSE_FILTER_IGNORE
		sticker.custom_minimum_size = Vector2(px(74), px(74))
		sticker.anchor_left = 1.0
		sticker.anchor_right = 1.0
		sticker.offset_left = -px(74) + px(18)
		sticker.offset_right = px(18)
		sticker.offset_top = px(6)
		sticker.offset_bottom = px(6) + px(74)
		sticker.pivot_offset = Vector2(px(74), px(74)) * 0.5
		sticker.rotation = deg_to_rad(8.0)
		sticker.add_theme_stylebox_override("panel", _panel_style(CREAM, 4, 999, 4, 0))
		var art := TextureRect.new()
		art.texture = texture
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		art.custom_minimum_size = Vector2(px(56), px(56))
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		sticker.add_child(art)
		stage.add_child(sticker)
	return stage

func _chips() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = "CrewChips"
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", int(px(8)))
	# Member counts need the backend; until the count is known the chip is hidden
	# rather than shown as an unfinished "— players".
	var members := Standings.members_count(_community.id)
	if members > 0:
		row.add_child(_pill("%s players" % fmt(members), CARD_INNER, CREAM, px(13)))
	row.add_child(_pill("%s pts this week" % fmt(_week_score()), CARD_INNER, CREAM, px(13)))
	return row

func _socials() -> HBoxContainer:
	var kinds: Array = []
	for kind in [&"x", &"telegram", &"website"]:
		if not _community.social_url(kind).is_empty():
			kinds.append(kind)
	if kinds.is_empty():
		return null
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", int(px(10)))
	for kind in kinds:
		row.add_child(social_button(kind, func() -> void:
			OS.shell_open(_community.social_url(kind))))
	return row

# ---------------------------------------------------------------------------
# CTA
# ---------------------------------------------------------------------------

func _cta_block() -> VBoxContainer:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", int(px(8)))
	var label := "PLAY" if _representing else "REP %s & PLAY" % _community.display_name.to_upper()
	var play := primary_button(label, _on_primary, px(70), px(26))
	play.name = "CrewPrimaryCta"
	column.add_child(play)
	var hint := "You're repping %s" % _community.display_name
	if not _representing:
		hint = "Points go to %s from your next run" % _community.display_name
	var hint_label := _make_base_label(hint, px(13), Color(CREAM.r, CREAM.g, CREAM.b, 0.8))
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(hint_label)
	var invite := secondary_button("INVITE TO %s" % _community.display_name.to_upper(), _on_invite, px(58), px(18))
	invite.name = "CrewInvite"
	column.add_child(invite)
	return column

func _on_invite() -> void:
	InviteService.share_crew(_community)

func _on_primary() -> void:
	if _community == null:
		return
	if not _representing and save_manager != null:
		save_manager.set_selected_community(_community.id)
		Toasts.show_message("You're repping %s" % _community.display_name)
		if ShellUI.instance != null:
			ShellUI.instance.refresh()
	navigate.emit(&"run", {})

# ---------------------------------------------------------------------------
# To join
# ---------------------------------------------------------------------------

func _ready_card() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", _panel_style(CARD, 4, 22, 5, 12))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", int(px(10)))
	panel.add_child(row)
	row.add_child(_status_dot(true, px(28)))
	var label := _make_base_label("You're in the %s crew" % _community.display_name, px(17), CREAM)
	label.add_theme_font_override("font", _bold())
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(label)
	return panel

func _build_join(page: VBoxContainer) -> void:
	var follow_url := _community.social_url(&"x")
	var has_follow := not follow_url.is_empty()
	var has_hold := not _community.token_symbol.is_empty() or not _community.token_ca.is_empty()
	var steps := (1 if has_follow else 0) + (1 if has_hold else 0)
	if steps == 0:
		# No prerequisites authored: render no section at all instead of an empty card.
		return
	var done := (1 if has_follow and _followed else 0) + (1 if has_hold and _holds else 0)
	var body := collapsible_section(page, "To join · %d/%d done" % [done, steps], &"lock", true)

	if has_follow:
		body.add_child(_join_row(
			_followed,
			"Follow @%s on X" % _handle() if not _handle().is_empty() else "Follow %s on X" % _community.display_name,
			"Opens X, then come back",
			"Done" if _followed else "Follow",
			_on_follow
		))
	if has_hold:
		var symbol := _community.token_symbol
		body.add_child(_join_row(
			_holds,
			"Hold any $%s" % symbol if not symbol.is_empty() else "Hold the crew token",
			"Checked from your wallet",
			"Verified" if _holds else "Connect",
			_on_hold
		))

func _join_row(done: bool, title: String, sub: String, action_text: String, action: Callable) -> PanelContainer:
	var panel := _row_box()
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", int(px(12)))
	panel.add_child(row)
	row.add_child(_status_dot(done, px(30)))
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	column.add_theme_constant_override("separation", 2)
	row.add_child(column)
	column.add_child(_plain_label(title, px(15), CREAM, true))
	column.add_child(_plain_label(sub, px(12), Color(CREAM.r, CREAM.g, CREAM.b, 0.75), false))
	row.add_child(light_button(action_text, action, px(14), px(38)))
	return panel

func _on_follow() -> void:
	var url := _community.social_url(&"x")
	if not url.is_empty():
		OS.shell_open(url)
	_followed = true
	_rebuild()

func _on_hold() -> void:
	if _wallet_address().is_empty():
		var wallet := get_node_or_null("/root/WalletService")
		if wallet != null and wallet.has_method("is_available") \
				and bool(wallet.call("is_available")) and wallet.has_method("connect_wallet"):
			wallet.call("connect_wallet")
			return
		Toasts.show_message("Wallet isn't available on this build")
		return
	_holds = true
	_rebuild()

func _handle() -> String:
	return _community.x_handle.strip_edges().trim_prefix("@")

# ---------------------------------------------------------------------------
# Token
# ---------------------------------------------------------------------------

func _build_token(page: VBoxContainer) -> void:
	var symbol := _community.token_symbol
	var title := "$%s token" % symbol if not symbol.is_empty() else "Token"
	var body := collapsible_section(page, title, &"coin", true)

	var ca_row := _row_box()
	var ca_box := HBoxContainer.new()
	ca_box.add_theme_constant_override("separation", int(px(12)))
	ca_row.add_child(ca_box)
	var ca_column := VBoxContainer.new()
	ca_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ca_column.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ca_box.add_child(ca_column)
	ca_column.add_child(_plain_label("Contract address", px(12), Color(CREAM.r, CREAM.g, CREAM.b, 0.75), false))
	ca_column.add_child(_plain_label(_short_ca(), px(15), CREAM, true))
	ca_box.add_child(light_button("Copy", _on_copy, px(14), px(38)))
	body.add_child(ca_row)

func _on_copy() -> void:
	DisplayServer.clipboard_set(_community.token_ca)
	Toasts.show_message("Copied")

func _short_ca() -> String:
	var ca := _community.token_ca
	if ca.length() <= 9:
		return ca
	return "%s…%s" % [ca.left(4), ca.right(4)]

# ---------------------------------------------------------------------------
# This week's rewards
# ---------------------------------------------------------------------------

func _build_rewards(page: VBoxContainer) -> void:
	var body := collapsible_section(page, "Your weekly tiers", &"trophy", true)
	var week_total := save_manager.week_total(_community.id) if save_manager != null else 0
	var week_note := _make_base_label("Your points this week: %s · resets Monday · rewards aren't live yet" % fmt(week_total), px(13), Color(CREAM.r, CREAM.g, CREAM.b, 0.8))
	week_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	week_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(week_note)
	var tiers := _community.weekly_tiers
	var next_shown := false
	for i in range(tiers.size()):
		var need := tiers[i]
		var reached := week_total >= need
		body.add_child(_tier_row(i, need, reached, week_total, not reached and not next_shown))
		if not reached and not next_shown:
			next_shown = true

func _tier_row(index: int, need: int, reached: bool, week_total: int, show_bar: bool) -> PanelContainer:
	var fills := [YOURS, GOLD, SILVER]
	var panel := _row_box()
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", int(px(12)))
	panel.add_child(row)

	var tile := PanelContainer.new()
	tile.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tile.custom_minimum_size = Vector2(px(44), px(44))
	tile.add_theme_stylebox_override("panel", _panel_style(fills[mini(index, fills.size() - 1)], 3, 12, 0, 0))
	var tile_label := _make_base_label("T%d" % (index + 1), px(18), INK)
	tile_label.add_theme_font_override("font", _bold())
	tile.add_child(tile_label)
	tile.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(tile)

	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	column.add_theme_constant_override("separation", 2)
	row.add_child(column)
	column.add_child(_plain_label("%s pts" % fmt(need), px(15), CREAM, true))
	var reward_text := _community.campaign_value("reward_text")
	if not reward_text.is_empty():
		column.add_child(_plain_label(reward_text, px(12), Color(CREAM.r, CREAM.g, CREAM.b, 0.8), false))
	if show_bar:
		var progress := Scoring.tier_progress(week_total, _community.weekly_tiers)
		column.add_child(race_bar(progress, GOLD, px(8)))

	if reached:
		var done := _plain_label("DONE", px(13), YOURS, true)
		done.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(done)
	else:
		var to_go := _plain_label("%s to go" % fmt(maxi(need - week_total, 0)), px(13), CREAM, true)
		to_go.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(to_go)
	return panel

# ---------------------------------------------------------------------------
# Top players
# ---------------------------------------------------------------------------

func _build_players(page: VBoxContainer) -> void:
	var body := collapsible_section(page, "Top players · this week", &"board", true)
	_players_box = VBoxContainer.new()
	_players_box.add_theme_constant_override("separation", int(px(6)))
	body.add_child(_players_box)
	_refresh_players()

## Weekly crew leaderboard: top 3 real players + the local player's row (YOURS
## border) with an MVP tag on #1. Mirrors the Quests "Top carriers" contract and
## re-renders when `Standings.crew_players` gets new data (no timed polling, Oct 10).
func _refresh_players() -> void:
	if _players_box == null or not is_instance_valid(_players_box):
		return
	for child in _players_box.get_children():
		_players_box.remove_child(child)
		child.queue_free()
	if _community == null:
		return
	var players := Standings.crew_players(save_manager, _community.id, &"weekly")
	var rows: Array = []
	var me: Dictionary = {}
	for row in players:
		if bool(row.get("local", false)) and int(row.get("score", 0)) <= 0:
			continue
		if bool(row.get("you", false)):
			if me.is_empty():
				me = row
		elif rows.size() < 3:
			rows.append(row)
	var rank := 0
	for row in rows:
		rank += 1
		_players_box.add_child(_player_row(int(row.get("rank", rank)), row, false))
	if not me.is_empty():
		_players_box.add_child(_player_row(int(me.get("rank", rank + 1)), me, true))
	if rows.is_empty() and me.is_empty():
		_players_box.add_child(make_sub("No players yet this week — play a run to appear here.", SIZE_SMALL - 2))
	elif Standings.connection_state() != "live":
		# Only local rows are known offline; say so instead of pretending the list
		# is complete.
		_players_box.add_child(make_sub("Connect to see the full crew board.", SIZE_SMALL - 4))

func _player_row(rank: int, row: Dictionary, mine: bool) -> PanelContainer:
	var panel := _row_box(YOURS if mine else INK)
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", int(px(12)))
	panel.add_child(line)

	var rank_label := _plain_label(str(maxi(rank, 1)), px(16), GOLD if rank == 1 else (YOURS if mine else CREAM), true)
	rank_label.custom_minimum_size.x = px(24)
	rank_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	line.add_child(rank_label)

	var name_label := _plain_label("You" if mine else _short_name(row), px(15), YOURS if mine else CREAM, true)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.clip_text = true
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	line.add_child(name_label)

	if rank == 1 and not mine:
		var mvp := _pill("MVP", GOLD, INK, px(11), 8, 1, 3, 0)
		mvp.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		line.add_child(mvp)

	var score_label := _plain_label(fmt(int(row.get("score", 0))), px(15), CREAM, true)
	score_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.add_child(score_label)
	return panel

## Short wallet address or display name (mockups use "7xKp…3fQa").
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

func _start_players_timer() -> void:
	if is_instance_valid(_players_timer):
		return
	_seen_version = Standings.version()
	_players_timer = Timer.new()
	_players_timer.wait_time = 1.0
	_players_timer.timeout.connect(func() -> void:
		if Standings.version() != _seen_version:
			_seen_version = Standings.version()
			_refresh_players())
	add_child(_players_timer)
	_players_timer.start()

# ---------------------------------------------------------------------------
# Data + shared pieces
# ---------------------------------------------------------------------------

func _week_rank() -> int:
	for row in Standings.communities_week(save_manager):
		if row["id"] == _community.id:
			return int(row["rank"])
	return Standings.communities_week(save_manager).size()

func _week_score() -> int:
	for row in Standings.communities_week(save_manager):
		if row["id"] == _community.id:
			return int(row["score"])
	return 0

func _wallet_address() -> String:
	var wallet := get_node_or_null("/root/WalletService")
	if wallet == null:
		return ""
	for key in ["wallet_address", "address"]:
		var value: Variant = wallet.get(key)
		if value is String and not String(value).is_empty():
			return String(value)
	return ""

func _plain_label(text: String, size: int, color: Color, bold: bool) -> Label:
	var label := _make_base_label(text, size, color)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	if bold:
		label.add_theme_font_override("font", _bold())
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return label

func _status_dot(done: bool, size: float) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.custom_minimum_size = Vector2(size, size)
	var style := StyleBoxFlat.new()
	style.bg_color = YOURS if done else CARD_INNER
	style.set_corner_radius_all(999)
	style.set_border_width_all(int(px(3)))
	style.border_color = INK
	panel.add_theme_stylebox_override("panel", style)
	panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if done:
		var icon := Icon.new()
		icon.setup(&"check", INK, size * 0.45)
		panel.add_child(icon)
	return panel

## Sticker panel with an arbitrary fill/ledge; `pad_bottom` can differ from `pad`.
func _panel_style(fill: Color, border: int, radius: int, ledge: int, pad: int, pad_bottom: int = -1, border_color: Color = INK) -> StyleBoxFlat:
	var style := _ledge(fill, int(px(border)), int(px(radius)), int(px(ledge)), border_color)
	style.content_margin_left = px(pad)
	style.content_margin_right = px(pad)
	style.content_margin_top = px(pad)
	style.content_margin_bottom = px(pad_bottom if pad_bottom >= 0 else pad)
	return style

func _row_box(border_color: Color = INK) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", _panel_style(CARD_INNER, 3, 16, 0, 11, -1, border_color))
	return panel

## Pill tag matching the mockups (INK text by default).
func _pill(text: String, fill: Color, text_color: Color = INK, font_size: int = -1, pad_h: int = 12, pad_v: int = 3, border: int = 3, ledge: int = 0) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := _ledge(fill, int(px(border)), 999, int(px(ledge)))
	style.content_margin_left = px(pad_h)
	style.content_margin_right = px(pad_h)
	style.content_margin_top = px(pad_v)
	style.content_margin_bottom = px(pad_v)
	panel.add_theme_stylebox_override("panel", style)
	panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var label := _make_base_label(text, font_size if font_size > 0 else int(px(11)), text_color)
	label.add_theme_font_override("font", _bold())
	panel.add_child(label)
	return panel

## Square CARD button with a code-drawn glyph (back chevron).
func _icon_button(kind: StringName, action: Callable, size: float, icon_size: float) -> Button:
	var button := Button.new()
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(size, size)
	button.add_theme_stylebox_override("normal", _panel_style(CARD, 3, 14, 3, 0))
	button.add_theme_stylebox_override("hover", _panel_style(CARD.lightened(0.06), 3, 14, 3, 0))
	button.add_theme_stylebox_override("pressed", _panel_style(CARD.darkened(0.06), 3, 14, 0, 0))
	button.add_theme_stylebox_override("focus", _panel_style(CARD, 3, 14, 3, 0))
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(center)
	var glyph: Control = null
	if kind == &"chevron":
		var back := ChevronLeft.new()
		back.custom_minimum_size = Vector2(icon_size, icon_size)
		glyph = back
	else:
		var icon := Icon.new()
		icon.setup(kind, CREAM, icon_size)
		glyph = icon
	center.add_child(glyph)
	bind_press(button, action)
	return button

func _rebuild() -> void:
	var id := _community.id if _community != null else &""
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_page_root = null
	_players_box = null
	_players_timer = null
	setup({"community_id": id})
