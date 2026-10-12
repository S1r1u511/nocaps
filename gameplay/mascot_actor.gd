extends Node2D
class_name MascotActor

## A community mascot travelling through the run. Renders the community's art (or a
## procedural placeholder when no art exists), exposes the head landing band, and
## shows the fitted cap once claimed. The player's own mascot carries a YOURS tag
## instead of a ring; rivals are slightly desaturated. Every mascot floats on a
## soft cloud puff. It never decides score or failure.

var definition: MascotDefinition
var cap_definition: CapDefinition
var is_target: bool = true
var accent: Color = Color.WHITE
var claimed: bool = false
## Only a centered ("perfect") landing seats the cap (owner decision 2026-10-01);
## edge landings claim the mascot but leave it bare.
var cap_seated: bool = false
## The YOURS onboarding tag is drawn only while this stays true (and until the
## mascot is landed on, so it never fights the PERFECT label); the run switches
## it off on own-crew mascots past the first few.
var show_yours_tag: bool = true
var passed_near: bool = false
var body_radius: float = 62.0

## Gameplay palette (docs/UI_V2_BRIEF.md §1).
const INK := Color("1d1033")
const YOURS := Color("5ee08a")
## #fbf2fb / #d9cdef at the mockup's soft cloud alphas, then dimmed so the puff
## never competes with the mascot or the cap.
const PUFF := Color(0.984, 0.949, 0.984, 0.28)
const PUFF_SHADE := Color(0.851, 0.804, 0.937, 0.16)
const RIVAL_TINT := Color(0.85, 0.85, 0.85)
const TAG_TEXT := "YOURS"
const TAG_FONT_SIZE := 24
const BOLD_FONT_PATH := "res://data/fonts/fredoka_bold.tres"

var _sprite: Sprite2D
var _cap_sprite: Sprite2D
var _content_size: Vector2 = Vector2(124.0, 124.0)
var _scale: float = 1.0
var _has_texture: bool = false
var _base_sprite_scale: Vector2 = Vector2.ONE
var _cap_base: Vector2 = Vector2.ZERO
var _clock: float = 0.0
var _phase: float = 0.0
var _tag_font: Font
var _tag_style: StyleBoxFlat

func _ready() -> void:
	_tag_font = load(BOLD_FONT_PATH) as Font
	if _tag_font == null:
		_tag_font = ThemeDB.fallback_font

func setup(
	def: MascotDefinition,
	target: bool,
	accent_color: Color,
	cap_def: CapDefinition,
	world_size: float,
	body_radius_ratio: float
) -> void:
	definition = def
	is_target = target
	accent = accent_color
	cap_definition = cap_def
	_phase = randf() * TAU
	_has_texture = def != null and def.idle_texture != null
	if _has_texture:
		_content_size = MascotFit.content_bounds(def.idle_texture).size
		_scale = MascotFit.scale_for(_content_size, world_size)
		body_radius = maxf(_content_size.x, _content_size.y) * _scale * body_radius_ratio
	else:
		_content_size = Vector2(124.0, 124.0)
		_scale = world_size / 124.0
		body_radius = world_size * 0.5
	_build_sprites()
	queue_redraw()

func head_top_y() -> float:
	if _has_texture:
		return position.y + MascotFit.head_top_y(definition, _content_size, _scale)
	return position.y - body_radius

func head_center_x() -> float:
	if _has_texture:
		return position.x + MascotFit.head_center_x(definition, _content_size, _scale)
	return position.x

func head_half_width() -> float:
	if _has_texture:
		return MascotFit.head_half_width(definition, _content_size, _scale)
	return body_radius * 0.55

func head_band_depth() -> float:
	if _has_texture:
		return MascotFit.head_depth(definition, _content_size, _scale)
	return body_radius * 0.35

func claim(seat_cap: bool = true) -> void:
	claimed = true
	cap_seated = seat_cap
	_refresh_cap()
	_pulse()
	queue_redraw()

func _process(delta: float) -> void:
	_clock += delta
	var bob := sin(_clock * 2.2 + _phase) * 3.0
	if _sprite != null:
		_sprite.position.y = bob
	if _cap_sprite != null:
		_cap_sprite.position = _cap_base + Vector2(0.0, bob)

func _pulse() -> void:
	if _sprite == null or not is_inside_tree():
		return
	_sprite.scale = _base_sprite_scale * 1.18
	var tween := create_tween()
	tween.tween_property(_sprite, "scale", _base_sprite_scale, 0.2) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _build_sprites() -> void:
	if _sprite == null:
		_sprite = Sprite2D.new()
		add_child(_sprite)
	if _has_texture:
		var texture := definition.idle_texture
		var used := MascotFit.content_bounds(texture)
		var tex_size := Vector2(float(texture.get_width()), float(texture.get_height()))
		_sprite.texture = texture
		_sprite.offset = tex_size * 0.5 - (used.position + used.size * 0.5)
		_sprite.scale = Vector2.ONE * _scale
		_sprite.visible = true
		_sprite.modulate = Color.WHITE if is_target else RIVAL_TINT
		_base_sprite_scale = Vector2.ONE * _scale
	else:
		_sprite.visible = false
	if _cap_sprite == null:
		_cap_sprite = Sprite2D.new()
		add_child(_cap_sprite)
	_refresh_cap()

func _refresh_cap() -> void:
	if _cap_sprite == null:
		return
	var cap_texture: Texture2D = null
	if cap_definition != null:
		cap_texture = cap_definition.center_texture
	_cap_sprite.texture = cap_texture
	_cap_sprite.visible = claimed and cap_seated and cap_texture != null and _has_texture
	if not _cap_sprite.visible:
		return
	_cap_sprite.position = MascotFit.cap_local_position(definition, _content_size, _scale)
	_cap_base = _cap_sprite.position
	var cap_width := MascotFit.cap_width(definition, _content_size, _scale)
	var texture_width := maxf(float(cap_texture.get_width()), 1.0)
	_cap_sprite.scale = Vector2.ONE * (cap_width / texture_width)
	_cap_sprite.rotation = deg_to_rad(definition.cap_rotation)

func _draw() -> void:
	_draw_puff()
	if not _has_texture:
		draw_circle(Vector2.ZERO, body_radius, accent.darkened(0.28))
		draw_arc(Vector2.ZERO, body_radius, 0.0, TAU, 48, accent, 4.0, true)
	if is_target and show_yours_tag and not claimed:
		_draw_yours_tag()

## A small, faint flattened puff sitting under the mascot, drawn behind the sprite
## so the mascot reads as floating in the cloud sea without stealing attention.
func _draw_puff() -> void:
	var sprite_half := _content_size * 0.5 * _scale
	var extent := maxf(sprite_half.x, sprite_half.y) * 2.0 * 1.2
	var radius := extent / 5.4
	var center := Vector2(0.0, sprite_half.y - 2.0)
	draw_set_transform(center, 0.0, Vector2(1.0, 0.55))
	draw_circle(Vector2(-radius * 1.15, 0.0), radius * 0.95, PUFF_SHADE)
	draw_circle(Vector2(radius * 1.15, 0.0), radius * 0.95, PUFF_SHADE)
	draw_circle(Vector2.ZERO, radius * 1.05, PUFF_SHADE)
	draw_set_transform(Vector2(0.0, center.y - radius * 0.12), 0.0, Vector2(1.0, 0.55))
	draw_circle(Vector2(-radius * 0.95, 0.0), radius * 0.78, PUFF)
	draw_circle(Vector2(radius * 0.95, 0.0), radius * 0.78, PUFF)
	draw_circle(Vector2(0.0, -radius * 0.32), radius * 0.92, PUFF)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

## The player's own mascot marker: a YOURS chip with a down arrow above the head.
func _draw_yours_tag() -> void:
	var font := _tag_font
	if font == null:
		font = ThemeDB.fallback_font
	var head_x := head_center_x() - position.x
	var head_y := head_top_y() - position.y
	var text_size := font.get_string_size(TAG_TEXT, HORIZONTAL_ALIGNMENT_LEFT, -1, TAG_FONT_SIZE)
	var chip_size := Vector2(maxf(text_size.x + 28.0, 84.0), float(TAG_FONT_SIZE) + 20.0)
	var tip_y := head_y - 8.0
	var chip_bottom := tip_y - 22.0
	var chip := Rect2(head_x - chip_size.x * 0.5, chip_bottom - chip_size.y, chip_size.x, chip_size.y)
	draw_style_box(_yours_tag_style(), chip)
	var baseline := chip.position.y \
		+ (chip.size.y + font.get_ascent(TAG_FONT_SIZE) - font.get_descent(TAG_FONT_SIZE)) * 0.5
	draw_string(
		font,
		Vector2(chip.position.x, baseline),
		TAG_TEXT,
		HORIZONTAL_ALIGNMENT_CENTER,
		chip.size.x,
		TAG_FONT_SIZE,
		INK
	)
	var arrow := PackedVector2Array([
		Vector2(head_x - 15.0, chip_bottom + 6.0),
		Vector2(head_x + 15.0, chip_bottom + 6.0),
		Vector2(head_x, tip_y),
	])
	draw_colored_polygon(arrow, YOURS)
	draw_polyline(PackedVector2Array([arrow[0], arrow[1], arrow[2], arrow[0]]), INK, 3.0, true)

func _yours_tag_style() -> StyleBoxFlat:
	if _tag_style == null:
		_tag_style = StyleBoxFlat.new()
		_tag_style.bg_color = YOURS
		_tag_style.border_color = INK
		_tag_style.set_border_width_all(5)
		_tag_style.set_corner_radius_all(16)
	return _tag_style
