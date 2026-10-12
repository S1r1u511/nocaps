extends Node2D
class_name CapController

## The player-controlled cap. Owns flight physics, cap art, and presentation juice
## (squash/stretch, tilt, death spin). It never decides score or failure.

signal flapped

const DEFAULT_SIDE_TEXTURE := "res://assets/caps/red_cap_side.png"

var velocity_y: float = 0.0
var cap_radius: float = 24.0
var max_fall_speed: float = 1150.0
var tilt_up: float = 0.5
var tilt_down: float = 1.0
var rotation_follow: float = 13.0
var flap_rotation_snap: float = 0.45
var land_rotation_snap: float = 0.62
var world_width: float = 96.0
var flap_stretch: float = 0.16
var land_squash: float = 0.26

var _sprite: Sprite2D
var _cap: CapDefinition
var _base_scale: float = 1.0
var _target_rotation: float = 0.0
var _dying: bool = false
var _tween: Tween
var _history: Array = []
var _aura_color: Color = Color.WHITE
var _aura_strength: float = 0.0

func _ready() -> void:
	_sprite = Sprite2D.new()
	add_child(_sprite)
	_apply_texture()

func _process(_delta: float) -> void:
	_history.push_front(position)
	if _history.size() > 8:
		_history.pop_back()
	queue_redraw()

## Short, fading air-line traces behind the cap. Skips big jumps (teleports) so it
## never draws stray long lines. A soft aura colored by the combo multiplier sits
## behind both the cap and the traces.
func _draw() -> void:
	if _aura_strength > 0.01:
		var glow := _aura_color
		glow.a = 0.16 + 0.30 * _aura_strength
		draw_arc(
			Vector2.ZERO, cap_radius * (1.15 + 0.30 * _aura_strength),
			0.0, TAU, 40, glow, 3.0 + 2.5 * _aura_strength, true
		)
		glow.a = 0.07 * _aura_strength
		draw_circle(Vector2.ZERO, cap_radius * (1.5 + 0.4 * _aura_strength), glow)

	if _history.size() < 2:
		return
	var speed := clampf(absf(velocity_y) / 900.0, 0.0, 1.0)
	for row in [-5.0, 5.0]:
		for i in range(1, _history.size()):
			var newer: Vector2 = _history[i - 1] - position + Vector2(0.0, row)
			var older: Vector2 = _history[i] - position + Vector2(0.0, row)
			if older.distance_to(newer) > 70.0:
				continue
			var t := 1.0 - float(i) / float(_history.size())
			var alpha := t * t * (0.28 + 0.32 * speed)
			draw_line(older, newer, Color(1.0, 1.0, 1.0, alpha), 0.5 + 2.0 * t, true)

## Combo aura: color and strength (0–1) set by the run as the multiplier rises.
func set_aura(color: Color, strength: float) -> void:
	_aura_color = color
	_aura_strength = clampf(strength, 0.0, 1.0)
	queue_redraw()

func set_cap(cap_definition: CapDefinition) -> void:
	_cap = cap_definition
	_apply_texture()

func set_world_width(value: float) -> void:
	world_width = maxf(value, 1.0)
	_apply_texture()

func flap(impulse: float) -> void:
	velocity_y = -impulse
	_snap_rotation(-flap_rotation_snap)
	_stretch(1.0 - flap_stretch, 1.0 + flap_stretch, 0.18)
	flapped.emit()

func bounce(impulse: float) -> void:
	velocity_y = -impulse
	_snap_rotation(-land_rotation_snap)
	_stretch(1.0 + land_squash, 1.0 - land_squash, 0.16)

func begin_death() -> void:
	_dying = true
	if _tween != null and _tween.is_valid():
		_tween.kill()
	if _sprite != null:
		_sprite.scale = Vector2.ONE * _base_scale

func revive() -> void:
	_dying = false
	_history.clear()
	_aura_strength = 0.0
	if _tween != null and _tween.is_valid():
		_tween.kill()
	if _sprite != null:
		_sprite.scale = Vector2.ONE * _base_scale
		_sprite.rotation = 0.0

func integrate(delta: float, gravity: float) -> void:
	velocity_y = minf(velocity_y + gravity * delta, max_fall_speed)
	position.y += velocity_y * delta
	if _sprite != null and not _dying:
		var t := clampf(velocity_y / maxf(max_fall_speed, 1.0), -1.0, 1.0)
		_target_rotation = t * (tilt_down if t > 0.0 else tilt_up)
		_sprite.rotation = lerp_angle(
			_sprite.rotation, _target_rotation, 1.0 - exp(-rotation_follow * delta)
		)

func spin(delta: float, speed: float) -> void:
	if _sprite != null:
		_sprite.rotation += speed * delta

## Flap and landing snap the tilt immediately so the cap reads as responsive.
func _snap_rotation(rotation: float) -> void:
	if _sprite == null or _dying:
		return
	_target_rotation = rotation
	_sprite.rotation = rotation

func _apply_texture() -> void:
	if _sprite == null:
		return
	var texture: Texture2D = null
	if _cap != null and _cap.side_texture != null:
		texture = _cap.side_texture
	if texture == null:
		texture = load(DEFAULT_SIDE_TEXTURE) as Texture2D
	_sprite.texture = texture
	if texture != null:
		var texture_width := maxf(float(texture.get_width()), 1.0)
		_base_scale = world_width / texture_width
		_sprite.scale = Vector2.ONE * _base_scale

func _stretch(scale_x: float, scale_y: float, time: float) -> void:
	if _sprite == null:
		return
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_sprite.scale = Vector2(_base_scale * scale_x, _base_scale * scale_y)
	_tween = create_tween()
	_tween.tween_property(_sprite, "scale", Vector2.ONE * _base_scale, time) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
