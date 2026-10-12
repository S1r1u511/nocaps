extends RefCounted
class_name CommunityRepository

## Resolves the authored community roster. Pure and headless-testable. The backend
## can overlay community configuration later without changing gameplay callers.

const DEFAULT_ROSTER_PATH := "res://data/communities/roster.tres"
const DEFAULT_CAP_PATH := "res://data/caps/default_cap.tres"
const DEFAULT_BACKGROUND_PATH := "res://data/backgrounds/default_background.tres"
## Runtime community overrides written by the DEV community editor. Applied on
## top of the authored roster without touching the `.tres` files.
const OVERRIDES_PATH := "user://community_overrides.json"

static var _overrides: Dictionary = {}
static var _overrides_loaded: bool = false

static func resolve_cap(community: CommunityDefinition) -> CapDefinition:
	if community != null and community.cap != null:
		return community.cap
	return load(DEFAULT_CAP_PATH) as CapDefinition

static func resolve_background(community: CommunityDefinition) -> BackgroundProfile:
	if community != null and community.background != null:
		return community.background
	return load(DEFAULT_BACKGROUND_PATH) as BackgroundProfile

static func load_roster(path: String = DEFAULT_ROSTER_PATH) -> CommunityRoster:
	var roster := load(path) as CommunityRoster
	if roster == null:
		return null
	return apply_overrides(roster)

## --- Lazy roster (Home) ---
##
## `load_roster()` loads every `community.tres` and, with it, every mascot/cap
## texture. Home only needs names, colors and sort order to lay itself out, and
## should not pay for ~10 MB of art before the first frame. `load_roster_lite()`
## reads the same authored roster but builds community definitions with no
## mascot/cap/background, so listing it loads no textures. Call `ensure_art()` on
## a community once it is actually shown (Home does this on the first frame after
## the first paint). The lite roster is cached and mutated in place, so hydrated
## art survives Home rebuilds. `load_roster()` stays eager for the run and every
## other screen.

const COMMUNITY_DIR := "res://data/communities"
const COMMUNITY_FILE := "community.tres"

static var _lite_roster: CommunityRoster = null

static func load_roster_lite(path: String = DEFAULT_ROSTER_PATH) -> CommunityRoster:
	if _lite_roster != null:
		return _lite_roster
	var text := _read_text(path)
	if text.is_empty():
		return load_roster(path)
	var roster := CommunityRoster.new()
	var list: Array[CommunityDefinition] = []
	for community_path in _community_paths(text):
		var community := _parse_community_lite(community_path)
		if community != null:
			list.append(community)
	if list.is_empty():
		return load_roster(path)
	roster.communities = list
	if path == DEFAULT_ROSTER_PATH:
		_lite_roster = apply_overrides(roster)
		return _lite_roster
	return apply_overrides(roster)

## Loads and attaches a community's art exactly once. Returns true when the
## community ends up with a mascot texture.
static func ensure_art(community: CommunityDefinition) -> bool:
	if community == null:
		return false
	if community.mascot != null and community.mascot.idle_texture != null:
		return true
	var path := _source_path(community)
	if path.is_empty() or not ResourceLoader.exists(path):
		return false
	var full := load(path) as CommunityDefinition
	if full == null:
		return false
	community.mascot = full.mascot
	community.cap = full.cap
	community.background = full.background
	return community.mascot != null and community.mascot.idle_texture != null

## Drops the cached lite roster (override edits change the authored metadata).
static func clear_lite_roster() -> void:
	_lite_roster = null

static func _read_text(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	return file.get_as_text()

static func _community_paths(roster_text: String) -> Array[String]:
	var paths: Array[String] = []
	var regex := RegEx.new()
	regex.compile('path="(res://data/communities/[^"]+/community\\.tres)"')
	for match in regex.search_all(roster_text):
		var path := match.get_string(1)
		if not paths.has(path):
			paths.append(path)
	return paths

static func _parse_community_lite(community_path: String) -> CommunityDefinition:
	var text := _read_text(community_path)
	if text.is_empty():
		return null
	var community := CommunityDefinition.new()
	var id := _string_field(text, '^id = &"(.*)"$')
	if not id.is_empty():
		community.id = StringName(id)
	community.display_name = _string_field(text, '^display_name = "(.*)"$')
	community.accent_color = _color_field(text)
	var enabled := _string_field(text, '^enabled = (true|false)$')
	if not enabled.is_empty():
		community.enabled = enabled == "true"
	var order := _string_field(text, '^sort_order = (-?[0-9]+)$')
	if not order.is_empty():
		community.sort_order = int(order)
	community.set_meta("source_path", community_path)
	return community

static func _string_field(text: String, pattern: String) -> String:
	var regex := RegEx.new()
	if regex.compile("(?m)" + pattern) != OK:
		return ""
	var match := regex.search(text)
	return match.get_string(1) if match != null else ""

static func _color_field(text: String) -> Color:
	var regex := RegEx.new()
	if regex.compile('(?m)^accent_color = Color\\(([^)]*)\\)') != OK:
		return Color("ffe15a")
	var match := regex.search(text)
	if match == null:
		return Color("ffe15a")
	var parts := match.get_string(1).split(",")
	var r := float(parts[0]) if parts.size() > 0 else 1.0
	var g := float(parts[1]) if parts.size() > 1 else 1.0
	var b := float(parts[2]) if parts.size() > 2 else 1.0
	var a := float(parts[3]) if parts.size() > 3 else 1.0
	return Color(r, g, b, a)

static func _source_path(community: CommunityDefinition) -> String:
	if community.has_meta("source_path"):
		return String(community.get_meta("source_path"))
	if community.id != &"":
		return "%s/%s/%s" % [COMMUNITY_DIR, String(community.id), COMMUNITY_FILE]
	return ""

## --- Runtime overrides (DEV editor) ---

static func load_overrides() -> Dictionary:
	if _overrides_loaded:
		return _overrides
	_overrides_loaded = true
	_overrides = {}
	if FileAccess.file_exists(OVERRIDES_PATH):
		var file := FileAccess.open(OVERRIDES_PATH, FileAccess.READ)
		if file != null:
			var parsed: Variant = JSON.parse_string(file.get_as_text())
			if parsed is Dictionary:
				_overrides = parsed
	return _overrides

static func save_overrides(data: Dictionary) -> void:
	_overrides = data
	_overrides_loaded = true
	clear_lite_roster()
	var file := FileAccess.open(OVERRIDES_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(data, "\t"))

static func clear_overrides() -> void:
	_overrides = {}
	_overrides_loaded = true
	clear_lite_roster()
	if FileAccess.file_exists(OVERRIDES_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(OVERRIDES_PATH))

static func reload_overrides() -> void:
	_overrides_loaded = false
	clear_lite_roster()
	load_overrides()

static func apply_overrides(roster: CommunityRoster) -> CommunityRoster:
	var overrides := load_overrides()
	if overrides.is_empty():
		return roster
	var result := CommunityRoster.new()
	var list: Array[CommunityDefinition] = []
	for community in roster.communities:
		if community == null:
			continue
		var copy := community.duplicate() as CommunityDefinition
		var data: Dictionary = overrides.get(String(community.id), {})
		if not data.is_empty():
			if data.has("display_name"):
				copy.display_name = String(data["display_name"])
			if data.has("short_description"):
				copy.short_description = String(data["short_description"])
			if data.has("accent_color"):
				copy.accent_color = Color(String(data["accent_color"]))
			if data.has("enabled"):
				copy.enabled = bool(data["enabled"])
			if data.has("sort_order"):
				copy.sort_order = int(data["sort_order"])
			if data.has("weekly_tiers"):
				var tiers := PackedInt32Array()
				for value in data["weekly_tiers"]:
					tiers.append(int(value))
				if tiers.size() > 0:
					copy.weekly_tiers = tiers
			if data.has("social_links"):
				var links: Array[String] = []
				for value in data["social_links"]:
					links.append(String(value))
				copy.social_links = links
		list.append(copy)
	result.communities = list
	return result

static func enabled_sorted(roster: CommunityRoster) -> Array[CommunityDefinition]:
	var list: Array[CommunityDefinition] = []
	if roster == null:
		return list
	for community in roster.communities:
		if community != null and community.enabled:
			list.append(community)
	list.sort_custom(func(a: CommunityDefinition, b: CommunityDefinition) -> bool:
		return a.sort_order < b.sort_order)
	return list

static func by_id(roster: CommunityRoster, id: StringName) -> CommunityDefinition:
	if roster == null:
		return null
	for community in roster.communities:
		if community != null and community.id == id:
			return community
	return null

## Selected community if it exists and is enabled, else the first enabled community.
static func resolve_selected(roster: CommunityRoster, selected_id: StringName) -> CommunityDefinition:
	var chosen := by_id(roster, selected_id)
	if chosen != null and chosen.enabled:
		return chosen
	var list := enabled_sorted(roster)
	return list[0] if not list.is_empty() else null

static func rivals_for(roster: CommunityRoster, target: CommunityDefinition) -> Array[CommunityDefinition]:
	var list: Array[CommunityDefinition] = []
	for community in enabled_sorted(roster):
		if community != target:
			list.append(community)
	return list
