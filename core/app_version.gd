class_name AppVersion
extends RefCounted

## Single source for the version label shown in the Profile footer, the DEV
## panel, and the web build. `application/config/version` holds the semantic
## version ("0.3.0"); scripts/release.sh stamps the short git hash into it for a
## release build ("v0.3.0 · 1a2b3c4", restored afterwards), so every built
## artifact shows the exact commit it came from.

## The bare semantic version, e.g. "1.0.0" (no "v", no " · hash").
static func semver() -> String:
	var value := String(ProjectSettings.get_setting("application/config/version", "")).strip_edges()
	value = value.trim_prefix("v")
	return value.split(" ", false)[0] if not value.is_empty() else "0.0.0"

## -1 / 0 / 1 comparing two "major.minor.patch" strings (missing parts are 0).
static func compare(a: String, b: String) -> int:
	var pa := a.trim_prefix("v").split(".")
	var pb := b.trim_prefix("v").split(".")
	for i in 3:
		var x := int(pa[i]) if i < pa.size() else 0
		var y := int(pb[i]) if i < pb.size() else 0
		if x != y:
			return -1 if x < y else 1
	return 0

## True when this build is older than `minimum` (an empty minimum never blocks).
static func is_below(minimum: String) -> bool:
	return not minimum.strip_edges().is_empty() and compare(semver(), minimum) < 0

static func label() -> String:
	var value := String(ProjectSettings.get_setting("application/config/version", "")).strip_edges()
	if value.is_empty():
		return "dev"
	if value.begins_with("v"):
		return value
	return "v" + value
