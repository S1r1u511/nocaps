extends RefCounted
class_name ServerClock

## The server's clock, as seen from this device (Oct 10, fundamentals E9).
##
## The server owns the day and the week: boards, quests and clashes must never
## depend on the phone's clock. Every backend response carries the server's time
## (Firestore `readTime` / `commitTime` in the body, or the HTTP `Date` header);
## `observe()` turns that into an offset from the device clock, and `now()` is
## device time + offset. Until the first response arrives the offset is 0 (the
## device clock), and the rules still refuse anything outside the current server
## day, so a wrong phone clock can only make a write fail, never land elsewhere.

const SECONDS_PER_DAY := 86400

static var _offset: float = 0.0
static var _known: bool = false

## Server time in unix seconds (best estimate).
static func now() -> float:
	return Time.get_unix_time_from_system() + _offset

## Seconds to add to device time to get server time.
static func offset() -> float:
	return _offset

## True once at least one server response has set the offset this session.
static func is_known() -> bool:
	return _known

## Current UTC day number (days since the Unix epoch) on the server clock.
static func day_number(unix_seconds: float = -1.0) -> int:
	var t := now() if unix_seconds < 0.0 else unix_seconds
	return int(floor(t / float(SECONDS_PER_DAY)))

## Converts a device timestamp (unix seconds) to server time using the current offset.
static func to_server(device_unix: float) -> float:
	return device_unix + _offset

## Feeds a completed backend response `{code, body, headers}` into the clock.
static func observe(result: Dictionary) -> void:
	if int(result.get("code", 0)) <= 0:
		return
	var server_unix := _from_body(result.get("body", null))
	if server_unix <= 0.0:
		server_unix = _from_headers(result.get("headers", PackedStringArray()))
	if server_unix > 0.0:
		set_server_time(server_unix)

## Sets the offset from a known server time (also used by tests).
static func set_server_time(server_unix: float) -> void:
	_offset = server_unix - Time.get_unix_time_from_system()
	_known = true

## Back to the device clock (tests).
static func reset() -> void:
	_offset = 0.0
	_known = false

# --- parsing ------------------------------------------------------------------

## Firestore bodies: a commit has `commitTime`; a runQuery returns an array of
## results that each carry `readTime`. RFC 3339, e.g. "2026-10-10T10:47:12.123456Z".
static func _from_body(body: Variant) -> float:
	var stamp := ""
	if body is Dictionary:
		stamp = String(body.get("commitTime", body.get("readTime", "")))
	elif body is Array and not (body as Array).is_empty() and body[0] is Dictionary:
		stamp = String(body[0].get("readTime", ""))
	return parse_rfc3339(stamp)

static func parse_rfc3339(stamp: String) -> float:
	if stamp.length() < 19:
		return 0.0
	var unix := Time.get_unix_time_from_datetime_string(stamp.substr(0, 19))
	return float(unix) if unix > 0 else 0.0

## HTTP `Date` header, e.g. "Date: Sat, 10 Oct 2026 10:47:12 GMT".
static func _from_headers(headers: Variant) -> float:
	if not (headers is PackedStringArray):
		return 0.0
	for line in headers:
		if String(line).to_lower().begins_with("date:"):
			return parse_http_date(String(line).substr(5).strip_edges())
	return 0.0

static func parse_http_date(value: String) -> float:
	var parts := value.split(" ", false)
	if parts.size() < 5:
		return 0.0
	var months := ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
	var month := months.find(parts[2]) + 1
	var hms := parts[4].split(":")
	if month <= 0 or hms.size() != 3:
		return 0.0
	var unix := Time.get_unix_time_from_datetime_dict({
		"year": int(parts[3]), "month": month, "day": int(parts[1]),
		"hour": int(hms[0]), "minute": int(hms[1]), "second": int(hms[2]),
	})
	return float(unix) if unix > 0 else 0.0
