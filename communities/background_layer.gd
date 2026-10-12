extends Resource
class_name BackgroundLayer

## One parallax layer of a BackgroundProfile. The layer is scaled to the viewport
## width (so author at 1080 px wide for crispness) and wraps horizontally, so the
## texture should tile seamlessly left-right.
## `scroll_factor` is relative to the world scroll speed (0 = static, 1 = same speed).

@export var texture: Texture2D
@export_range(0.0, 2.0, 0.01) var scroll_factor: float = 0.4
## Pixels from the top of the viewport (or from the bottom when `align_bottom`).
@export var y_offset: float = 0.0
## Anchor the layer to the bottom of the viewport instead of the top.
@export var align_bottom: bool = false
@export var modulate: Color = Color.WHITE
