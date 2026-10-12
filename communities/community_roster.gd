extends Resource
class_name CommunityRoster

## Authored, ordered list of communities. Explicit (not a folder scan) so order and
## enablement are controlled; the backend can overlay this later.

@export var communities: Array[CommunityDefinition] = []
