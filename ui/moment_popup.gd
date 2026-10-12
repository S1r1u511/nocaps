extends UiScreen
class_name MomentPopup

## Renders the three scoreboard/pride popup surfaces from `meta/moments.gd`
## (docs/15 §3, brief §2). Code-built — no scene. Add one `MomentPopup` under a
## CanvasLayer (or a screen) at full rect; it positions each surface itself and
## consumes the moment via `Moments.dismiss()` when it ends.
##
## - `run_toast`: compact, top of screen, 1.8 s, never centered, mouse IGNORE so
##   it never blocks a tap on the run HUD.
## - `result_card`: slides up over the lower half, 3 s or tap; `build_row()` docks
##   the same content as an inline row.
## - `home_banner`: slides in above an optional `anchor` control, auto-dismiss.
##
## SCOREBOARD moments use gold/red accents, PRIDE moments green/gold (brief §1).
## Reduced motion skips every tween and shows the surface instantly.

signal dismissed(id: String)

const RUN_TOAST_SECONDS := 1.8
const RESULT_CARD_SECONDS := 3.0
const HOME_BANNER_SECONDS := 4.0
const SIDE_MARGIN := 24.0
const MAX_WIDTH := 660.0
## Mockup `live_run.html` card is 350/390 of the width (×1.85 ≈ 648 at 720).
const RUN_TOAST_MAX_RATIO := 0.9
## Mockup run-toast type/art (mockup px × 1.85): title 55, detail 26, mascot 118.
const RUN_TOAST_TITLE_SIZE := 55
const RUN_TOAST_DETAIL_SIZE := 26
const RUN_TOAST_ICON_SIZE := 118.0
## Viewport px kept clear under the top HUD band for the run toast.
const HUD_BAND := 150.0

## At most one card may be on screen at a time. Extra requests wait here until
## the live card has fully faded and freed; nothing ever stacks.
var _live: Array[Control] = []
var _queue: Array = []


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var moments := Moments.instance()
	if not moments.enabled_changed.is_connected(_on_moments_enabled_changed):
		moments.enabled_changed.connect(_on_moments_enabled_changed)


## True while a card (toast, result card or banner) is on screen. A new popup
## request is held in `_queue` until this goes false.
func is_showing() -> bool:
	return not _live.is_empty()


## Dispatches a moment to its surface, honoring the one-at-a-time rule.
## `board_row` moments are composed by the Board screen via `build_row()`; a
## popup ignores them.
func show_moment(moment: Dictionary, options: Dictionary = {}) -> void:
	if moment.is_empty() or not Moments.is_enabled():
		return
	var kind := StringName(moment.get("surface", &""))
	match kind:
		&"run_toast", &"result_card", &"home_banner":
			_enqueue(kind, moment, options)
		_:
			_complete(moment)


## Compact centered top toast below the HUD pills; 1.8 s; never blocks input.
## `options.top_offset` (viewport px) overrides the HUD band clearance.
func show_run_toast(moment: Dictionary, options: Dictionary = {}) -> void:
	if not Moments.is_enabled():
		return
	_enqueue(&"run_toast", moment, options)


## Lower-half card; 3 s or tap to dismiss.
func show_result_card(moment: Dictionary, options: Dictionary = {}) -> void:
	if not Moments.is_enabled():
		return
	_enqueue(&"result_card", moment, options)


## Banner above `options.anchor` (or near the top); auto-dismiss.
func show_home_banner(moment: Dictionary, options: Dictionary = {}) -> void:
	if not Moments.is_enabled():
		return
	_enqueue(&"home_banner", moment, options)


## The master switch went off: drop every queued/live card so no moment UI can
## survive the toggle.
func _on_moments_enabled_changed(enabled: bool) -> void:
	if enabled:
		return
	for card in _live:
		if not is_instance_valid(card):
			continue
		var id := String(card.get_meta(&"moment_id", ""))
		card.queue_free()
		if not id.is_empty():
			Moments.dismiss(id)
			dismissed.emit(id)
	_live.clear()
	_queue.clear()


# ---------------------------------------------------------------------------
# One-at-a-time scheduling
# ---------------------------------------------------------------------------

## Shows immediately when nothing is live, otherwise waits its turn.
func _enqueue(kind: StringName, moment: Dictionary, options: Dictionary) -> void:
	if _live.is_empty():
		_present(kind, moment, options)
		return
	_queue.append({"kind": kind, "moment": moment, "options": options})


func _present(kind: StringName, moment: Dictionary, options: Dictionary) -> void:
	match kind:
		&"run_toast":
			_present_run_toast(moment, options)
		&"result_card":
			_present_result_card(moment, options)
		&"home_banner":
			_present_home_banner(moment, options)


## Promotes the oldest waiting request once the live card is gone, so the rule
## holds for every surface combination.
func _drain() -> void:
	if not _live.is_empty() or _queue.is_empty():
		return
	var next: Dictionary = _queue.pop_front()
	_present(StringName(next["kind"]), next["moment"], next["options"])


func _present_run_toast(moment: Dictionary, options: Dictionary) -> void:
	# Fixed mockup band: a full-width sticker card with the crew mascot, title 55
	# and detail 26 (audit A P1-2). The width is pinned (never hugged to the text)
	# and both labels ellipsize, so the card height stays inside the band between
	# the "TRAPS" toast and the feedback lane.
	var card := _run_toast_panel(moment)
	var width := minf(_screen().x * RUN_TOAST_MAX_RATIO, MAX_WIDTH)
	var top_offset := float(options.get("top_offset", HUD_BAND))
	_place(card, Vector2((_screen().x - width) * 0.5, ShellUI.safe_top + top_offset), width)
	_run(card, moment, RUN_TOAST_SECONDS, bool(_reduced(options)), true)


func _present_result_card(moment: Dictionary, options: Dictionary) -> void:
	var card := _moment_panel(moment, false)
	var y := _screen().y - ShellUI.safe_bottom - px(360) - card.get_combined_minimum_size().y
	_place(card, Vector2((_screen().x - _width()) * 0.5, maxf(ShellUI.safe_top + px(12), y)))
	_tap_to_dismiss(card, moment)
	_run(card, moment, RESULT_CARD_SECONDS, bool(_reduced(options)), false)


func _present_home_banner(moment: Dictionary, options: Dictionary) -> void:
	var card := _moment_panel(moment, true)
	var anchor: Variant = options.get("anchor", null)
	var y := ShellUI.safe_top + px(10)
	if anchor != null and anchor is Control and is_instance_valid(anchor):
		y = maxf(
			ShellUI.safe_top + px(6),
			(anchor as Control).get_global_rect().position.y - px(20) - card.get_combined_minimum_size().y
		)
	_place(card, Vector2((_screen().x - _width()) * 0.5, y))
	_run(card, moment, HOME_BANNER_SECONDS, bool(_reduced(options)), true)


## The same content as an inline row (Result card can dock into a list).
func build_row(moment: Dictionary) -> Control:
	return _moment_panel(moment, true)


# ---------------------------------------------------------------------------
# Panel construction
# ---------------------------------------------------------------------------

func _moment_panel(moment: Dictionary, compact: bool) -> PanelContainer:
	var accent := _accent(moment)
	var dark := accent == LIVE
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", _moment_style(accent))

	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", int(px(14)))
	panel.add_child(row)

	row.add_child(_moment_icon(moment))

	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 2)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(column)

	var text_color := CREAM if dark else INK
	var title := _make_base_label(String(moment.get("title", "")), 40 if not compact else 34, text_color)
	title.add_theme_font_override("font", _bold())
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	column.add_child(title)

	var detail := String(moment.get("detail", ""))
	if not detail.is_empty():
		var detail_label := _make_base_label(detail, 26 if not compact else 24,
			CORAL if dark else Color(INK.r, INK.g, INK.b, 0.78))
		detail_label.add_theme_font_override("font", _bold())
		detail_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		column.add_child(detail_label)

	return panel


## The run toast only: mockup `live_run.html` proportions — mascot 118, title 55,
## detail 26 — inside a fixed-height card (no wrap; long copy ellipsizes).
func _run_toast_panel(moment: Dictionary) -> PanelContainer:
	var accent := _accent(moment)
	var dark := accent == LIVE
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", _run_toast_style(accent))

	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", int(px(12)))
	panel.add_child(row)
	row.add_child(_run_toast_icon(moment))

	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", int(px(2)))
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(column)

	var text_color := CREAM if dark else INK
	column.add_child(_run_toast_label(String(moment.get("title", "")), RUN_TOAST_TITLE_SIZE, text_color))
	var detail := String(moment.get("detail", ""))
	if not detail.is_empty():
		column.add_child(_run_toast_label(detail, RUN_TOAST_DETAIL_SIZE,
			CORAL if dark else Color(INK.r, INK.g, INK.b, 0.78)))
	return panel


func _run_toast_label(text: String, size: int, color: Color) -> Label:
	var label := _make_base_label(text, size, color)
	label.add_theme_font_override("font", _bold())
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	# One line, ellipsized: the card height must never grow past its band.
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	label.clip_text = true
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.custom_minimum_size.x = 0.0
	return label


## Crew mascot at the mockup's 118 px, falling back to the accent glyph when no
## community is resolved (tests, empty roster).
func _run_toast_icon(moment: Dictionary) -> Control:
	var wrap := Control.new()
	wrap.custom_minimum_size = Vector2(RUN_TOAST_ICON_SIZE, RUN_TOAST_ICON_SIZE)
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var texture := _mascot_texture()
	if texture != null:
		var art := TextureRect.new()
		art.texture = texture
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		art.set_anchors_preset(Control.PRESET_FULL_RECT)
		wrap.add_child(art)
		return wrap
	var icon: Icon
	if String(moment.get("emotion", "")) == Moments.EMOTION_PRIDE:
		icon = crown_icon(96.0)
	elif String(moment.get("accent", "")) == "red":
		icon = live_dot(48.0)
	else:
		icon = crown_icon(96.0, INK)
	icon.set_anchors_preset(Control.PRESET_CENTER)
	wrap.add_child(icon)
	return wrap


func _mascot_texture() -> Texture2D:
	if save_manager == null or save_manager.selected_community_id == &"":
		return null
	var entry := CommunityRepository.by_id(CommunityRepository.load_roster(), save_manager.selected_community_id)
	if entry == null or entry.mascot == null:
		return null
	return entry.mascot.idle_texture


## Run toast sticker: tight vertical padding so the 118 px art + title 55 fit
## inside the fixed band above the feedback lane.
func _run_toast_style(accent: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	if accent == LIVE:
		style.bg_color = INK
		style.border_color = LIVE
	else:
		style.bg_color = accent
		style.border_color = INK
	style.set_border_width_all(7)
	style.border_width_bottom = 13
	style.set_corner_radius_all(41)
	style.content_margin_left = 22.0
	style.content_margin_right = 22.0
	style.content_margin_top = 10.0
	style.content_margin_bottom = 10.0
	return style


func _moment_style(accent: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	if accent == LIVE:
		style.bg_color = INK
		style.border_color = LIVE
		style.set_border_width_all(6)
		style.set_corner_radius_all(32)
		style.border_width_bottom = 12
	else:
		style.bg_color = accent
		style.border_color = INK
		style.set_border_width_all(7)
		style.set_corner_radius_all(40)
		style.border_width_bottom = 16
	style.content_margin_left = 26.0
	style.content_margin_right = 26.0
	style.content_margin_top = 18.0
	style.content_margin_bottom = 24.0
	return style


func _moment_icon(moment: Dictionary) -> Control:
	var wrap := Control.new()
	wrap.custom_minimum_size = Vector2(52, 52)
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var icon: Icon
	if String(moment.get("emotion", "")) == Moments.EMOTION_PRIDE:
		icon = crown_icon(48.0)
	elif String(moment.get("accent", "")) == "red":
		icon = live_dot(24.0)
	else:
		icon = crown_icon(44.0, INK)
	icon.set_anchors_preset(Control.PRESET_CENTER)
	wrap.add_child(icon)
	return wrap


# ---------------------------------------------------------------------------
# Placement + lifecycle
# ---------------------------------------------------------------------------

func _place(card: Control, top_left: Vector2, width: float = -1.0) -> void:
	card.position = top_left
	card.size = Vector2(width if width > 0.0 else _width(), card.get_combined_minimum_size().y)
	add_child(card)
	_live.append(card)


## Lets a width-capped toast wrap its copy instead of forcing a wider panel.
func _clamp_labels(node: Node) -> void:
	for child in node.get_children():
		if child is Label:
			(child as Label).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			(child as Label).custom_minimum_size.x = 0.0
		_clamp_labels(child)


func _run(card: Control, moment: Dictionary, hold: float, reduced: bool, from_top: bool) -> void:
	card.set_meta(&"moment_id", String(moment.get("id", "")))
	var state := {"done": false}
	var finish := func() -> void:
		if bool(state["done"]):
			return
		state["done"] = true
		_complete(moment, card)
	if reduced:
		card.modulate.a = 1.0
		await get_tree().create_timer(hold).timeout
		finish.call()
		return
	var target_y := card.position.y
	card.modulate.a = 0.0
	card.position.y = target_y + (-26.0 if from_top else 26.0)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(card, "modulate:a", 1.0, 0.16)
	tween.tween_property(card, "position:y", target_y, 0.2) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.chain().tween_interval(hold)
	tween.chain().tween_property(card, "modulate:a", 0.0, 0.18)
	tween.parallel().tween_property(card, "position:y", target_y + (-18.0 if from_top else 18.0), 0.18)
	tween.chain().tween_callback(finish)


func _tap_to_dismiss(card: Control, moment: Dictionary) -> void:
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.gui_input.connect(func(event: InputEvent) -> void:
		var pressed := false
		if event is InputEventScreenTouch:
			pressed = event.pressed
		elif event is InputEventMouseButton:
			pressed = event.pressed and event.button_index == MOUSE_BUTTON_LEFT
		if pressed:
			_complete(moment, card))


func _complete(moment: Dictionary, card: Control = null) -> void:
	if card != null and is_instance_valid(card):
		_live.erase(card)
		card.queue_free()
	Moments.dismiss(String(moment.get("id", "")))
	dismissed.emit(String(moment.get("id", "")))
	_drain()


func _reduced(options: Dictionary) -> bool:
	if options.has("reduced_motion"):
		return bool(options["reduced_motion"])
	return save_manager != null and save_manager.reduced_motion


func _accent(moment: Dictionary) -> Color:
	match String(moment.get("accent", "gold")):
		"green":
			return YOURS
		"red":
			return LIVE
		_:
			return GOLD


func _width() -> float:
	return minf(_screen().x - SIDE_MARGIN * 2.0, MAX_WIDTH)


func _screen() -> Vector2:
	var current := size
	if current.x <= 0.0 or current.y <= 0.0:
		current = get_viewport_rect().size
	return current
