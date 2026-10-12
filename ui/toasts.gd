extends CanvasLayer
class_name Toasts

## Bottom-center sticker toasts for menu feedback ("Tier reached", "Name saved",
## "Link copied"). Add the `Toasts` CanvasLayer to the app shell.
##
## The band sits ABOVE the persistent tab bar, so a toast can never cover the
## navigation or the active screen's primary action. Toasts are user-triggered
## feedback only: no run/result moment ever uses this surface.

static var instance: Toasts

const BOLD_FONT_PATH := "res://data/fonts/fredoka_bold.tres"
## Gap between the toast band and the top of the tab bar.
const BAR_GAP := 14.0

var _box: VBoxContainer
var _bold: Font

func _ready() -> void:
	instance = self
	layer = 60
	_bold = load(BOLD_FONT_PATH) as Font
	var anchor := MarginContainer.new()
	anchor.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	anchor.offset_top = -(ShellUI.BAR_HEIGHT + ShellUI.safe_bottom + 150.0 + BAR_GAP)
	anchor.offset_bottom = -(ShellUI.BAR_HEIGHT + ShellUI.safe_bottom + BAR_GAP)
	anchor.grow_vertical = Control.GROW_DIRECTION_BEGIN
	anchor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(anchor)
	_box = VBoxContainer.new()
	_box.alignment = BoxContainer.ALIGNMENT_END
	_box.add_theme_constant_override("separation", 8)
	_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	anchor.add_child(_box)

static func show_message(text: String) -> void:
	if instance == null or not is_instance_valid(instance):
		return
	instance._spawn(text)

func _spawn(text: String) -> void:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var style := StyleBoxFlat.new()
	style.bg_color = Color("2b1b4a")
	style.set_corner_radius_all(22)
	style.set_border_width_all(6)
	style.border_color = Color("1d1033")
	style.border_width_bottom = 14
	style.content_margin_left = 30.0
	style.content_margin_right = 30.0
	style.content_margin_top = 12.0
	style.content_margin_bottom = 18.0
	panel.add_theme_stylebox_override("panel", style)
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_override("font", _bold)
	label.add_theme_font_size_override("font_size", 26)
	label.add_theme_color_override("font_color", Color("fff4dc"))
	# An autowrap Label has no width requirement of its own; give it the natural
	# one-line width (capped to the screen), so short toasts stay compact instead
	# of collapsing to one character per line.
	var natural := _bold.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 26).x
	var max_width := get_viewport().get_visible_rect().size.x - 120.0
	label.custom_minimum_size.x = minf(natural, max_width)
	panel.add_child(label)
	_box.add_child(panel)
	panel.modulate.a = 0.0
	panel.position.y = 10.0
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(panel, "modulate:a", 1.0, 0.18)
	tween.tween_property(panel, "position:y", 0.0, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.set_parallel(false)
	tween.tween_interval(2.2)
	tween.tween_property(panel, "modulate:a", 0.0, 0.25)
	tween.tween_callback(panel.queue_free)
