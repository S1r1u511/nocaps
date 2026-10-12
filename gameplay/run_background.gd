extends Node2D
class_name RunBackground

## Calm background: an optional painted sky (cover-cropped, INK-scrimmed) or the
## procedural fallback gradient sky and soft sun glow, plus a soft cloud sea low on
## the bottom edge that replaces any floor/ground visual (cappycap feel: subtle,
## semi-transparent, no outlines). Optional parallax layer textures (from a
## BackgroundProfile) draw on top.

const INK := Color("1d1033")
const CLOUD_BACK := Color("e9dcf7")
const CLOUD_FRONT := Color("fbf2fb")
const CLOUD_SPAN_PAD := 480.0
const CLOUD_STEP := 42.0
const CLOUD_PARALLAX := 0.08

var _profile: BackgroundProfile
var _viewport_size: Vector2 = Vector2(720.0, 1280.0)
var _layer_nodes: Array = []
var _sky: GradientTexture2D
var _scrim: GradientTexture2D
var _sky_texture: Texture2D
var _dusk_scrim: GradientTexture2D
var _cloud_scroll: float = 0.0

func _ready() -> void:
	var viewport := get_viewport()
	if viewport != null:
		viewport.size_changed.connect(_on_viewport_resized)

## Keeps the sky, sun, parallax layers, and cloud sea sized to the live viewport
## (720×1280, 720×1560, or any other device) instead of a fixed baseline.
func _on_viewport_resized() -> void:
	var viewport := get_viewport()
	if viewport == null:
		return
	_viewport_size = viewport.get_visible_rect().size
	_build()

func apply(profile: BackgroundProfile, _ground_y: float = 0.0) -> void:
	_profile = profile
	var viewport := get_viewport()
	if viewport != null:
		_viewport_size = viewport.get_visible_rect().size
	_build()

func scroll(step: float) -> void:
	for entry in _layer_nodes:
		var sprite: Sprite2D = entry["sprite"]
		if not is_instance_valid(sprite):
			continue
		sprite.position.x -= step * float(entry["factor"])
		var width := float(entry["width"])
		if width > 1.0 and sprite.position.x <= -width:
			sprite.position.x += width
	_cloud_scroll = fposmod(_cloud_scroll + step * CLOUD_PARALLAX, 100000.0)
	queue_redraw()

func _build() -> void:
	for child in get_children():
		child.queue_free()
	_layer_nodes.clear()

	var sky_top := Color("141a33")
	var sky_bottom := Color("4a3a63")
	if _profile != null:
		sky_top = _profile.sky_top_color
		sky_bottom = _profile.sky_bottom_color
	_sky_texture = _profile.sky_texture if _profile != null else null
	if _sky_texture != null:
		_sky = null
		_scrim = null
		_dusk_scrim = _make_dusk_scrim()
	else:
		_sky = _make_gradient(sky_top, sky_bottom)
		_scrim = _make_gradient(Color(0.02, 0.02, 0.06, 0.0), Color(0.02, 0.02, 0.06, 0.5))
		_dusk_scrim = null

	if _profile != null:
		for layer in _profile.layers:
			if layer == null or layer.texture == null:
				continue
			var texture := layer.texture
			var layer_scale := _viewport_size.x / maxf(float(texture.get_width()), 1.0)
			var scaled_height := float(texture.get_height()) * layer_scale
			var sprite := Sprite2D.new()
			sprite.texture = texture
			sprite.centered = false
			sprite.scale = Vector2.ONE * layer_scale
			sprite.modulate = layer.modulate
			var y := layer.y_offset
			if layer.align_bottom:
				y = _viewport_size.y - scaled_height + layer.y_offset
			sprite.position = Vector2(0.0, y)
			add_child(sprite)
			_layer_nodes.append({
				"sprite": sprite,
				"factor": layer.scroll_factor,
				"width": _viewport_size.x,
			})

	queue_redraw()

func _draw() -> void:
	if _sky_texture != null:
		_draw_sky_texture()
		if _dusk_scrim != null:
			draw_texture_rect(_dusk_scrim, Rect2(Vector2.ZERO, _viewport_size), false)
	else:
		if _sky != null:
			draw_texture_rect(_sky, Rect2(Vector2.ZERO, _viewport_size), false)
		_draw_sun()
		if _scrim != null:
			draw_texture_rect(
				_scrim,
				Rect2(Vector2(0.0, _viewport_size.y * 0.4), Vector2(_viewport_size.x, _viewport_size.y * 0.6)),
				false
			)

	_draw_cloud_sea()

func _draw_sun() -> void:
	var accent := Color("ffcf7a")
	if _profile != null:
		accent = _profile.accent_color
	var sun := Vector2(_viewport_size.x * 0.68, _viewport_size.y * 0.24)
	for i in range(5):
		var radius := 34.0 + float(i) * 30.0
		var alpha := 0.06 * (1.0 - float(i) / 5.0)
		draw_circle(sun, radius, Color(accent.r, accent.g, accent.b, alpha))
	draw_circle(sun, 26.0, Color(accent.r, accent.g, accent.b, 0.85))

## Two soft cloud banks hugging the bottom edge: a dimmer, taller back layer and a
## brighter, lower front layer. Flat wavy silhouettes fade in from the crest, with
## no outlines, mirroring the cappycap prototype's cloud sea. Kept deliberately
## faint and low so nothing competes with mascots or the cap.
func _draw_cloud_sea() -> void:
	var span := _viewport_size.x + CLOUD_SPAN_PAD
	var back := fposmod(_cloud_scroll, span)
	var front := fposmod(_cloud_scroll * 1.6, span)
	_draw_cloud_layer(back, span, 150.0, 0.0, 22.0, CLOUD_BACK, 0.04, 0.20)
	_draw_cloud_layer(front, span, 96.0, 90.0, 16.0, CLOUD_FRONT, 0.11, 0.30)

## One continuous wavy silhouette spanning the whole viewport, with the wave
## evaluated in world space so the crest is unbroken from edge to edge (no tile
## seam anywhere, including the left and right edges).
func _draw_cloud_layer(
	x_offset: float,
	width: float,
	height: float,
	seed: float,
	amplitude: float,
	color: Color,
	alpha_top: float,
	alpha_bottom: float
) -> void:
	var bottom := _viewport_size.y + 12.0
	var crest := _viewport_size.y - height
	var points := PackedVector2Array()
	var colors := PackedColorArray()
	var x := 0.0
	while x <= width:
		var wave := sin((x_offset + x + seed) * 0.021) + 0.6 * cos((x_offset + x + seed) * 0.047)
		points.append(Vector2(x, crest + wave * amplitude))
		colors.append(Color(color.r, color.g, color.b, alpha_top))
		x += CLOUD_STEP
	points.append(Vector2(width, bottom))
	colors.append(Color(color.r, color.g, color.b, alpha_bottom))
	points.append(Vector2(0.0, bottom))
	colors.append(Color(color.r, color.g, color.b, alpha_bottom))
	draw_polygon(points, colors)

## Cover-fits the painted sky: fills the viewport, keeps its aspect, crops the
## center horizontally, and anchors the bottom so the painted skyline sits low.
func _draw_sky_texture() -> void:
	var texture_size := Vector2(float(_sky_texture.get_width()), float(_sky_texture.get_height()))
	if texture_size.x <= 0.0 or texture_size.y <= 0.0:
		return
	var cover := maxf(_viewport_size.x / texture_size.x, _viewport_size.y / texture_size.y)
	var drawn_size := texture_size * cover
	var origin := Vector2(
		(_viewport_size.x - drawn_size.x) * 0.5,
		_viewport_size.y - drawn_size.y
	)
	draw_texture_rect(_sky_texture, Rect2(origin, drawn_size), false)

func _make_dusk_scrim() -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(INK, 0.35))
	gradient.set_color(1, Color(INK, 0.45))
	gradient.add_point(0.5, Color(INK, 0.15))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_LINEAR
	texture.fill_from = Vector2(0.5, 0.0)
	texture.fill_to = Vector2(0.5, 1.0)
	texture.width = 8
	texture.height = int(maxf(_viewport_size.y, 2.0))
	return texture

func _make_gradient(top: Color, bottom: Color) -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.set_color(0, top)
	gradient.set_color(1, bottom)
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_LINEAR
	texture.fill_from = Vector2(0.5, 0.0)
	texture.fill_to = Vector2(0.5, 1.0)
	texture.width = 8
	texture.height = int(maxf(_viewport_size.y, 2.0))
	return texture
