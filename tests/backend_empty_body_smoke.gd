extends SceneTree

## Backend HTTP decoding: an empty/whitespace body and response code 0
## (offline/transport failure) must return the offline `{}` shape without ever
## calling `JSON.parse_string("")`, which logs an engine ERROR. A non-JSON body
## (e.g. an HTML 403 error page) is never parsed either; it is preserved under
## `raw` so the caller can log it.
##   scripts/run_tests.sh backend_empty_body_smoke

const TestEnv := preload("res://tests/test_env.gd")

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	if not TestEnv.begin("backend_empty_body_smoke"):
		return
	assert(BackendClient.decode_body("") == {}, "empty body decodes to {}")
	assert(BackendClient.decode_body("   \n\t") == {}, "whitespace body decodes to {}")
	var parsed: Variant = BackendClient.decode_body('{"ok": 1}')
	assert(parsed is Dictionary and int(parsed["ok"]) == 1, "valid JSON still decodes")
	assert(BackendClient.decode_body("not json") == {"raw": "not json"},
		"unparseable body is preserved as raw text, never JSON-parsed")

	var empty: Dictionary = BackendClient._response(200, "", PackedStringArray())
	assert(int(empty["code"]) == 200 and (empty["body"] as Dictionary).is_empty(),
		"a 200 with an empty body is {}")
	var offline: Dictionary = BackendClient._response(0, "", PackedStringArray())
	assert(int(offline["code"]) == 0 and (offline["body"] as Dictionary).is_empty(),
		"response code 0 is the offline shape")
	var ok: Dictionary = BackendClient._response(200, '{"ok": 1}', PackedStringArray())
	assert(int(ok["code"]) == 200 and int((ok["body"] as Dictionary)["ok"]) == 1,
		"a 200 with a JSON body decodes normally")

	print("BACKEND_EMPTY_BODY_PASS: empty/offline bodies never JSON-parse (no engine ERROR)")
	quit()
