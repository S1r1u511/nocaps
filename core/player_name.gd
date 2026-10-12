extends RefCounted
class_name PlayerName

## Player display names for boards. A name is optional: without one the player
## shows as "Guest 1234" (from their stable player id). Names are 3–16 chars of
## letters, digits and `_`, with a small blocklist. Display only: never used as
## an id or for auth.

const MIN_LENGTH := 3
const MAX_LENGTH := 16
## Lowercase substrings that are never allowed in a name. Kept short and obvious;
## the backend can extend it later.
const BLOCKED := [
	"fuck", "shit", "bitch", "cunt", "nigg", "fag", "rape", "nazi", "hitler",
	"porn", "slut", "whore", "retard", "kys", "admin", "nocaps_team", "moderator",
]

## Cleans raw input: trims, spaces -> `_`, drops anything else not allowed.
static func sanitize(text: String) -> String:
	var out := ""
	for ch in text.strip_edges().replace(" ", "_"):
		var code := ch.unicode_at(0)
		var ok := (code >= 48 and code <= 57) or (code >= 65 and code <= 90) \
			or (code >= 97 and code <= 122) or ch == "_"
		if ok:
			out += ch
	while out.contains("__"):
		out = out.replace("__", "_")
	return out.trim_prefix("_").trim_suffix("_").left(MAX_LENGTH)

## Empty string when `name` is acceptable, otherwise a short reason to show.
static func problem(name: String) -> String:
	if name.length() < MIN_LENGTH:
		return "Use at least %d letters or numbers" % MIN_LENGTH
	if name.length() > MAX_LENGTH:
		return "Keep it to %d characters" % MAX_LENGTH
	if sanitize(name) != name:
		return "Letters, numbers and _ only"
	var lower := name.to_lower()
	for word in BLOCKED:
		if lower.contains(word):
			return "Pick a different name"
	if lower.begins_with("guest"):
		return "Pick a name that isn't Guest"
	return ""

static func is_valid(name: String) -> bool:
	return problem(name).is_empty()

## "Guest 1234" from the stable player id.
static func guest_name(player_id: String) -> String:
	var digits := ""
	for ch in player_id:
		if ch >= "0" and ch <= "9":
			digits += ch
	return "Guest %s" % ("0000" + digits).right(4)

## The name shown on boards for this save.
static func board_name(save: SaveManager) -> String:
	if save == null:
		return "Guest"
	if is_valid(save.display_name):
		return save.display_name
	return guest_name(save.ensure_player_id())
