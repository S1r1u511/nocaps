extends RefCounted
class_name Clash

## "Today's clash": the top 2 crews on today's daily crew board (UTC day).
##
## The rule is deliberately tiny and shared with the web platform
## (`nocaps-web/lib/clash.ts`) so the phone and the site name the same two crews:
##   - from today's daily rows (the numbers Home already shows: the backend's
##     number plus this device's still-queued runs), sort by score descending,
##     ties broken by crew id ascending;
##   - the top 2 crews with score > 0 are today's clash;
##   - fewer than 2 crews with points means there is no clash yet;
##   - the day is the UTC day, so it resets at 00:00 UTC.
##
## The pure rule lives in `from_rows`; `today` is the thin wrapper around the
## standings source Home already loads. No new network calls.

## Two clash sides from rows `[{id, name, score, ...}]`.
## Returns `{active: bool, a: {id, name, score}|null, b: {id, name, score}|null, rows: Array}`.
static func from_rows(rows: Array) -> Dictionary:
	var sorted := rows.duplicate()
	sorted.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var left := int(a.get("score", 0))
		var right := int(b.get("score", 0))
		if left == right:
			return String(a.get("id", "")) < String(b.get("id", ""))
		return left > right)
	var contenders: Array = []
	for row in sorted:
		if int(row.get("score", 0)) <= 0:
			break  # sorted: every following score is <= 0 too
		contenders.append(_side(row))
		if contenders.size() == 2:
			break
	if contenders.size() < 2:
		return {"active": false, "a": null, "b": null, "rows": sorted}
	return {"active": true, "a": contenders[0], "b": contenders[1], "rows": sorted}

## Today's clash straight from the standings Home already loads. Reuses the same
## fetch/cache Home uses, so this adds no network call.
static func today(save_manager: SaveManager) -> Dictionary:
	return from_rows(Standings.communities_today(save_manager))

## True when `id` is one of the two clash crews.
static func has_crew(clash: Dictionary, id: StringName) -> bool:
	if not bool(clash.get("active", false)) or id == &"":
		return false
	var key := String(id)
	var a: Variant = clash.get("a")
	var b: Variant = clash.get("b")
	return (a is Dictionary and String(a["id"]) == key) or (b is Dictionary and String(b["id"]) == key)

## Seconds until the next 00:00 UTC. `unix_seconds` defaults to now (testable).
static func seconds_to_reset(unix_seconds: int = -1) -> int:
	var now := int(ServerClock.now()) if unix_seconds < 0 else unix_seconds
	var rem := now % 86400
	if rem < 0:
		rem += 86400
	return 86400 - rem

## "hh:mm" until the UTC reset.
static func reset_text(unix_seconds: int = -1) -> String:
	var total := seconds_to_reset(unix_seconds)
	return "%02d:%02d" % [total / 3600, (total % 3600) / 60]

static func _side(row: Dictionary) -> Dictionary:
	return {
		"id": String(row.get("id", "")),
		"name": String(row.get("name", "")),
		"score": int(row.get("score", 0)),
	}
