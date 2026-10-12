extends RefCounted
class_name SafeArea

## Display safe-area insets in game (viewport) coordinates, so HUD and menu
## chrome can dodge notches and gesture bars. Returns zero on desktop.

static func insets() -> Vector4:
	if not OS.has_feature("mobile"):
		return Vector4.ZERO
	var display_size := DisplayServer.window_get_size()
	if display_size.x <= 0 or display_size.y <= 0:
		return Vector4.ZERO
	var safe := DisplayServer.get_display_safe_area()
	if safe.size.x <= 0 or safe.size.y <= 0:
		return Vector4.ZERO
	var viewport_size := Vector2(720.0, 1280.0)
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null and tree.root != null:
		viewport_size = tree.root.get_visible_rect().size
	var scale_x := display_size.x / maxf(viewport_size.x, 1.0)
	var scale_y := display_size.y / maxf(viewport_size.y, 1.0)
	return Vector4(
		float(safe.position.x) / scale_x,
		float(safe.position.y) / scale_y,
		float(display_size.x - safe.end.x) / scale_x,
		float(display_size.y - safe.end.y) / scale_y
	)

static func top() -> float:
	return insets().y

static func bottom() -> float:
	return insets().w
