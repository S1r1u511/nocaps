extends SceneTree

## Headless preset baker: takes a preset JSON exported from the in-run DEV panel
## and writes its values into the authored default tuning resource.
##
## Usage:
##   Godot --headless --path . --script res://tools/import_preset.gd -- <path>
##
## <path> may be an absolute host path (e.g. /tmp/dev_preset_export.json) or a
## Godot path (res:// or user://). It accepts either a DEV-panel export wrapper
## {"name": ..., "values": {...}} or a bare {field: value} object. Only fields
## present in the JSON are overwritten.

const DEFAULT_TUNING_PATH := "res://data/tuning/default_run_tuning.tres"

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		push_error("import_preset: missing JSON path")
		print("usage: Godot --headless --path . --script res://tools/import_preset.gd -- <path>")
		quit(2)
		return

	var path := String(args[0])
	var values := _read_values(path)
	if values.is_empty():
		push_error("import_preset: no values found in %s" % path)
		quit(1)
		return

	var tuning := ResourceLoader.load(
		DEFAULT_TUNING_PATH, "", ResourceLoader.CACHE_MODE_IGNORE
	) as RunTuning
	if tuning == null:
		push_error("import_preset: could not load %s" % DEFAULT_TUNING_PATH)
		quit(1)
		return

	var applied := 0
	var skipped: Array[String] = []
	for prop in tuning.get_property_list():
		var name := String(prop["name"])
		if name == "script" or name.begins_with("_"):
			continue
		if not (int(prop["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE):
			continue
		if not values.has(name):
			continue
		var current: Variant = tuning.get(name)
		var value: Variant = values[name]
		if current is Color:
			tuning.set(name, Color(String(value)))
		elif current is int:
			tuning.set(name, int(value))
		elif current is float:
			tuning.set(name, float(value))
		elif current is bool:
			tuning.set(name, bool(value))
		else:
			skipped.append(name)
			continue
		applied += 1

	var err := _write_resource(tuning)
	if err != OK:
		push_error("import_preset: save failed (%d)" % err)
		quit(1)
		return

	print("IMPORT_PRESET_OK: applied %d values to %s" % [applied, DEFAULT_TUNING_PATH])
	if not skipped.is_empty():
		print("import_preset: skipped unsupported fields: %s" % ", ".join(PackedStringArray(skipped)))
	quit(0)

## Writes the resource explicitly (all fields, authored style) instead of using
## ResourceSaver, which omits default-valued properties and reshapes the file.
func _write_resource(tuning: RunTuning) -> Error:
	var lines: PackedStringArray = []
	lines.append('[gd_resource type="Resource" script_class="RunTuning" load_steps=2 format=3]')
	lines.append("")
	lines.append('[ext_resource type="Script" path="res://data/tuning/run_tuning.gd" id="1"]')
	lines.append("")
	lines.append("[resource]")
	lines.append('script = ExtResource("1")')
	for prop in tuning.get_property_list():
		var name := String(prop["name"])
		if name == "script" or name.begins_with("_"):
			continue
		var usage := int(prop["usage"])
		if not (usage & PROPERTY_USAGE_SCRIPT_VARIABLE) or not (usage & PROPERTY_USAGE_STORAGE):
			continue
		lines.append("%s = %s" % [name, var_to_str(tuning.get(name))])
	var file := FileAccess.open(DEFAULT_TUNING_PATH, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string("\n".join(lines) + "\n")
	return OK

func _read_values(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("import_preset: file not found: %s" % path)
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("import_preset: cannot open: %s" % path)
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		push_error("import_preset: JSON root is not an object")
		return {}
	var dict: Dictionary = parsed
	if dict.get("values") is Dictionary:
		return dict["values"]
	return dict
