extends Resource
class_name BackgroundProfile

## Per-community (or default) background theming: colors plus optional parallax
## layers. A community without its own profile falls back to the shared default.
## See docs/08_VISUALS_HANDOFF.md.

@export var sky_top_color: Color = Color("0b1b33")
@export var sky_bottom_color: Color = Color("274060")
@export var accent_color: Color = Color("ffe15a")
@export var ground_color: Color = Color("141c2b")
@export var ground_line_color: Color = Color("f0b85a")
## Optional painted sky. When set, RunBackground draws it cover-cropped instead of
## the procedural gradient sky, sun glow, and hills, then lays a dusk scrim over it.
@export var sky_texture: Texture2D
## Optional full-screen backdrop image, drawn cover-cropped and static behind the
## parallax layers. Use this for a single painted scene; use `layers` for tiling
## parallax strips.
@export var backdrop_texture: Texture2D
@export var layers: Array[BackgroundLayer] = []
