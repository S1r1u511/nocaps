extends CanvasLayer

## Debug-only in-run tuning panel, opened by the run's DEV button and shown only
## with the `nocaps_dev` feature. It pauses the run, edits the live `RunTuning`,
## and never writes the authored resource. Changes are live until a preset is
## loaded or the game is restarted. See docs/07_TUNING_GUIDE.md.
##
## Getting tunings back into the repo:
##   1. Tune on the phone, then press EXPORT (also copies the JSON to the
##      clipboard and writes user://dev_preset_export.json).
##   2. Pull the exported file off a connected debug build:
##        adb exec-out run-as com.nocapsfun.game.dev \
##          cat files/dev_preset_export.json > /tmp/dev_preset_export.json
##      (`user://` resolves to /data/data/com.nocapsfun.game.dev/files on Android;
##      a rooted device can `adb pull` that path directly, and a release build
##      cannot be read with run-as.)
##   3. Bake it into the authored default:
##        "$HOME/Downloads/Godot.app/Contents/MacOS/Godot" --headless \
##          --path . --script res://tools/import_preset.gd -- /tmp/dev_preset_export.json
##
## Presets (up to PRESET_LIMIT) live in user://dev_presets.json; the active
## preset and the live working snapshot persist across relaunches so a tuning
## session survives a restart. Quick tests are dev affordances, never rules.

const PRESETS_PATH := "user://dev_presets.json"
const EXPORT_PATH := "user://dev_preset_export.json"
const PRESET_LIMIT := 20
const DEFAULT_TUNING_PATH := "res://data/tuning/default_run_tuning.tres"

const INK := Color("1d1033")
const CARD := Color("241640")
const CARD_INNER := Color("35205c")
const GOLD := Color("ffd23f")
const CREAM := Color("fff4dc")
const MUTED := Color("b9a6d8")

## Numeric fields, grouped into collapsible sections. Entry format:
##   [label, field, min, max, step]
## Colors (target_accent, rival_color, hazard_color) are not sliders but still
## round-trip through presets and EXPORT.
const SECTIONS := [
	{
		"title": "PHYSICS",
		"expanded": true,
		"fields": [
			["CAP X", "cap_x", 100.0, 400.0, 5.0],
			["START Y", "start_y", 200.0, 1000.0, 10.0],
			["GRAVITY", "gravity", 1200.0, 4200.0, 50.0],
			["FLAP", "flap_impulse", 400.0, 1200.0, 10.0],
			["BOUNCE", "bounce_impulse", 400.0, 1400.0, 10.0],
			["MAX FALL", "max_fall_speed", 800.0, 2200.0, 25.0],
			["CAP RADIUS", "cap_radius", 8.0, 48.0, 1.0],
			["TILT UP", "tilt_up", 0.0, 1.5, 0.05],
			["TILT DOWN", "tilt_down", 0.0, 1.5, 0.05],
			["ROT FOLLOW", "rotation_follow", 0.0, 30.0, 1.0],
			["FLAP SNAP", "flap_rotation_snap", 0.0, 1.0, 0.01],
			["LAND SNAP", "land_rotation_snap", 0.0, 1.0, 0.01],
		],
	},
	{
		"title": "SPACING",
		"expanded": false,
		"fields": [
			["LINE Y", "mascot_line_y", 400.0, 1100.0, 10.0],
			["TARGET VAR", "target_line_variance", 0.0, 120.0, 5.0],
			["RIVAL VAR", "rival_line_variance", 0.0, 160.0, 5.0],
			["WORLD SIZE", "mascot_world_size", 80.0, 260.0, 5.0],
			["BODY RATIO", "mascot_body_radius_ratio", 0.1, 0.6, 0.01],
			["OPEN MIN", "gap_time_opening_min", 0.8, 4.0, 0.05],
			["OPEN MAX", "gap_time_opening_max", 0.8, 4.0, 0.05],
			["EARLY MIN", "gap_time_early_min", 0.8, 3.0, 0.05],
			["EARLY MAX", "gap_time_early_max", 0.8, 3.5, 0.05],
			["MID MIN", "gap_time_mid_min", 0.7, 2.5, 0.05],
			["MID MAX", "gap_time_mid_max", 0.7, 3.0, 0.05],
			["LATE MIN", "gap_time_late_min", 0.6, 2.5, 0.05],
			["LATE MAX", "gap_time_late_max", 0.7, 3.0, 0.05],
			["MID @ LAND", "gap_phase_mid_landings", 0.0, 20.0, 1.0],
			["LATE @ LAND", "gap_phase_late_landings", 0.0, 40.0, 1.0],
			["OPEN TARGETS", "opening_targets", 0.0, 10.0, 1.0],
			["RIVALS EARLY", "max_rivals_early", 0.0, 6.0, 1.0],
			["RIVALS MID", "max_rivals_mid", 0.0, 6.0, 1.0],
			["RIVALS LATE", "max_rivals_late", 0.0, 6.0, 1.0],
			["MAX INTERVAL", "target_max_interval", 1.0, 10.0, 0.5],
			["MAX DISTANCE", "target_max_distance", 800.0, 8000.0, 100.0],
		],
	},
	{
		"title": "SPEED RAMP",
		"expanded": false,
		"fields": [
			["BASE SPEED", "base_scroll_speed", 150.0, 600.0, 10.0],
			["SPEED / LAND", "speed_gain_per_landing", 0.0, 0.5, 0.01],
			["SPEED / SEC", "speed_gain_per_second", 0.0, 0.1, 0.005],
			["MAX SPEED x", "max_scroll_multiplier", 1.0, 4.0, 0.1],
			["EASE IN (s)", "speed_ease_in_seconds", 0.0, 40.0, 1.0],
			["EASE START", "speed_ease_in_start", 0.4, 1.2, 0.02],
		],
	},
	{
		"title": "CAMERA",
		"expanded": false,
		"fields": [
			["ZOOM", "camera_zoom", 0.6, 1.0, 0.01],
		],
	},
	{
		"title": "LANDING / SCORING",
		"expanded": false,
		"fields": [
			["PERFECT HEAD", "perfect_head_ratio", 0.1, 1.0, 0.05],
		],
	},
	{
		"title": "HAZARDS",
		"expanded": false,
		"fields": [
			["START DELAY", "hazard_start_delay", 0.0, 15.0, 0.5],
			["RAMP (s)", "hazard_ramp_seconds", 5.0, 60.0, 1.0],
			["INT MIN", "hazard_interval_min", 0.3, 3.0, 0.05],
			["INT MIN TIGHT", "hazard_interval_min_tight", 0.2, 2.0, 0.05],
			["INT MAX", "hazard_interval_max", 0.5, 4.0, 0.05],
			["INT MAX TIGHT", "hazard_interval_max_tight", 0.3, 3.0, 0.05],
			["MAX TRAPS", "hazard_max_concurrent", 1.0, 10.0, 1.0],
			["RADIUS", "hazard_radius", 8.0, 48.0, 1.0],
			["CLEAR MASCOT", "hazard_clear_from_mascots", 0.0, 400.0, 10.0],
			["CLEAR SPAWN", "hazard_clear_from_next_spawn", 0.0, 500.0, 10.0],
			["SPACING X", "hazard_min_spacing_x", 40.0, 500.0, 10.0],
			["SPACING Y", "hazard_min_spacing_y", 40.0, 400.0, 10.0],
			["SAFE AFTER", "hazard_safe_after_mascot", 0.0, 2.0, 0.05],
		],
	},
	{
		"title": "FAIRNESS",
		"expanded": false,
		"fields": [
			["SKIP GRACE", "skip_penalty_grace", 0.0, 30.0, 0.5],
		],
	},
	{
		"title": "SURPRISE SPIKE",
		"expanded": false,
		"fields": [
			["ZONE %", "surprise_ceiling_zone", 0.05, 0.4, 0.01],
			["DWELL (s)", "surprise_ceiling_dwell", 0.1, 1.5, 0.05],
			["TELEGRAPH", "surprise_ceiling_telegraph", 0.1, 1.0, 0.05],
			["COOLDOWN", "surprise_ceiling_cooldown", 1.0, 12.0, 0.5],
		],
	},
	{
		"title": "FEEL / FX",
		"expanded": false,
		"fields": [
			["FAIL DELAY", "fail_delay", 0.0, 1.5, 0.05],
			["SHAKE", "shake_strength", 0.0, 40.0, 1.0],
			["SHAKE TIME", "shake_time", 0.0, 1.0, 0.01],
			["FLAP STRETCH", "flap_stretch", 0.0, 0.4, 0.01],
			["LAND SQUASH", "land_squash", 0.0, 0.4, 0.01],
			["HAPTIC LIGHT", "haptic_light_ms", 0.0, 60.0, 1.0],
			["HAPTIC HEAVY", "haptic_heavy_ms", 0.0, 120.0, 1.0],
		],
	},
]

var _run: Node
var _root: Control
var _column: VBoxContainer
var _presets_box: VBoxContainer
var _status: Label
var _toast: Label
var _modal: Control
var _modal_title: Label
var _modal_edit: LineEdit
var _modal_callback: Callable

var _sliders: Dictionary = {}
var _value_labels: Dictionary = {}
var _steps: Dictionary = {}
var _toggle_rows: Array = []
var _preset_rows: Array = []
var _field_names: Array[String] = []
var _defaults: RunTuning
var _data: Dictionary = {}
var _data_loaded: bool = false
var _dirty: bool = false
var _persist_timer: Timer

func _ready() -> void:
	_run = get_parent()
	if not _enabled():
		visible = false
		return
	_build()
	call_deferred("_apply_persisted")

func _enabled() -> bool:
	return OS.has_feature("nocaps_dev")

## Opens the panel and freezes the run (called by the run's DEV button).
func open() -> void:
	if _root == null:
		return
	_sync_toggles()
	_sync_sliders()
	_update_preset_marks()
	_root.visible = true
	if _run != null and _run.has_method("set_process"):
		_run.call("set_process", false)

func close() -> void:
	if _dirty:
		_persist()
	if _root != null:
		_root.visible = false

func is_open() -> bool:
	return _root != null and _root.visible

# ---------------------------------------------------------------------------
# Build
# ---------------------------------------------------------------------------

func _build() -> void:
	_load_data()
	_ensure_playtest_preset()

	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.visible = false
	add_child(_root)

	var scrim := ColorRect.new()
	scrim.color = Color(0.02, 0.01, 0.05, 0.78)
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(scrim)

	var insets := SafeArea.insets()
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 12 + int(insets.y))
	margin.add_theme_constant_override("margin_bottom", 12 + int(insets.w))
	_root.add_child(margin)

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _card_style())
	margin.add_child(panel)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	panel.add_child(column)

	var resume := Button.new()
	resume.text = "RESUME"
	resume.custom_minimum_size = Vector2(0.0, 76.0)
	_style_button(resume, GOLD, INK, 30)
	resume.pressed.connect(func() -> void:
		if _run != null and _run.has_method("resume_from_dev"):
			_run.call("resume_from_dev"))
	column.add_child(resume)

	_status = Label.new()
	_status.add_theme_font_size_override("font_size", 20)
	_status.add_theme_color_override("font_color", MUTED)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_status)

	var version := Label.new()
	version.text = AppVersion.label()
	version.add_theme_font_size_override("font_size", 16)
	version.add_theme_color_override("font_color", Color(MUTED.r, MUTED.g, MUTED.b, 0.6))
	version.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(version)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	column.add_child(scroll)

	_column = VBoxContainer.new()
	_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_column.add_theme_constant_override("separation", 8)
	scroll.add_child(_column)

	_build_quick_tests()
	_build_presets()
	for section in SECTIONS:
		var body := _add_section(String(section["title"]), bool(section.get("expanded", false)))
		for field in section["fields"]:
			_add_slider(body, field[0], field[1], field[2], field[3], field[4])
	_refresh_presets()

	_build_modal()
	_build_toast()

	_persist_timer = Timer.new()
	_persist_timer.one_shot = true
	_persist_timer.wait_time = 0.4
	_persist_timer.timeout.connect(_persist)
	add_child(_persist_timer)

func _build_quick_tests() -> void:
	var body := _add_section("QUICK TESTS", true)

	_add_toggle(body, "HAZARDS",
		func() -> bool: return bool(_run._spawn.hazards_enabled),
		func(value: bool) -> void: _run._spawn.hazards_enabled = value)
	_add_toggle(body, "SURPRISE SPIKE",
		func() -> bool: return bool(_run.dev_surprise_enabled),
		func(value: bool) -> void: _run.dev_surprise_enabled = value)
	_add_toggle(body, "FORCE TARGET",
		func() -> bool: return bool(_run._spawn.force_target),
		func(value: bool) -> void: _run._spawn.force_target = value)
	_add_toggle(body, "INVINCIBLE",
		func() -> bool: return bool(_run.dev_invincible),
		func(value: bool) -> void: _run.dev_invincible = value)
	# Master switch for every moment surface (run toast, result card, board rows,
	# home banners). Persisted by `meta/moments.gd`; off means no moment UI at all.
	_add_toggle(body, "MOMENTS",
		func() -> bool: return Moments.is_enabled(),
		func(value: bool) -> void: Moments.set_enabled(value))
	_add_toggle(body, "FIXED SEED",
		func() -> bool: return int(_run.tuning.run_seed) != 0,
		func(value: bool) -> void: _run.tuning.run_seed = 1337 if value else 0)
	# Passing your own crew's mascot without landing costs a point after the
	# grace window (FAIRNESS section holds the grace time).
	_add_toggle(body, "SKIP PENALTY",
		func() -> bool: return bool(_run.tuning.skip_penalty_enabled),
		func(value: bool) -> void: _run.tuning.skip_penalty_enabled = value)

	var restart := Button.new()
	restart.text = "RESTART RUN"
	restart.custom_minimum_size = Vector2(0.0, 66.0)
	_style_button(restart, CARD_INNER, CREAM, 24)
	restart.pressed.connect(func() -> void:
		if _run.has_method("restart"):
			_run.call("restart")
			_run.call("set_process", false))
	body.add_child(restart)

	var sign_test := Button.new()
	sign_test.text = "SIGN TEST (WALLET)"
	sign_test.custom_minimum_size = Vector2(0.0, 66.0)
	_style_button(sign_test, CARD_INNER, CREAM, 24)
	sign_test.pressed.connect(_dev_sign_test)
	body.add_child(sign_test)

func _build_presets() -> void:
	var body := _add_section("PRESETS", true)

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	body.add_child(actions)

	var save := Button.new()
	save.text = "SAVE AS"
	save.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	save.custom_minimum_size = Vector2(0.0, 62.0)
	_style_button(save, CARD_INNER, CREAM, 22)
	save.pressed.connect(_prompt_save_as)
	actions.add_child(save)

	var export := Button.new()
	export.text = "EXPORT"
	export.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	export.custom_minimum_size = Vector2(0.0, 62.0)
	_style_button(export, CARD_INNER, CREAM, 22)
	export.pressed.connect(_export)
	actions.add_child(export)

	_presets_box = VBoxContainer.new()
	_presets_box.add_theme_constant_override("separation", 8)
	body.add_child(_presets_box)

func _add_section(title: String, expanded: bool) -> VBoxContainer:
	var header := Button.new()
	header.text = ("▾  " if expanded else "▸  ") + title
	header.alignment = HORIZONTAL_ALIGNMENT_LEFT
	header.custom_minimum_size = Vector2(0.0, 62.0)
	_style_button(header, CARD_INNER, CREAM, 26)
	_column.add_child(header)

	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 8)
	body.visible = expanded
	_column.add_child(body)

	header.pressed.connect(func() -> void:
		body.visible = not body.visible
		header.text = ("▾  " if body.visible else "▸  ") + title)
	return body

func _add_slider(
	body: VBoxContainer, label_text: String, field: String,
	min_value: float, max_value: float, step: float
) -> void:
	_steps[field] = step

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	body.add_child(row)

	var name_label := Label.new()
	name_label.text = label_text
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 22)
	name_label.add_theme_color_override("font_color", CREAM)
	row.add_child(name_label)

	var value_label := Label.new()
	value_label.custom_minimum_size = Vector2(110.0, 0.0)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	value_label.add_theme_font_size_override("font_size", 22)
	value_label.add_theme_color_override("font_color", GOLD)
	row.add_child(value_label)

	var reset := Button.new()
	reset.text = "↺"
	reset.tooltip_text = "Reset to default"
	reset.custom_minimum_size = Vector2(60.0, 50.0)
	_style_button(reset, INK, GOLD, 24)
	reset.pressed.connect(_reset_field.bind(field))
	row.add_child(reset)

	var slider := HSlider.new()
	slider.min_value = min_value
	slider.max_value = max_value
	slider.step = step
	slider.custom_minimum_size = Vector2(0.0, 48.0)
	slider.set_value_no_signal(float(_run.tuning.get(field)))
	slider.add_theme_stylebox_override("slider", _track_style(CARD_INNER))
	slider.add_theme_stylebox_override("grabber_area", _track_style(GOLD))
	slider.add_theme_stylebox_override("grabber_area_highlight", _track_style(GOLD.lightened(0.15)))
	var grabber := _make_grabber(GOLD)
	slider.add_theme_icon_override("grabber", grabber)
	slider.add_theme_icon_override("grabber_highlight", grabber)
	slider.value_changed.connect(_set_field.bind(field))
	body.add_child(slider)

	_sliders[field] = slider
	_value_labels[field] = value_label
	value_label.text = _format_value(field, float(_run.tuning.get(field)))

func _add_toggle(body: VBoxContainer, label_text: String, getter: Callable, setter: Callable) -> void:
	var button := Button.new()
	button.custom_minimum_size = Vector2(0.0, 62.0)
	_style_button(button, CARD_INNER, CREAM, 24)
	_refresh_toggle(button, label_text, bool(getter.call()))
	button.pressed.connect(func() -> void:
		var next := not bool(getter.call())
		setter.call(next)
		_refresh_toggle(button, label_text, next)
		_mark_dirty())
	body.add_child(button)
	_toggle_rows.append({"button": button, "label": label_text, "getter": getter})

func _refresh_toggle(button: Button, label_text: String, state: bool) -> void:
	button.text = "%s: %s" % [label_text, "ON" if state else "OFF"]
	button.add_theme_color_override("font_color", GOLD if state else CREAM)

func _build_modal() -> void:
	_modal = Control.new()
	_modal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_modal.mouse_filter = Control.MOUSE_FILTER_STOP
	_modal.visible = false
	_root.add_child(_modal)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.62)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_modal.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_modal.add_child(center)

	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(600.0, 0.0)
	card.add_theme_stylebox_override("panel", _card_style())
	center.add_child(card)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 16)
	card.add_child(column)

	_modal_title = Label.new()
	_modal_title.add_theme_font_size_override("font_size", 28)
	_modal_title.add_theme_color_override("font_color", CREAM)
	column.add_child(_modal_title)

	_modal_edit = LineEdit.new()
	_modal_edit.custom_minimum_size = Vector2(0.0, 68.0)
	_modal_edit.add_theme_font_size_override("font_size", 26)
	column.add_child(_modal_edit)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 12)
	column.add_child(buttons)

	var cancel := Button.new()
	cancel.text = "CANCEL"
	cancel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cancel.custom_minimum_size = Vector2(0.0, 62.0)
	_style_button(cancel, CARD_INNER, CREAM, 22)
	cancel.pressed.connect(_close_modal)
	buttons.add_child(cancel)

	var ok := Button.new()
	ok.text = "OK"
	ok.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ok.custom_minimum_size = Vector2(0.0, 62.0)
	_style_button(ok, GOLD, INK, 22)
	ok.pressed.connect(_confirm_modal)
	buttons.add_child(ok)

	_modal_edit.text_submitted.connect(func(_text: String) -> void: _confirm_modal())

func _build_toast() -> void:
	_toast = Label.new()
	_toast.visible = false
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_toast.offset_top = 130.0
	_toast.offset_bottom = 196.0
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_toast.add_theme_font_size_override("font_size", 30)
	_toast.add_theme_color_override("font_color", CREAM)
	_toast.add_theme_color_override("font_outline_color", INK)
	_toast.add_theme_constant_override("outline_size", 8)
	_root.add_child(_toast)

# ---------------------------------------------------------------------------
# Styling helpers
# ---------------------------------------------------------------------------

func _card_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = CARD
	style.corner_radius_top_left = 22
	style.corner_radius_top_right = 22
	style.corner_radius_bottom_right = 22
	style.corner_radius_bottom_left = 22
	style.content_margin_left = 16.0
	style.content_margin_right = 16.0
	style.content_margin_top = 16.0
	style.content_margin_bottom = 16.0
	return style

func _track_style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_right = 6
	style.corner_radius_bottom_left = 6
	style.content_margin_top = 6.0
	style.content_margin_bottom = 6.0
	return style

func _style_button(button: Button, bg: Color, fg: Color, font_size: int) -> void:
	button.add_theme_stylebox_override("normal", _button_style(bg))
	button.add_theme_stylebox_override("hover", _button_style(bg.lightened(0.08)))
	button.add_theme_stylebox_override("pressed", _button_style(bg.darkened(0.12)))
	button.add_theme_stylebox_override("focus", _button_style(bg))
	button.add_theme_color_override("font_color", fg)
	button.add_theme_color_override("font_hover_color", fg)
	button.add_theme_color_override("font_pressed_color", fg)
	button.add_theme_font_size_override("font_size", font_size)

func _button_style(bg: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.corner_radius_top_left = 14
	style.corner_radius_top_right = 14
	style.corner_radius_bottom_right = 14
	style.corner_radius_bottom_left = 14
	style.content_margin_left = 16.0
	style.content_margin_right = 16.0
	style.content_margin_top = 8.0
	style.content_margin_bottom = 8.0
	return style

## A chunky round grabber so the sliders are easy to grab with a thumb.
func _make_grabber(color: Color) -> ImageTexture:
	var size := 44
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var center := Vector2(size * 0.5, size * 0.5)
	var radius := size * 0.42
	for y in size:
		for x in size:
			var distance := Vector2(x + 0.5, y + 0.5).distance_to(center)
			var alpha := clampf((radius - distance) / 1.5, 0.0, 1.0)
			image.set_pixel(x, y, Color(color.r, color.g, color.b, alpha))
	return ImageTexture.create_from_image(image)

# ---------------------------------------------------------------------------
# Live edits + defaults
# ---------------------------------------------------------------------------

func _format_value(field: String, value: float) -> String:
	if _run.tuning.get(field) is int:
		return "%d" % int(round(value))
	var step := float(_steps.get(field, 0.01))
	if step >= 1.0:
		return "%.0f" % value
	if step >= 0.01:
		return "%.2f" % value
	return "%.3f" % value

func _set_field(field: String, value: float) -> void:
	var current: Variant = _run.tuning.get(field)
	if current is int:
		_run.tuning.set(field, int(round(value)))
	else:
		_run.tuning.set(field, value)
	if _value_labels.has(field):
		_value_labels[field].text = _format_value(field, value)
	_run.apply_tuning()
	_mark_dirty()

func _reset_field(field: String) -> void:
	var defaults := _default_values()
	if defaults == null:
		return
	_run.tuning.set(field, defaults.get(field))
	_sync_slider(field)
	_run.apply_tuning()
	_mark_dirty()

## Restores every authored resource value (never writes the resource itself).
## Loads uncached: the live tuning often IS the default resource instance, so a
## plain load would return the already-mutated values.
func _reset_to_default() -> void:
	var defaults := _default_values()
	if defaults == null:
		return
	for name in _tuning_fields():
		_run.tuning.set(name, defaults.get(name))
	_sync_sliders()
	_run.apply_tuning()
	_mark_dirty()

func _default_values() -> RunTuning:
	if _defaults == null:
		_defaults = ResourceLoader.load(
			DEFAULT_TUNING_PATH, "", ResourceLoader.CACHE_MODE_IGNORE
		) as RunTuning
	return _defaults

func _sync_slider(field: String) -> void:
	if _sliders.has(field):
		var slider: HSlider = _sliders[field]
		slider.set_value_no_signal(float(_run.tuning.get(field)))
	if _value_labels.has(field):
		_value_labels[field].text = _format_value(field, float(_run.tuning.get(field)))

func _sync_sliders() -> void:
	for field in _sliders:
		_sync_slider(field)

func _sync_toggles() -> void:
	for row in _toggle_rows:
		var button: Button = row["button"]
		var getter: Callable = row["getter"]
		_refresh_toggle(button, String(row["label"]), bool(getter.call()))

# ---------------------------------------------------------------------------
# Persistence + presets
# ---------------------------------------------------------------------------

## Every exported RunTuning value, for full-fidelity presets.
func _tuning_fields() -> Array[String]:
	if _field_names.is_empty():
		for prop in _run.tuning.get_property_list():
			var name := String(prop["name"])
			if name == "script" or name.begins_with("_"):
				continue
			if int(prop["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE:
				_field_names.append(name)
	return _field_names

## Colors survive JSON as "#rrggbbaa" strings; other types round-trip as-is.
func _encode(value: Variant) -> Variant:
	if value is Color:
		return (value as Color).to_html(true)
	return value

func _decode(current: Variant, value: Variant) -> Variant:
	if current is Color:
		return Color(String(value))
	if current is int:
		return int(value)
	if current is float:
		return float(value)
	if current is bool:
		return bool(value)
	return value

func _snapshot() -> Dictionary:
	var values := {}
	for name in _tuning_fields():
		values[name] = _encode(_run.tuning.get(name))
	return values

func _apply_values(values: Dictionary) -> void:
	for name in _tuning_fields():
		if values.has(name):
			_run.tuning.set(name, _decode(_run.tuning.get(name), values[name]))

## On launch, re-apply the last working snapshot so a tuning session survives a
## relaunch, then re-sync the UI. DEV builds only (this node never builds otherwise).
func _apply_persisted() -> void:
	_load_data()
	var working: Dictionary = _data.get("working", {})
	if working is Dictionary and not working.is_empty():
		_apply_values(working)
		_run.apply_tuning()
		if _run.has_method("restart"):
			_run.call("restart")
		if _root != null and _root.visible and _run.has_method("set_process"):
			_run.call("set_process", false)
	_sync_sliders()
	_sync_toggles()
	_update_preset_marks()

func _load_data() -> void:
	if _data_loaded:
		return
	_data_loaded = true
	if FileAccess.file_exists(PRESETS_PATH):
		var file := FileAccess.open(PRESETS_PATH, FileAccess.READ)
		if file != null:
			var parsed: Variant = JSON.parse_string(file.get_as_text())
			if parsed is Dictionary:
				_data = parsed
	if not (_data.get("presets", []) is Array):
		_data["presets"] = []
	if not (_data.get("working", {}) is Dictionary):
		_data["working"] = {}
	if not _data.has("next_name"):
		_data["next_name"] = 1
	if not _data.has("active"):
		_data["active"] = -1

func _save_data() -> void:
	var file := FileAccess.open(PRESETS_PATH, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify(_data, "\t"))

## The owner-approved playtest_v05 snapshot ships as a named preset on first use,
## so it can be reloaded after any live tuning session. It captures the authored
## defaults (opening ease-in, lower speed cap, world zoom-out, safe zone).
func _ensure_playtest_preset() -> void:
	var presets: Array = _data.get("presets", [])
	for preset in presets:
		if preset is Dictionary and String(preset.get("name", "")) == "playtest_v05":
			return
	presets.append({"name": "playtest_v05", "values": _snapshot()})
	_data["presets"] = presets
	_save_data()

func _mark_dirty() -> void:
	_dirty = true
	_update_preset_marks()
	if _persist_timer != null:
		_persist_timer.start()

func _persist() -> void:
	_data["working"] = _snapshot()
	_save_data()
	_dirty = false

func _active_index() -> int:
	return int(_data.get("active", -1))

func _is_modified() -> bool:
	var index := _active_index()
	var presets: Array = _data.get("presets", [])
	if index < 0 or index >= presets.size():
		return false
	var values: Dictionary = presets[index].get("values", {})
	return _values_differ(_snapshot(), values)

func _values_differ(a: Dictionary, b: Dictionary) -> bool:
	for name in _tuning_fields():
		if a.has(name) != b.has(name):
			return true
		if a.has(name) and not _equal_encoded(a[name], b[name]):
			return true
	return false

func _equal_encoded(a: Variant, b: Variant) -> bool:
	if a is String or b is String:
		return String(a) == String(b)
	if (a is float or a is int) and (b is float or b is int):
		return is_equal_approx(float(a), float(b))
	return a == b

func _refresh_presets() -> void:
	if _presets_box == null:
		return
	for child in _presets_box.get_children():
		_presets_box.remove_child(child)
		child.queue_free()
	_preset_rows.clear()

	var presets: Array = _data.get("presets", [])
	if presets.is_empty():
		var empty := Label.new()
		empty.text = "No presets yet — tune, then SAVE AS"
		empty.add_theme_font_size_override("font_size", 20)
		empty.add_theme_color_override("font_color", MUTED)
		_presets_box.add_child(empty)
		_update_preset_marks()
		return

	for i in range(presets.size()):
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		_presets_box.add_child(row)

		var load := Button.new()
		load.text = "LOAD"
		load.custom_minimum_size = Vector2(96.0, 58.0)
		_style_button(load, CARD_INNER, CREAM, 20)
		load.pressed.connect(_load_preset.bind(i))
		row.add_child(load)

		var name_label := Label.new()
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		name_label.add_theme_font_size_override("font_size", 21)
		name_label.add_theme_color_override("font_color", CREAM)
		row.add_child(name_label)

		var rename := Button.new()
		rename.text = "RENAME"
		rename.custom_minimum_size = Vector2(120.0, 58.0)
		_style_button(rename, CARD_INNER, CREAM, 18)
		rename.pressed.connect(_prompt_rename.bind(i))
		row.add_child(rename)

		var remove := Button.new()
		remove.text = "DELETE"
		remove.custom_minimum_size = Vector2(120.0, 58.0)
		_style_button(remove, CARD_INNER, Color("ff8f8f"), 18)
		remove.pressed.connect(_delete_preset.bind(i))
		row.add_child(remove)

		_preset_rows.append({"label": name_label, "index": i})

	_update_preset_marks()

func _update_preset_marks() -> void:
	if _status == null:
		return
	var presets: Array = _data.get("presets", [])
	var active := _active_index()
	var modified := _is_modified()
	for row in _preset_rows:
		var i: int = row["index"]
		if i < 0 or i >= presets.size():
			continue
		var label: Label = row["label"]
		var mark := ""
		if i == active:
			mark = "● "
		var suffix := "  *" if (i == active and modified) else ""
		label.text = mark + String(presets[i].get("name", "Preset")) + suffix
		label.add_theme_color_override("font_color", GOLD if i == active else CREAM)
	if active >= 0 and active < presets.size():
		var state := String(presets[active].get("name", "Preset"))
		_status.text = "ACTIVE: %s%s" % [state, "  (modified)" if modified else ""]
	else:
		_status.text = "ACTIVE: unsaved tuning"

# ---------------------------------------------------------------------------
# Preset actions
# ---------------------------------------------------------------------------

func _prompt_save_as() -> void:
	var default_name := "Preset %d" % int(_data.get("next_name", 1))
	_open_prompt("SAVE PRESET AS", default_name, _save_preset)

func _save_preset(name: String) -> void:
	var presets: Array = _data.get("presets", [])
	if presets.size() >= PRESET_LIMIT:
		_show_toast("Limit: %d presets" % PRESET_LIMIT)
		return
	var values := _snapshot()
	presets.append({"name": name, "values": values})
	_data["presets"] = presets
	_data["active"] = presets.size() - 1
	_data["next_name"] = int(_data.get("next_name", 1)) + 1
	_data["working"] = values
	_save_data()
	_refresh_presets()
	_show_toast("Saved")

func _prompt_rename(index: int) -> void:
	var presets: Array = _data.get("presets", [])
	if index < 0 or index >= presets.size():
		return
	var current := String(presets[index].get("name", "Preset"))
	_open_prompt("RENAME PRESET", current, func(name: String) -> void: _rename_preset(index, name))

func _rename_preset(index: int, name: String) -> void:
	var presets: Array = _data.get("presets", [])
	if index < 0 or index >= presets.size():
		return
	presets[index]["name"] = name
	_save_data()
	_refresh_presets()

func _load_preset(index: int) -> void:
	var presets: Array = _data.get("presets", [])
	if index < 0 or index >= presets.size():
		return
	var values: Dictionary = presets[index].get("values", {})
	_apply_values(values)
	_sync_sliders()
	_run.apply_tuning()
	_data["active"] = index
	_data["working"] = _snapshot()
	_save_data()
	_update_preset_marks()

func _delete_preset(index: int) -> void:
	var presets: Array = _data.get("presets", [])
	if index < 0 or index >= presets.size():
		return
	presets.remove_at(index)
	var active := _active_index()
	if active == index:
		active = -1
	elif active > index:
		active -= 1
	_data["active"] = active
	_data["presets"] = presets
	_save_data()
	_refresh_presets()

func _export() -> void:
	var presets: Array = _data.get("presets", [])
	var active := _active_index()
	var preset_name := "unsaved"
	if active >= 0 and active < presets.size():
		preset_name = String(presets[active].get("name", preset_name))
	var payload := {
		"name": preset_name,
		"values": _snapshot(),
		"exported_utc": Time.get_datetime_string_from_system(true),
	}
	var json := JSON.stringify(payload, "\t")
	DisplayServer.clipboard_set(json)
	var file := FileAccess.open(EXPORT_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(json)
	_show_toast("Copied")

# ---------------------------------------------------------------------------
# DEV-only wallet sign test (never used by product code; docs/13 §4.1)
# ---------------------------------------------------------------------------

## Signs a throwaway challenge with the connected wallet and logs the detached
## Ed25519 signature so the `sign_message` path can be exercised on device.
func _dev_sign_test() -> void:
	if not WalletService.message_signed.is_connected(_on_dev_signed):
		WalletService.message_signed.connect(_on_dev_signed)
	if not WalletService.wallet_error.is_connected(_on_dev_wallet_error):
		WalletService.wallet_error.connect(_on_dev_wallet_error)
	var challenge := "nocaps dev sign test %d" % int(Time.get_unix_time_from_system())
	print("NOCAPS dev: sign_message request: %s" % challenge)
	_show_toast("Signing...")
	WalletService.sign_message(challenge)

func _on_dev_signed(message: String, signature: String) -> void:
	print("NOCAPS dev: message_signed '%s' -> %s" % [message, signature])
	_show_toast("Signed")

func _on_dev_wallet_error(code: String, detail: String) -> void:
	print("NOCAPS dev: wallet_error %s (%s)" % [code, detail])
	_show_toast("Error: %s" % code)

# ---------------------------------------------------------------------------
# Modal + toast
# ---------------------------------------------------------------------------

func _open_prompt(title: String, initial: String, callback: Callable) -> void:
	if _modal == null:
		return
	_modal_callback = callback
	_modal_title.text = title
	_modal_edit.text = initial
	_modal.visible = true
	_modal_edit.grab_focus()
	_modal_edit.select_all()

func _close_modal() -> void:
	if _modal != null:
		_modal.visible = false
	_modal_callback = Callable()

func _confirm_modal() -> void:
	var text := _modal_edit.text.strip_edges()
	var callback := _modal_callback
	_close_modal()
	if text.is_empty() or not callback.is_valid():
		return
	callback.call(text)

func _show_toast(text: String) -> void:
	if _toast == null:
		return
	_toast.text = text
	_toast.modulate.a = 1.0
	_toast.visible = true
	var tween := create_tween()
	tween.tween_interval(0.9)
	tween.tween_property(_toast, "modulate:a", 0.0, 0.4)
	tween.tween_callback(func() -> void: _toast.visible = false)
