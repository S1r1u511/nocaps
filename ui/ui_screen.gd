extends Control
class_name UiScreen

## NOCAPS UI v2 kit — "arcade sticker" (docs/UI_V2_BRIEF.md §1–2). Owns the design
## tokens, the page scaffold, and the shared component set every screen composes:
## sticker cards, chunky ledge buttons, outlined titles, chips/tags, avatar tiles,
## race bars, collapsible sections, and the podium. Screens never hand-roll colors,
## borders, ledges, or button styles. Screens build in `setup` and ask AppFlow to
## navigate by emitting `navigate`.

signal navigate(screen: StringName, payload: Dictionary)

# ---------------------------------------------------------------------------
# Tokens (brief §1)
# ---------------------------------------------------------------------------

const INK := Color("1d1033")
const CARD := Color("2b1b4a")
const CARD_INNER := Color("3a2466")
const GOLD := Color("ffd23f")
const CREAM := Color("fff4dc")
const YOURS := Color("5ee08a")
const LILAC := Color("b9a8d6")
const CORAL := Color("ff8a7a")
const LIVE := Color("ff5a4e")
const SILVER := Color("c7c3d9")
const BRONZE := Color("e0a577")

# ---------------------------------------------------------------------------
# Type + scale (brief §1)
# ---------------------------------------------------------------------------

const SIZE_DISPLAY := 96
const SIZE_BODY := 31
const SIZE_SMALL := 24
const SIZE_SCORE_RESULT := 236
const SIZE_SCORE_HUD := 155
const MOCKUP_SCALE := 1.85
const BOLD_FONT_PATH := "res://data/fonts/fredoka_bold.tres"

## A finger may travel this many pixels before a press becomes a drag: the page
## scrolls and the pressed control's action is dropped. Keep in sync with the
## `ScrollContainer.scroll_deadzone` set by `build_page` and the local scrolls.
const DRAG_DEADZONE := 14.0

## Injected by AppFlow before `setup`.
var save_manager: SaveManager
var backend_client: BackendClient

var _page_root: ScrollContainer
var _bold_font: Font = null

func bind_services(save: SaveManager, backend: BackendClient) -> void:
	save_manager = save
	backend_client = backend

func setup(_payload: Dictionary) -> void:
	pass

## Mockup px → viewport px (brief §0).
static func px(value: float) -> float:
	return roundf(value * MOCKUP_SCALE)

# ---------------------------------------------------------------------------
# Page + cards
# ---------------------------------------------------------------------------

## A scrollable page: a vertical stack of cards with room for the tab bar.
func build_page() -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.scroll_deadzone = DRAG_DEADZONE
	add_child(scroll)

	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_theme_constant_override("margin_left", 30)
	margin.add_theme_constant_override("margin_right", 30)
	margin.add_theme_constant_override("margin_top", int(28.0 + ShellUI.safe_top))
	margin.add_theme_constant_override("margin_bottom", int(153.0 + ShellUI.safe_bottom))
	scroll.add_child(margin)

	var page := VBoxContainer.new()
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.add_theme_constant_override("separation", 22)
	margin.add_child(page)
	_page_root = scroll
	return page

## Sticker card: CARD fill, INK border + solid ledge, radius 40, padding 26.
## Returns its inner column. `padding` can be tightened for compact cards.
func sticker_card(page: VBoxContainer, separation: int = 18, accent: Color = Color.TRANSPARENT, padding: int = 26) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", _card_style(accent))
	page.add_child(panel)

	var inner := MarginContainer.new()
	inner.add_theme_constant_override("margin_left", padding)
	inner.add_theme_constant_override("margin_right", padding)
	inner.add_theme_constant_override("margin_top", padding)
	inner.add_theme_constant_override("margin_bottom", padding)
	panel.add_child(inner)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", separation)
	inner.add_child(column)
	return column

## Legacy name kept for screens not yet rebuilt; delegates to `sticker_card`.
func make_card(page: VBoxContainer, separation: int = 10, accent: Color = Color.TRANSPARENT) -> VBoxContainer:
	return sticker_card(page, separation, accent)

# ---------------------------------------------------------------------------
# Components (brief §2)
# ---------------------------------------------------------------------------

## GOLD chunky button: INK border + 13 px ledge, INK text, presses down.
func primary_button(text: String, action: Callable, height: float = 133.0, font_size: int = 44) -> Button:
	var button := _kit_button(text, GOLD, INK, font_size, 7, 40, 13)
	button.custom_minimum_size = Vector2(0, height)
	bind_press(button, action)
	return button

## CARD chunky button: same border/ledge, CREAM text.
func secondary_button(text: String, action: Callable, height: float = 115.0, font_size: int = 33) -> Button:
	var button := _kit_button(text, CARD, CREAM, font_size, 7, 40, 13)
	button.custom_minimum_size = Vector2(0, height)
	bind_press(button, action)
	return button

## CREAM light button for inline actions (Follow / Connect / Copy).
func light_button(text: String, action: Callable, font_size: int = SIZE_SMALL, height: float = 70.0) -> Button:
	var button := _kit_button(text, CREAM, INK, font_size, 6, 22, 6)
	button.custom_minimum_size = Vector2(0, height)
	bind_press(button, action)
	return button

## Display title with INK outline + solid drop (home crew name, THE RACE, …).
## The label never widens its column: a long crew name is ellipsized instead of
## overflowing the page (screens set the final alignment they need).
func outlined_title(text: String, color: Color = CREAM, size: int = SIZE_DISPLAY) -> Label:
	var label := _make_base_label(text, size, color)
	label.add_theme_font_override("font", _bold())
	label.add_theme_color_override("font_outline_color", INK)
	label.add_theme_constant_override("outline_size", 12)
	label.add_theme_color_override("font_shadow_color", INK)
	label.add_theme_constant_override("shadow_offset_x", 0)
	label.add_theme_constant_override("shadow_offset_y", 9)
	label.add_theme_constant_override("shadow_outline_size", 12)
	label.clip_text = true
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.custom_minimum_size.x = 0.0
	return label

## Solid pill with INK border and INK text (status, rank, combo, tags).
func chip(text: String, fill: Color = GOLD, icon_kind: StringName = &"", icon_size: float = SIZE_SMALL - 2) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", _pill_style(fill, 6, 6))
	panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	if icon_kind == &"":
		panel.add_child(_chip_label(text))
		return panel
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 8)
	panel.add_child(row)
	var icon := Icon.new()
	icon.setup(icon_kind, INK, icon_size)
	row.add_child(icon)
	row.add_child(_chip_label(text))
	return panel

## Rounded-square mascot tile, radius 30% of size; GOLD border when focused/you.
## `size` is the outer size (the border overlaps the art, like the mockups).
func avatar_tile(community: CommunityDefinition, size: float = 115.0, focused: bool = false) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.custom_minimum_size = Vector2(size, size)
	var style := StyleBoxFlat.new()
	style.bg_color = CARD_INNER
	style.set_corner_radius_all(int(size * 0.3))
	style.set_border_width_all(7)
	style.border_color = GOLD if focused else INK
	style.content_margin_left = 0.0
	style.content_margin_top = 0.0
	style.content_margin_right = 0.0
	style.content_margin_bottom = 0.0
	panel.add_theme_stylebox_override("panel", style)
	if community != null and community.mascot != null and community.mascot.idle_texture != null:
		var preview := MascotPreview.new()
		preview.setup(community, size)
		panel.add_child(preview)
	return panel

## INK track bar with a rounded fill scaled to the leader.
func race_bar(progress: float, color: Color = GOLD, height: float = 30.0) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.custom_minimum_size = Vector2(0, height)
	bar.max_value = 1.0
	bar.step = 0.001
	bar.value = clampf(progress, 0.0, 1.0)
	bar.show_percentage = false
	var background := StyleBoxFlat.new()
	background.bg_color = INK
	background.set_corner_radius_all(999)
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	fill.set_corner_radius_all(999)
	bar.add_theme_stylebox_override("background", background)
	bar.add_theme_stylebox_override("fill", fill)
	return bar

## Sticker card whose header toggles the body; returns the body column to fill.
func collapsible_section(
	page: VBoxContainer,
	title: String,
	icon_kind: StringName = &"",
	open: bool = true,
	trailing: Control = null
) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", _card_style())
	page.add_child(panel)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 0)
	panel.add_child(column)

	var header := PanelContainer.new()
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_theme_stylebox_override("panel", _section_header_style())
	column.add_child(header)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(row)
	if icon_kind != &"":
		var icon := Icon.new()
		icon.setup(icon_kind, GOLD, 34.0)
		icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(icon)
	var title_label := _make_base_label(title, SIZE_BODY, CREAM)
	title_label.add_theme_font_override("font", _bold())
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(title_label)
	if trailing != null:
		trailing.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(trailing)
	var chevron := Icon.new()
	chevron.setup(&"chevron_down", CREAM, 28.0)
	chevron.pivot_offset = Vector2(14.0, 14.0)
	chevron.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(chevron)

	var hit := Button.new()
	hit.text = ""
	hit.focus_mode = Control.FOCUS_NONE
	hit.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	hit.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	hit.add_theme_stylebox_override("hover", _header_hover_style())
	hit.add_theme_stylebox_override("pressed", _header_pressed_style())
	hit.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	header.add_child(hit)

	var body_margin := MarginContainer.new()
	body_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body_margin.clip_contents = true
	body_margin.add_theme_constant_override("margin_left", 26)
	body_margin.add_theme_constant_override("margin_right", 26)
	body_margin.add_theme_constant_override("margin_top", 0)
	body_margin.add_theme_constant_override("margin_bottom", 26)
	column.add_child(body_margin)

	var body := VBoxContainer.new()
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_theme_constant_override("separation", 14)
	body_margin.add_child(body)

	_set_section_open(body_margin, body, chevron, open, false)
	var state := {"open": open}
	bind_press(hit, func() -> void:
		state["open"] = not bool(state["open"])
		_set_section_open(body_margin, body, chevron, bool(state["open"]), true))
	return body

## Three-column race podium (2nd · 1st with crown · 3rd) from standings rows.
func podium(rows: Array, mine_id: StringName = &"") -> Control:
	var wrap := HBoxContainer.new()
	wrap.alignment = BoxContainer.ALIGNMENT_END
	wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wrap.add_theme_constant_override("separation", 16)
	for place in [1, 0, 2]:
		if place >= rows.size():
			continue
		wrap.add_child(_podium_column(rows[place], place, mine_id))
	return wrap

## Code-drawn gold crown for #1 moments.
func crown_icon(size: float = 44.0, color: Color = GOLD) -> Icon:
	var icon := Icon.new()
	icon.setup(&"crown", color, size)
	return icon

## The small red "live" dot.
func live_dot(size: float = 17.0) -> Icon:
	var icon := Icon.new()
	icon.setup(&"dot", LIVE, size)
	return icon

## Standings connection dot: YOURS green when the last successful fetch is
## recent, LILAC when offline, pulsing LILAC while the first fetch is in flight.
func connection_dot(size: float = 17.0) -> Icon:
	var dot := Icon.new()
	dot.setup(&"dot", LILAC, size)
	update_connection_dot(dot)
	return dot

## Re-applies the current `Standings.connection_state()` to a dot from
## `connection_dot`; screens call this from their 10 s refresh.
func update_connection_dot(dot: Icon) -> void:
	if dot == null:
		return
	if dot.has_meta(&"connection_pulse"):
		var pulse: Tween = dot.get_meta(&"connection_pulse")
		if pulse != null and pulse.is_valid():
			pulse.kill()
		dot.remove_meta(&"connection_pulse")
	dot.modulate = Color.WHITE
	match Standings.connection_state():
		"live":
			dot.set_color(YOURS)
		"connecting":
			dot.set_color(LILAC)
			var tween := dot.create_tween().set_loops()
			tween.tween_property(dot, "modulate:a", 0.35, 0.6) \
				.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
			tween.tween_property(dot, "modulate:a", 1.0, 0.6) \
				.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
			dot.set_meta(&"connection_pulse", tween)
		_:
			dot.set_color(LILAC)

## CREAM square button with a code-drawn social glyph (X / Telegram / Website).
func social_button(kind: StringName, action: Callable) -> Button:
	var button := light_button("", action, SIZE_SMALL, 85.0)
	button.custom_minimum_size = Vector2(85, 85)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(center)
	var icon := Icon.new()
	icon.setup(kind, INK, 34.0)
	center.add_child(icon)
	return button

# ---------------------------------------------------------------------------
# Text
# ---------------------------------------------------------------------------

## Small label above a block ("LIVE RACE", "ALL CREWS"). No letter spacing.
func make_kicker(text: String, icon_kind: StringName = &"") -> Control:
	var label := _make_base_label(text, SIZE_SMALL, LILAC)
	label.add_theme_font_override("font", _bold())
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	if icon_kind == &"":
		return label
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var icon := Icon.new()
	icon.setup(icon_kind, LILAC, 26.0)
	row.add_child(icon)
	row.add_child(label)
	return row

func make_h1(text: String) -> Label:
	var label := outlined_title(text, CREAM, 64)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	return label

func make_h2(text: String, size: int = SIZE_BODY) -> Label:
	var label := _make_base_label(text, size, CREAM)
	label.add_theme_font_override("font", _bold())
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	return label

## Secondary copy (wraps inside its column).
func make_sub(text: String, size: int = SIZE_SMALL) -> Label:
	var label := _make_base_label(text, size, LILAC)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label

# ---------------------------------------------------------------------------
# Stats, bars, segmented controls
# ---------------------------------------------------------------------------

## A stat tile: value + label, e.g. best score / games played.
func make_stat(value: String, label_text: String) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", _tile_style())
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	panel.add_child(column)
	var value_label := _make_base_label(value, 48, CREAM)
	value_label.add_theme_font_override("font", _bold())
	column.add_child(value_label)
	var name_label := _make_base_label(label_text, SIZE_SMALL, LILAC)
	column.add_child(name_label)
	return panel

## Segmented control: options = [{"key": StringName, "text": String}].
func make_segmented(options: Array, active: StringName, on_select: Callable) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = CARD_INNER
	style.set_corner_radius_all(30)
	style.set_border_width_all(6)
	style.border_color = INK
	style.content_margin_left = 6.0
	style.content_margin_right = 6.0
	style.content_margin_top = 6.0
	style.content_margin_bottom = 12.0
	panel.add_theme_stylebox_override("panel", style)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	panel.add_child(row)
	for option in options:
		var key: StringName = option.get("key", &"")
		var button := Button.new()
		button.text = String(option.get("text", ""))
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.custom_minimum_size = Vector2(0, 62)
		button.focus_mode = Control.FOCUS_NONE
		button.add_theme_font_override("font", _bold())
		button.add_theme_font_size_override("font_size", SIZE_SMALL)
		var active_now := key == active
		button.add_theme_stylebox_override("normal", _seg_style(active_now))
		button.add_theme_stylebox_override("hover", _seg_style(active_now))
		button.add_theme_stylebox_override("pressed", _seg_style(true))
		button.add_theme_stylebox_override("focus", _seg_style(active_now))
		button.add_theme_color_override("font_color", INK if active_now else LILAC)
		button.add_theme_color_override("font_hover_color", INK if active_now else CREAM)
		button.add_theme_color_override("font_pressed_color", INK)
		bind_press(button, func() -> void: on_select.call(key))
		row.add_child(button)
	return panel

# ---------------------------------------------------------------------------
# Buttons (legacy navigation helpers kept working until screens are rebuilt)
# ---------------------------------------------------------------------------

func make_button(text: String, target: StringName, payload: Dictionary = {}) -> Button:
	var button := _make_base_button(text, "ghost")
	bind_press(button, func() -> void: navigate.emit(target, payload))
	return button

func make_action_button(text: String, action: Callable) -> Button:
	return primary_button(text, action)

func make_ghost_action_button(text: String, action: Callable) -> Button:
	return secondary_button(text, action)

# ---------------------------------------------------------------------------
# Misc
# ---------------------------------------------------------------------------

## Rounded text input matching the sticker kit.
func make_input(placeholder: String, text: String = "", max_length: int = 18) -> LineEdit:
	var input := LineEdit.new()
	input.placeholder_text = placeholder
	input.text = text
	input.max_length = max_length
	input.add_theme_font_override("font", _bold())
	input.add_theme_font_size_override("font_size", SIZE_SMALL)
	input.add_theme_color_override("font_color", CREAM)
	input.add_theme_color_override("font_placeholder_color", LILAC)
	input.add_theme_color_override("caret_color", GOLD)
	var style := StyleBoxFlat.new()
	style.bg_color = CARD_INNER
	style.set_corner_radius_all(22)
	style.set_border_width_all(6)
	style.border_color = INK
	style.content_margin_left = 22.0
	style.content_margin_right = 22.0
	style.content_margin_top = 14.0
	style.content_margin_bottom = 20.0
	input.add_theme_stylebox_override("normal", style)
	input.add_theme_stylebox_override("focus", style)
	return input

## Shared pointer tracker for every interactive control on a page. Buttons and
## tappable cards pass pointer events through to the page scroll (mouse_filter
## PASS) and consult this state so a press only counts when the finger moved
## less than `DRAG_DEADZONE` px. `on_tap` (optional) fires once on release.
static func track_gesture(control: Control, on_tap: Callable = Callable()) -> Dictionary:
	var state := {"origin": Vector2.ZERO, "active": false, "dragged": false, "tapped": false}
	control.gui_input.connect(func(event: InputEvent) -> void:
		var position := Vector2.INF
		var pressed := false
		var released := false
		if event is InputEventScreenTouch:
			position = event.position
			pressed = event.pressed
			released = not event.pressed
		elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			position = event.position
			pressed = event.pressed
			released = not event.pressed
		elif event is InputEventScreenDrag or event is InputEventMouseMotion:
			position = event.position
		if pressed:
			state["origin"] = position
			state["active"] = true
			state["dragged"] = false
			state["tapped"] = false
			return
		if not state["active"] or position == Vector2.INF:
			return
		if position.distance_to(state["origin"]) >= DRAG_DEADZONE:
			state["dragged"] = true
		if released:
			state["active"] = false
			if not state["dragged"] and not state["tapped"] and on_tap.is_valid():
				state["tapped"] = true
				on_tap.call(state["origin"]))
	return state

## Wires a Button so drags bubble to the page scroll and a press whose finger
## travelled past the deadzone is dropped instead of firing the action.
func bind_press(button: Button, action: Callable) -> void:
	button.mouse_filter = Control.MOUSE_FILTER_PASS
	var gesture := track_gesture(button)
	button.pressed.connect(func() -> void:
		if not bool(gesture["dragged"]):
			action.call())

## Makes a whole card/panel/row tappable (mouse + touch) like a big button.
## Taps fire on release only, never after a drag, and an inline button wins the
## tap so the card does not double-fire.
func make_tappable(control: Control, action: Callable) -> void:
	control.mouse_filter = Control.MOUSE_FILTER_PASS
	track_gesture(control, func(origin: Vector2) -> void:
		if not _point_on_button(control, control.get_global_transform() * origin):
			action.call())
	control.mouse_entered.connect(func() -> void: control.modulate = Color(1.06, 1.05, 1.0))
	control.mouse_exited.connect(func() -> void: control.modulate = Color.WHITE)

## True when a descendant BaseButton covers `global_point` (canvas coordinates).
func _point_on_button(node: Node, global_point: Vector2) -> bool:
	for child in node.get_children():
		if child is BaseButton:
			var button := child as BaseButton
			var local_point: Vector2 = button.get_global_transform().affine_inverse() * global_point
			if button.is_visible_in_tree() and Rect2(Vector2.ZERO, button.size).has_point(local_point):
				return true
		if child is Control and _point_on_button(child, global_point):
			return true
	return false

func make_spacer(height: float = 12.0) -> Control:
	var spacer := Control.new()
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	spacer.custom_minimum_size = Vector2(0, height)
	return spacer

## Centers a control inside expanding containers.
func make_center(control: Control) -> CenterContainer:
	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(control)
	return center

## Thousands-separated integer for stats and scores.
static func fmt(value: int) -> String:
	var text := str(absi(value))
	var out := ""
	var count := 0
	for i in range(text.length() - 1, -1, -1):
		out = text[i] + out
		count += 1
		if count % 3 == 0 and i > 0:
			out = "," + out
	return ("-" if value < 0 else "") + out

## Quick page entrance: fade + slight rise. Called by AppFlow after `setup`.
func play_intro() -> void:
	if _page_root == null or not is_inside_tree():
		return
	_page_root.modulate.a = 0.0
	_page_root.scale = Vector2(0.99, 0.99)
	_page_root.pivot_offset = _page_root.size * 0.5
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(_page_root, "modulate:a", 1.0, 0.2)
	tween.tween_property(_page_root, "scale", Vector2.ONE, 0.24) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

## Slow idle breathing for hero art (safe inside containers: scale only).
func breathe(node: Control, amount: float = 0.025, duration: float = 1.8) -> void:
	node.pivot_offset = node.size * 0.5
	var tween := node.create_tween().set_loops()
	tween.tween_property(node, "scale", Vector2.ONE * (1.0 + amount), duration) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(node, "scale", Vector2.ONE, duration) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

## Subtle scale pulse for a primary call to action (1.00 ↔ 1.03).
func pulse(node: Control, duration: float = 0.9) -> void:
	node.resized.connect(func() -> void: node.pivot_offset = node.size * 0.5)
	node.pivot_offset = node.size * 0.5
	var tween := node.create_tween().set_loops()
	tween.tween_property(node, "scale", Vector2.ONE * 1.03, duration) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(node, "scale", Vector2.ONE, duration) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

# ---------------------------------------------------------------------------
# Internals
# ---------------------------------------------------------------------------

func _bold() -> Font:
	if _bold_font == null:
		_bold_font = load(BOLD_FONT_PATH) as Font
	return _bold_font

func _make_base_label(text: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	return label

func _chip_label(text: String) -> Label:
	var label := _make_base_label(text, SIZE_SMALL, INK)
	label.add_theme_font_override("font", _bold())
	return label

func _make_base_button(text: String, variant: String) -> Button:
	match variant:
		"primary":
			return primary_button(text, func() -> void: pass, 96.0, SIZE_BODY)
		"danger":
			var danger := _kit_button(text, CORAL, INK, SIZE_BODY, 7, 40, 13)
			danger.custom_minimum_size = Vector2(0, 96)
			return danger
		_:
			return secondary_button(text, func() -> void: pass, 96.0, SIZE_BODY)

## Ledge button: INK border + solid bottom ledge; pressed sinks without resizing.
func _kit_button(text: String, fill: Color, text_color: Color, font_size: int, border: int, radius: int, ledge: int) -> Button:
	var button := Button.new()
	button.text = text
	button.mouse_filter = Control.MOUSE_FILTER_PASS
	button.focus_mode = Control.FOCUS_NONE
	# A long crew name ellipsizes inside the button instead of widening it past
	# the page (screens still set explicit widths where the layout needs it).
	button.clip_text = true
	button.add_theme_font_override("font", _bold())
	button.add_theme_font_size_override("font_size", font_size)
	button.add_theme_stylebox_override("normal", _button_style(fill, border, radius, ledge, false))
	button.add_theme_stylebox_override("hover", _button_style(fill.lightened(0.06), border, radius, ledge, false))
	button.add_theme_stylebox_override("pressed", _button_style(fill.darkened(0.06), border, radius, ledge, true))
	button.add_theme_stylebox_override("focus", _button_style(fill, border, radius, ledge, false))
	button.add_theme_color_override("font_color", text_color)
	button.add_theme_color_override("font_hover_color", text_color)
	button.add_theme_color_override("font_pressed_color", text_color)
	button.add_theme_color_override("font_focus_color", text_color)
	button.add_theme_constant_override("h_separation", 12)
	return button

func _button_style(fill: Color, border: int, radius: int, ledge: int, pressed: bool) -> StyleBoxFlat:
	var style := _ledge(fill, border, radius, 0 if pressed else ledge)
	style.content_margin_left = 26.0
	style.content_margin_right = 26.0
	style.content_margin_top = 20.0 + (float(ledge) if pressed else 0.0)
	style.content_margin_bottom = 20.0
	return style

func _seg_style(active: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = GOLD if active else Color(0, 0, 0, 0)
	style.set_corner_radius_all(22)
	style.set_border_width_all(6 if active else 0)
	style.border_color = INK
	style.content_margin_top = 8.0
	style.content_margin_bottom = 8.0
	return style

func _card_style(accent: Color = Color.TRANSPARENT) -> StyleBoxFlat:
	var style := _ledge(CARD, 7, 40, 9)
	if accent != Color.TRANSPARENT:
		style.border_color = accent
	return style

func _tile_style() -> StyleBoxFlat:
	var style := _ledge(CARD_INNER, 6, 30, 6)
	style.content_margin_left = 20.0
	style.content_margin_right = 20.0
	style.content_margin_top = 18.0
	style.content_margin_bottom = 18.0
	return style

func _pill_style(fill: Color, border: int, ledge: int) -> StyleBoxFlat:
	var style := _ledge(fill, border, 999, ledge)
	style.content_margin_left = 24.0
	style.content_margin_right = 24.0
	style.content_margin_top = 8.0
	style.content_margin_bottom = 8.0
	return style

func _section_header_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0)
	style.content_margin_left = 26.0
	style.content_margin_right = 26.0
	style.content_margin_top = 22.0
	style.content_margin_bottom = 22.0
	return style

func _header_hover_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(1, 1, 1, 0.06)
	style.set_corner_radius_all(40)
	return style

func _header_pressed_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.16)
	style.set_corner_radius_all(40)
	return style

func _ledge(fill: Color, border: int, radius: int, ledge: int, border_color: Color = INK) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.set_corner_radius_all(radius)
	style.border_color = border_color
	style.set_border_width_all(border)
	style.border_width_bottom = border + ledge
	return style

func _expander() -> Control:
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return spacer

func _set_section_open(margin: MarginContainer, body: VBoxContainer, chevron: Icon, open: bool, animate: bool) -> void:
	chevron.rotation = PI if open else 0.0
	if not animate:
		body.visible = open
		margin.custom_minimum_size.y = 0.0
		return
	if open:
		body.visible = true
		var target := margin.get_combined_minimum_size().y
		margin.custom_minimum_size.y = 0.0
		var tween := margin.create_tween()
		tween.tween_property(margin, "custom_minimum_size:y", target, 0.22) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tween.tween_callback(func() -> void: margin.custom_minimum_size.y = 0.0)
	else:
		margin.custom_minimum_size.y = margin.size.y
		var tween := margin.create_tween()
		tween.tween_property(margin, "custom_minimum_size:y", 0.0, 0.22) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tween.tween_callback(func() -> void: body.visible = false)

func _podium_column(row: Dictionary, place: int, mine_id: StringName) -> VBoxContainer:
	var heights := [315.0, 222.0, 167.0]
	var colors := [GOLD, SILVER, BRONZE]
	var mascot_sizes := [226.0, 192.0, 178.0]
	var number_sizes := [70, 56, 48]

	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.alignment = BoxContainer.ALIGNMENT_END
	column.add_theme_constant_override("separation", 8)

	if place == 0:
		var crown := crown_icon(44.0)
		crown.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		column.add_child(crown)

	var community: CommunityDefinition = row.get("community")
	if community != null and community.mascot != null and community.mascot.idle_texture != null:
		var preview := MascotPreview.new()
		preview.setup(community, mascot_sizes[place])
		column.add_child(make_center(preview))

	var block := PanelContainer.new()
	block.mouse_filter = Control.MOUSE_FILTER_IGNORE
	block.custom_minimum_size = Vector2(0, heights[place])
	var style := StyleBoxFlat.new()
	style.bg_color = colors[place]
	style.set_corner_radius_all(30)
	style.corner_radius_bottom_left = 0
	style.corner_radius_bottom_right = 0
	style.set_border_width_all(7)
	style.border_width_bottom = 0
	style.border_color = INK
	style.content_margin_left = 12.0
	style.content_margin_right = 12.0
	style.content_margin_top = 16.0
	style.content_margin_bottom = 12.0
	block.add_theme_stylebox_override("panel", style)
	column.add_child(block)

	var content := VBoxContainer.new()
	content.alignment = BoxContainer.ALIGNMENT_BEGIN
	content.add_theme_constant_override("separation", 4)
	block.add_child(content)
	var rank_label := _make_base_label(str(int(row.get("rank", place + 1))), number_sizes[place], INK)
	rank_label.add_theme_font_override("font", _bold())
	content.add_child(rank_label)
	var name_label := _make_base_label(String(row.get("name", "")), 33 if place == 0 else 28, INK)
	name_label.add_theme_font_override("font", _bold())
	content.add_child(name_label)
	var score_label := _make_base_label(fmt(int(row.get("score", 0))), 31 if place == 0 else 28, INK)
	score_label.add_theme_font_override("font", _bold())
	content.add_child(score_label)
	if mine_id != &"" and StringName(row.get("id", "")) == mine_id:
		var yours := PanelContainer.new()
		yours.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var yours_style := StyleBoxFlat.new()
		yours_style.bg_color = INK
		yours_style.set_corner_radius_all(999)
		yours_style.content_margin_left = 18.0
		yours_style.content_margin_right = 18.0
		yours_style.content_margin_top = 4.0
		yours_style.content_margin_bottom = 4.0
		yours.add_theme_stylebox_override("panel", yours_style)
		yours.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		var yours_label := _make_base_label("YOUR CREW", SIZE_SMALL - 2, YOURS)
		yours_label.add_theme_font_override("font", _bold())
		yours.add_child(yours_label)
		content.add_child(yours)
	return column
