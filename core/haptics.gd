extends RefCounted
class_name Haptics

## Thin, guarded haptics helper so platform detail stays out of gameplay.
## `enabled` is set from the player's setting at boot. No-op off mobile.

static var enabled: bool = true

static func light(ms: int = 12) -> void:
	_vibrate(ms)

static func heavy(ms: int = 55) -> void:
	_vibrate(ms)

static func _vibrate(ms: int) -> void:
	if not enabled or ms <= 0:
		return
	if not OS.has_feature("mobile"):
		return
	Input.vibrate_handheld(ms)
