extends Node2D
class_name Hazard

## One of the four ported hazards: spike ball, buzzsaw, storm cloud, or ceiling
## spikes. Presentation and motion only; the run decides collisions.
## See docs/01_GDD.md §3.6.

enum Kind { SPIKE, SAW, CLOUD, CEIL }

var kind: int = Kind.SPIKE
var radius: float = 22.0
var size: Vector2 = Vector2(74.0, 46.0)
var amplitude: float = 0.0
var speed: float = 0.8
var spin: float = 0.0
var seed: float = 0.0
var base_y: float = 0.0
var ext: float = 0.0
var ext_target: float = 0.0
var ceiling_width: float = 96.0
var ceiling_height: float = 48.0
## Scripted hazards (the surprise ceiling spike) drive their own ext and position;
## the run's proximity controller must leave them alone.
var scripted: bool = false

var _clock: float = 0.0
var _bolt_on: bool = false

func configure_spike(value: float, base: float, amp: float) -> void:
	kind = Kind.SPIKE
	radius = value
	base_y = base
	amplitude = amp
	seed = randf() * TAU
	position.y = base_y
	queue_redraw()

func configure_saw(value: float, base: float, amp: float, drift_speed: float) -> void:
	kind = Kind.SAW
	radius = value
	base_y = base
	amplitude = amp
	speed = drift_speed
	seed = randf() * TAU
	spin = randf() * TAU
	position.y = base_y
	queue_redraw()

func configure_cloud(value: Vector2, base: float, amp: float) -> void:
	kind = Kind.CLOUD
	size = value
	base_y = base
	amplitude = amp
	seed = randf() * TAU
	position.y = base_y
	queue_redraw()

func configure_ceiling(width: float, height: float) -> void:
	kind = Kind.CEIL
	ceiling_width = width
	ceiling_height = height
	ext = 0.0
	ext_target = 0.0
	position.y = 0.0
	queue_redraw()

func _process(delta: float) -> void:
	_clock += delta
	match kind:
		Kind.SPIKE:
			position.y = base_y + sin(_clock * 0.5 + seed) * amplitude
			rotation += 2.6 * delta
		Kind.SAW:
			position.y = base_y + sin(_clock * speed + seed) * amplitude
			spin += _clock * 0.0 + delta * 6.5
			rotation = spin
		Kind.CLOUD:
			position.y = base_y + sin(_clock * 0.8 + seed) * amplitude
			_bolt_on = sin(_clock * 9.0 + seed) > 0.2
			queue_redraw()
		Kind.CEIL:
			ext += (ext_target - ext) * minf(1.0, delta * (6.5 if ext_target > ext else 3.4))
			queue_redraw()

func _draw() -> void:
	match kind:
		Kind.SPIKE:
			_draw_spike()
		Kind.SAW:
			_draw_saw()
		Kind.CLOUD:
			_draw_cloud()
		Kind.CEIL:
			_draw_ceiling()

func _draw_spike() -> void:
	# All-silver spiked ball, spinning, with the v2 INK outline.
	var spikes := 9
	var ink := Color("1d1033")
	var silver := Color("dfe7f2")
	var silver_mid := Color("9fb0c9")
	for i in range(spikes):
		var angle := TAU * float(i) / float(spikes) + 0.2
		var tip := Vector2(cos(angle), sin(angle)) * radius * 1.75
		var a := Vector2(cos(angle - 0.28), sin(angle - 0.28)) * radius * 0.95
		var b := Vector2(cos(angle + 0.28), sin(angle + 0.28)) * radius * 0.95
		draw_colored_polygon(PackedVector2Array([a, tip, b]), silver)
		draw_polyline(PackedVector2Array([a, tip, b]), ink, 3.5, true)
	draw_circle(Vector2.ZERO, radius, silver_mid)
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 40, ink, 3.5, true)
	draw_circle(Vector2(-radius * 0.32, -radius * 0.32), radius * 0.26, Color(1.0, 1.0, 1.0, 0.35))

func _draw_saw() -> void:
	var teeth := 12
	var ink := Color("1d1033")
	var body := Color("9aa7bd")
	for i in range(teeth):
		var angle := TAU * float(i) / float(teeth)
		var tip := Vector2(cos(angle), sin(angle)) * radius * 1.35
		var a := Vector2(cos(angle - 0.16), sin(angle - 0.16)) * radius
		var b := Vector2(cos(angle + 0.16), sin(angle + 0.16)) * radius
		draw_colored_polygon(PackedVector2Array([a, tip, b]), body)
		draw_polyline(PackedVector2Array([a, tip, b]), ink, 3.5, true)
	draw_circle(Vector2.ZERO, radius, Color("6b7688"))
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 32, ink, 3.5, true)
	draw_circle(Vector2.ZERO, radius * 0.35, Color("2f3646"))

func _draw_cloud() -> void:
	var half := size * 0.5
	var ink := Color("1d1033")
	var puff := Color("8b9ab6")
	var puffs := [
		[Vector2(-half.x * 0.45, 0.0), half.y * 0.75, puff],
		[Vector2(half.x * 0.45, 0.0), half.y * 0.75, puff],
		[Vector2(0.0, -half.y * 0.25), half.y * 0.95, puff.lightened(0.08)],
	]
	var body := Rect2(-half.x * 0.7, -half.y * 0.2, size.x * 0.7, half.y * 0.9)
	# Ink pass first, then the fill pass covers the interior seams — the same
	# two-pass trick the cappycap prototype uses for its storm cloud.
	for entry in puffs:
		draw_circle(entry[0], float(entry[1]) + 3.5, ink)
	draw_rect(body.grow(3.5), ink)
	for entry in puffs:
		draw_circle(entry[0], entry[1], entry[2])
	draw_rect(body, puff)
	if _bolt_on:
		var bolt := PackedVector2Array([
			Vector2(-4.0, half.y * 0.4), Vector2(6.0, half.y * 0.7),
			Vector2(0.0, half.y * 0.75), Vector2(10.0, half.y * 1.15),
		])
		draw_polyline(bolt, ink, 8.0, true)
		draw_polyline(bolt, Color("ffd23f"), 4.0, true)

func _draw_ceiling() -> void:
	if ext < 0.03:
		return
	var height := ceiling_height * ext
	var width := ceiling_width
	var count := 5
	var step := width / float(count)
	var ink := Color("1d1033")
	var color := Color("cdd7e8")
	for i in range(count):
		var x0 := -width * 0.5 + float(i) * step
		var band := PackedVector2Array([
			Vector2(x0 + 2.0, height - 14.0),
			Vector2(x0 + step * 0.5, height),
			Vector2(x0 + step - 2.0, height - 14.0),
		])
		draw_colored_polygon(band, color)
		draw_polyline(PackedVector2Array([band[0], band[1], band[2], band[0]]), ink, 3.5, true)
	var base := Rect2(-width * 0.5 - 3.0, height - 21.0, width + 6.0, 14.0)
	draw_rect(base, Color("8b9ab6"))
	draw_rect(base, ink, false, 3.5)
