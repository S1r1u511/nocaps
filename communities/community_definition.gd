extends Resource
class_name CommunityDefinition

## Authored community identity. Everything the run, selection UI, result, and
## leaderboard need comes from here (or from its optional cap/background, else the
## shared defaults). Adding a community is art + resources only.

@export var id: StringName = &"community"
@export var display_name: String = "Community"
@export_multiline var short_description: String = ""
## Long-form copy. Empty for now; the UI hides it until it is authored.
@export_multiline var description: String = ""
@export var mascot: MascotDefinition
## Optional: uses the shared default cap when null.
@export var cap: CapDefinition
## Optional: uses the shared default background when null.
@export var background: BackgroundProfile
@export var accent_color: Color = Color("ffe15a")
@export var enabled: bool = true
@export var sort_order: int = 0
@export var social_links: Array[String] = []
## Open / token / nft / role / follow. Model now, mechanisms later.
@export var eligibility_type: StringName = &"open"
@export var eligibility_config: Dictionary = {}
## Three weekly contribution thresholds (ascending). Crossing one shows a banner
## and is recorded for future rewards; v1 adds no bonus to leaderboards.
@export var weekly_tiers: PackedInt32Array = PackedInt32Array([150, 450, 1100])

## v2 identity/social additions. `social_links` stays the fallback when these
## are empty. See docs/UI_V2_BRIEF.md §4.
@export var x_handle: String = ""
@export var telegram_url: String = ""
@export var website_url: String = ""
@export var discord_url: String = ""
@export var token_symbol: String = ""
@export var token_ca: String = ""
## Demo chart mode for the token section: demo / live / off.
@export var token_show_chart: String = "off"
## {"title": String, "reward_text": String, "ends_at": ISO string}. Empty = none.
@export var featured_campaign: Dictionary = {}

const SOCIAL_X := &"x"
const SOCIAL_TELEGRAM := &"telegram"
const SOCIAL_WEBSITE := &"website"

## Resolves a social destination, preferring the explicit v2 fields and falling
## back to `social_links`. Returns "" when the community has no such link.
func social_url(kind: StringName) -> String:
	match kind:
		&"x":
			var handle := x_handle.strip_edges().trim_prefix("@")
			if not handle.is_empty():
				return "https://x.com/%s" % handle
			return _link_matching(["x.com/", "twitter.com/"])
		&"telegram":
			var telegram := telegram_url.strip_edges()
			if not telegram.is_empty():
				return telegram
			return _link_matching(["t.me/", "telegram."])
		&"website":
			var website := website_url.strip_edges()
			if not website.is_empty():
				return website
			return _first_other_link()
	return ""

func has_featured_campaign() -> bool:
	return not featured_campaign.is_empty()

func campaign_value(key: String, fallback: String = "") -> String:
	return String(featured_campaign.get(key, fallback))

func _link_matching(needles: Array) -> String:
	for link in social_links:
		var lower := String(link).to_lower()
		for needle in needles:
			if lower.contains(String(needle)):
				return String(link)
	return ""

func _first_other_link() -> String:
	for link in social_links:
		var lower := String(link).to_lower()
		if lower.contains("x.com/") or lower.contains("twitter.com/") or lower.contains("t.me/"):
			continue
		return String(link)
	return ""
