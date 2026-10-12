extends CanvasLayer
class_name ShellUI

## Persistent menu chrome for the v2 "arcade sticker" shell: a solid INK bottom
## tab bar (PLAY · EXPLORE · BOARD · PROFILE) with GOLD active state and LILAC
## inactive state. The backdrop lives in `scenes/main.tscn`. The chrome hides
## during a run and on Result. Safe-area aware for notched Android devices.

const INK := Color("1d1033")
const GOLD := Color("ffd23f")
const LILAC := Color("b9a8d6")
const BOLD_FONT_PATH := "res://data/fonts/fredoka_bold.tres"
const BAR_HEIGHT := 137.0

const TABS := [
	{"key": &"home", "text": "PLAY", "icon": &"play"},
	{"key": &"community_select", "text": "EXPLORE", "icon": &"compass"},
	{"key": &"leaderboard", "text": "BOARD", "icon": &"board"},
	{"key": &"profile", "text": "PROFILE", "icon": &"profile"},
]
const HIDDEN_SCREENS := [&"run", &"result"]
const TAB_FOR_SCREEN := {
	&"home": &"home",
	&"quests": &"home",
	&"community_select": &"community_select",
	&"community_detail": &"community_select",
	&"community_editor": &"profile",
	&"leaderboard": &"leaderboard",
	&"profile": &"profile",
}

static var instance: ShellUI
static var safe_top: float = 0.0
static var safe_bottom: float = 0.0

var app: Node
var _tabs: PanelContainer
var _tab_buttons: Dictionary = {}
var _tab_icons: Dictionary = {}
var _bold: Font

func _ready() -> void:
	instance = self
	_bold = load(BOLD_FONT_PATH) as Font
	_apply_safe_area()
	_build_tab_bar()
	if get_viewport() != null:
		get_viewport().size_changed.connect(_apply_safe_area)

func _exit_tree() -> void:
	if instance == self:
		instance = null

func bind_app(app_flow: Node) -> void:
	app = app_flow
	refresh()

## Shows/hides the chrome and highlights the active tab.
func set_screen(screen: StringName) -> void:
	var hidden := screen in HIDDEN_SCREENS
	_tabs.visible = not hidden
	var active: StringName = TAB_FOR_SCREEN.get(screen, &"")
	for key in _tab_buttons:
		_style_tab(key, key == active)
	refresh()

## v2 keeps no global player chip; retained for existing callers (Home, Profile,
## AppFlow) until they are rebuilt.
func refresh() -> void:
	pass

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

func _apply_safe_area() -> void:
	var insets := SafeArea.insets()
	safe_top = insets.y
	safe_bottom = insets.w
	if _tabs != null:
		_tabs.offset_top = -(BAR_HEIGHT + safe_bottom)
		_tabs.offset_bottom = 0.0
		_tabs.add_theme_stylebox_override("panel", _tabbar_style())

func _build_tab_bar() -> void:
	_tabs = PanelContainer.new()
	_tabs.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_tabs.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_tabs.offset_top = -(BAR_HEIGHT + safe_bottom)
	_tabs.offset_bottom = 0.0
	_tabs.add_theme_stylebox_override("panel", _tabbar_style())
	add_child(_tabs)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 0)
	_tabs.add_child(row)
	for tab in TABS:
		var key: StringName = tab["key"]
		var button := Button.new()
		button.text = ""
		button.focus_mode = Control.FOCUS_NONE
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.custom_minimum_size = Vector2(0, 96)
		button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		button.pressed.connect(func() -> void:
			if app != null:
				app.call("go_to", key, {}))
		var content := VBoxContainer.new()
		content.set_anchors_preset(Control.PRESET_FULL_RECT)
		content.alignment = BoxContainer.ALIGNMENT_CENTER
		content.add_theme_constant_override("separation", 6)
		content.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var icon := Icon.new()
		icon.setup(tab["icon"], LILAC, 41.0)
		icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		content.add_child(icon)
		var label := Label.new()
		label.text = String(tab["text"])
		label.add_theme_font_override("font", _bold)
		label.add_theme_font_size_override("font_size", 24)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		content.add_child(label)
		button.add_child(content)
		row.add_child(button)
		_tab_buttons[key] = button
		_tab_icons[key] = icon
		_tab_icons[String(key) + ":label"] = label

func _style_tab(key: StringName, active: bool) -> void:
	var button: Button = _tab_buttons.get(key)
	if button == null:
		return
	button.add_theme_stylebox_override("normal", _tab_style(active, false))
	button.add_theme_stylebox_override("hover", _tab_style(active, true))
	button.add_theme_stylebox_override("pressed", _tab_style(true, false))
	button.add_theme_stylebox_override("focus", _tab_style(active, false))
	var icon: Icon = _tab_icons.get(key)
	if icon != null:
		icon.set_color(GOLD if active else LILAC)
	var label: Label = _tab_icons.get(String(key) + ":label")
	if label != null:
		label.add_theme_color_override("font_color", GOLD if active else LILAC)

func _tabbar_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = INK
	style.content_margin_left = 12.0
	style.content_margin_right = 12.0
	style.content_margin_top = 14.0
	style.content_margin_bottom = 14.0 + safe_bottom
	return style

func _tab_style(active: bool, hover: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	if hover and not active:
		style.bg_color = Color(1, 1, 1, 0.05)
	else:
		style.bg_color = Color(0, 0, 0, 0)
	style.set_corner_radius_all(22)
	style.content_margin_top = 6.0
	style.content_margin_bottom = 6.0
	return style
