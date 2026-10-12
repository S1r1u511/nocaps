extends RefCounted
class_name InviteService

## Crew invite boundary: the canonical invite link + share text, the platform
## share dispatch, and the web `?crew=<id>` deep link. UI screens call
## `share_crew()` and never touch the bridge or JavaScript themselves.
##
## - Android: the `NocapsBridge` Kotlin plugin opens the native ACTION_SEND
##   chooser (`share_text`). No bridge -> clipboard fallback.
## - Web: `navigator.share` when the browser has it; otherwise a clipboard copy
##   (with a "Link copied" toast). Both run through `JavaScriptBridge`. The
##   loader iframe grants `web-share`; the query is read from the top-level URL
##   when it is reachable (the game runs same-origin in the /game iframe) and
##   from the game's own URL otherwise.
## - Desktop/editor: clipboard + toast.
##
## Deep links: only the web `?crew=` path is implemented. Android App Links /
## a custom scheme are LATER (see docs/02_UX.md §6).
##
## See docs/03_ARCHITECTURE.md §3 for the platform boundary rule.

const BRIDGE_NAME := "NocapsBridge"
const SITE_URL := "https://play.nocaps.fun/"
const CREW_PARAM := "crew"
const TEXT_TEMPLATE := "Play for %s on NOCAPS 🧢 %s"

## Web share -> clipboard fallback, driven from GDScript with one eval. Returns
## "share" (system sheet opened), "copied" or "failed".
const WEB_SHARE_JS := """
(function () {
	var text = NOCAPS_INVITE_TEXT;
	function copyFallback() {
		try {
			var area = document.createElement("textarea");
			area.value = text;
			area.setAttribute("readonly", "");
			area.style.position = "fixed";
			area.style.left = "-9999px";
			document.body.appendChild(area);
			area.select();
			var copied = false;
			try { copied = document.execCommand("copy"); } catch (error) { copied = false; }
			document.body.removeChild(area);
			if (copied) return "copied";
		} catch (error) {}
		if (navigator.clipboard && navigator.clipboard.writeText) {
			try {
				navigator.clipboard.writeText(text);
				return "copied";
			} catch (error) {}
		}
		return "failed";
	}
	try {
		if (navigator.share) {
			navigator.share({ text: text })["catch"](function () {});
			return "share";
		}
	} catch (error) {}
	return copyFallback();
})()
"""

## `?crew=<id>` from the top-level URL (same-origin iframe) or this page's URL.
const WEB_QUERY_JS := """
(function () {
	try {
		if (window.top && window.top.location && window.top.location.search) {
			return String(window.top.location.search);
		}
	} catch (error) {}
	try { return String(window.location.search || ""); } catch (error) {}
	return "";
})()
"""

## The canonical invite link for a crew.
static func link(community: CommunityDefinition) -> String:
	return "%s?%s=%s" % [SITE_URL, CREW_PARAM, String(community.id).uri_encode()]

## The canonical share text for a crew.
static func share_text(community: CommunityDefinition) -> String:
	return TEXT_TEMPLATE % [community.display_name, link(community)]

## Shares the crew invite via the platform's best option. Never blocks.
static func share_crew(community: CommunityDefinition) -> void:
	if community == null:
		return
	var text := share_text(community)
	if OS.has_feature("web"):
		_share_web(text)
		return
	if OS.has_feature("android") and Engine.has_singleton(BRIDGE_NAME):
		var bridge := Engine.get_singleton(BRIDGE_NAME)
		if bridge != null and bridge.has_method("share_text"):
			bridge.call("share_text", text)
			return
	DisplayServer.clipboard_set(text)
	Toasts.show_message("Link copied")

# ---------------------------------------------------------------------------
# Web
# ---------------------------------------------------------------------------

static func _share_web(text: String) -> void:
	var script := WEB_SHARE_JS.replace("NOCAPS_INVITE_TEXT", JSON.stringify(text))
	var result := String(JavaScriptBridge.eval(script, true))
	if result == "share":
		return
	if result == "copied":
		Toasts.show_message("Link copied")
		return
	DisplayServer.clipboard_set(text)
	Toasts.show_message("Link copied")

static func deep_link_crew_id() -> StringName:
	if not OS.has_feature("web"):
		return &""
	return crew_id_from_query(String(JavaScriptBridge.eval(WEB_QUERY_JS, true)))

## Pure query parser: "?crew=wif", "crew=wif&x=1", a trailing fragment, and
## percent-encoding are all tolerated. Unknown/missing -> empty.
static func crew_id_from_query(query: String) -> StringName:
	var text := query.strip_edges()
	var fragment := text.find("#")
	if fragment >= 0:
		text = text.substr(0, fragment)
	if text.begins_with("?"):
		text = text.substr(1)
	for pair in text.split("&", false):
		var parts := pair.split("=", true, 1)
		if parts.size() != 2 or parts[0] != CREW_PARAM:
			continue
		var value := parts[1].uri_decode().strip_edges().to_lower()
		if value.is_empty():
			return &""
		return StringName(value)
	return &""

## Boot policy for a deep-linked id: unknown or disabled ids are ignored. Valid
## ids always open that crew's page; the selection is only set when the player
## has none yet, so an existing different selection is never overridden.
static func accept_deep_link(save_manager: SaveManager, id: StringName) -> StringName:
	if id == &"":
		return &""
	var community := CommunityRepository.by_id(CommunityRepository.load_roster(), id)
	if community == null or not community.enabled:
		return &""
	if save_manager != null and save_manager.selected_community_id == &"":
		save_manager.set_selected_community(id)
		print("NOCAPS invite: deep link crew=%s" % id)
	return id
