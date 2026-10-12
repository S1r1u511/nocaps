extends Node
class_name BackendClient

## Client-agnostic backend boundary. Gameplay and UI never talk to Firebase
## directly; everything goes through this node. Spark-plan deployment: the client
## writes runs, crew/player entries, quest claims, membership, and champions
## straight to Firestore over its REST API with an anonymous Firebase Auth ID
## token — no Cloud Functions in the path. Offline-first: when unconfigured or
## unreachable, calls fail fast with `{ok:false, error:"offline"}` and queued
## runs retry later, so the game stays fully playable.
##
## Tier-0 (2026-09-26): the anonymous session is persisted so the uid is stable
## across launches; every run/quest commit includes `rate_limits/{uid}` (2 s
## limit) and is validated against `backend/firestore.rules`. See
## docs/10_BACKEND.md §6–7 and docs/14_LEADERBOARD_SECURITY_AND_REWARDS.md.

signal signed_in(player_id: String)
signal leaderboard_loaded(view: StringName, period: StringName, rows: Array)
signal submission_result(ok: bool, message: String)

## Local Firebase emulator defaults (backend/README.md). Used automatically when
## running from the editor so development never needs shipped config. Exported
## builds read the non-secret project config from ProjectSettings (`[nocaps]`).
const EMULATOR_PROJECT_ID := "demo-nocaps"
const EMULATOR_AUTH_URL := "http://127.0.0.1:9099/identitytoolkit.googleapis.com"
const EMULATOR_FIRESTORE_URL := "http://127.0.0.1:8080/v1/projects/demo-nocaps/databases/(default)"
const EMULATOR_API_KEY := "fake-api-key"
const SETTING_PROJECT_ID := "nocaps/backend/project_id"
const SETTING_AUTH_URL := "nocaps/backend/auth_url"
const SETTING_API_KEY := "nocaps/backend/api_key"
const SETTING_FIRESTORE_URL := "nocaps/backend/firestore_url"
const REQUEST_TIMEOUT_SECONDS := 10.0
const LEADERBOARD_LIMIT := 50
const CREW_PLAYER_LIMIT := 50

## Anonymous session mirror so the Firebase uid survives relaunches. Contains no
## secrets beyond the Firebase refresh token the SDK itself persists; never
## wallet material.
const SESSION_PATH := "user://firebase_session.json"

## Rule-enforced minimum seconds between run/quest commits per uid.
const MIN_SUBMIT_SECONDS := 2.0

## Mirrors the bounds enforced by backend/firestore.rules so an out-of-range run
## fails fast instead of retrying forever against a rule rejection.
const MAX_RUN_SCORE := 1000
const MAX_RUN_CONTRIBUTION := 1250
const MAX_RUN_LANDINGS := 500
const MAX_RUN_DURATION_MS := 30 * 60 * 1000

## Last live client in the shell, used by `Standings` for its cached refreshes.
static var instance: BackendClient

## Set once the Firebase project exists (non-secret client config).
var configured: bool = false
var project_id: String = ""
var firestore_base_url: String = ""
var auth_base_url: String = ""
var api_key: String = ""
var player_id: String = ""

var _id_token: String = ""
var _refresh_token: String = ""
var _token_expires_at: float = 0.0
var _signing_in: bool = false
## Communities whose `crew_members` doc has been created this session.
var _member_synced: Dictionary = {}
## Guards against overlapping quest-claim drains triggered by repeated sign-ins.
var _draining_quests: bool = false

func _ready() -> void:
	instance = self
	if not configured:
		if OS.has_feature("editor"):
			configure_for_emulator()
		else:
			configure_from_settings()
	if not signed_in.is_connected(_on_signed_in):
		signed_in.connect(_on_signed_in)
	# Anonymous sign-in starts at boot so the first leaderboard read reuses a ready
	# session instead of paying the sign-up round trip on first screen view.
	if is_available():
		sign_in_guest()

func _exit_tree() -> void:
	if instance == self:
		instance = null

## Reads the deployed project's non-secret config from `project.godot`.
func configure_from_settings() -> void:
	var id := String(ProjectSettings.get_setting(SETTING_PROJECT_ID, ""))
	if id.is_empty():
		return
	configure(
		id,
		String(ProjectSettings.get_setting(SETTING_AUTH_URL, "https://identitytoolkit.googleapis.com")),
		String(ProjectSettings.get_setting(SETTING_API_KEY, "")),
		String(ProjectSettings.get_setting(SETTING_FIRESTORE_URL, ""))
	)

func configure(id: String, auth_url: String, key: String, firestore_url: String = "") -> void:
	project_id = id
	auth_base_url = auth_url
	api_key = key
	firestore_base_url = firestore_url if not firestore_url.is_empty() else _default_firestore_url(id)
	configured = not id.is_empty() and not api_key.is_empty()
	_id_token = ""
	_refresh_token = ""
	_token_expires_at = 0.0
	player_id = ""
	_member_synced.clear()
	_load_session()

func configure_for_emulator() -> void:
	configure(EMULATOR_PROJECT_ID, EMULATOR_AUTH_URL, EMULATOR_API_KEY, EMULATOR_FIRESTORE_URL)

func is_available() -> bool:
	return configured and not firestore_base_url.is_empty()

## Coroutine: awaits anonymous sign-in when configured, then emits `signed_in`.
## Offline it returns the local guest id immediately.
func sign_in_guest() -> String:
	if not is_available():
		player_id = "guest-local"
		signed_in.emit(player_id)
		return player_id
	if _has_valid_token():
		signed_in.emit(player_id)
		return player_id
	var token := await _ensure_token()
	if not token.is_empty():
		signed_in.emit(player_id)
	return player_id

## Retries queued quest claims once a session exists (docs/15 §5). Called after
## sign-in and whenever a token is (re)acquired, so a claim made offline reaches
## the server on the next connection. Idempotent: an empty queue is a no-op and
## the drain itself treats an existing claim doc as already done.
func _on_signed_in(_player_id: String) -> void:
	_drain_quest_claims()

func _drain_quest_claims() -> void:
	if _draining_quests:
		return
	var save := _locate_save_manager()
	if save == null or save.pending_quest_claims.is_empty():
		return
	_draining_quests = true
	Quests.flush_async(save, self, func(_summary: Dictionary) -> void:
		_draining_quests = false)

## Finds the shell's SaveManager without a hard dependency: it is a sibling in
## `main.tscn`, with a tree search as the fallback for tests/other roots.
func _locate_save_manager() -> SaveManager:
	var parent := get_parent()
	if parent != null:
		var sibling := parent.get_node_or_null("SaveManager")
		if sibling is SaveManager:
			return sibling
	var tree := get_tree()
	if tree != null:
		var found := tree.root.find_child("SaveManager", true, false)
		if found is SaveManager:
			return found
	return null

## Synchronous compatibility path (offline/queue tests). Online submissions use
## `submit_run_async` so the queue can clear when the server confirms.
func submit_run(record: Dictionary) -> Dictionary:
	if not is_available():
		return {"ok": false, "error": "offline"}
	if record.is_empty():
		return {"ok": false, "error": "empty_record"}
	_submit(record, func(result: Dictionary) -> void:
		submission_result.emit(bool(result.get("ok", false)), String(result.get("error", ""))))
	return {"ok": false, "error": "pending"}

func submit_run_async(record: Dictionary, callback: Callable) -> void:
	_submit(record, callback)

## One atomic Firestore commit per run: create the immutable runs/{runId}
## document (fails if it already exists — that is the idempotency guard), stamp
## the rate limiter, and increment the crew's + player's daily and weekly entries.
## The rules only accept an increment whose run was created in the same commit.
func _submit(record: Dictionary, callback: Callable) -> void:
	if not is_available():
		callback.call({"ok": false, "error": "offline"})
		return
	if record.is_empty():
		callback.call({"ok": false, "error": "empty_record"})
		return
	var run_id := String(record.get("run_id", ""))
	var community_id := String(record.get("community_id", ""))
	var score := int(record.get("score", 0))
	var contribution := int(record.get("contribution", 0))
	var landings := int(record.get("landings", 0))
	var duration := int(record.get("duration_ms", 0))
	if run_id.is_empty() or community_id.is_empty() \
			or score < 0 or score > MAX_RUN_SCORE \
			or contribution < 0 or contribution > MAX_RUN_CONTRIBUTION \
			or landings < 0 or landings > MAX_RUN_LANDINGS \
			or duration < 0 or duration > MAX_RUN_DURATION_MS:
		callback.call({"ok": false, "error": "rejected"})
		return
	var token := await _ensure_token()
	if token.is_empty() or player_id.is_empty():
		callback.call({"ok": false, "error": "auth_failed"})
		return
	var day_key := "daily_" + day_id()
	var week_key := "weekly_" + week_id()
	var day_start := day_start_unix()
	var week_start := week_start_unix()
	var name := _community_name(community_id)
	var me := PlayerName.board_name(_locate_save_manager())
	# Offline rule C (Oct 10): a run goes on the boards only if it reaches the
	# server on the same server day it was played. Otherwise only the run itself
	# is saved (personal score). The rules enforce "current server day" anyway.
	var counted := RunSubmission.counts_today(record)
	var writes := [
		_rate_write(player_id),
		_run_write(run_id, community_id, score, contribution, landings, duration),
	]
	if counted:
		writes.append_array([
			_entry_write(day_key, day_start, "community", community_id, name, player_id, "run", run_id, contribution, landings, 0),
			_entry_write(week_key, week_start, "community", community_id, name, player_id, "run", run_id, contribution, landings, 0),
			_entry_write(day_key, day_start, "player", community_id, me, player_id, "run", run_id, contribution, landings, 1),
			_entry_write(week_key, week_start, "player", community_id, me, player_id, "run", run_id, contribution, landings, 1),
		])
	var board := BattleService.board_for(community_id) if counted else ""
	var result: Dictionary
	if not board.is_empty():
		var with_board := writes.duplicate()
		with_board.append(_board_write(board, run_id, contribution, me))
		result = await _post_firestore("documents:commit", {"writes": with_board}, token)
	if board.is_empty() or int(result.get("code", 0)) not in [200, 409]:
		# No battle, or the board refused the write (battle just ended, board
		# missing): the run itself must still count everywhere else.
		result = await _post_firestore("documents:commit", {"writes": writes}, token)
	var code := int(result.get("code", 0))
	if code == 200 or code == 409:
		ensure_crew_member(community_id)
		callback.call({
			"ok": true,
			"duplicate": code == 409,
			"contribution": contribution,
			"streak": int(record.get("streak_days", 0)),
			"board_status": RunSubmission.STATUS_COUNTED if counted else RunSubmission.STATUS_PERSONAL_ONLY,
		})
	else:
		callback.call({"ok": false, "error": _commit_error(code, result)})

## Synchronous compatibility path (offline/tests). Emits `leaderboard_loaded`.
func fetch_leaderboard(view: StringName, period: StringName) -> Dictionary:
	if not is_available():
		return {"ok": false, "error": "offline", "rows": []}
	_fetch(view, period, func(result: Dictionary) -> void:
		leaderboard_loaded.emit(view, period, result.get("rows", [])))
	return {"ok": false, "error": "pending", "rows": [], "view": view, "period": period}

func fetch_leaderboard_async(view: StringName, period: StringName, callback: Callable) -> void:
	_fetch(view, period, callback)

## --- Crew / player / quest / champion APIs ----------------------------------

## Top players of one crew for a period, highest score first:
## [{uid, name, score, runs, rank}].
func fetch_crew_players_async(community_id: StringName, period: StringName, callback: Callable) -> void:
	var token := await _ensure_token()
	if token.is_empty():
		callback.call({"ok": false, "error": "auth_failed", "rows": []})
		return
	var period_type := "weekly" if period == &"weekly" else "daily"
	var period_id := _iso_week_id() if period_type == "weekly" else _today_id()
	var parent := "leaderboards/%s_%s" % [period_type, period_id]
	var query := {
		"structuredQuery": {
			"from": [{"collectionId": "entries"}],
			"where": {"compositeFilter": {"op": "AND", "filters": [
				{"fieldFilter": {
					"field": {"fieldPath": "entityType"}, "op": "EQUAL",
					"value": _string_value("player"),
				}},
				{"fieldFilter": {
					"field": {"fieldPath": "communityId"}, "op": "EQUAL",
					"value": _string_value(String(community_id)),
				}},
			]}},
			"orderBy": [{"field": {"fieldPath": "score"}, "direction": "DESCENDING"}],
			"limit": CREW_PLAYER_LIMIT,
		},
	}
	var result := await _post_firestore("documents/%s:runQuery" % parent, query, token)
	if int(result.get("code", 0)) == 200 and result.get("body") is Array:
		var rows: Array = []
		for item in result.get("body", []):
			if item is Dictionary and item.get("document") is Dictionary:
				var row := _row_from_document(item["document"])
				if String(row.get("uid", "")).is_empty():
					row["uid"] = String(row.get("entityId", "")).trim_prefix("player_").trim_suffix("_%s" % community_id)
				row["rank"] = rows.size() + 1
				rows.append(row)
		callback.call({"ok": true, "rows": rows, "periodId": period_id})
	else:
		callback.call({"ok": false, "error": "http_%d" % int(result.get("code", 0)), "rows": []})

## COUNT of crew players with a score strictly above `score` (for ranks outside
## the fetched top list). Calls back with `{ok, count}`.
func crew_players_above_async(community_id: StringName, score: int, period: StringName, callback: Callable) -> void:
	var token := await _ensure_token()
	if token.is_empty():
		callback.call({"ok": false, "error": "auth_failed", "count": 0})
		return
	var period_type := "weekly" if period == &"weekly" else "daily"
	var period_id := _iso_week_id() if period_type == "weekly" else _today_id()
	var parent := "leaderboards/%s_%s" % [period_type, period_id]
	var payload := {
		"structuredAggregationQuery": {
			"structuredQuery": {
				"from": [{"collectionId": "entries"}],
				"where": {"compositeFilter": {"op": "AND", "filters": [
					{"fieldFilter": {
						"field": {"fieldPath": "entityType"}, "op": "EQUAL",
						"value": _string_value("player"),
					}},
					{"fieldFilter": {
						"field": {"fieldPath": "communityId"}, "op": "EQUAL",
						"value": _string_value(String(community_id)),
					}},
					{"fieldFilter": {
						"field": {"fieldPath": "score"}, "op": "GREATER_THAN",
						"value": _int_value(score),
					}},
				]}},
			},
			"aggregations": [{"alias": "count", "count": {}}],
		},
	}
	var result := await _post_firestore("documents/%s:runAggregationQuery" % parent, payload, token)
	callback.call(_aggregation_result(result))

## COUNT of `crew_members` documents for a community. Calls back with
## `{ok, count}`; the caller caches it (60 s per the competition spec).
func crew_members_count_async(community_id: StringName, callback: Callable) -> void:
	var token := await _ensure_token()
	if token.is_empty():
		callback.call({"ok": false, "error": "auth_failed", "count": 0})
		return
	var payload := {
		"structuredAggregationQuery": {
			"structuredQuery": {
				"from": [{"collectionId": "crew_members"}],
				"where": {"fieldFilter": {
					"field": {"fieldPath": "communityId"}, "op": "EQUAL",
					"value": _string_value(String(community_id)),
				}},
			},
			"aggregations": [{"alias": "count", "count": {}}],
		},
	}
	var result := await _post_firestore("documents:runAggregationQuery", payload, token)
	callback.call(_aggregation_result(result))

## Most recent champion for a crew (closed period), or `{}` when none exists.
func fetch_last_champion_async(community_id: StringName, callback: Callable) -> void:
	var token := await _ensure_token()
	if token.is_empty():
		callback.call({"ok": false, "error": "auth_failed", "champion": {}})
		return
	var query := {
		"structuredQuery": {
			"from": [{"collectionId": "champions"}],
			"where": {"fieldFilter": {
				"field": {"fieldPath": "communityId"}, "op": "EQUAL",
				"value": _string_value(String(community_id)),
			}},
			"orderBy": [{"field": {"fieldPath": "periodStart"}, "direction": "DESCENDING"}],
			"limit": 1,
		},
	}
	var result := await _post_firestore("documents:runQuery", query, token)
	if int(result.get("code", 0)) == 200 and result.get("body") is Array:
		var champion: Dictionary = {}
		for item in result.get("body", []):
			if item is Dictionary and item.get("document") is Dictionary:
				champion = _champion_from_document(item["document"])
				break
		callback.call({"ok": true, "champion": champion})
	else:
		callback.call({"ok": false, "error": "http_%d" % int(result.get("code", 0)), "champion": {}})

## Idempotent champion write: the first client to observe a closed period creates
## the doc; later writers get a duplicate and keep the existing one.
func create_champion_async(
	period_key: String,
	period_start: int,
	community_id: String,
	winner: String,
	score: int,
	mvp_uid: String,
	callback: Callable
) -> void:
	var token := await _ensure_token()
	if token.is_empty():
		callback.call({"ok": false, "error": "auth_failed"})
		return
	var write := {
		"update": {
			"name": _document_name("champions", period_key),
			"fields": {
				"periodKey": _string_value(period_key),
				"periodStart": _timestamp_value(period_start),
				"communityId": _string_value(community_id),
				"winner": _string_value(winner),
				"score": _int_value(score),
				"mvpUid": _string_value(mvp_uid),
			},
		},
		"updateMask": {"fieldPaths": ["periodKey", "periodStart", "communityId", "winner", "score", "mvpUid"]},
		"updateTransforms": [{"fieldPath": "createdAt", "setToServerValue": "REQUEST_TIME"}],
		"currentDocument": {"exists": false},
	}
	var result := await _post_firestore("documents:commit", {"writes": [write]}, token)
	var code := int(result.get("code", 0))
	if code == 200 or code == 409:
		callback.call({"ok": true, "duplicate": code == 409})
	else:
		callback.call({"ok": false, "error": _commit_error(code, result)})

## Claim one daily quest: create-only claim + daily counter + crew/player entry
## increments for both periods, all in one atomic commit. `points` must be 1..150;
## the server caps 300 points per uid per UTC day. Idempotent: a duplicate claim
## (the claim doc already exists) is reported as done, never double-counted.
func claim_quest_async(quest_id: String, points: int, community_id: StringName, callback: Callable) -> void:
	if not is_available():
		callback.call({"ok": false, "error": "offline"})
		return
	if quest_id.is_empty() or points < 1 or points > 150:
		callback.call({"ok": false, "error": "rejected"})
		return
	var token := await _ensure_token()
	if token.is_empty() or player_id.is_empty():
		callback.call({"ok": false, "error": "auth_failed"})
		return
	var wire_id := _wire_quest_id(quest_id)
	var day := day_id()
	var day_start := day_start_unix()
	var week_key := "weekly_" + week_id()
	var week_start := week_start_unix()
	var claim_id := "%s_%s_%s" % [player_id, day, wire_id]
	var counter_id := "%s_%s" % [player_id, day]
	var community := String(community_id)
	var name := _community_name(community)
	var me := PlayerName.board_name(_locate_save_manager())
	var writes := [
		_rate_write(player_id),
		_claim_write(claim_id, community, day, day_start, wire_id, points),
		_quest_daily_write(counter_id, day, day_start, claim_id, points),
		_entry_write("daily_" + day, day_start, "community", community, name, player_id, "quest", claim_id, points, 0, 0),
		_entry_write(week_key, week_start, "community", community, name, player_id, "quest", claim_id, points, 0, 0),
		_entry_write("daily_" + day, day_start, "player", community, me, player_id, "quest", claim_id, points, 0, 0),
		_entry_write(week_key, week_start, "player", community, me, player_id, "quest", claim_id, points, 0, 0),
	]
	var result := await _post_firestore("documents:commit", {"writes": writes}, token)
	var code := int(result.get("code", 0))
	if code == 200 or code == 409:
		callback.call({"ok": true, "duplicate": code == 409, "points": points, "day": day})
		return
	var error := _commit_error(code, result)
	if error == "rejected" and await _claim_exists(claim_id, token):
		callback.call({"ok": true, "duplicate": true, "points": points, "day": day})
		return
	callback.call({"ok": false, "error": error})


## Idempotency probe: a rejected commit counts as done when the claim document
## already exists for this uid (ALREADY_EXISTS, or a permission-denied create that
## collided with the existing doc). The claim rules allow reading your own claim.
func _claim_exists(claim_id: String, token: String) -> bool:
	var payload := {"documents": [_document_name("quest_claims", claim_id)]}
	var result := await _post_firestore("documents:batchGet", payload, token)
	if int(result.get("code", 0)) != 200 or not (result.get("body") is Array):
		return false
	for item in result.get("body", []):
		if item is Dictionary and item.get("found") is Dictionary:
			return true
	return false


## The quest_claims rules require `questId` to be lowercase alphanumeric so the
## `{uid}_{day}_{questId}` document id splits into exactly three parts; authored
## quest ids use underscores, so normalize them at the wire boundary.
static func _wire_quest_id(quest_id: String) -> String:
	var out := ""
	for ch in quest_id.to_lower():
		if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9"):
			out += ch
	if out.is_empty():
		out = "quest"
	return out.substr(0, 32)

## Best-effort create-only membership doc; attempted once per community per
## session. Failures are silent (count only), never block play or submission.
## Links a Solana wallet to this player for rewards (`wallet_links/{uid}`). The
## platform collected a read-only SIWS signature; it is stored as-is so payouts
## can verify it. Calls back `{ok, error?}`.
func link_wallet_async(address: String, message: String, signature: String, method: String, name: String, callback: Callable) -> void:
	var token := await _ensure_token()
	if token.is_empty() or player_id.is_empty():
		callback.call({"ok": false, "error": "auth_failed"})
		return
	# Oct 10 (D2/D3): the server verifies the signature and writes wallet_links;
	# the rules no longer let the app write it. `message` is base64 SIWS text.
	var url := "https://us-central1-%s.cloudfunctions.net/linkWallet" % project_id
	var result := await _request(url, {
		"address": address,
		"messageB64": message,
		"signature": signature,
		"method": method,
		"name": name,
	}, _json_headers(token))
	var code := int(result.get("code", 0))
	var body: Variant = result.get("body", {})
	if code == 200 and body is Dictionary and bool(body.get("ok", false)):
		callback.call({"ok": true, "verified": true})
	elif code == 0:
		callback.call({"ok": false, "error": "offline"})
	else:
		var error := String(body.get("error", "http_%d" % code)) if body is Dictionary else "http_%d" % code
		print("NOCAPS wallet: linkWallet HTTP %d %s" % [code, String(body.get("raw", "")).left(120) if body is Dictionary else ""])
		callback.call({"ok": false, "error": error})

func ensure_crew_member(community_id: StringName) -> void:
	var key := String(community_id)
	if key.is_empty() or _member_synced.has(key) or not is_available():
		return
	if player_id.is_empty():
		return
	_sync_membership(key)

func _sync_membership(key: String) -> void:
	var token := await _ensure_token()
	if token.is_empty():
		return
	var result := await _post_firestore("documents:commit", {"writes": [_member_write(key)]}, token)
	var code := int(result.get("code", 0))
	if code == 200 or code == 409:
		_member_synced[key] = true

## Reads the current period's entries filtered by `entityType` and ordered by
## score desc. Public per the rules, but reads sign in so every call shares the
## session identity and quota.
func _fetch(view: StringName, period: StringName, callback: Callable) -> void:
	if not is_available():
		callback.call({"ok": false, "error": "offline", "rows": []})
		return
	var token := await _ensure_token()
	if token.is_empty():
		callback.call({"ok": false, "error": "auth_failed", "rows": []})
		return
	var period_type := "weekly" if period == &"weekly" else "daily"
	var period_id := _iso_week_id() if period_type == "weekly" else _today_id()
	var entity_type := "player" if view == &"players" else "community"
	var parent := "leaderboards/%s_%s" % [period_type, period_id]
	var query := {
		"structuredQuery": {
			"from": [{"collectionId": "entries"}],
			"where": {"fieldFilter": {
				"field": {"fieldPath": "entityType"},
				"op": "EQUAL",
				"value": _string_value(entity_type),
			}},
			"orderBy": [{"field": {"fieldPath": "score"}, "direction": "DESCENDING"}],
			"limit": LEADERBOARD_LIMIT,
		},
	}
	var result := await _post_firestore("documents/%s:runQuery" % parent, query, token)
	if int(result.get("code", 0)) == 200 and result.get("body") is Array:
		var rows: Array = []
		for item in result.get("body", []):
			if item is Dictionary and item.get("document") is Dictionary:
				rows.append(_row_from_document(item["document"]))
		callback.call({"ok": true, "rows": rows, "periodId": period_id})
	else:
		callback.call({"ok": false, "error": "http_%d" % int(result.get("code", 0)), "rows": []})

## --- Firestore write shapes --------------------------------------------------

func _run_write(run_id: String, community_id: String, score: int, contribution: int, landings: int, duration: int) -> Dictionary:
	return {
		"update": {
			"name": _document_name("runs", run_id),
			"fields": {
				"uid": _string_value(player_id),
				"communityId": _string_value(community_id),
				"score": _int_value(score),
				"contribution": _int_value(contribution),
				"landings": _int_value(landings),
				"duration": _int_value(duration),
			},
		},
		"updateMask": {"fieldPaths": ["uid", "communityId", "score", "contribution", "landings", "duration"]},
		"updateTransforms": [{"fieldPath": "createdAt", "setToServerValue": "REQUEST_TIME"}],
		"currentDocument": {"exists": false},
	}

## Transform-only write that advances the per-uid rate limiter to request time.
## The rules require this exact stamp in the same commit as a run or quest claim.
func _rate_write(uid: String) -> Dictionary:
	return {
		"transform": {
			"document": _document_name("rate_limits", uid),
			"fieldTransforms": [{"fieldPath": "lastSubmitAt", "setToServerValue": "REQUEST_TIME"}],
		},
	}

## Community or player leaderboard entry. `source` is "run" or "quest"; `ref_id`
## is the runId or claimId created in the same commit. Deltas come from the parent
## document, so the rules can prove causality with getAfter().
func _entry_write(
	period_key: String,
	period_start: int,
	entity_type: String,
	community_id: String,
	name: String,
	uid: String,
	source: String,
	ref_id: String,
	score_delta: int,
	landings_delta: int,
	runs_delta: int
) -> Dictionary:
	var entry_id := "community_%s" % community_id
	if entity_type == "player":
		entry_id = "player_%s_%s" % [uid, community_id]
	var fields := {
		"entityType": _string_value(entity_type),
		"communityId": _string_value(community_id),
		"name": _string_value(name),
		"periodKey": _string_value(period_key),
		"periodStart": _timestamp_value(period_start),
		"source": _string_value(source),
	}
	if source == "run":
		fields["lastRunId"] = _string_value(ref_id)
	else:
		fields["lastQuestId"] = _string_value(ref_id)
	if entity_type == "player":
		fields["uid"] = _string_value(uid)
	var transforms: Array = [{"fieldPath": "score", "increment": _int_value(score_delta)}]
	if entity_type == "community":
		transforms.append({"fieldPath": "landings", "increment": _int_value(landings_delta)})
	else:
		transforms.append({"fieldPath": "runs", "increment": _int_value(runs_delta)})
	return {
		"update": {
			"name": _document_name("leaderboards/%s/entries" % period_key, entry_id),
			"fields": fields,
		},
		"updateMask": {"fieldPaths": fields.keys()},
		"updateTransforms": transforms,
	}

func _claim_write(claim_id: String, community_id: String, day: String, day_start: int, quest_id: String, points: int) -> Dictionary:
	return {
		"update": {
			"name": _document_name("quest_claims", claim_id),
			"fields": {
				"uid": _string_value(player_id),
				"communityId": _string_value(community_id),
				"day": _string_value(day),
				"dayStart": _timestamp_value(day_start),
				"questId": _string_value(quest_id),
				"points": _int_value(points),
			},
		},
		"updateMask": {"fieldPaths": ["uid", "communityId", "day", "dayStart", "questId", "points"]},
		"updateTransforms": [{"fieldPath": "createdAt", "setToServerValue": "REQUEST_TIME"}],
		"currentDocument": {"exists": false},
	}

func _quest_daily_write(counter_id: String, day: String, day_start: int, claim_id: String, points: int) -> Dictionary:
	return {
		"update": {
			"name": _document_name("quest_daily", counter_id),
			"fields": {
				"uid": _string_value(player_id),
				"day": _string_value(day),
				"dayStart": _timestamp_value(day_start),
				"lastClaimId": _string_value(claim_id),
			},
		},
		"updateMask": {"fieldPaths": ["uid", "day", "dayStart", "lastClaimId"]},
		"updateTransforms": [{"fieldPath": "total", "increment": _int_value(points)}],
	}

func _member_write(community_id: String) -> Dictionary:
	return {
		"update": {
			"name": _document_name("crew_members", "%s_%s" % [community_id, player_id]),
			"fields": {
				"communityId": _string_value(community_id),
				"uid": _string_value(player_id),
			},
		},
		"updateMask": {"fieldPaths": ["communityId", "uid"]},
		"updateTransforms": [{"fieldPath": "joinedAt", "setToServerValue": "REQUEST_TIME"}],
		"currentDocument": {"exists": false},
	}

## --- Auth -------------------------------------------------------------------

func _has_valid_token() -> bool:
	return not _id_token.is_empty() and Time.get_unix_time_from_system() < _token_expires_at

## Serializes concurrent sign-ins so every caller shares one anonymous uid.
## Refreshes the session token first; a fresh anonymous sign-up is the fallback.
func _ensure_token() -> String:
	if _has_valid_token():
		return _id_token
	while _signing_in:
		await get_tree().process_frame
	if _has_valid_token():
		return _id_token
	_signing_in = true
	var token := ""
	if not _refresh_token.is_empty():
		token = await _refresh_id_token()
	if token.is_empty():
		token = await _sign_up_anonymous()
	_signing_in = false
	# A freshly (re)acquired token is a reconnect signal: emit so queued quest
	# claims drain even when no explicit sign-in call happened.
	if not token.is_empty():
		signed_in.emit(player_id)
	return token

func _sign_up_anonymous() -> String:
	var url := "%s/v1/accounts:signUp?key=%s" % [auth_base_url, api_key]
	var result := await _request(url, {"returnSecureToken": true}, _json_headers(""))
	var response := _as_dict(result.get("body"))
	if int(result.get("code", 0)) != 200:
		_id_token = ""
		_token_expires_at = 0.0
		return ""
	return _accept_token(response, "idToken", "refreshToken", "localId", "expiresIn")

func _refresh_id_token() -> String:
	var url := "%s/v1/token?key=%s" % [_secure_token_base(), api_key]
	var form := "grant_type=refresh_token&refresh_token=%s" % _refresh_token.uri_encode()
	var result := await _request(
		url,
		form,
		PackedStringArray(["Content-Type: application/x-www-form-urlencoded"])
	)
	var response := _as_dict(result.get("body"))
	if int(result.get("code", 0)) != 200:
		_refresh_token = ""
		_id_token = ""
		_token_expires_at = 0.0
		return ""
	return _accept_token(response, "id_token", "refresh_token", "user_id", "expires_in")

## Normalizes an identitytoolkit / securetoken token response into client state.
func _accept_token(response: Dictionary, id_key: String, refresh_key: String, uid_key: String, expires_key: String) -> String:
	var token := String(response.get(id_key, ""))
	if token.is_empty():
		_id_token = ""
		_token_expires_at = 0.0
		return ""
	_id_token = token
	var refresh := String(response.get(refresh_key, ""))
	if not refresh.is_empty():
		_refresh_token = refresh
	player_id = String(response.get(uid_key, player_id))
	var expires := float(String(response.get(expires_key, "3600")))
	_token_expires_at = Time.get_unix_time_from_system() + maxf(expires - 60.0, 30.0)
	_save_session()
	return _id_token

func _secure_token_base() -> String:
	var suffix := "identitytoolkit.googleapis.com"
	if auth_base_url.ends_with(suffix):
		return auth_base_url.substr(0, auth_base_url.length() - suffix.length()) + "securetoken.googleapis.com"
	return "https://securetoken.googleapis.com"

## --- Session persistence -----------------------------------------------------

## Loads the previous session for THIS project only, so a stable anonymous uid
## survives relaunches. Refresh failure falls back to a fresh anonymous sign-up.
func _load_session() -> void:
	if not FileAccess.file_exists(SESSION_PATH):
		return
	var file := FileAccess.open(SESSION_PATH, FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		return
	var data: Dictionary = parsed
	if String(data.get("project_id", "")) != project_id:
		return
	_refresh_token = String(data.get("refresh_token", ""))
	player_id = String(data.get("player_id", ""))

func _save_session() -> void:
	if project_id.is_empty() or player_id.is_empty():
		return
	var file := FileAccess.open(SESSION_PATH, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify({
		"project_id": project_id,
		"player_id": player_id,
		"refresh_token": _refresh_token,
	}))

## --- REST plumbing -----------------------------------------------------------

## Reads `config/app` (public, no token). Calls back with
## {ok, minVersion, latestVersion, message, updateUrl}; offline -> {ok: false}.
func fetch_app_config_async(callback: Callable) -> void:
	if not is_available():
		callback.call({"ok": false, "error": "offline"})
		return
	var request := HTTPRequest.new()
	request.timeout = REQUEST_TIMEOUT_SECONDS
	if OS.has_feature("web"):
		request.accept_gzip = false
	add_child(request)
	var error := request.request("%s/documents/config/app" % firestore_base_url, PackedStringArray(), HTTPClient.METHOD_GET)
	if error != OK:
		request.queue_free()
		callback.call({"ok": false, "error": "offline"})
		return
	var completed: Array = await request.request_completed
	request.queue_free()
	var result := _response(int(completed[1]), (completed[3] as PackedByteArray).get_string_from_utf8(), completed[2])
	ServerClock.observe(result)
	var body: Variant = result.get("body", {})
	if int(result.get("code", 0)) != 200 or not (body is Dictionary):
		callback.call({"ok": false, "error": "http_%d" % int(result.get("code", 0))})
		return
	var fields: Dictionary = body.get("fields", {})
	var text := func(key: String) -> String:
		var v: Variant = fields.get(key, {})
		return String(v.get("stringValue", "")) if v is Dictionary else ""
	callback.call({
		"ok": true,
		"minVersion": text.call("minVersion"),
		"latestVersion": text.call("latestVersion"),
		"message": text.call("message"),
		"updateUrl": text.call("updateUrl"),
	})

func _post_firestore(path: String, payload: Dictionary, token: String) -> Dictionary:
	return await _request("%s/%s" % [firestore_base_url, path], payload, _json_headers(token))

func _json_headers(token: String) -> PackedStringArray:
	var headers := PackedStringArray(["Content-Type: application/json"])
	if not token.is_empty():
		headers.append("Authorization: Bearer %s" % token)
	return headers

## `payload` may be a Dictionary/Array (JSON) or a raw form-encoded String.
func _request(url: String, payload: Variant, headers: PackedStringArray) -> Dictionary:
	var request := HTTPRequest.new()
	request.timeout = REQUEST_TIMEOUT_SECONDS
	if OS.has_feature("web"):
		# Browser fetch already decompresses the body, so Godot's own gzip unwrap fails.
		request.accept_gzip = false
	add_child(request)
	var body := ""
	if payload is Dictionary or payload is Array:
		body = JSON.stringify(payload)
	elif payload is String:
		body = payload
	var error := request.request(url, headers, HTTPClient.METHOD_POST, body)
	if error != OK:
		request.queue_free()
		return {"code": 0, "body": {}}
	var completed: Array = await request.request_completed
	request.queue_free()
	var result := _response(int(completed[1]), (completed[3] as PackedByteArray).get_string_from_utf8(), completed[2])
	ServerClock.observe(result)
	return result

## Maps a completed HTTP response to `{code, body, headers}` without ever
## JSON-parsing an empty body: a bare `JSON.parse_string("")` logs an engine
## ERROR. An empty body or response code 0 (offline/transport failure) is {}.
static func _response(code: int, text: String, headers: PackedStringArray) -> Dictionary:
	if code <= 0:
		return {"code": 0, "body": {}, "headers": headers}
	return {"code": code, "body": decode_body(text), "headers": headers}

## Decodes an HTTP body guardedly: empty or whitespace bodies decode to {}.
static func decode_body(text: String) -> Variant:
	var trimmed := text.strip_edges()
	if trimmed.is_empty():
		return {}
	# Only JSON bodies are parsed: an HTML error page (e.g. a 403 from Google's
	# front end) would otherwise log an engine "Parse JSON failed" error.
	if not (trimmed.begins_with("{") or trimmed.begins_with("[")):
		return {"raw": trimmed.left(200)}
	var parsed: Variant = JSON.parse_string(trimmed)
	return parsed if parsed != null else {}

## The live battle, if any: one query on `tournaments` (public read, 1 read even
## when empty). Calls back with {ok, battle: {id, title, crews, start_ms,
## duration_s} or {}, server_ms} — server_ms from the HTTP Date header so the
## window doesn't depend on the phone's clock.
func fetch_live_battle_async(callback: Callable) -> void:
	if not is_available():
		callback.call({"ok": false, "error": "offline"})
		return
	var token := await _ensure_token()
	if token.is_empty():
		callback.call({"ok": false, "error": "auth_failed"})
		return
	var query := {"structuredQuery": {
		"from": [{"collectionId": "tournaments"}],
		"where": {"fieldFilter": {"field": {"fieldPath": "status"}, "op": "EQUAL", "value": {"stringValue": "live"}}},
		"limit": 1,
	}}
	var result := await _post_firestore("documents:runQuery", query, token)
	if int(result.get("code", 0)) != 200 or not result.get("body") is Array:
		callback.call({"ok": false, "error": "http_%d" % int(result.get("code", 0))})
		return
	callback.call({"ok": true, "battle": parse_battle(result["body"]), "server_ms": server_ms_from(result.get("headers", PackedStringArray()))})

## runQuery rows -> {id, title, crews, start_ms, duration_s}, or {} when none.
static func parse_battle(rows: Array) -> Dictionary:
	for row in rows:
		if not row is Dictionary or not row.get("document") is Dictionary:
			continue
		var doc: Dictionary = row["document"]
		var fields: Dictionary = doc.get("fields", {})
		var crews := PackedStringArray()
		var values: Variant = fields.get("crews", {}).get("arrayValue", {}).get("values", [])
		if values is Array:
			for value in values:
				if value is Dictionary and value.has("stringValue"):
					crews.append(String(value["stringValue"]))
		var start := String(fields.get("startAt", {}).get("timestampValue", ""))
		return {
			"id": String(doc.get("name", "")).get_file(),
			"title": String(fields.get("title", {}).get("stringValue", "")),
			"crews": crews,
			"start_ms": timestamp_ms(start),
			"duration_s": int(fields.get("durationSec", {}).get("integerValue", "0")),
		}
	return {}

## RFC 3339 ("2026-10-03T10:09:51.101Z") -> unix ms. 0 when unparseable.
static func timestamp_ms(value: String) -> int:
	if value.length() < 19:
		return 0
	var base := int(Time.get_unix_time_from_datetime_string(value.substr(0, 19)))
	var ms := 0
	if value.length() > 20 and value[19] == ".":
		var frac := ""
		for ch in value.substr(20):
			if ch < "0" or ch > "9":
				break
			frac += ch
		ms = int((frac + "000").substr(0, 3))
	return base * 1000 + ms

## "Date: Tue, 07 Oct 2026 14:00:00 GMT" -> unix ms, or 0.
static func server_ms_from(headers: PackedStringArray) -> int:
	const MONTHS := ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"]
	for header in headers:
		if not header.to_lower().begins_with("date:"):
			continue
		var parts := header.substr(5).strip_edges().split(" ", false)
		if parts.size() < 5:
			return 0
		var month := MONTHS.find(parts[2].to_lower().substr(0, 3)) + 1
		if month <= 0:
			return 0
		var stamp := "%s-%02d-%02dT%s" % [parts[3], month, int(parts[1]), parts[4]]
		return int(Time.get_unix_time_from_datetime_string(stamp)) * 1000
	return 0

## Both crew boards of a battle in one batchGet: {ok, scores: {crew: n}, mine: {crew: n}}.
func fetch_battle_boards_async(battle_id: String, crew_list: PackedStringArray, callback: Callable) -> void:
	if not is_available() or crew_list.is_empty():
		callback.call({"ok": false, "error": "offline"})
		return
	var token := await _ensure_token()
	if token.is_empty():
		callback.call({"ok": false, "error": "auth_failed"})
		return
	var names: Array = []
	for crew in crew_list:
		names.append(_document_name("boards", "%s_%s" % [battle_id, crew]))
	var result := await _post_firestore("documents:batchGet", {"documents": names}, token)
	if int(result.get("code", 0)) != 200 or not result.get("body") is Array:
		callback.call({"ok": false, "error": "http_%d" % int(result.get("code", 0))})
		return
	callback.call(parse_boards(result["body"], player_id))

static func parse_boards(rows: Array, uid: String) -> Dictionary:
	var scores: Dictionary = {}
	var mine: Dictionary = {}
	for row in rows:
		if not row is Dictionary or not row.get("found") is Dictionary:
			continue
		var fields: Dictionary = row["found"].get("fields", {})
		var crew := String(fields.get("crew", {}).get("stringValue", ""))
		if crew.is_empty():
			continue
		scores[crew] = int(fields.get("score", {}).get("integerValue", "0"))
		var players: Dictionary = fields.get("players", {}).get("mapValue", {}).get("fields", {})
		if not uid.is_empty() and players.get(uid) is Dictionary:
			var me: Dictionary = players[uid].get("mapValue", {}).get("fields", {})
			mine[crew] = int(me.get("s", {}).get("integerValue", "0"))
	return {"ok": true, "scores": scores, "mine": mine}

## Adds a run's contribution to the live battle board (crew total + this
## player's row). Field paths quote the uid; the doc must already exist (the
## admin creates it at Start).
func _board_write(board_id: String, run_id: String, contribution: int, name: String) -> Dictionary:
	var key := "`%s`" % player_id
	var player := {"mapValue": {"fields": {"n": _string_value(name.substr(0, 32))}}}
	return {
		"update": {
			"name": _document_name("boards", board_id),
			"fields": {
				"lastRunId": _string_value(run_id),
				"players": {"mapValue": {"fields": {player_id: player}}},
			},
		},
		"updateMask": {"fieldPaths": ["lastRunId", "players.%s.n" % key]},
		"updateTransforms": [
			{"fieldPath": "score", "increment": _int_value(contribution)},
			{"fieldPath": "players.%s.s" % key, "increment": _int_value(contribution)},
		],
		"currentDocument": {"exists": true},
	}

func _document_name(collection_path: String, document_id: String) -> String:
	return "projects/%s/databases/(default)/documents/%s/%s" % [
		project_id, collection_path, document_id.uri_encode()
	]

static func _default_firestore_url(id: String) -> String:
	return "https://firestore.googleapis.com/v1/projects/%s/databases/(default)" % id

func _community_name(community_id: String) -> String:
	var community := CommunityRepository.by_id(CommunityRepository.load_roster(), StringName(community_id))
	if community != null:
		return community.display_name
	return community_id

## --- Row / value conversion --------------------------------------------------

func _row_from_document(document: Dictionary) -> Dictionary:
	var fields: Dictionary = document.get("fields", {})
	var entity_id := String(document.get("name", "")).get_file()
	var community_id := _string_from(fields.get("communityId", {}))
	return {
		"id": community_id if not community_id.is_empty() else entity_id,
		"entityId": entity_id,
		"entityType": _string_from(fields.get("entityType", {})),
		"communityId": community_id,
		"name": _string_from(fields.get("name", {})),
		"uid": _string_from(fields.get("uid", {})),
		"score": _int_from(fields.get("score", {})),
		"landings": _int_from(fields.get("landings", {})),
		"runs": _int_from(fields.get("runs", {})),
	}

func _champion_from_document(document: Dictionary) -> Dictionary:
	var fields: Dictionary = document.get("fields", {})
	return {
		"periodKey": _string_from(fields.get("periodKey", {})),
		"communityId": _string_from(fields.get("communityId", {})),
		"winner": _string_from(fields.get("winner", {})),
		"mvpUid": _string_from(fields.get("mvpUid", {})),
		"score": _int_from(fields.get("score", {})),
	}

## Parses a runAggregationQuery response into `{ok, count}`.
static func _aggregation_result(result: Dictionary) -> Dictionary:
	if int(result.get("code", 0)) != 200 or not (result.get("body") is Array):
		return {"ok": false, "error": "http_%d" % int(result.get("code", 0)), "count": 0}
	for item in result.get("body", []):
		if not item is Dictionary:
			continue
		var aggregate: Variant = item.get("result", {}).get("aggregateFields", {})
		if aggregate is Dictionary and aggregate.has("count"):
			return {"ok": true, "count": _int_from(aggregate["count"])}
	return {"ok": true, "count": 0}

static func _as_dict(value: Variant) -> Dictionary:
	return value if value is Dictionary else {}

static func _string_value(value: String) -> Dictionary:
	return {"stringValue": value}

static func _int_value(value: int) -> Dictionary:
	return {"integerValue": str(value)}

## Unix seconds -> Firestore timestampValue (UTC ISO-8601, e.g. 2026-09-26T00:00:00Z).
static func _timestamp_value(unix_seconds: int) -> Dictionary:
	return {"timestampValue": Time.get_datetime_string_from_unix_time(unix_seconds) + "Z"}

static func _string_from(value: Variant) -> String:
	if value is Dictionary:
		return String(value.get("stringValue", ""))
	return ""

static func _int_from(value: Variant) -> int:
	if value is Dictionary:
		if value.has("integerValue"):
			return int(String(value.get("integerValue", "0")))
		if value.has("doubleValue"):
			return int(float(value.get("doubleValue", 0.0)))
	return 0

## Maps a failed commit to a queue-facing error token.
static func _commit_error(code: int, result: Dictionary) -> String:
	var body: Variant = result.get("body", {})
	if body is Dictionary and body.get("error") is Dictionary:
		var status := String(body["error"].get("status", ""))
		if status == "PERMISSION_DENIED":
			return "rejected"
	if code == 403:
		return "rejected"
	if code == 0:
		return "offline"
	return "http_%d" % code

## --- Period ids (UTC) --------------------------------------------------------

## Public UTC period helpers on the SERVER clock (ServerClock, Oct 10). The rules
## accept a board write only for the current server day / ISO week.

static func day_id() -> String:
	return Time.get_datetime_string_from_unix_time(int(ServerClock.now()), true).substr(0, 10)

static func week_id() -> String:
	var now := int(ServerClock.now())
	var date := Time.get_datetime_dict_from_unix_time(now)
	return _iso_week_for(date.year, date.month, date.day)

## Unix seconds of today's UTC midnight (server clock).
static func day_start_unix() -> int:
	var date := Time.get_datetime_dict_from_unix_time(int(ServerClock.now()))
	return int(Time.get_unix_time_from_datetime_dict({
		"year": date.year, "month": date.month, "day": date.day,
		"hour": 0, "minute": 0, "second": 0,
	}))

## Unix seconds of this ISO week's Monday UTC midnight.
static func week_start_unix() -> int:
	var start := day_start_unix()
	var date := Time.get_datetime_dict_from_unix_time(start)
	return start - _days_since_monday(date.year, date.month, date.day) * 86400

static func _today_id() -> String:
	return day_id()

static func _iso_week_id() -> String:
	return week_id()

## ISO-8601 week of the year that contains the first Thursday of that year.
static func _iso_week_for(year: int, month: int, day: int) -> String:
	var noon := Time.get_unix_time_from_datetime_dict({
		"year": year, "month": month, "day": day, "hour": 12, "minute": 0, "second": 0,
	})
	var thursday := int(noon) - _days_since_monday(year, month, day) * 86400 + 3 * 86400
	var thursday_date := Time.get_date_dict_from_unix_time(thursday)
	var iso_year: int = thursday_date.year
	var jan1 := int(Time.get_unix_time_from_datetime_dict({
		"year": iso_year, "month": 1, "day": 1, "hour": 12, "minute": 0, "second": 0,
	}))
	var first_thursday_offset := 3 - _days_since_monday(iso_year, 1, 1)
	if first_thursday_offset < 0:
		first_thursday_offset += 7
	var week := int((thursday - jan1) / 86400 - first_thursday_offset) / 7 + 1
	return "%04d-W%02d" % [iso_year, week]

## 0 = Monday … 6 = Sunday, via the Julian day number.
static func _days_since_monday(year: int, month: int, day: int) -> int:
	var a := int((14 - month) / 12)
	var y := year + 4800 - a
	var m := month + 12 * a - 3
	var jdn := day + int((153 * m + 2) / 5) + 365 * y + int(y / 4) - int(y / 100) + int(y / 400) - 32045
	return jdn % 7
