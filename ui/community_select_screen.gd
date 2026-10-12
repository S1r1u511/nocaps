extends UiScreen

## Explore — v2 "arcade sticker" (docs/UI_V2_BRIEF.md §5–6, docs/mockups/explore.html).
## Featured campaign card (only when a crew has `featured_campaign`), filter chips,
## a 2-column grid of crew tiles, and the "more caps games" teaser. Crew tiles and
## the featured card open the community page; today's points + ranks come from
## `Standings.communities_today()`.

## TODO(ui-v2 kit): these pieces are composed locally from kit tokens because no
## §2 component exists yet — fold them into `ui/ui_screen.gd` when it is next
## touched: `campaign_card` (GOLD card variant), `filter_chip` (toggle pill),
## `grid_tile` (2-column crew tile), and the teaser card (StyleBoxFlat cannot
## draw the mockup's dashed border, so it is a solid purple outline).
const TOKEN_PINK := Color("f5a3c7")
const TEASER_BORDER := Color("7b5fc7")

var _filter: StringName = &"all"
var _communities: Array[CommunityDefinition] = []
var _standings_by_id: Dictionary = {}
var _chips: HFlowContainer
var _grid: GridContainer
var _empty_state: Label

func setup(_payload: Dictionary) -> void:
	_standings_by_id = {}
	for row in Standings.communities_today(save_manager):
		_standings_by_id[String(row.get("id", ""))] = row
	_communities = CommunityRepository.enabled_sorted(CommunityRepository.load_roster())

	var page := build_page()
	_apply_page_insets(page)
	page.add_child(_title())

	var featured := _featured_community()
	if featured != null:
		page.add_child(_campaign_card(featured))

	_chips = HFlowContainer.new()
	_chips.name = "ExploreChips"
	_chips.add_theme_constant_override("h_separation", int(px(6)))
	_chips.add_theme_constant_override("v_separation", int(px(6)))
	page.add_child(_chips)
	_build_chips()

	_grid = GridContainer.new()
	_grid.name = "ExploreGrid"
	_grid.columns = 2
	_grid.add_theme_constant_override("h_separation", int(px(12)))
	_grid.add_theme_constant_override("v_separation", int(px(12)))
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.add_child(_grid)

	_empty_state = make_sub("No crews match yet.", SIZE_SMALL)
	_empty_state.name = "ExploreEmpty"
	_empty_state.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_empty_state.visible = false
	page.add_child(_empty_state)

	_build_grid()

	page.add_child(_teaser_card())

## Explore owns equal side gutters (40 px at the 720-wide baseline) and leaves the
## tab bar plus 24 px clear at the end of the scroll.
func _apply_page_insets(page: VBoxContainer) -> void:
	var margin := page.get_parent() as MarginContainer
	if margin == null:
		return
	margin.add_theme_constant_override("margin_left", 40)
	margin.add_theme_constant_override("margin_right", 40)
	margin.add_theme_constant_override("margin_bottom", int(ShellUI.BAR_HEIGHT + ShellUI.safe_bottom + 24.0))

func _title() -> Label:
	var label := outlined_title("EXPLORE", CREAM, int(px(44)))
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	return label

# ---------------------------------------------------------------------------
# Featured campaign
# ---------------------------------------------------------------------------

func _featured_community() -> CommunityDefinition:
	for community in _communities:
		if community != null and community.has_featured_campaign():
			return community
	return null

func _campaign_card(community: CommunityDefinition) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _panel_style(GOLD, 4, 24, 6, 14))

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", int(px(12)))
	panel.add_child(row)

	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", int(px(6)))
	row.add_child(column)

	var tags := HBoxContainer.new()
	tags.add_theme_constant_override("separation", int(px(6)))
	column.add_child(tags)
	tags.add_child(_pill("THIS WEEK", INK, GOLD))
	var countdown := _countdown(community.campaign_value("ends_at"))
	if not countdown.is_empty():
		tags.add_child(_pill(countdown, CREAM, INK))

	column.add_child(_ink_text(community.campaign_value("title", community.display_name), px(22), 700))
	var reward := community.campaign_value("reward_text")
	if not reward.is_empty():
		column.add_child(_ink_text(reward, px(14), 600))
	column.add_child(_see_crew_button(community.id))

	var preview := MascotPreview.new()
	preview.setup(community, px(120))
	preview.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(preview)

	make_tappable(panel, func() -> void:
		navigate.emit(&"community_detail", {"community_id": community.id}))
	return panel

func _see_crew_button(community_id: StringName) -> Button:
	var button := Button.new()
	button.text = "See crew →"
	button.focus_mode = Control.FOCUS_NONE
	button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	button.custom_minimum_size = Vector2(0.0, px(40))
	button.add_theme_font_override("font", _bold())
	button.add_theme_font_size_override("font_size", int(px(15)))
	button.add_theme_stylebox_override("normal", _plain_button_style(INK, false))
	button.add_theme_stylebox_override("hover", _plain_button_style(INK.lightened(0.08), false))
	button.add_theme_stylebox_override("pressed", _plain_button_style(INK.darkened(0.08), true))
	button.add_theme_stylebox_override("focus", _plain_button_style(INK, false))
	button.add_theme_color_override("font_color", GOLD)
	button.add_theme_color_override("font_hover_color", GOLD)
	button.add_theme_color_override("font_pressed_color", GOLD)
	bind_press(button, func() -> void:
		navigate.emit(&"community_detail", {"community_id": community_id}))
	return button

## ISO `ends_at` → mockup-style "Ends in 3d 4h"; empty when missing/unparseable.
func _countdown(ends_at: String) -> String:
	var iso := ends_at.strip_edges()
	if iso.is_empty():
		return ""
	var unix := Time.get_unix_time_from_datetime_string(iso)
	if unix <= 0.0 and iso.length() == 10:
		unix = Time.get_unix_time_from_datetime_string(iso + "T00:00:00")
	if unix <= 0.0:
		return ""
	var seconds := int(unix - ServerClock.now())
	if seconds <= 0:
		return "Ends soon"
	if seconds >= 86400:
		return "Ends in %dd %dh" % [seconds / 86400, (seconds % 86400) / 3600]
	if seconds >= 3600:
		return "Ends in %dh" % (seconds / 3600)
	return "Ends in %dm" % maxi(seconds / 60, 1)

# ---------------------------------------------------------------------------
# Filters
# ---------------------------------------------------------------------------

func _build_chips() -> void:
	for child in _chips.get_children():
		_chips.remove_child(child)
		child.queue_free()
	var defs := [["all", "All"], ["rewards", "Rewards"], ["open", "Open to join"], ["token", "Token crews"]]
	for entry in defs:
		_chips.add_child(_filter_chip(String(entry[1]), StringName(entry[0])))

func _filter_chip(label: String, key: StringName) -> Button:
	var active := key == _filter
	var button := Button.new()
	button.text = label
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(0.0, px(36))
	button.add_theme_font_override("font", _bold())
	button.add_theme_font_size_override("font_size", int(px(12)))
	button.add_theme_stylebox_override("normal", _filter_style(active, false))
	button.add_theme_stylebox_override("hover", _filter_style(active, false))
	button.add_theme_stylebox_override("pressed", _filter_style(active, true))
	button.add_theme_stylebox_override("focus", _filter_style(active, false))
	button.add_theme_color_override("font_color", INK if active else CREAM)
	button.add_theme_color_override("font_hover_color", INK if active else GOLD)
	button.add_theme_color_override("font_pressed_color", INK if active else CREAM)
	bind_press(button, func() -> void: _set_filter(key))
	return button

func _set_filter(key: StringName) -> void:
	if _filter == key:
		return
	_filter = key
	_build_chips()
	_build_grid()

func _filter_style(active: bool, pressed: bool) -> StyleBoxFlat:
	var style := _ledge(GOLD if active else CARD, int(px(3)), 999, 0 if pressed else int(px(3)))
	style.content_margin_left = px(10)
	style.content_margin_right = px(10)
	style.content_margin_top = px(4) + (px(3) if pressed else 0.0)
	style.content_margin_bottom = px(4)
	return style

func _matches_filter(community: CommunityDefinition) -> bool:
	match _filter:
		&"rewards":
			return community.has_featured_campaign()
		&"open":
			return community.eligibility_type == &"open"
		&"token":
			return not community.token_ca.is_empty()
	return true

# ---------------------------------------------------------------------------
# Crew grid
# ---------------------------------------------------------------------------

func _build_grid() -> void:
	for child in _grid.get_children():
		_grid.remove_child(child)
		child.queue_free()
	var matches := 0
	for community in _communities:
		if _matches_filter(community):
			matches += 1
			_grid.add_child(_grid_tile(community))
	if _empty_state != null and is_instance_valid(_empty_state):
		_empty_state.visible = matches == 0

func _grid_tile(community: CommunityDefinition) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", _panel_style(CARD, 4, 22, 5, 10, 12))

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", int(px(2)))
	panel.add_child(column)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	column.add_child(top)
	var rank := _rank_of(community)
	top.add_child(_pill("#%d" % rank, GOLD if rank == 1 else CREAM, INK))
	top.add_child(_expander())
	if community.has_featured_campaign():
		top.add_child(_pill("REWARDS", YOURS, INK))

	var preview := MascotPreview.new()
	preview.setup(community, px(104))
	preview.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.add_child(preview)

	var name_label := _make_base_label(community.display_name, int(px(19)), CREAM)
	name_label.add_theme_font_override("font", _bold())
	# A long crew name ellipsizes inside the tile instead of widening its grid
	# column past the page.
	name_label.clip_text = true
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.custom_minimum_size.x = 0.0
	column.add_child(name_label)

	var meta := _make_base_label("%s pts today" % fmt(_score_of(community)), int(px(12)), Color(CREAM.r, CREAM.g, CREAM.b, 0.8))
	column.add_child(meta)

	var open := community.eligibility_type == &"open"
	column.add_child(_pill("OPEN" if open else "HOLD TOKEN", LILAC if open else TOKEN_PINK, INK))

	make_tappable(panel, func() -> void:
		navigate.emit(&"community_detail", {"community_id": community.id}))
	return panel

func _rank_of(community: CommunityDefinition) -> int:
	var row: Dictionary = _standings_by_id.get(String(community.id), {})
	return int(row.get("rank", _communities.size()))

func _score_of(community: CommunityDefinition) -> int:
	var row: Dictionary = _standings_by_id.get(String(community.id), {})
	return int(row.get("score", 0))

# ---------------------------------------------------------------------------
# Teaser
# ---------------------------------------------------------------------------

func _teaser_card() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", _panel_style(CARD, 4, 22, 0, 14))

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", int(px(10)))
	panel.add_child(column)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	column.add_child(header)
	var title := _make_base_label("More caps games", int(px(18)), CREAM)
	title.add_theme_font_override("font", _bold())
	title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(title)
	header.add_child(_expander())
	header.add_child(_pill("SOON", LILAC, INK))

	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", int(px(8)))
	grid.add_theme_constant_override("v_separation", int(px(8)))
	column.add_child(grid)
	grid.add_child(_teaser_tile(_fit_cap_icon(), "NOCAPS FIT"))
	grid.add_child(_teaser_tile(_lock_icon()))
	grid.add_child(_teaser_tile(_lock_icon()))
	return panel

func _teaser_tile(icon: Control, label_text: String = "") -> PanelContainer:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.custom_minimum_size = Vector2(0.0, px(76))
	panel.add_theme_stylebox_override("panel", _panel_style(CARD_INNER, 3, 16, 0, 4))
	var column := VBoxContainer.new()
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 8)
	panel.add_child(column)
	column.add_child(make_center(icon))
	if not label_text.is_empty():
		var label := _make_base_label(label_text, int(px(12)), CREAM)
		label.add_theme_font_override("font", _bold())
		column.add_child(label)
	return panel

func _fit_cap_icon() -> Control:
	var cap: CapDefinition = CommunityRepository.resolve_cap(null)
	if cap == null or cap.side_texture == null:
		return _lock_icon()
	var texture := TextureRect.new()
	texture.texture = cap.side_texture
	texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	texture.custom_minimum_size = Vector2(px(40), px(24))
	texture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return texture

func _lock_icon() -> Control:
	var icon := Icon.new()
	icon.setup(&"lock", LILAC, px(22))
	return icon

# ---------------------------------------------------------------------------
# Local kit pieces (see TODO above)
# ---------------------------------------------------------------------------

## Sticker card with an arbitrary fill/ledge; `pad_bottom` can differ from `pad`.
func _panel_style(fill: Color, border: int, radius: int, ledge: int, pad: int, pad_bottom: int = -1) -> StyleBoxFlat:
	var style := _ledge(fill, int(px(border)), int(px(radius)), int(px(ledge)))
	style.content_margin_left = px(pad)
	style.content_margin_right = px(pad)
	style.content_margin_top = px(pad)
	style.content_margin_bottom = px(pad_bottom if pad_bottom >= 0 else pad)
	return style

## Pill tag matching the mockups (INK text by default).
func _pill(text: String, fill: Color, text_color: Color = INK) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := _ledge(fill, 4, 999, 0)
	style.content_margin_left = px(8)
	style.content_margin_right = px(8)
	style.content_margin_top = 2.0
	style.content_margin_bottom = 6.0
	panel.add_theme_stylebox_override("panel", style)
	panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var label := _make_base_label(text, int(px(11)), text_color)
	label.add_theme_font_override("font", _bold())
	panel.add_child(label)
	return panel

## INK label for the GOLD campaign card (kit text helpers are CREAM/LILAC).
func _ink_text(text: String, size: int, weight: int) -> Label:
	var label := _make_base_label(text, size, INK)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if weight >= 700:
		label.add_theme_font_override("font", _bold())
	return label

## Borderless rounded button (the mockup's dark "See crew →").
func _plain_button_style(fill: Color, pressed: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.set_corner_radius_all(int(px(14)))
	style.content_margin_left = px(16)
	style.content_margin_right = px(16)
	style.content_margin_top = px(4) + (px(4) if pressed else 0.0)
	style.content_margin_bottom = px(4)
	return style
