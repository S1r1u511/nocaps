extends UiScreen

## Home — v2 "arcade sticker" (docs/UI_V2_BRIEF.md §5–6, docs/mockups/home.html).
## Tall phones (720×1560) get the full mockup proportions; shorter viewports
## shrink only the hero and the vertical gaps so everything stays above the tab
## bar without scrolling. Standings come from `Standings` and refresh while the
## screen is visible.

const BATTLE_REFRESH_SECONDS := 20
const BATTLE_DISCOVERY_SECONDS := 60

# Full-scale layout values (mockup px × 1.85).
const HERO_MAX := 462.0
## Shrink floor allows a taller banner/chip row to fit on short phones without
## overlap; the final clamp keeps the hero at the same floor.
const HERO_MIN := 130.0
const HERO_FLOOR := 130.0
const TILE_SIZE := 115.0
const TILE_GAP := 22.0
const CTA_HEIGHT := 133.0
const CTA_FONT := 59
const RACE_AVATAR := 60.0
const RACE_BAR := 30.0
const WORDMARK_SIZE := 56
const PILL_FONT := 26
const TAB_CLEARANCE := 137.0
const SIDE_MARGIN := 30
const CTA_INSET := 10
const TOP_PAD := 24
const BOTTOM_PAD := 8

## Gaps between sections (mockup scaled) and their compact minimums.
const GAPS_FULL := [26.0, 15.0, 4.0, 15.0, 30.0, 33.0, 37.0]
const GAPS_MIN := [8.0, 5.0, 0.0, 5.0, 8.0, 10.0, 12.0]

var _focus_index: int = -1
var _standings: Array = []
var _communities: Array[CommunityDefinition] = []
var _chip_host: VBoxContainer
var _race_rows: VBoxContainer
var _race_dot: Icon
var _refresh_timer: Timer
var _seen_version: int = -1
var _watch_ticks: int = 0
## Battle/Clash card: title label, a 1 s clock and a note.
var _race_title: Label
var _race_note: Label
## "resets in hh:mm" beside the title while today's clash owns the card.
var _race_reset: Label
var _clock_timer: Timer
var _spacers: Array[Control] = []
var _hero_holder: Control
var _cta_wrap: Control
var _race_card: Control
var _page_column: VBoxContainer
## Reserved bottom slot holding the QUESTS entry, above the tab bar.
var _bottom_slot: VBoxContainer
var _quests_row: Control
## Last hero height built, so re-fitting does not rebuild the hero unnecessarily.
var _hero_size: float = -1.0
## True while a deferred re-measure is queued (chip-row layout settle, P0-1).
var _refit_queued: bool = false
## Lite roster backing this screen; art is attached on the first frame after the
## first paint (see `_hydrate_art_deferred`) so no community texture blocks boot.
var _roster: CommunityRoster
var _art_hydrated: bool = false
## Guards the one-time boot timing line across Home rebuilds.
var _boot_frame_logged: bool = false

func setup(_payload: Dictionary) -> void:
	BattleService.refresh_if_stale(20000)
	BattleService.refresh_boards()
	_standings = Standings.communities_today(save_manager)
	_roster = CommunityRepository.load_roster_lite()
	_communities = CommunityRepository.enabled_sorted(_roster)
	_spacers.clear()

	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.scroll_deadzone = DRAG_DEADZONE
	add_child(scroll)
	_page_root = scroll

	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var safe_top := maxf(ShellUI.safe_top, 0.0)
	var safe_bottom := maxf(ShellUI.safe_bottom, 0.0)
	margin.add_theme_constant_override("margin_left", SIDE_MARGIN)
	margin.add_theme_constant_override("margin_right", SIDE_MARGIN)
	margin.add_theme_constant_override("margin_top", int(TOP_PAD + safe_top))
	# Reserve the sticky tab bar below the content: the page still fits without
	# scrolling on the reference sizes, but if a very short viewport runs out of
	# shrink budget the bottom slot can be scrolled clear of the bar (P0-1).
	margin.add_theme_constant_override("margin_bottom", int(TAB_CLEARANCE + BOTTOM_PAD + safe_bottom))
	scroll.add_child(margin)

	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 0)
	margin.add_child(column)

	if _communities.is_empty():
		_build_empty(column)
		return

	var selected_id: StringName = save_manager.selected_community_id if save_manager != null else &""
	if _focus_index < 0 or _focus_index >= _communities.size():
		var focus_id := StringName(_payload.get("focus_id", ""))
		_focus_index = _index_of(_communities, focus_id) if focus_id != &"" else -1
		if _focus_index < 0:
			_focus_index = _index_of(_communities, selected_id)
		if _focus_index < 0:
			_focus_index = _index_of(_communities, _leader_id())
		_focus_index = clampi(_focus_index, 0, _communities.size() - 1)
	var focused: CommunityDefinition = _communities[_focus_index]
	var representing := selected_id != &"" and focused.id == selected_id

	column.add_child(_build_header())
	_spacers.append(_make_gap(column))
	_chip_host = VBoxContainer.new()
	_chip_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_chip_host.add_theme_constant_override("separation", 0)
	column.add_child(_chip_host)
	_refresh_chip(focused)
	_spacers.append(_make_gap(column))
	_hero_holder = Control.new()
	_hero_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(_hero_holder)
	_spacers.append(_make_gap(column))
	column.add_child(_build_name(focused))
	_spacers.append(_make_gap(column))
	column.add_child(_build_subline(focused, selected_id))
	_spacers.append(_make_gap(column))
	column.add_child(_build_strip(focused))
	_spacers.append(_make_gap(column))
	column.add_child(_build_cta(focused, selected_id, representing))
	_spacers.append(_make_gap(column))
	_build_race_card(column)
	# Reserved bottom slot: the QUESTS entry, in the layout so it can never float
	# over the hero, race card, PLAY or tab bar.
	_bottom_slot = VBoxContainer.new()
	_bottom_slot.name = "HomeBottomSlot"
	_bottom_slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_bottom_slot.add_theme_constant_override("separation", 0)
	column.add_child(_bottom_slot)
	_build_quests_entry(_bottom_slot)
	_quests_row = _bottom_slot.get_child(_bottom_slot.get_child_count() - 1)
	_page_column = column

	_fit_hero_and_gaps(column)
	_start_refresh_timer()
	_queue_art_hydration()
	_notify_first_frame()

## Defers community-art loading off the first frame; the first paint only needs
## names, colors and layout, not the mascot/cap textures.
func _queue_art_hydration() -> void:
	if _art_hydrated or not is_inside_tree():
		return
	call_deferred("_hydrate_art_deferred")

## Loads every shown community's art on the first frame after the first paint,
## then rebuilds so the tiles/hero/race show the real art.
func _hydrate_art_deferred() -> void:
	if _art_hydrated:
		return
	_art_hydrated = true
	if _communities.is_empty() or not is_inside_tree():
		return
	var loaded := false
	for community in _communities:
		if CommunityRepository.ensure_art(community):
			loaded = true
	if loaded:
		_rebuild()

## One line for on-device cold-start measurement.
func _notify_first_frame() -> void:
	if _boot_frame_logged or not is_inside_tree():
		return
	_boot_frame_logged = true
	# process_frame fires on the frame after Home's first paint is submitted.
	get_tree().process_frame.connect(_log_first_frame, CONNECT_ONE_SHOT)

func _log_first_frame() -> void:
	print("NOCAPS boot: first_frame_ms=%d" % Time.get_ticks_msec())

func _build_empty(column: VBoxContainer) -> void:
	column.add_child(make_spacer(40))
	var card := sticker_card(column, 12)
	var title := outlined_title("NOCAPS", GOLD, 64)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	card.add_child(title)
	var note := _make_base_label("No crews yet.", SIZE_BODY, CREAM)
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	card.add_child(note)

# ---------------------------------------------------------------------------
# Sections
# ---------------------------------------------------------------------------

## Wordmark top-left, guest pill top-right.
func _build_header() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 0)
	var brand := HBoxContainer.new()
	brand.add_theme_constant_override("separation", 0)
	brand.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	brand.add_child(_wordmark("NO", CREAM))
	brand.add_child(_wordmark("CAPS", GOLD))
	row.add_child(brand)
	row.add_child(_expander())
	row.add_child(_guest_pill())
	return row

func _wordmark(text: String, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", _bold())
	label.add_theme_font_size_override("font_size", WORDMARK_SIZE)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", INK)
	label.add_theme_constant_override("outline_size", 11)
	label.add_theme_color_override("font_shadow_color", INK)
	label.add_theme_constant_override("shadow_offset_x", 0)
	label.add_theme_constant_override("shadow_offset_y", 7)
	label.add_theme_constant_override("shadow_outline_size", 11)
	return label

func _guest_pill() -> PanelContainer:
	var pill := PanelContainer.new()
	pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = CARD
	style.set_corner_radius_all(999)
	style.set_border_width_all(6)
	style.border_color = INK
	style.border_width_bottom = 12
	style.content_margin_left = 15.0
	style.content_margin_right = 22.0
	style.content_margin_top = 8.0
	style.content_margin_bottom = 14.0
	pill.add_theme_stylebox_override("panel", style)
	pill.size_flags_vertical = Control.SIZE_SHRINK_CENTER

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	pill.add_child(row)
	var cap: CapDefinition = CommunityRepository.resolve_cap(null)
	if cap != null and cap.side_texture != null:
		var icon := TextureRect.new()
		icon.texture = cap.side_texture
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.custom_minimum_size = Vector2(px(26), px(18))
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(icon)
	var name_label := _make_base_label(_guest_name(), PILL_FONT, CREAM)
	name_label.add_theme_font_override("font", _bold())
	row.add_child(name_label)
	return pill

func _build_name(focused: CommunityDefinition) -> Label:
	var label := outlined_title(focused.display_name.to_upper(), CREAM, SIZE_DISPLAY)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return label

func _build_subline(focused: CommunityDefinition, selected_id: StringName) -> Label:
	var text := "Pick a crew. Every landing adds to their score."
	if selected_id != &"":
		var represented := CommunityRepository.by_id(_roster, selected_id)
		if represented == null:
			represented = focused
		var streak := save_manager.streak_days if save_manager != null else 0
		text = "You're repping %s" % represented.display_name
		if streak > 0:
			text += " · %d-day streak" % streak
	var label := _make_base_label(text, SIZE_BODY, Color(CREAM.r, CREAM.g, CREAM.b, 0.9))
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	return label

func _build_strip(focused: CommunityDefinition) -> HBoxContainer:
	var strip := HBoxContainer.new()
	strip.name = "HomeCrewStrip"
	strip.alignment = BoxContainer.ALIGNMENT_CENTER
	strip.add_theme_constant_override("separation", int(TILE_GAP))
	for index in _strip_indices():
		var community: CommunityDefinition = _communities[index]
		var tile := avatar_tile(community, TILE_SIZE, community == focused)
		_make_tile_tappable(tile, index)
		strip.add_child(tile)
	return strip

## Crew strip follows today's ranking like the LIVE RACE card
## (`Standings.top3_plus_mine`): no crew selected -> the top 3; otherwise the top 3
## plus the player's crew, or the #4 crew when the player's crew is already in the
## top 3. Offline/no data falls back to the roster's current order.
func _strip_indices() -> Array:
	var my_id: StringName = save_manager.selected_community_id if save_manager != null else &""
	var indices: Array = []
	for row in Standings.top3_plus_mine(save_manager, my_id):
		var index := _index_of(_communities, StringName(row.get("id", "")))
		if index >= 0 and not indices.has(index):
			indices.append(index)
	if my_id != &"" and indices.size() == 3:
		var fourth := _next_ranked_index(indices)
		if fourth >= 0:
			indices.append(fourth)
	if indices.is_empty():
		return _strip_order()
	return indices

## Highest-ranked enabled crew not already in `excluded` (the #4 slot when the
## player's crew is inside the top 3).
func _next_ranked_index(excluded: Array) -> int:
	for row in _standings:
		var index := _index_of(_communities, StringName(row.get("id", "")))
		if index >= 0 and not excluded.has(index):
			return index
	return -1

## Fallback order when there is no usable ranking: today's rank first, then the
## roster position for crews missing from the standings.
func _strip_order() -> Array:
	var order: Array = []
	for i in range(_communities.size()):
		order.append(i)
	order.sort_custom(func(a: int, b: int) -> bool:
		return _rank_of(_communities[a]) < _rank_of(_communities[b]))
	return order

func _build_cta(focused: CommunityDefinition, selected_id: StringName, representing: bool) -> MarginContainer:
	var wrap := MarginContainer.new()
	wrap.add_theme_constant_override("margin_left", CTA_INSET)
	wrap.add_theme_constant_override("margin_right", CTA_INSET)
	var text := "PLAY"
	if selected_id == &"":
		text = "REP %s & PLAY" % focused.display_name.to_upper()
	elif not representing:
		text = "SWITCH TO %s" % focused.display_name.to_upper()
	var button := primary_button(text, _on_primary, CTA_HEIGHT, CTA_FONT)
	button.name = "HomePrimaryCta"
	wrap.add_child(button)
	if representing:
		pulse(button)
	_cta_wrap = wrap
	return wrap

## The race card: a live crew battle takes it over (title + clock + crews), else
## today's clash — the top 2 crews on today's daily board, their scores, the lead
## bar and the UTC reset (docs B2 / meta/clash.gd).
func _build_race_card(column: VBoxContainer) -> void:
	var card := sticker_card(column, 10, Color.TRANSPARENT, 18)
	_race_card = card.get_parent().get_parent() as Control
	_race_card.name = "HomeRaceCard"
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	card.add_child(header)
	_race_dot = connection_dot()
	_race_dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(_race_dot)
	var title := make_h2("LIVE RACE", 30)
	title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.clip_text = true
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title.name = "HomeRaceTitle"
	header.add_child(title)
	_race_title = title
	_race_reset = _make_base_label("", SIZE_SMALL, LILAC)
	_race_reset.name = "HomeClashReset"
	_race_reset.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_race_reset.visible = false
	header.add_child(_race_reset)
	header.add_child(_link_button("All crews →", func() -> void:
		navigate.emit(&"community_select", {})))
	_race_rows = VBoxContainer.new()
	_race_rows.add_theme_constant_override("separation", 6)
	card.add_child(_race_rows)
	_race_note = _make_base_label("", SIZE_SMALL, CREAM)
	_race_note.name = "HomeBattleNote"
	_race_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# Single line with an explicit wrap where copy needs it: an autowrap label has
	# no width during the first fit and would report an enormous minimum height,
	# collapsing the hero. `\n` keeps the copy readable without that.
	_race_note.autowrap_mode = TextServer.AUTOWRAP_OFF
	_race_note.clip_text = true
	_race_note.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_race_note.visible = false
	card.add_child(_race_note)
	_refresh_race_rows()

func _link_button(text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_font_override("font", _bold())
	button.add_theme_font_size_override("font_size", SIZE_SMALL)
	button.add_theme_color_override("font_color", CREAM)
	button.add_theme_color_override("font_hover_color", GOLD)
	button.add_theme_color_override("font_pressed_color", GOLD)
	button.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	button.add_theme_stylebox_override("hover", StyleBoxEmpty.new())
	button.add_theme_stylebox_override("pressed", StyleBoxEmpty.new())
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	bind_press(button, action)
	return button

func _race_row(row: Dictionary, leader_score: int, is_leader: bool, is_mine: bool) -> HBoxContainer:
	var community: CommunityDefinition = row["community"]
	var accent: Color = community.accent_color if community != null else GOLD
	var panel := HBoxContainer.new()
	panel.add_theme_constant_override("separation", 18)
	if community != null:
		var tile := avatar_tile(community, RACE_AVATAR, is_leader)
		tile.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		panel.add_child(tile)
	var bar_color := YOURS if is_mine else (GOLD if is_leader else accent)
	var bar := race_bar(_score_ratio(int(row["score"]), leader_score), bar_color, RACE_BAR)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	panel.add_child(bar)
	if is_mine:
		var tag := chip("YOU", YOURS)
		tag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		panel.add_child(tag)
	var score := _make_base_label(fmt(int(row["score"])), 28, CREAM)
	score.add_theme_font_override("font", _bold())
	score.custom_minimum_size.x = 100.0
	score.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	score.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	panel.add_child(score)
	return panel

## Compact entry under the live race card. Shows a dot when a quest is claimable
## and routes to `quests`, guarded until that route is registered.
func _build_quests_entry(column: VBoxContainer) -> void:
	var card := sticker_card(column, 0, Color.TRANSPARENT, 12)
	card.name = "HomeQuestsRow"
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", int(px(8)))
	card.add_child(row)
	if _quests_claimable():
		var dot := Icon.new()
		dot.setup(&"dot", GOLD, px(13))
		dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(dot)
	var label := make_h2("QUESTS", 28)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(label)
	row.add_child(_expander())
	var chevron := Icon.new()
	chevron.setup(&"chevron", CREAM, px(18))
	chevron.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(chevron)
	make_tappable(card, _open_quests)

func _quests_claimable() -> bool:
	if save_manager == null:
		return false
	for quest in Quests.active_quests(save_manager):
		if bool(quest.get("claimable", false)):
			return true
	return false

## Opens the Quests screen (a no-op if the route is missing).
func _open_quests() -> void:
	if not AppFlow.SCREENS.has(&"quests"):
		push_warning("HomeScreen: route 'quests' is not registered yet, ignoring tap")
		return
	navigate.emit(&"quests", {})

# ---------------------------------------------------------------------------
# Fitting: full mockup hero on tall phones, shrunk hero + gaps on short ones.
# ---------------------------------------------------------------------------

func _fit_hero_and_gaps(column: VBoxContainer) -> void:
	# `column.get_combined_minimum_size()` includes the hero/gap sizes this
	# function owns, so subtract them before budgeting. Without this, every
	# re-entry (chip refresh, banner show/hide, the deferred re-measure below)
	# shrinks the hero/gaps again and the page creeps under the tab bar.
	var controlled := _hero_holder.custom_minimum_size.y if _hero_holder != null else 0.0
	for spacer in _spacers:
		controlled += spacer.custom_minimum_size.y
	var fixed := maxf(column.get_combined_minimum_size().y - controlled, 0.0)
	var top := float(TOP_PAD) + maxf(ShellUI.safe_top, 0.0)
	var available := get_viewport_rect().size.y - TAB_CLEARANCE - maxf(ShellUI.safe_bottom, 0.0) - top - BOTTOM_PAD
	var budget := available - fixed

	var gaps: Array = GAPS_FULL.duplicate()
	var hero := HERO_MAX
	var overflow := hero + _sum(gaps) - budget
	if overflow > 0.0:
		var full := _sum(GAPS_FULL)
		var minimum := _sum(GAPS_MIN)
		var shrinkable := full - minimum
		var shrink := minf(overflow, shrinkable)
		var t := 0.0 if shrinkable <= 0.0 else shrink / shrinkable
		for i in range(gaps.size()):
			gaps[i] = lerpf(GAPS_FULL[i], GAPS_MIN[i], t)
		overflow -= shrink
	if overflow > 0.0:
		var hero_shrink := minf(overflow, HERO_MAX - HERO_MIN)
		hero -= hero_shrink
		overflow -= hero_shrink
	if overflow > 0.0:
		var total := _sum(gaps)
		var new_total := maxf(total - overflow, 0.0)
		var scale := 0.0 if total <= 0.0 else new_total / total
		for i in range(gaps.size()):
			gaps[i] = maxf(gaps[i] * scale, 0.0)
		overflow = maxf(overflow - total, 0.0)
	hero = maxf(hero, HERO_FLOOR)
	if overflow > 0.0:
		# Very short viewport: drop below the design floor rather than let the
		# bottom slot slide under the tab bar. The bottom margin keeps any
		# remaining excess reachable by scrolling.
		var below_floor := minf(overflow, hero)
		hero -= below_floor
		overflow -= below_floor
	hero = maxf(hero, 0.0)

	var changed := false
	for i in range(_spacers.size()):
		# Layout sizes quantize to whole pixels, so comparing with float-exact
		# equality makes the deferred re-measure below oscillate 1341 <-> 1342
		# forever and rebuild the hero every pass. Only a real (>= 1 px) change
		# warrants another pass.
		if absf(_spacers[i].custom_minimum_size.y - gaps[i]) >= 1.0:
			changed = true
		_spacers[i].custom_minimum_size.y = gaps[i]
	if _hero_holder != null:
		if absf(_hero_holder.custom_minimum_size.y - hero) >= 1.0:
			changed = true
		_hero_holder.custom_minimum_size.y = hero
		if absf(hero - _hero_size) > 0.5 or _hero_holder.get_child_count() == 0:
			_hero_size = hero
			_build_hero(_hero_holder, _communities[_focus_index], hero)
	# The chip row is a FlowContainer and only reports its wrapped height after a
	# layout pass; re-measure once the tree has settled so the first fit cannot
	# under-reserve the QUESTS slot.
	if changed:
		_queue_refit()

## Re-runs the fit after the current frame's layout has settled; converges via
## the `changed` check inside `_fit_hero_and_gaps`.
func _queue_refit() -> void:
	if _refit_queued or not is_inside_tree():
		return
	_refit_queued = true
	call_deferred("_refit_home")

func _refit_home() -> void:
	_refit_queued = false
	if _page_column != null and is_instance_valid(_page_column):
		_fit_hero_and_gaps(_page_column)

func _build_hero(holder: Control, community: CommunityDefinition, hero: float) -> void:
	for child in holder.get_children():
		holder.remove_child(child)
		child.queue_free()
	if community == null or hero <= 0.0:
		return

	var ellipse_w := hero * 0.84
	var ellipse_h := hero * 0.184
	var ellipse := Icon.new()
	ellipse.setup(&"ellipse", Color(INK.r, INK.g, INK.b, 0.55), 1.0)
	ellipse.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ellipse.anchor_left = 0.5
	ellipse.anchor_right = 0.5
	ellipse.anchor_top = 1.0
	ellipse.anchor_bottom = 1.0
	ellipse.offset_left = -ellipse_w * 0.5
	ellipse.offset_right = ellipse_w * 0.5
	ellipse.offset_top = -(ellipse_h + px(4))
	ellipse.offset_bottom = -px(4)
	ellipse.resized.connect(ellipse.queue_redraw)
	holder.add_child(ellipse)

	var preview := MascotPreview.new()
	preview.setup(community, hero)
	preview.anchor_left = 0.5
	preview.anchor_right = 0.5
	preview.anchor_top = 1.0
	preview.anchor_bottom = 1.0
	preview.offset_left = -hero * 0.5
	preview.offset_right = hero * 0.5
	preview.offset_top = -hero
	preview.offset_bottom = 0.0
	preview.resized.connect(func() -> void: preview.pivot_offset = preview.size * 0.5)
	holder.add_child(preview)
	breathe(preview, 0.025, 1.8)
	make_tappable(preview, func() -> void:
		navigate.emit(&"community_detail", {"community_id": community.id}))

func _make_gap(column: VBoxContainer) -> Control:
	var spacer := Control.new()
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(spacer)
	return spacer

# ---------------------------------------------------------------------------
# State + live race
# ---------------------------------------------------------------------------

func _refresh_chip(focused: CommunityDefinition) -> void:
	if _chip_host == null or focused == null:
		return
	for child in _chip_host.get_children():
		_chip_host.remove_child(child)
		child.queue_free()
	var rank := _rank_of(focused)
	# A flow container wraps rank + streak + MVP chips instead of overflowing the
	# page, so long crew names or all three chips can never collide or clip.
	var row := HFlowContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.alignment = FlowContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("h_separation", int(px(8)))
	row.add_theme_constant_override("v_separation", int(px(8)))
	if rank == 1:
		row.add_child(chip("#1 TODAY · LEADING", GOLD, &"crown", px(20)))
	else:
		row.add_child(chip("#%d TODAY" % rank, GOLD))
	for extra in _hero_extra_chips(focused):
		row.add_child(extra)
	_chip_host.add_child(row)
	# The chip row can wrap to a second line; re-fit so it never grows under the
	# tab bar. Skipped during setup, where the final fit runs after all sections.
	if _page_column != null and _hero_holder != null:
		_fit_hero_and_gaps(_page_column)

## MVP and streak chips for the hero, only when the data exists (docs/15 §3).
func _hero_extra_chips(focused: CommunityDefinition) -> Array[Control]:
	var chips: Array[Control] = []
	var streak := save_manager.streak_days if save_manager != null else 0
	if streak >= 2:
		chips.append(chip("%d-DAY STREAK" % streak, YOURS, &"flame", px(20)))
	if _is_mvp(focused):
		chips.append(chip("MVP", GOLD, &"crown", px(20)))
	return chips

## True when the player is the represented crew's weekly MVP (needs live data; the
## offline local row never counts).
func _is_mvp(focused: CommunityDefinition) -> bool:
	if save_manager == null or focused == null:
		return false
	if save_manager.selected_community_id != focused.id:
		return false
	var carriers := Standings.top_carriers(save_manager, focused.id)
	if carriers.is_empty():
		return false
	var first: Dictionary = carriers[0]
	return bool(first.get("you", false)) and not bool(first.get("local", false))

func _refresh_race_rows() -> void:
	if _race_rows == null:
		return
	for child in _race_rows.get_children():
		_race_rows.remove_child(child)
		child.queue_free()
	if _battle_on():
		_fill_battle_rows()
		return
	_fill_clash_rows()

## A live crew battle (or its 3-2-1) takes over the race card: the battle's
## crews with their battle points, the clock in the title, and whether your runs
## count. Same battles and boards as play.nocaps.fun.
func _battle_on() -> bool:
	return BattleService.is_live() or BattleService.in_countdown()

## Otherwise the card shows today's clash: the top 2 crews on today's daily board
## (the same numbers Home already loads), the lead bar, and the UTC reset. Fewer
## than two crews with points means there is no clash yet.
func _fill_clash_rows() -> void:
	var roster := _roster
	var my_id: StringName = save_manager.selected_community_id if save_manager != null else &""
	var clash := Clash.from_rows(_standings)
	var active := bool(clash.get("active", false))
	if _race_title != null:
		if active:
			_race_title.text = "TODAY'S CLASH · %s vs %s" % [clash["a"]["name"], clash["b"]["name"]]
		else:
			_race_title.text = "TODAY'S CLASH"
	if _race_reset != null:
		_race_reset.visible = active
		if active:
			_update_clash_clock()
	if _race_note == null:
		return
	_race_note.visible = true
	if not active:
		_race_note.text = "Starts with the first runs.\nPlay to put %s on top." % _my_crew_name(roster, my_id)
		return
	var a: Dictionary = clash["a"]
	var b: Dictionary = clash["b"]
	var leader := maxi(int(a["score"]), int(b["score"]))
	for side in [a, b]:
		var community := CommunityRepository.by_id(roster, StringName(side["id"]))
		var row := {"id": side["id"], "score": side["score"], "community": community}
		_race_rows.add_child(_race_row(row, leader, int(side["score"]) == leader, String(side["id"]) == String(my_id)))
	_race_note.text = _clash_note(roster, clash, my_id)
	_ensure_clock_timer()

## The line under the clash: my crew's stake, or how far the #2 spot is.
func _clash_note(roster: CommunityRoster, clash: Dictionary, my_id: StringName) -> String:
	var a: Dictionary = clash["a"]
	var b: Dictionary = clash["b"]
	var key := String(my_id)
	if key != "" and (key == String(a["id"]) or key == String(b["id"])):
		var side: Dictionary = a if key == String(a["id"]) else b
		return "Your runs count for %s" % side["name"]
	if key == "":
		return "Pick a crew. Play to break into today's clash."
	var row := _row_for(my_id)
	var rank := int(row.get("rank", _standings.size()))
	var behind := maxi(int(b["score"]) - int(row.get("score", 0)), 0)
	return "%s is #%d, %s pts behind #2. Play to break in." % [
		String(row.get("name", _my_crew_name(roster, my_id))), rank, fmt(behind)]

func _my_crew_name(roster: CommunityRoster, my_id: StringName) -> String:
	if my_id != &"":
		var community := CommunityRepository.by_id(roster, my_id)
		if community != null:
			return community.display_name
	return "your crew"

func _row_for(id: StringName) -> Dictionary:
	for row in _standings:
		if String(row.get("id", "")) == String(id):
			return row
	return {}

func _update_clash_clock() -> void:
	if _race_reset == null or not _race_reset.visible or _battle_on():
		return
	_race_reset.text = "resets in %s" % Clash.reset_text()

func _fill_battle_rows() -> void:
	var roster := _roster
	var rows := BattleService.standings()
	var leader := int(rows[0]["score"]) if not rows.is_empty() else 0
	var my_id := String(save_manager.selected_community_id) if save_manager != null else ""
	if _race_reset != null:
		_race_reset.visible = false
	for i in range(rows.size()):
		var community := CommunityRepository.by_id(roster, StringName(rows[i]["id"]))
		var row := {"id": rows[i]["id"], "score": rows[i]["score"], "community": community}
		_race_rows.add_child(_race_row(row, leader, i == 0 and leader > 0, String(rows[i]["id"]) == my_id))
	_update_battle_clock()
	if _race_note != null:
		_race_note.visible = true
		var mine := CommunityRepository.by_id(roster, StringName(my_id)) if not my_id.is_empty() else null
		if mine != null and BattleService.crews.has(my_id):
			var pts := int(BattleService.my_scores.get(my_id, 0))
			_race_note.text = "Your runs count for %s%s" % [mine.display_name,
				" · you: %s pts" % fmt(pts) if pts > 0 else ""]
		else:
			_race_note.text = "Rep %s to join the battle" % " or ".join(_battle_crew_names(roster))
	_ensure_clock_timer()

func _battle_crew_names(roster: CommunityRoster) -> PackedStringArray:
	var names := PackedStringArray()
	for id in BattleService.crews:
		var c := CommunityRepository.by_id(roster, StringName(id))
		names.append(c.display_name if c != null else id)
	return names

func _update_battle_clock() -> void:
	if _race_title == null or not _battle_on():
		return
	var label := BattleService.title.to_upper()
	_race_title.text = "%s · %s" % [label, "STARTING" if BattleService.in_countdown() else BattleService.clock_text()]

func _ensure_clock_timer() -> void:
	if is_instance_valid(_clock_timer):
		return
	_clock_timer = Timer.new()
	_clock_timer.wait_time = 1.0
	_clock_timer.timeout.connect(func() -> void:
		var was_battle := _battle_on()
		_update_battle_clock()
		_update_clash_clock()
		if was_battle != _battle_on():
			_refresh_race_rows())
	add_child(_clock_timer)
	_clock_timer.start()

func _on_primary() -> void:
	if _communities.is_empty():
		return
	var focused: CommunityDefinition = _communities[_focus_index]
	var selected: StringName = save_manager.selected_community_id if save_manager != null else &""
	if selected == &"":
		_represent(focused, false)
		navigate.emit(&"run", {})
	elif selected == focused.id:
		navigate.emit(&"run", {})
	else:
		_represent(focused, true)
		_rebuild()

## Persists the focused crew as represented. Switching announces with a toast;
## the first-choice "REP & PLAY" path stays quiet and launches straight away.
func _represent(community: CommunityDefinition, announce: bool) -> void:
	if save_manager != null and community != null:
		save_manager.set_selected_community(community.id)
		if announce:
			Toasts.show_message("You're now repping %s" % community.display_name)
		if ShellUI.instance != null:
			ShellUI.instance.refresh()

func _guest_name() -> String:
	if save_manager != null and not save_manager.display_name.is_empty():
		return save_manager.display_name
	return "Guest"

func _focused() -> CommunityDefinition:
	if _communities.is_empty():
		return null
	return _communities[clampi(_focus_index, 0, _communities.size() - 1)]

func _leader_id() -> StringName:
	if _standings.is_empty():
		return &""
	return StringName(_standings[0]["id"])

func _rank_of(community: CommunityDefinition) -> int:
	for row in _standings:
		if row["id"] == community.id:
			return int(row["rank"])
	return _standings.size()

func _index_of(communities: Array[CommunityDefinition], id: StringName) -> int:
	if id != &"":
		for i in range(communities.size()):
			if communities[i].id == id:
				return i
	return -1

func _score_ratio(score: int, leader_score: int) -> float:
	if leader_score <= 0:
		return 0.0
	return clampf(float(score) / float(leader_score), 0.0, 1.0)

func _sum(values: Array) -> float:
	var total := 0.0
	for value in values:
		total += float(value)
	return total

func _make_tile_tappable(tile: Control, index: int) -> void:
	make_tappable(tile, func() -> void: _focus(index))

func _focus(index: int) -> void:
	_focus_index = index
	_rebuild()

## No timed polling (Oct 10, fundamentals E10). A cheap 1 s watch re-renders only
## when Standings has new data (a fetch finished: screen open, resume, after a run),
## and refreshes on a timer only while a battle is live (BATTLE_REFRESH_SECONDS).
## Looking for a newly started battle costs one small query a minute.
func _start_refresh_timer() -> void:
	if is_instance_valid(_refresh_timer):
		return
	_seen_version = Standings.version()
	_refresh_timer = Timer.new()
	_refresh_timer.wait_time = 1.0
	_refresh_timer.timeout.connect(_on_watch_tick)
	add_child(_refresh_timer)
	_refresh_timer.start()

func _on_watch_tick() -> void:
	_watch_ticks += 1
	var battle := BattleService.is_live() or BattleService.in_countdown()
	if Standings.version() != _seen_version or (battle and _watch_ticks % BATTLE_REFRESH_SECONDS == 0):
		_seen_version = Standings.version()
		_refresh_standings()
	elif _watch_ticks % BATTLE_DISCOVERY_SECONDS == 0:
		BattleService.refresh()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_RESUMED and is_inside_tree():
		_refresh_standings()

## Re-reads today's standings while Home is visible; the chip and live race
## update in place so the page never resets under the player.
func _refresh_standings() -> void:
	BattleService.refresh()
	BattleService.refresh_boards()
	_standings = Standings.communities_today(save_manager)
	_refresh_chip(_focused())
	_refresh_race_rows()
	update_connection_dot(_race_dot)

func _rebuild() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_refresh_timer = null
	_clock_timer = null
	_race_title = null
	_race_note = null
	_race_reset = null
	_chip_host = null
	_race_rows = null
	_race_dot = null
	_hero_holder = null
	_cta_wrap = null
	_race_card = null
	_page_column = null
	_bottom_slot = null
	_quests_row = null
	_hero_size = -1.0
	_refit_queued = false
	_spacers.clear()
	setup({})
