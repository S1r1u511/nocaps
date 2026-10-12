extends RefCounted
class_name MascotFit

## Pure fit math. Values are authored as fractions of the mascot's opaque content
## bounds, so art resolution and transparent padding never affect fit. Node-space
## results are relative to the mascot's origin (content centered on origin).
## See docs/09_COMMUNITY_SYSTEM_HANDOFF.md.

static func scale_for(content_size: Vector2, world_size: float) -> float:
	return world_size / maxf(maxf(content_size.x, content_size.y), 1.0)

## Seated cap center, relative to the mascot origin.
static func cap_local_position(def: MascotDefinition, content_size: Vector2, scale: float) -> Vector2:
	var frac := def.cap_anchor - Vector2(0.5, 0.5)
	return Vector2(frac.x * content_size.x, frac.y * content_size.y) * scale

static func cap_width(def: MascotDefinition, content_size: Vector2, scale: float) -> float:
	return def.cap_scale * content_size.x * scale

## The seated cap's rendered width for a mascot at the given world size. The
## in-flight cap uses this so the flying cap matches the seated cap automatically.
static func seated_cap_width(def: MascotDefinition, world_size: float) -> float:
	if def == null or def.idle_texture == null:
		return 0.0
	var content := content_bounds(def.idle_texture).size
	var scale := scale_for(content, world_size)
	return def.cap_scale * content.x * scale

static func head_center_x(def: MascotDefinition, content_size: Vector2, scale: float) -> float:
	return (def.head_band_center_x - 0.5) * content_size.x * scale

static func head_top_y(def: MascotDefinition, content_size: Vector2, scale: float) -> float:
	return (def.head_band_top - 0.5) * content_size.y * scale

static func head_half_width(def: MascotDefinition, content_size: Vector2, scale: float) -> float:
	return def.head_band_half_width * content_size.x * scale

static func head_depth(def: MascotDefinition, content_size: Vector2, scale: float) -> float:
	return def.head_band_depth * content_size.y * scale

static var _content_cache: Dictionary = {}

## Opaque bounds of a texture, cached. Lets fit ignore transparent padding.
static func content_bounds(texture: Texture2D) -> Rect2:
	if texture == null:
		return Rect2()
	if _content_cache.has(texture):
		return _content_cache[texture]
	var size := Vector2(float(texture.get_width()), float(texture.get_height()))
	var rect := Rect2(Vector2.ZERO, size)
	var image := texture.get_image()
	if image != null:
		if image.is_compressed():
			image.decompress()
		var used := image.get_used_rect()
		if used.size.x > 0 and used.size.y > 0:
			rect = used
	_content_cache[texture] = rect
	return rect
