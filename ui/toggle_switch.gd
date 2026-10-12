extends Button
class_name ToggleSwitch

## Compact arcade switch matching the v2 kit: INK-outlined rounded track with a
## CREAM knob, YOURS when on. Emits `switched(on)`. Drags scroll the page: the
## knob only flips when the finger moved less than the kit's drag deadzone.

signal switched(on: bool)

const TRACK_ON := Color("5ee08a")
const TRACK_OFF := Color("3a2466")
const KNOB := Color("fff4dc")
const BORDER := Color("1d1033")

var on: bool = false
var _knob: float = 0.0
var _gesture: Dictionary = {}

func setup(value: bool) -> void:
	on = value
	_knob = 1.0 if on else 0.0
	custom_minimum_size = Vector2(52, 30)
	focus_mode = Control.FOCUS_NONE
	mouse_filter = Control.MOUSE_FILTER_PASS
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	if _gesture.is_empty():
		_gesture = UiScreen.track_gesture(self)
	queue_redraw()

func _pressed() -> void:
	if bool(_gesture.get("dragged", false)):
		return
	on = not on
	var tween := create_tween()
	tween.tween_method(_set_knob, _knob, 1.0 if on else 0.0, 0.16) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	switched.emit(on)

func _set_knob(value: float) -> void:
	_knob = value
	queue_redraw()

func _draw() -> void:
	var border := 3.0
	var radius := size.y * 0.5
	var track_color := TRACK_ON if on else TRACK_OFF
	draw_rect(Rect2(Vector2(radius, 0.0), Vector2(size.x - radius * 2.0, size.y)), track_color, true)
	draw_circle(Vector2(radius, radius), radius - border, track_color)
	draw_circle(Vector2(size.x - radius, radius), radius - border, track_color)

	draw_arc(Vector2(radius, radius), radius - border * 0.5, PI * 0.5, PI * 1.5, 24, BORDER, border, true)
	draw_arc(Vector2(size.x - radius, radius), radius - border * 0.5, -PI * 0.5, PI * 0.5, 24, BORDER, border, true)
	draw_line(Vector2(radius, border * 0.5), Vector2(size.x - radius, border * 0.5), BORDER, border, true)
	draw_line(Vector2(radius, size.y - border * 0.5), Vector2(size.x - radius, size.y - border * 0.5), BORDER, border, true)

	var knob_radius := radius - border - 2.0
	var knob_x := lerpf(radius, size.x - radius, _knob)
	draw_circle(Vector2(knob_x, radius), knob_radius, KNOB)
	draw_arc(Vector2(knob_x, radius), knob_radius, 0.0, TAU, 24, BORDER, 2.0, true)
