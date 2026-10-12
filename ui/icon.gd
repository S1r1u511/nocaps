extends Control
class_name Icon

## Tiny code-drawn icon set for the shell, chips, and headers. No image assets:
## everything is vector-drawn at the requested size.

var kind: StringName = &"play"
var color: Color = Color.WHITE

func setup(kind_value: StringName, color_value: Color, size_value: float = 18.0) -> void:
	kind = kind_value
	color = color_value
	custom_minimum_size = Vector2(size_value, size_value)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	queue_redraw()

func set_color(color_value: Color) -> void:
	color = color_value
	queue_redraw()

func _draw() -> void:
	var w := size.x
	var h := size.y
	match kind:
		&"play":
			draw_colored_polygon(PackedVector2Array([
				Vector2(w * 0.30, h * 0.20),
				Vector2(w * 0.80, h * 0.50),
				Vector2(w * 0.30, h * 0.80),
			]), color)
		&"crew":
			draw_rect(Rect2(Vector2(w * 0.16, h * 0.10), Vector2(w * 0.10, h * 0.80)), color)
			draw_colored_polygon(PackedVector2Array([
				Vector2(w * 0.26, h * 0.14),
				Vector2(w * 0.90, h * 0.30),
				Vector2(w * 0.26, h * 0.50),
			]), color)
		&"board":
			draw_rect(Rect2(Vector2(w * 0.18, h * 0.55), Vector2(w * 0.16, h * 0.30)), color)
			draw_rect(Rect2(Vector2(w * 0.42, h * 0.28), Vector2(w * 0.16, h * 0.57)), color)
			draw_rect(Rect2(Vector2(w * 0.66, h * 0.42), Vector2(w * 0.16, h * 0.43)), color)
		&"compass":
			draw_arc(Vector2(w * 0.5, h * 0.5), w * 0.40, 0.0, TAU, 32, color, w * 0.10, true)
			draw_colored_polygon(PackedVector2Array([
				Vector2(w * 0.66, h * 0.34),
				Vector2(w * 0.56, h * 0.56),
				Vector2(w * 0.34, h * 0.66),
				Vector2(w * 0.44, h * 0.44),
			]), color)
		&"profile":
			draw_circle(Vector2(w * 0.5, h * 0.32), w * 0.17, color)
			draw_arc(Vector2(w * 0.5, h * 0.86), w * 0.30, PI, TAU, 24, color, w * 0.16, true)
		&"crown":
			draw_colored_polygon(PackedVector2Array([
				Vector2(w * 0.06, h * 0.72),
				Vector2(w * 0.20, h * 0.14),
				Vector2(w * 0.38, h * 0.48),
				Vector2(w * 0.50, h * 0.08),
				Vector2(w * 0.62, h * 0.48),
				Vector2(w * 0.80, h * 0.14),
				Vector2(w * 0.94, h * 0.72),
			]), color)
			draw_rect(Rect2(Vector2(w * 0.06, h * 0.74), Vector2(w * 0.88, h * 0.16)), color)
		&"ellipse":
			draw_set_transform(Vector2(w * 0.5, h * 0.5), 0.0, Vector2(w * 0.5, h * 0.5))
			draw_circle(Vector2.ZERO, 1.0, color)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		&"flame":
			draw_colored_polygon(PackedVector2Array([
				Vector2(w * 0.5, h * 0.10),
				Vector2(w * 0.74, h * 0.46),
				Vector2(w * 0.80, h * 0.70),
				Vector2(w * 0.62, h * 0.90),
				Vector2(w * 0.38, h * 0.90),
				Vector2(w * 0.20, h * 0.70),
				Vector2(w * 0.26, h * 0.46),
				Vector2(w * 0.42, h * 0.62),
			]), color)
		&"coin":
			draw_circle(Vector2(w * 0.5, h * 0.5), w * 0.36, color)
			draw_circle(Vector2(w * 0.5, h * 0.5), w * 0.22, Color(color.r, color.g, color.b, 0.35))
		&"target":
			draw_arc(Vector2(w * 0.5, h * 0.5), w * 0.36, 0.0, TAU, 32, color, w * 0.10, true)
			draw_circle(Vector2(w * 0.5, h * 0.5), w * 0.10, color)
		&"trophy":
			draw_colored_polygon(PackedVector2Array([
				Vector2(w * 0.26, h * 0.14),
				Vector2(w * 0.74, h * 0.14),
				Vector2(w * 0.66, h * 0.54),
				Vector2(w * 0.34, h * 0.54),
			]), color)
			draw_rect(Rect2(Vector2(w * 0.44, h * 0.54), Vector2(w * 0.12, h * 0.18)), color)
			draw_rect(Rect2(Vector2(w * 0.28, h * 0.72), Vector2(w * 0.44, h * 0.14)), color)
		&"chevron":
			draw_polyline(PackedVector2Array([
				Vector2(w * 0.36, h * 0.24),
				Vector2(w * 0.62, h * 0.50),
				Vector2(w * 0.36, h * 0.76),
			]), color, w * 0.12, true)
		&"check":
			draw_polyline(PackedVector2Array([
				Vector2(w * 0.22, h * 0.54),
				Vector2(w * 0.42, h * 0.74),
				Vector2(w * 0.78, h * 0.28),
			]), color, w * 0.14, true)
		&"chevron_down":
			draw_polyline(PackedVector2Array([
				Vector2(w * 0.24, h * 0.36),
				Vector2(w * 0.50, h * 0.62),
				Vector2(w * 0.76, h * 0.36),
			]), color, w * 0.12, true)
		&"down_arrow":
			draw_colored_polygon(PackedVector2Array([
				Vector2(w * 0.12, h * 0.18),
				Vector2(w * 0.88, h * 0.18),
				Vector2(w * 0.50, h * 0.88),
			]), color)
		&"dot":
			draw_circle(Vector2(w * 0.5, h * 0.5), w * 0.42, color)
		&"lock":
			draw_arc(Vector2(w * 0.5, h * 0.42), w * 0.20, PI, TAU, 20, color, w * 0.12, true)
			draw_rect(Rect2(Vector2(w * 0.24, h * 0.42), Vector2(w * 0.52, h * 0.42)), color)
		&"pause":
			draw_rect(Rect2(Vector2(w * 0.22, h * 0.12), Vector2(w * 0.20, h * 0.76)), color)
			draw_rect(Rect2(Vector2(w * 0.58, h * 0.12), Vector2(w * 0.20, h * 0.76)), color)
		&"wallet":
			draw_rect(Rect2(Vector2(w * 0.10, h * 0.24), Vector2(w * 0.80, h * 0.56)), color, false, w * 0.10)
			draw_circle(Vector2(w * 0.72, h * 0.52), w * 0.07, color)
		&"edit":
			draw_colored_polygon(PackedVector2Array([
				Vector2(w * 0.14, h * 0.86),
				Vector2(w * 0.30, h * 0.80),
				Vector2(w * 0.82, h * 0.28),
				Vector2(w * 0.68, h * 0.14),
				Vector2(w * 0.16, h * 0.66),
			]), color)
		&"x":
			draw_line(Vector2(w * 0.22, h * 0.22), Vector2(w * 0.78, h * 0.78), color, w * 0.14, true)
			draw_line(Vector2(w * 0.78, h * 0.22), Vector2(w * 0.22, h * 0.78), color, w * 0.14, true)
		&"telegram":
			draw_colored_polygon(PackedVector2Array([
				Vector2(w * 0.12, h * 0.50),
				Vector2(w * 0.88, h * 0.14),
				Vector2(w * 0.72, h * 0.84),
				Vector2(w * 0.47, h * 0.60),
				Vector2(w * 0.36, h * 0.82),
				Vector2(w * 0.32, h * 0.58),
			]), color)
		&"website":
			draw_arc(Vector2(w * 0.5, h * 0.5), w * 0.38, 0.0, TAU, 32, color, w * 0.10, true)
			draw_line(Vector2(w * 0.12, h * 0.5), Vector2(w * 0.88, h * 0.5), color, w * 0.10, true)
			draw_polyline(PackedVector2Array([
				Vector2(w * 0.50, h * 0.12),
				Vector2(w * 0.34, h * 0.50),
				Vector2(w * 0.50, h * 0.88),
				Vector2(w * 0.66, h * 0.50),
				Vector2(w * 0.50, h * 0.12),
			]), color, w * 0.10, true)
