extends Node2D
class_name Effects

## Lightweight code-drawn effects layer: colored dots with gravity and ground
## bounce, expanding rings, radiating sparks, lightning arcs, ambient motes, and
## outlined text popups (plain and GOLD sticker pills). One node, one draw pass;
## no per-particle nodes. Reduced motion suppresses motion-heavy effects.

const MAX_DOTS := 360
const MAX_RINGS := 40
const MAX_SPARKS := 160
const MAX_ARCS := 8
const MAX_POPUPS := 24

## Gameplay palette (docs/UI_V2_BRIEF.md §1).
const INK := Color("1d1033")
const GOLD := Color("ffd23f")
const BOLD_FONT_PATH := "res://data/fonts/fredoka_bold.tres"

var ground_y: float = 1150.0
var reduced_motion: bool = false

var _dots: Array = []
var _rings: Array = []
var _sparks: Array = []
var _arcs: Array = []
var _popups: Array = []
var _motes: Array = []
var _mote_bounds: Vector2 = Vector2(720.0, 1280.0)
var _font: Font

func _ready() -> void:
	_font = load(BOLD_FONT_PATH) as Font
	if _font == null:
		_font = ThemeDB.fallback_font

func configure(ground: float) -> void:
	ground_y = ground

func set_reduced_motion(value: bool) -> void:
	reduced_motion = value

## Slow ambient specks so the world still feels alive between events.
func spawn_motes(bounds: Vector2, count: int = 16) -> void:
	_mote_bounds = bounds
	_motes.clear()
	var total := count / 2 if reduced_motion else count
	for i in range(total):
		_motes.append({
			"pos": Vector2(randf() * bounds.x, randf() * bounds.y),
			"vel": Vector2(randf_range(-8.0, 8.0), randf_range(-16.0, -5.0)),
			"radius": randf_range(1.2, 3.0),
			"phase": randf() * TAU,
			"alpha": randf_range(0.05, 0.16),
		})

func clear() -> void:
	_dots.clear()
	_rings.clear()
	_sparks.clear()
	_arcs.clear()
	_popups.clear()
	queue_redraw()

func burst(pos: Vector2, count: int, colors: Array, speed: float, radius: float) -> void:
	if reduced_motion:
		return
	for i in range(count):
		if _dots.size() >= MAX_DOTS:
			break
		var angle := randf() * TAU
		var magnitude := randf_range(speed * 0.35, speed)
		_dots.append({
			"pos": pos,
			"vel": Vector2(cos(angle), sin(angle)) * magnitude - Vector2(0.0, speed * 0.25),
			"gravity": 900.0,
			"life": randf_range(0.45, 1.0),
			"max_life": 1.0,
			"radius": randf_range(radius * 0.5, radius),
			"color": colors[randi() % colors.size()],
		})

## Combo/streak milestone payoff: layered rings, a colored starburst, and a
## generous burst in the multiplier's color.
func streak_burst(pos: Vector2, color: Color, mult: int) -> void:
	if reduced_motion:
		return
	for i in range(3):
		ring(pos - Vector2(0.0, 7.0 * float(i)))
	starburst(pos, color, 18 + mult * 4)
	burst(pos, 22 + mult * 6, [color, Color.WHITE, color.lightened(0.35)], 430.0 + mult * 60.0, 6.0)

## A broken combo: a short, muted puff so the loss reads without noise.
func combo_lost(pos: Vector2) -> void:
	if reduced_motion:
		return
	burst(pos, 10, [Color("9fb0c9"), Color("cdd7e8")], 150.0, 3.0)

func ring(pos: Vector2) -> void:
	if reduced_motion:
		return
	if _rings.size() >= MAX_RINGS:
		return
	_rings.append({"pos": pos, "radius": 14.0, "life": 0.42, "max_life": 0.42})

## Radiating spark rays; used for the satisfying landing payoff.
func starburst(pos: Vector2, color: Color, count: int = 12) -> void:
	if reduced_motion:
		return
	for i in range(count):
		if _sparks.size() >= MAX_SPARKS:
			break
		var angle := TAU * float(i) / float(count) + randf() * 0.25
		_sparks.append({
			"pos": pos,
			"dir": Vector2(cos(angle), sin(angle)),
			"length": 10.0,
			"life": 0.34,
			"max_life": 0.34,
			"color": color,
		})

## A short jagged lightning bolt; used for cloud deaths and zap hits.
func arc(pos: Vector2, color: Color = Color("ffd60a")) -> void:
	if reduced_motion:
		return
	if _arcs.size() >= MAX_ARCS:
		return
	var points := PackedVector2Array()
	var segments := 5
	var step := 46.0
	points.append(pos)
	for i in range(1, segments):
		points.append(pos + Vector2(randf_range(-22.0, 22.0), step * float(i)))
	points.append(pos + Vector2(randf_range(-10.0, 10.0), step * float(segments)))
	_arcs.append({"points": points, "life": 0.16, "max_life": 0.16, "color": color})

func popup(pos: Vector2, text: String, color: Color, size: int = 28, angle: float = 0.0) -> void:
	if _popups.size() >= MAX_POPUPS:
		return
	var entry := {
		"pos": pos,
		"vel_y": -70.0,
		"life": 1.15,
		"max_life": 1.15,
		"text": text,
		"color": color,
		"size": size,
		"angle": angle,
	}
	_drop_overlapping(_popup_rect(entry))
	_popups.append(entry)

## In-world sticker popup: a GOLD pill with an INK border/ledge and ink text,
## tilted like a slapped-on sticker (docs/mockups/v3/run.html "×3 COMBO").
func sticker_popup(pos: Vector2, text: String, size: int = 28, angle: float = 0.0) -> void:
	if _popups.size() >= MAX_POPUPS:
		return
	var style := StyleBoxFlat.new()
	style.bg_color = GOLD
	style.border_color = INK
	style.set_border_width_all(6)
	style.border_width_bottom = 12
	style.set_corner_radius_all(999)
	var entry := {
		"pos": pos,
		"vel_y": -70.0,
		"life": 1.15,
		"max_life": 1.15,
		"text": text,
		"color": INK,
		"size": size,
		"sticker": style,
		"angle": angle,
	}
	_drop_overlapping(_popup_rect(entry))
	_popups.append(entry)

## World-space rects of the live text popups. The owner rule (2026-10-01) is that
## no two popup rects may ever overlap; tests assert this through this accessor.
func popup_rects() -> Array[Rect2]:
	var out: Array[Rect2] = []
	for p in _popups:
		out.append(_popup_rect(p))
	return out

## A popup's axis-aligned bounds, measured with the same font metrics it draws
## with (outline + shadow for plain text, pill padding for stickers).
func _popup_rect(p: Dictionary) -> Rect2:
	if _font == null:
		return Rect2()
	var text_size := _font.get_string_size(
		p["text"], HORIZONTAL_ALIGNMENT_LEFT, -1, int(p["size"])
	)
	var local: Rect2
	if p.has("sticker"):
		var box := text_size + Vector2(40.0, 18.0)
		local = Rect2(-box * 0.5, box)
	else:
		var pad := float(int(maxf(3.0, roundf(float(p["size"]) * 0.26)))) + 2.0
		var ascent := _font.get_ascent(int(p["size"]))
		var descent := _font.get_descent(int(p["size"]))
		var drop := maxf(3.0, roundf(float(p["size"]) * 0.2))
		local = Rect2(
			Vector2(-text_size.x * 0.5 - pad, -ascent - pad),
			Vector2(text_size.x + pad * 2.0, ascent + descent + pad * 2.0 + drop)
		)
	var origin: Vector2 = p["pos"]
	var angle := float(p.get("angle", 0.0))
	if is_zero_approx(angle):
		return Rect2(origin + local.position, local.size)
	var min_v := Vector2(INF, INF)
	var max_v := Vector2(-INF, -INF)
	for corner in [
		local.position,
		local.position + Vector2(local.size.x, 0.0),
		local.position + local.size,
		local.position + Vector2(0.0, local.size.y),
	]:
		var rotated: Vector2 = (corner as Vector2).rotated(angle) + origin
		min_v = min_v.min(rotated)
		max_v = max_v.max(rotated)
	return Rect2(min_v, max_v - min_v)

## Owner rule: feedback never stacks. A new popup drops every live popup whose
## rect it would intersect, so two popups can never be readable on top of
## each other. Popups only drift vertically at the same rate, so rects that are
## disjoint at spawn stay disjoint for their whole life.
func _drop_overlapping(rect: Rect2) -> void:
	if _popups.is_empty():
		return
	var kept: Array = []
	for p in _popups:
		if _popup_rect(p).intersects(rect):
			continue
		kept.append(p)
	_popups = kept

func _process(delta: float) -> void:
	_update_motes(delta)
	if _dots.is_empty() and _rings.is_empty() and _sparks.is_empty() \
			and _arcs.is_empty() and _popups.is_empty():
		return

	var kept_dots: Array = []
	for d in _dots:
		var life: float = d["life"] - delta
		if life > 0.0:
			var vel: Vector2 = d["vel"]
			vel.y += float(d["gravity"]) * delta
			var pos: Vector2 = d["pos"] + vel * delta
			if pos.y > ground_y - 2.0:
				pos.y = ground_y - 2.0
				vel.y *= -0.35
				vel.x *= 0.7
			d["life"] = life
			d["vel"] = vel
			d["pos"] = pos
			kept_dots.append(d)
	_dots = kept_dots

	var kept_rings: Array = []
	for r in _rings:
		var life: float = r["life"] - delta
		if life > 0.0:
			r["life"] = life
			r["radius"] = float(r["radius"]) + (112.0 - float(r["radius"])) * minf(1.0, delta * 7.5)
			kept_rings.append(r)
	_rings = kept_rings

	var kept_popups: Array = []
	for p in _popups:
		var life: float = p["life"] - delta
		if life > 0.0:
			p["life"] = life
			p["pos"] = p["pos"] + Vector2(0.0, p["vel_y"] * delta)
			p["vel_y"] = float(p["vel_y"]) * 0.94
			kept_popups.append(p)
	_popups = kept_popups

	var kept_sparks: Array = []
	for s in _sparks:
		var life: float = s["life"] - delta
		if life > 0.0:
			s["life"] = life
			s["length"] = float(s["length"]) + 520.0 * delta
			kept_sparks.append(s)
	_sparks = kept_sparks

	var kept_arcs: Array = []
	for a in _arcs:
		var life: float = a["life"] - delta
		if life > 0.0:
			a["life"] = life
			kept_arcs.append(a)
	_arcs = kept_arcs

	queue_redraw()

func _update_motes(delta: float) -> void:
	if _motes.is_empty():
		return
	for m in _motes:
		var pos: Vector2 = m["pos"] + m["vel"] * delta
		pos.x += sin(float(m["phase"]) + pos.y * 0.01) * 6.0 * delta
		if pos.y < -8.0:
			pos.y = _mote_bounds.y + 8.0
		if pos.x < -8.0:
			pos.x = _mote_bounds.x + 8.0
		elif pos.x > _mote_bounds.x + 8.0:
			pos.x = -8.0
		m["pos"] = pos
	queue_redraw()

func _draw() -> void:
	for m in _motes:
		draw_circle(m["pos"], m["radius"], Color(1.0, 0.96, 0.85, m["alpha"]))

	for d in _dots:
		var alpha: float = clampf(float(d["life"]) / float(d["max_life"]), 0.0, 1.0)
		var color: Color = d["color"]
		color.a = alpha
		draw_circle(d["pos"], d["radius"], color)
		draw_arc(d["pos"], d["radius"], 0.0, TAU, 12, Color(0.12, 0.09, 0.16, alpha), 1.6, true)

	for r in _rings:
		var alpha: float = clampf(float(r["life"]) / float(r["max_life"]), 0.0, 1.0) * 0.6
		draw_arc(r["pos"], r["radius"], 0.0, TAU, 48, Color(1.0, 1.0, 1.0, alpha), 4.5, true)
		draw_arc(r["pos"], float(r["radius"]) * 0.74, 0.0, TAU, 48, Color(1.0, 0.84, 0.24, alpha), 2.0, true)

	for s in _sparks:
		var alpha: float = clampf(float(s["life"]) / float(s["max_life"]), 0.0, 1.0)
		var color: Color = s["color"]
		color.a = alpha
		var dir: Vector2 = s["dir"]
		draw_line(s["pos"] + dir * 6.0, s["pos"] + dir * float(s["length"]), color, 3.0 * alpha, true)

	for a in _arcs:
		var alpha: float = clampf(float(a["life"]) / float(a["max_life"]), 0.0, 1.0)
		var color: Color = a["color"]
		color.a = alpha
		draw_polyline(a["points"], color, 4.0, true)
		draw_polyline(a["points"], Color(1.0, 1.0, 1.0, alpha * 0.8), 1.6, true)

	if _font == null:
		return
	for p in _popups:
		var alpha: float = minf(1.0, clampf(float(p["life"]) / float(p["max_life"]), 0.0, 1.0) * 1.6)
		if p.has("sticker"):
			_draw_sticker_popup(p, alpha)
			continue
		var color: Color = p["color"]
		color.a = alpha
		var ink := Color(INK.r, INK.g, INK.b, alpha)
		var text: String = p["text"]
		var size: int = p["size"]
		var angle := float(p.get("angle", 0.0))
		var width := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		var origin: Vector2 = p["pos"] - Vector2(width * 0.5, 0.0)
		if angle != 0.0:
			# Tilt around the popup's own point so the text stays put.
			draw_set_transform(Vector2(p["pos"]), angle, Vector2.ONE)
			origin = Vector2(-width * 0.5, 0.0)
		var outline := int(maxf(3.0, roundf(float(size) * 0.26)))
		var drop := Vector2(0.0, maxf(3.0, roundf(float(size) * 0.2)))
		draw_string(_font, origin + drop, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, ink)
		draw_string_outline(_font, origin, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, outline, ink)
		draw_string(_font, origin, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)
		if angle != 0.0:
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

## One sticker popup: tilted GOLD pill (INK border + ledge) with centered ink text.
func _draw_sticker_popup(p: Dictionary, alpha: float) -> void:
	var text: String = p["text"]
	var size: int = p["size"]
	var style: StyleBoxFlat = p["sticker"]
	var fill := GOLD
	fill.a = alpha
	style.bg_color = fill
	var border := INK
	border.a = alpha
	style.border_color = border
	var text_size := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size)
	var box := text_size + Vector2(40.0, 18.0)
	draw_set_transform(Vector2(p["pos"]), float(p.get("angle", 0.0)), Vector2.ONE)
	draw_style_box(style, Rect2(-box * 0.5, box))
	var ascent := _font.get_ascent(size)
	var descent := _font.get_descent(size)
	var baseline := (ascent - descent) * 0.5 - 3.0
	var ink := INK
	ink.a = alpha
	draw_string(
		_font, Vector2(-text_size.x * 0.5, baseline), text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, size, ink
	)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
