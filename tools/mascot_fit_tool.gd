@tool
extends Node2D

## Mascot Fit Tool (editor only).
##
## Assign a `community` (recommended) and/or a `mascot` and `cap`:
## - `mascot`/`cap` override the community's for preview only. They never change
##   what the game uses.
## - If left empty, they are resolved from `community` (mascot, and the community's
##   cap or the shared default cap).
## A status line above the mascot shows which mascot/cap is being previewed, so you
## can tell a community cap from the default fallback.
##
## Edit fit fields on the mascot in the Inspector and watch the seated cap and head
## landing band update live. Green rect = landing band; blue rect = opaque content
## bounds; white cross = node origin. Excluded from exports (tools/**).

@export var community: CommunityDefinition:
	set(value):
		community = value
		_rebuild()
@export var mascot: MascotDefinition:
	set(value):
		mascot = value
		_rebuild()
@export var cap: CapDefinition:
	set(value):
		cap = value
		_rebuild()
## Preview size: the larger opaque content dimension, in pixels.
@export_range(40.0, 600.0, 1.0) var world_size: float = 180.0:
	set(value):
		world_size = value
		_rebuild()
@export_range(0.25, 4.0, 0.01) var zoom: float = 1.5:
	set(value):
		zoom = value
		_rebuild()
@export var show_band: bool = true:
	set(value):
		show_band = value
		queue_redraw()
@export var show_content_bounds: bool = true:
	set(value):
		show_content_bounds = value
		queue_redraw()

var _sprite: Sprite2D
var _cap_sprite: Sprite2D
var _content_size: Vector2 = Vector2(1.0, 1.0)
var _scale: float = 1.0
var _signature: String = ""
var _status: String = ""

func _ready() -> void:
	set_process(true)
	_rebuild()

func _process(_delta: float) -> void:
	if not Engine.is_editor_hint():
		return
	if _build_signature() != _signature:
		_rebuild()

func _rebuild() -> void:
	_ensure_nodes()
	_signature = _build_signature()

	var active_mascot := _resolve_mascot()
	var active_cap := _resolve_cap()
	_status = _status_text(active_cap)

	if active_mascot == null or active_mascot.idle_texture == null:
		_sprite.texture = null
		_cap_sprite.texture = null
		_cap_sprite.visible = false
		queue_redraw()
		return

	var texture := active_mascot.idle_texture
	var used := MascotFit.content_bounds(texture)
	_content_size = used.size
	_scale = MascotFit.scale_for(_content_size, world_size) * zoom

	var tex_size := Vector2(float(texture.get_width()), float(texture.get_height()))
	_sprite.texture = texture
	_sprite.offset = tex_size * 0.5 - (used.position + used.size * 0.5)
	_sprite.scale = Vector2.ONE * _scale

	var cap_texture: Texture2D = active_cap.center_texture if active_cap != null else null
	_cap_sprite.texture = cap_texture
	_cap_sprite.visible = cap_texture != null
	if _cap_sprite.visible:
		_cap_sprite.position = MascotFit.cap_local_position(active_mascot, _content_size, _scale)
		var cap_width := MascotFit.cap_width(active_mascot, _content_size, _scale)
		_cap_sprite.scale = Vector2.ONE * (cap_width / maxf(float(cap_texture.get_width()), 1.0))
		_cap_sprite.rotation = deg_to_rad(active_mascot.cap_rotation)

	queue_redraw()

func _resolve_mascot() -> MascotDefinition:
	if mascot != null:
		return mascot
	if community != null:
		return community.mascot
	return null

func _resolve_cap() -> CapDefinition:
	if cap != null:
		return cap
	if community != null:
		return CommunityRepository.resolve_cap(community)
	return null

func _status_text(active_cap: CapDefinition) -> String:
	var mascot_label := "?"
	if mascot != null:
		mascot_label = "%s (manual)" % mascot.id
	elif community != null and community.mascot != null:
		mascot_label = "%s (community)" % community.mascot.id

	var cap_label := "none"
	if cap != null:
		cap_label = "%s (manual/preview)" % cap.id
	elif community != null and community.cap != null:
		cap_label = "%s (community)" % community.cap.id
	elif active_cap != null:
		cap_label = "%s (default fallback)" % active_cap.id
	return "mascot: %s   cap: %s" % [mascot_label, cap_label]

func _ensure_nodes() -> void:
	if _sprite == null:
		_sprite = Sprite2D.new()
		add_child(_sprite)
	if _cap_sprite == null:
		_cap_sprite = Sprite2D.new()
		add_child(_cap_sprite)

func _build_signature() -> String:
	return "%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s" % [
		mascot, cap, community, world_size, zoom, show_band,
		_resolve_mascot(), _resolve_cap(),
		_resolve_mascot().cap_anchor if _resolve_mascot() != null else "",
		_resolve_mascot().cap_scale if _resolve_mascot() != null else "",
		_resolve_mascot().cap_rotation if _resolve_mascot() != null else "",
		_resolve_mascot().head_band_center_x if _resolve_mascot() != null else "",
		_resolve_mascot().head_band_depth if _resolve_mascot() != null else "",
	]

func _draw() -> void:
	var active_mascot := _resolve_mascot()
	if active_mascot == null or active_mascot.idle_texture == null:
		return
	var size := _content_size * _scale
	if show_content_bounds:
		draw_rect(Rect2(-size * 0.5, size), Color(0.4, 0.7, 1.0, 0.5), false, 1.0)
	if show_band:
		var center_x := MascotFit.head_center_x(active_mascot, _content_size, _scale)
		var top := MascotFit.head_top_y(active_mascot, _content_size, _scale)
		var half := MascotFit.head_half_width(active_mascot, _content_size, _scale)
		var depth := MascotFit.head_depth(active_mascot, _content_size, _scale)
		draw_rect(Rect2(center_x - half, top, half * 2.0, depth), Color(0.2, 1.0, 0.4, 1.0), false, 2.0)
	draw_line(Vector2(-12.0, 0.0), Vector2(12.0, 0.0), Color.WHITE, 1.0)
	draw_line(Vector2(0.0, -12.0), Vector2(0.0, 12.0), Color.WHITE, 1.0)
	var font := ThemeDB.fallback_font
	if font != null:
		draw_string(
			font, Vector2(-size.x * 0.5, -size.y * 0.5 - 24.0), _status,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1, 1, 1, 0.85)
		)
