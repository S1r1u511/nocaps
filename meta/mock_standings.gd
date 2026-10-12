extends RefCounted
class_name MockStandings

## Demo weekly standings until the backend phase. Community bases are demo pacing
## values for the roster crews only (no invented crews); the player's local
## contribution is merged in so the board reacts to play.

const COMMUNITY_DAILY := {"mert": 2140, "wif": 1720}
const COMMUNITY_WEEKLY := {"mert": 12480, "wif": 9860}

## Sorted community rows: [{name, sub, score, mine, community}].
static func communities(save: SaveManager, period: StringName) -> Array:
	var weekly := period == &"weekly"
	var selected := &""
	if save != null:
		selected = save.selected_community_id
	var rows: Array = []
	for community in CommunityRepository.enabled_sorted(CommunityRepository.load_roster()):
		var base := int((COMMUNITY_WEEKLY if weekly else COMMUNITY_DAILY).get(String(community.id), 4200))
		var mine := 0
		if save != null and selected == community.id:
			mine = save.week_total(community.id) if weekly else save.day_total(community.id)
		rows.append({
			"name": community.display_name,
			"sub": "YOURS" if selected == community.id else "",
			"score": base + mine,
			"mine": selected == community.id,
			"community": community,
		})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["score"] > b["score"])
	return rows

static func rank_label(index: int) -> String:
	match index:
		0:
			return "1st"
		1:
			return "2nd"
		2:
			return "3rd"
	return "%d" % (index + 1)
