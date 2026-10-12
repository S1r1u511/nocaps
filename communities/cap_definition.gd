extends Resource
class_name CapDefinition

## A cap design. A community may supply its own; otherwise the shared default cap
## is used. Multiple caps per community (reward unlocks) can be added later as a
## list without changing gameplay code. See docs/09_COMMUNITY_SYSTEM_HANDOFF.md.

@export var id: StringName = &"default"
@export var display_name: String = "Default Cap"
@export var side_texture: Texture2D
@export var center_texture: Texture2D
