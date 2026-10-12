extends SceneTree

## Community roster importer (docs/11_COMMUNITY_AUTHORING.md):
##   Godot --headless --path . --script res://tools/import_communities.gd
##   Godot --headless --path . --script res://tools/import_communities.gd -- --dry-run
##
## Reads data/communities/roster.json and writes/updates each crew's
## data/communities/<id>/community.tres. The roster is authoritative for the fields
## it owns; empty values clear them. Fields the roster does not own (mascot, cap,
## background, weekly_tiers) are preserved. A file is only rewritten when a value
## actually changes, so an unchanged roster leaves every .tres untouched.
##
## Roster -> resource mapping:
##   permission            -> enabled
##   join_rules/min_hold   -> eligibility_type + eligibility_config
##   campaign.reward       -> featured_campaign.reward_text
##   list position         -> sort_order

const ROSTER_PATH := "res://data/communities/roster.json"
const COMMUNITIES_DIR := "res://data/communities"
const ROSTER_RESOURCE_PATH := "res://data/communities/roster.tres"
const BASE58_ALPHABET := "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz"
const JOIN_RULES := ["follow_x", "hold_token"]
const CHART_MODES := ["", "demo", "live", "off"]

var _errors: Array[String] = []
var _warnings: Array[String] = []
var _seen_ids: Dictionary = {}
var _registered_ids: Dictionary = {}
var _dry_run := false
var _id_regex := RegEx.new()
var _changed_count := 0
var _created_count := 0
var _unchanged_count := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var args := OS.get_cmdline_args() + OS.get_cmdline_user_args()
	if args.has("--help") or args.has("-h"):
		print_usage()
		quit(0)
		return
	_dry_run = args.has("--dry-run")
	_id_regex.compile("^[a-z][a-z0-9_]*$")
	_registered_ids = _roster_resource_ids()

	var text := FileAccess.get_file_as_string(ROSTER_PATH)
	if text.is_empty():
		_fail("could not read %s" % ROSTER_PATH)
		_finish()
		return
	var json := JSON.new()
	if json.parse(text) != OK:
		_fail("%s parse error at line %d: %s" % [ROSTER_PATH, json.get_error_line(), json.get_error_message()])
		_finish()
		return
	if not (json.data is Array):
		_fail("%s must be a top-level array of crew objects" % ROSTER_PATH)
		_finish()
		return

	var entries: Array = json.data
	var parsed_entries: Array[Dictionary] = []
	for i in range(entries.size()):
		var parsed := _parse_entry(i, entries[i])
		if not parsed.is_empty():
			parsed_entries.append(parsed)
	for parsed in parsed_entries:
		_apply_entry(parsed, int(parsed["_order"]))
	_finish()

func print_usage() -> void:
	print("Community roster importer (docs/11_COMMUNITY_AUTHORING.md)")
	print("  Godot --headless --path . --script res://tools/import_communities.gd")
	print("  Godot --headless --path . --script res://tools/import_communities.gd -- --dry-run")
	print("")
	print("Reads %s and writes data/communities/<id>/community.tres." % ROSTER_PATH)
	print("--dry-run prints the changes without writing any file.")

# ---------------------------------------------------------------------------
# Validation
# ---------------------------------------------------------------------------

func _parse_entry(index: int, raw: Variant) -> Dictionary:
	var error_mark := _errors.size()
	var ctx := "roster.json[%d]" % index
	if not (raw is Dictionary):
		_fail("%s: entry must be an object" % ctx)
		return {}
	var entry := raw as Dictionary

	if not entry.has("id") or entry["id"] == null or not (entry["id"] is String):
		_fail("%s: missing 'id' (a string)" % ctx)
		return {}
	var id := String(entry["id"]).strip_edges()
	if id.is_empty():
		_fail("%s: missing 'id'" % ctx)
		return {}
	ctx = "roster.json[%d] (%s)" % [index, id]
	if not _id_regex.search(id):
		_fail("%s: id must be lowercase letters/digits/underscores, starting with a letter" % ctx)
		return {}
	if _seen_ids.has(id):
		_fail("%s: duplicate id (already imported in this run)" % ctx)
		return {}
	if not _registered_ids.has(id):
		_warn("%s: not listed in %s — add it there (editor) so it appears in the game" % [ctx, ROSTER_RESOURCE_PATH])
	_seen_ids[id] = true

	var parsed := {
		"id": id,
		"_order": index,
		"display_name": _string_field(entry, "display_name", ctx),
		"short_description": _string_field(entry, "short_description", ctx),
		"description": _string_field(entry, "description", ctx),
		"accent_color": Color(),
		"has_accent_color": false,
		"x_handle": "", "telegram_url": "", "website_url": "", "discord_url": "",
		"token_symbol": "", "token_ca": "", "token_show_chart": "",
		"join_rules": [], "min_hold": -1.0,
		"campaign_title": "", "campaign_reward": "", "campaign_ends_at": "",
		"permission": true,
	}

	var accent := _string_field(entry, "accent_color", ctx)
	if not accent.is_empty():
		if not Color.html_is_valid(accent):
			_fail("%s: accent_color '%s' is not a hex color (e.g. \"#FFD23F\")" % [ctx, accent])
			return {}
		parsed["accent_color"] = Color.html(accent)
		parsed["has_accent_color"] = true

	var socials := _sub_dict(entry, "socials", ctx)
	parsed["x_handle"] = _string_field(socials, "x_handle", ctx + " socials")
	parsed["telegram_url"] = _string_field(socials, "telegram_url", ctx + " socials")
	parsed["website_url"] = _string_field(socials, "website_url", ctx + " socials")
	parsed["discord_url"] = _string_field(socials, "discord_url", ctx + " socials")

	var token := _sub_dict(entry, "token", ctx)
	parsed["token_symbol"] = _string_field(token, "symbol", ctx + " token")
	var ca := _string_field(token, "ca", ctx + " token")
	if not ca.is_empty() and not _is_base58(ca):
		_fail("%s token: ca must be a base58 string of 32-44 characters (Solana mint) or empty" % ctx)
		return {}
	parsed["token_ca"] = ca
	var chart := _string_field(token, "show_chart", ctx + " token")
	if not CHART_MODES.has(chart):
		_fail("%s token: show_chart must be 'demo', 'live', 'off' or empty" % ctx)
		return {}
	parsed["token_show_chart"] = chart

	parsed["join_rules"] = _parse_join_rules(entry, ctx)
	parsed["min_hold"] = _parse_min_hold(entry, ctx)

	var campaign := _sub_dict(entry, "campaign", ctx)
	parsed["campaign_title"] = _string_field(campaign, "title", ctx + " campaign")
	parsed["campaign_reward"] = _string_field(campaign, "reward", ctx + " campaign")
	parsed["campaign_ends_at"] = _string_field(campaign, "ends_at", ctx + " campaign")
	if not parsed["campaign_ends_at"].is_empty():
		var iso: String = parsed["campaign_ends_at"]
		var unix := Time.get_unix_time_from_datetime_string(iso)
		if unix <= 0.0 and iso.length() == 10:
			unix = Time.get_unix_time_from_datetime_string(iso + "T00:00:00")
		if unix <= 0.0:
			_warn("%s campaign: ends_at '%s' is not an ISO date/time; the countdown will be hidden" % [ctx, iso])

	if entry.has("permission") and entry["permission"] != null and str(entry["permission"]) != "":
		if entry["permission"] is bool:
			parsed["permission"] = bool(entry["permission"])
		else:
			_fail("%s: permission must be true or false" % ctx)
			return {}
	if _errors.size() > error_mark:
		return {}
	return parsed

func _parse_join_rules(entry: Dictionary, ctx: String) -> Array[String]:
	var rules: Array[String] = []
	if not entry.has("join_rules") or entry["join_rules"] == null:
		return rules
	if not (entry["join_rules"] is Array):
		_fail("%s: join_rules must be an array of rule ids" % ctx)
		return rules
	for value in entry["join_rules"]:
		var rule := String(value) if value is String else ""
		if rule.is_empty() or not JOIN_RULES.has(rule):
			_fail("%s: join_rules value '%s' is not one of: %s" % [ctx, value, ", ".join(JOIN_RULES)])
			return rules
		if not rules.has(rule):
			rules.append(rule)
	return rules

func _parse_min_hold(entry: Dictionary, ctx: String) -> float:
	if not entry.has("min_hold") or entry["min_hold"] == null:
		return -1.0
	var value: Variant = entry["min_hold"]
	if value is String and String(value).strip_edges().is_empty():
		return -1.0
	if not (value is float or value is int):
		_fail("%s: min_hold must be a number >= 0 or empty" % ctx)
		return -1.0
	if float(value) < 0.0:
		_fail("%s: min_hold must be >= 0" % ctx)
		return -1.0
	return float(value)

func _string_field(source: Dictionary, key: String, ctx: String) -> String:
	if not source.has(key) or source[key] == null:
		return ""
	if source[key] is String:
		return String(source[key]).strip_edges()
	_fail("%s: '%s' must be a string" % [ctx, key])
	return ""

func _sub_dict(source: Dictionary, key: String, ctx: String) -> Dictionary:
	if not source.has(key) or source[key] == null:
		return {}
	if source[key] is Dictionary:
		return source[key] as Dictionary
	_fail("%s: '%s' must be an object" % [ctx, key])
	return {}

func _is_base58(value: String) -> bool:
	if value.length() < 32 or value.length() > 44:
		return false
	for i in range(value.length()):
		if not BASE58_ALPHABET.contains(value[i]):
			return false
	return true

func _roster_resource_ids() -> Dictionary:
	var ids := {}
	var roster := load(ROSTER_RESOURCE_PATH) as CommunityRoster
	if roster == null:
		_warn("could not load %s" % ROSTER_RESOURCE_PATH)
		return ids
	for community in roster.communities:
		if community != null:
			ids[String(community.id)] = true
	return ids

# ---------------------------------------------------------------------------
# Apply
# ---------------------------------------------------------------------------

func _apply_entry(parsed: Dictionary, sort_order: int) -> void:
	var id: String = parsed["id"]
	var resource_path := "%s/%s/community.tres" % [COMMUNITIES_DIR, id]
	var creating := not FileAccess.file_exists(resource_path)
	var community: CommunityDefinition = null
	if creating:
		community = CommunityDefinition.new()
		community.id = StringName(id)
	else:
		community = ResourceLoader.load(resource_path, "", ResourceLoader.CACHE_MODE_IGNORE) as CommunityDefinition
		if community == null:
			_fail("%s: %s is not a CommunityDefinition resource" % [id, resource_path])
			return

	var changes: Array[String] = []
	if not _attach_missing_refs(changes, community, id, creating):
		return
	_diff(changes, community, "display_name", parsed["display_name"])
	_diff(changes, community, "short_description", parsed["short_description"])
	_diff(changes, community, "description", parsed["description"])
	if parsed["has_accent_color"]:
		_diff(changes, community, "accent_color", parsed["accent_color"])
	_diff(changes, community, "x_handle", parsed["x_handle"])
	_diff(changes, community, "telegram_url", parsed["telegram_url"])
	_diff(changes, community, "website_url", parsed["website_url"])
	_diff(changes, community, "discord_url", parsed["discord_url"])
	_diff(changes, community, "token_symbol", parsed["token_symbol"])
	_diff(changes, community, "token_ca", parsed["token_ca"])
	if not String(parsed["token_show_chart"]).is_empty():
		_diff(changes, community, "token_show_chart", parsed["token_show_chart"])
	_diff(changes, community, "enabled", parsed["permission"])
	_diff(changes, community, "sort_order", sort_order)
	_diff(changes, community, "featured_campaign", _campaign_dict(parsed))

	var rules: Array[String] = parsed["join_rules"]
	var eligibility_type: StringName = &"token" if rules.has("hold_token") else &"open"
	var config := {}
	if not rules.is_empty():
		config["join_rules"] = rules
	if float(parsed["min_hold"]) > 0.0:
		config["min_hold"] = parsed["min_hold"]
	_diff(changes, community, "eligibility_type", eligibility_type)
	_diff(changes, community, "eligibility_config", config)

	if creating:
		_created_count += 1
	else:
		if changes.is_empty():
			_unchanged_count += 1
			print("%s: unchanged" % id)
			return
		_changed_count += 1
	if _dry_run:
		print("[dry-run] %s: %s" % [id, "create" if creating else "update"])
		for change in changes:
			print("    %s" % change)
		return
	var error := ResourceSaver.save(community, resource_path)
	if error != OK:
		_fail("%s: save failed for %s (error %d)" % [id, resource_path, error])
		return
	print("%s: %s %s" % [id, "created" if creating else "updated", resource_path])
	for change in changes:
		print("    %s" % change)

## Fills refs that are not set yet from the standard per-crew paths. Existing
## mascot/cap/background references are never replaced.
func _attach_missing_refs(changes: Array[String], community: CommunityDefinition, id: String, creating: bool) -> bool:
	var dir := "%s/%s" % [COMMUNITIES_DIR, id]
	if community.mascot == null:
		var mascot_path := "%s/mascot.tres" % dir
		if not FileAccess.file_exists(mascot_path):
			if creating:
				_fail("%s: cannot create %s/%s/community.tres — %s is missing (add the art and mascot first, docs/11)" % [id, COMMUNITIES_DIR, id, mascot_path])
				return false
			_warn("%s: no mascot.tres reference and no %s — the crew will not render" % [id, mascot_path])
		else:
			var mascot := ResourceLoader.load(mascot_path)
			if mascot is MascotDefinition:
				_diff(changes, community, "mascot", mascot)
	var cap_path := "%s/cap.tres" % dir
	if community.cap == null and FileAccess.file_exists(cap_path):
		var cap := ResourceLoader.load(cap_path)
		if cap is CapDefinition:
			_diff(changes, community, "cap", cap)
	var background_path := "%s/background.tres" % dir
	if community.background == null and FileAccess.file_exists(background_path):
		var background := ResourceLoader.load(background_path)
		if background is BackgroundProfile:
			_diff(changes, community, "background", background)
	return true

func _campaign_dict(parsed: Dictionary) -> Dictionary:
	var campaign := {}
	if not String(parsed["campaign_title"]).is_empty():
		campaign["title"] = parsed["campaign_title"]
	if not String(parsed["campaign_reward"]).is_empty():
		campaign["reward_text"] = parsed["campaign_reward"]
	if not String(parsed["campaign_ends_at"]).is_empty():
		campaign["ends_at"] = parsed["campaign_ends_at"]
	return campaign

func _diff(changes: Array[String], target: Object, property: String, value: Variant) -> void:
	var old: Variant = target.get(property)
	if not _differs(old, value):
		return
	changes.append("%s: %s -> %s" % [property, var_to_str(old), var_to_str(value)])
	target.set(property, value)

func _differs(old: Variant, new: Variant) -> bool:
	if old is Color and new is Color:
		return not (old as Color).is_equal_approx(new)
	if old is float and new is float:
		return not is_equal_approx(old, new)
	if old is float or new is float:
		return not is_equal_approx(float(old), float(new))
	return old != new

# ---------------------------------------------------------------------------
# Reporting
# ---------------------------------------------------------------------------

func _fail(message: String) -> void:
	_errors.append(message)
	push_error("import_communities: %s" % message)

func _warn(message: String) -> void:
	_warnings.append(message)
	print("warning: %s" % message)

func _finish() -> void:
	if _errors.is_empty():
		print("import_communities: %d created, %d updated, %d unchanged (%s)" % [
			_created_count, _changed_count, _unchanged_count,
			"dry-run" if _dry_run else "written",
		])
		quit(0)
	else:
		push_error("import_communities: %d error(s); fix them and run again" % _errors.size())
		quit(1)
