extends RefCounted
class_name EmbedService

## Platform embed boundary (nocaps-web docs/EMBED.md). When the web build runs
## inside the platform (play.nocaps.fun) its iframe URL carries
## `?embed=1&crew=<id>`: the game skips its own home/crew/board screens, starts
## the run for that crew, and reports to the parent page with postMessage:
##   nocaps-run-finished {score, coins, crew, best, new_best}  every run end
##   nocaps-exit {to: "home" | "board"}                         leave the game
##   nocaps-player {player, name}                               signed in / renamed
##   nocaps-wallet-linked {address} | nocaps-wallet-failed {reason}
## Inbound (platform -> game), accepted only from the parent window on an allowed
## platform origin: nocaps-link-wallet {address, message, signature, method},
## nocaps-battle {board, crew, startsInMs, endsInMs} (a live battle; board = "" ends it).
## Load progress/ready/failure come from web/game_bridge.js before the engine
## runs. Outside the web build (Android, desktop, tests) nothing here is active
## unless a test injects a query with `use_query()`.

const QUERY_JS := "(function(){try{return String(window.location.search||'')}catch(e){return ''}})()"
const EMBED_PARAM := "embed"

static var _loaded := false
static var _query := ""
## Messages posted while testing off-web (newest last).
static var posted: Array[Dictionary] = []

## Test hook: behave as if the page URL carried `query`.
static func use_query(query: String) -> void:
	_query = query
	_loaded = true
	posted.clear()

## Platform origins allowed to talk to the game (production, Vercel previews,
## local dev).
const PLATFORM_ORIGIN := "^(https://(play\\.)?nocaps\\.fun|https://nocaps-web[-a-z0-9]*\\.vercel\\.app|http://(localhost|127\\.0\\.0\\.1)(:[0-9]+)?)$"
const LISTEN_JS := "window.addEventListener('message',function(e){try{if(e.source!==window.parent||!window.__nocapsInbox)return;window.__nocapsInbox(String(e.origin),JSON.stringify(e.data));}catch(err){}});"

static var _handler: Callable
static var _inbox: JavaScriptObject = null

static func is_platform_origin(origin: String) -> bool:
	var re := RegEx.create_from_string(PLATFORM_ORIGIN)
	return re.search(origin) != null

## Routes inbound platform messages to `handler(data: Dictionary)`.
static func listen(handler: Callable) -> void:
	_handler = handler
	if not OS.has_feature("web") or not is_embedded() or _inbox != null:
		return
	_inbox = JavaScriptBridge.create_callback(_on_js_message)
	var window := JavaScriptBridge.get_interface("window")
	window.__nocapsInbox = _inbox
	JavaScriptBridge.eval(LISTEN_JS, true)

static func _on_js_message(args: Array) -> void:
	if args.size() < 2:
		return
	receive(JSON.parse_string(String(args[1])), String(args[0]))

## Entry point for one inbound message (also the test hook).
static func receive(data: Variant, origin: String) -> void:
	if not (data is Dictionary) or not is_platform_origin(origin):
		return
	if not String(data.get("type", "")).begins_with("nocaps-"):
		return
	if _handler.is_valid():
		_handler.call(data)

## Live battle from the platform: `nocaps-battle {board, crew, startsInMs, endsInMs}`
## where board = "<tournamentId>_<crew>" ("" ends it). BattleService holds the
## window and decides which board a run counts for (same path as the app).
static func set_battle(data: Dictionary) -> void:
	var board := String(data.get("board", ""))
	var crew := String(data.get("crew", ""))
	var suffix := "_" + crew
	if board.is_empty() or crew.is_empty() or not board.ends_with(suffix) \
			or not RegEx.create_from_string("^[a-z0-9_-]{1,100}$").search(board):
		BattleService.clear()
		return
	BattleService.set_window(board.trim_suffix(suffix), PackedStringArray([crew]),
		int(data.get("startsInMs", 0)), int(data.get("endsInMs", 0)), "embed")

## Board doc id for a run of `crew` finishing now, or "" when no battle counts it.
static func battle_board_for(crew: String, now_ms: int = -1) -> String:
	return BattleService.board_for(crew, now_ms)

## Tells the platform which anonymous player this is (on sign-in and rename).
static func player(player_id: String, name: String) -> void:
	if player_id.is_empty() or player_id == "guest-local":
		return
	post("nocaps-player", {"player": player_id, "name": name})

static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	if OS.has_feature("web"):
		_query = String(JavaScriptBridge.eval(QUERY_JS, true))

static func is_embedded() -> bool:
	_load()
	return has_flag(_query, EMBED_PARAM)

## The crew the platform asked for (may be empty or unknown; callers validate).
## Player name the platform collected (`?name=`), sanitized; empty if absent.
static func player_name() -> String:
	_load()
	for part in _query.trim_prefix("?").split("&"):
		var kv := part.split("=", true, 1)
		if kv.size() == 2 and kv[0] == "name":
			return PlayerName.sanitize(kv[1].uri_decode())
	return ""

static func crew_id() -> StringName:
	_load()
	return InviteService.crew_id_from_query(_query)

## True when `key` is present as `key=1`, `key=true` or a bare `key`.
static func has_flag(query: String, key: String) -> bool:
	var text := query.strip_edges()
	var fragment := text.find("#")
	if fragment >= 0:
		text = text.substr(0, fragment)
	text = text.trim_prefix("?")
	for pair in text.split("&", false):
		var parts := pair.split("=", true, 1)
		if parts[0] != key:
			continue
		if parts.size() == 1:
			return true
		var value := parts[1].uri_decode().strip_edges().to_lower()
		return value == "1" or value == "true" or value == "yes"
	return false

static func post(type: String, data: Dictionary = {}) -> void:
	if not is_embedded():
		return
	var message := data.duplicate()
	message["type"] = type
	if OS.has_feature("web"):
		JavaScriptBridge.eval(
			"try{window.parent.postMessage(%s,'*')}catch(e){}" % JSON.stringify(message), true
		)
	else:
		posted.append(message)

## Reports a finished run (the result payload built by gameplay/run.gd).
## `player` is the anonymous player id the run was submitted under and `name`
## its board name, so the platform can tie a wallet sign-in to these scores.
static func run_finished(payload: Dictionary, player: String = "", name: String = "") -> void:
	var message := {
		"score": int(payload.get("score", 0)),
		"coins": int(payload.get("coins", 0)),
		"crew": String(payload.get("community_id", "")),
		"best": int(payload.get("best", 0)),
		"new_best": bool(payload.get("new_best", false)),
	}
	if not player.is_empty():
		message["player"] = player
	if not name.is_empty():
		message["name"] = name
	post("nocaps-run-finished", message)

## Asks the platform to take over (`to`: "home" or "board").
static func exit(to: String = "home") -> void:
	post("nocaps-exit", {"to": to})
