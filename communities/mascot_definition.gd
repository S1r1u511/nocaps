extends Resource
class_name MascotDefinition

## Authored mascot identity: art plus cap fit and head landing band. Fit values are
## fractions of the mascot's opaque content bounds, so art resolution and transparent
## padding never affect fit. Tune with `tools/mascot_fit_tool.tscn`.
## See docs/09_COMMUNITY_SYSTEM_HANDOFF.md.

@export var id: StringName = &"mascot"
@export var display_name: String = "Mascot"
@export var idle_texture: Texture2D
@export var claimed_texture: Texture2D

@export_group("Cap fit (fractions of the mascot's opaque content)")
## Where the seated cap's center sits: (0,0) top-left of the content, (1,1) bottom-right.
@export var cap_anchor: Vector2 = Vector2(0.5, 0.12)
## Cap width as a fraction of the content width.
@export_range(0.05, 2.0, 0.01) var cap_scale: float = 0.5
@export_range(-180.0, 180.0, 1.0) var cap_rotation: float = 0.0

@export_group("Head landing band (fractions of the mascot's opaque content)")
@export_range(0.0, 1.0, 0.01) var head_band_center_x: float = 0.5
@export_range(0.05, 1.0, 0.01) var head_band_half_width: float = 0.28
@export_range(0.0, 1.0, 0.01) var head_band_top: float = 0.0
@export_range(0.02, 1.0, 0.01) var head_band_depth: float = 0.14
