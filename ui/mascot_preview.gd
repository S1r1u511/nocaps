extends Control
class_name MascotPreview

## A community mascot with its cap seated, used everywhere a community is shown
## (home hero, crew cards, boards, result, hub). Draws directly with the shared
## `MascotFit` math so menus get clean art only: no cloud puff, no rival tint, no
## gameplay effects. Keeps the mockups' hard INK drop shadow.

const SHADOW := Color("1d1033")
const SHADOW_RATIO := 0.026

var _root: Node2D
var _sprite: Sprite2D
var _cap: Sprite2D

func setup(community: CommunityDefinition, size_px: float = 64.0) -> void:
	custom_minimum_size = Vector2(size_px, size_px)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_clear()
	if community == null or community.mascot == null or community.mascot.idle_texture == null:
		return
	var definition: MascotDefinition = community.mascot
	var texture: Texture2D = definition.idle_texture
	var content := MascotFit.content_bounds(texture)
	var content_size := content.size
	var scale := MascotFit.scale_for(content_size, size_px)
	var tex_size := Vector2(float(texture.get_width()), float(texture.get_height()))

	# Fit the whole composite (mascot + seated cap) inside the box, then align it
	# bottom-center so the cap never spills over neighbours above.
	var bounds := Rect2(-content_size * 0.5 * scale, content_size * scale)
	var cap := CommunityRepository.resolve_cap(community)
	var cap_texture: Texture2D = cap.center_texture if cap != null else null
	if cap_texture != null:
		var cap_used := MascotFit.content_bounds(cap_texture)
		var cap_scale := MascotFit.cap_width(definition, content_size, scale) \
			/ maxf(float(cap_texture.get_width()), 1.0)
		var cap_rect := Rect2(
			MascotFit.cap_local_position(definition, content_size, scale) - cap_used.size * cap_scale * 0.5,
			cap_used.size * cap_scale
		)
		bounds = bounds.merge(cap_rect)
	var fit := minf(size_px / maxf(bounds.size.x, 1.0), size_px / maxf(bounds.size.y, 1.0))
	scale *= fit

	_root = Node2D.new()
	_root.position = Vector2(size_px * 0.5 - bounds.get_center().x * fit, size_px - bounds.end.y * fit)
	add_child(_root)

	_sprite = Sprite2D.new()
	_sprite.texture = texture
	_sprite.offset = tex_size * 0.5 - (content.position + content.size * 0.5)
	_sprite.scale = Vector2.ONE * scale
	_root.add_child(_make_shadow(_sprite, size_px))
	_root.add_child(_sprite)

	if cap_texture == null:
		return
	_cap = Sprite2D.new()
	_cap.texture = cap_texture
	_cap.position = MascotFit.cap_local_position(definition, content_size, scale)
	var cap_width := MascotFit.cap_width(definition, content_size, scale)
	_cap.scale = Vector2.ONE * (cap_width / maxf(float(cap_texture.get_width()), 1.0))
	_cap.rotation = deg_to_rad(definition.cap_rotation)
	_root.add_child(_make_shadow(_cap, size_px))
	_root.add_child(_cap)

func _make_shadow(source: Sprite2D, size_px: float) -> Sprite2D:
	var shadow := Sprite2D.new()
	shadow.texture = source.texture
	shadow.offset = source.offset
	shadow.scale = source.scale
	shadow.rotation = source.rotation
	shadow.position = source.position + Vector2(0.0, size_px * SHADOW_RATIO)
	shadow.modulate = SHADOW
	return shadow

func _clear() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_root = null
	_sprite = null
	_cap = null

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and _root != null and is_instance_valid(_root):
		_root.position = size * 0.5
