extends SceneTree

## Contact sheet for the screens-polish captures: tiles several PNGs into one
## image so a review can read many screens in one attachment.
##
##   Godot --headless --path . --script res://tools/contact_sheet.gd -- \
##     --out=/abs/path/sheet.png --cols=3 --scale=0.5 a.png b.png c.png
##
## Images are laid out left-to-right, top-to-bottom, in the order given.

func _initialize() -> void:
	var options := _parse_args()
	var paths: Array = []
	var out := ""
	var cols := 3
	var scale := 0.5
	var positional: Array = options.get("_", [])
	for i in range(positional.size()):
		paths.append(String(positional[i]))
	if paths.is_empty():
		push_error("contact_sheet: no images given")
		quit(1)
		return
	out = String(options.get("out", ""))
	if out.is_empty():
		push_error("contact_sheet: --out required")
		quit(1)
		return
	cols = int(options.get("cols", 3))
	scale = float(options.get("scale", 0.5))

	var tiles: Array[Image] = []
	var tile_w := 0
	var tile_h := 0
	for path in paths:
		var image := Image.load_from_file(String(path))
		if image == null:
			push_error("contact_sheet: cannot load %s" % path)
			quit(1)
			return
		if scale != 1.0:
			image.resize(int(image.get_width() * scale), int(image.get_height() * scale),
				Image.INTERPOLATE_LANCZOS)
		tiles.append(image)
		tile_w = maxi(tile_w, image.get_width())
		tile_h = maxi(tile_h, image.get_height())

	var rows := int(ceil(float(tiles.size()) / float(cols)))
	var gap := 8
	var sheet := Image.create(cols * tile_w + (cols + 1) * gap,
		rows * tile_h + (rows + 1) * gap, false, Image.FORMAT_RGBA8)
	sheet.fill(Color("20202a"))
	for i in range(tiles.size()):
		var col := i % cols
		var row := i / cols
		var x := gap + col * (tile_w + gap)
		var y := gap + row * (tile_h + gap)
		sheet.blit_rect(tiles[i], Rect2i(Vector2i.ZERO, tiles[i].get_size()), Vector2i(x, y))
	var error := sheet.save_png(out)
	if error != OK:
		push_error("contact_sheet: save failed (%s)" % error_string(error))
		quit(1)
		return
	print("SHEET_SAVED %s %s (%d tiles)" % [out, sheet.get_size(), tiles.size()])
	quit()

func _parse_args() -> Dictionary:
	var out: Dictionary = {"_": []}
	for arg in OS.get_cmdline_user_args():
		var text := String(arg)
		if text.begins_with("--"):
			var body := text.substr(2)
			var split := body.split("=", true, 1)
			if split.size() == 2:
				out[split[0]] = split[1]
			else:
				out[body] = true
		else:
			out["_"].append(text)
	return out
