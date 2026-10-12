extends UiScreen

## DEV-only community data editor. Edits runtime overrides (name, description,
## accent, enablement, order, weekly tiers, links) saved to
## `user://community_overrides.json`; the authored `.tres` files are untouched.
## Reachable from Profile when DEV is available. See docs/11_COMMUNITY_AUTHORING.md.

const ACCENT_SWATCHES := [
	Color("d94f3d"), Color("f0a23c"), Color("ffe36e"), Color("5ee08a"),
	Color("4fb6e8"), Color("8b7cf0"), Color("ef6ea8"), Color("e9eefb"),
]

var _editing: StringName = &""
var _accent: Color = Color("ffe36e")
var _form: VBoxContainer
var _inputs: Dictionary = {}

func setup(_payload: Dictionary) -> void:
	var page := build_page()
	page.add_child(make_kicker("DEV · COMMUNITY EDITOR", &"crew"))
	page.add_child(make_h1("Community data"))
	page.add_child(make_sub("Runtime overrides saved to user://community_overrides.json. Authored .tres files stay untouched; reset clears the overrides."))

	var communities := _all_communities()
	if communities.is_empty():
		page.add_child(make_sub("No communities in the roster."))
		page.add_child(make_button("BACK TO PROFILE", &"profile"))
		return

	if _editing == &"":
		_editing = communities[0].id
	var options: Array = []
	for community in communities:
		options.append({"key": community.id, "text": community.display_name})
	page.add_child(make_segmented(options, _editing, _set_editing))

	_form = VBoxContainer.new()
	_form.add_theme_constant_override("separation", 12)
	page.add_child(_form)
	_build_form()

	page.add_child(make_action_button("SAVE COMMUNITY", _on_save))
	page.add_child(make_ghost_action_button("RESET OVERRIDES", _on_reset))
	page.add_child(make_button("BACK TO PROFILE", &"profile"))

func _all_communities() -> Array[CommunityDefinition]:
	var list: Array[CommunityDefinition] = []
	var roster := CommunityRepository.load_roster()
	if roster == null:
		return list
	for community in roster.communities:
		if community != null:
			list.append(community)
	return list

func _set_editing(id: StringName) -> void:
	_editing = id
	_rebuild()

func _rebuild() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	setup({})

func _current() -> CommunityDefinition:
	return CommunityRepository.by_id(CommunityRepository.load_roster(), _editing)

func _build_form() -> void:
	for child in _form.get_children():
		_form.remove_child(child)
		child.queue_free()
	_inputs.clear()
	var community := _current()
	if community == null:
		return
	_accent = community.accent_color

	var card := make_card(_form)
	card.add_child(make_kicker("IDENTITY"))
	card.add_child(_labeled_input("display_name", "Display name", community.display_name, 24))
	card.add_child(_labeled_input("short_description", "Short description", community.short_description, 90))

	card.add_child(make_kicker("ACCENT"))
	var swatches := HBoxContainer.new()
	swatches.add_theme_constant_override("separation", 8)
	card.add_child(swatches)
	for swatch in ACCENT_SWATCHES:
		swatches.add_child(_swatch_button(swatch))

	var order_row := HBoxContainer.new()
	order_row.add_theme_constant_override("separation", 12)
	card.add_child(order_row)
	var order_column := VBoxContainer.new()
	order_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	order_column.add_child(make_kicker("SORT ORDER"))
	order_column.add_child(_input_for("sort_order", str(community.sort_order), 4))
	order_row.add_child(order_column)
	var enabled_column := VBoxContainer.new()
	enabled_column.add_child(make_kicker("ENABLED"))
	var enabled := ToggleSwitch.new()
	enabled.setup(community.enabled)
	_inputs["enabled"] = enabled
	enabled_column.add_child(enabled)
	order_row.add_child(enabled_column)

	var tiers_card := make_card(_form)
	tiers_card.add_child(make_kicker("WEEKLY TIERS", &"trophy"))
	var tier_row := HBoxContainer.new()
	tier_row.add_theme_constant_override("separation", 10)
	tiers_card.add_child(tier_row)
	for i in range(3):
		var column := VBoxContainer.new()
		column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		column.add_child(make_kicker("TIER %d" % (i + 1)))
		var value := 0
		if i < community.weekly_tiers.size():
			value = community.weekly_tiers[i]
		column.add_child(_input_for("tier%d" % i, str(value), 8))
		tier_row.add_child(column)

	var links_card := make_card(_form)
	links_card.add_child(make_kicker("SOCIAL LINKS"))
	links_card.add_child(make_sub("Comma-separated URLs.", 12))
	links_card.add_child(_input_for("links", ", ".join(community.social_links), 240))

func _labeled_input(key: String, label_text: String, value: String, max_length: int) -> VBoxContainer:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	column.add_child(make_kicker(label_text))
	column.add_child(_input_for(key, value, max_length))
	return column

func _input_for(key: String, value: String, max_length: int) -> LineEdit:
	var input := make_input("", value, max_length)
	_inputs[key] = input
	return input

func _swatch_button(color: Color) -> Button:
	var button := Button.new()
	button.custom_minimum_size = Vector2(42, 42)
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(14)
	style.set_border_width_all(3)
	style.border_color = Color.WHITE if color.is_equal_approx(_accent) else Color(1, 1, 1, 0.15)
	button.add_theme_stylebox_override("normal", style)
	button.add_theme_stylebox_override("hover", style)
	button.add_theme_stylebox_override("pressed", style)
	button.add_theme_stylebox_override("focus", style)
	bind_press(button, func() -> void:
		_accent = color
		_build_form())
	return button

func _on_save() -> void:
	var data := CommunityRepository.load_overrides()
	var tiers: Array = []
	for i in range(3):
		var input: LineEdit = _inputs.get("tier%d" % i)
		tiers.append(int(input.text) if input != null and input.text.is_valid_int() else 0)
	var links: Array = []
	var links_input: LineEdit = _inputs.get("links")
	if links_input != null:
		for part in links_input.text.split(",", false):
			var link := part.strip_edges()
			if not link.is_empty():
				links.append(link)
	var enabled: ToggleSwitch = _inputs.get("enabled")
	var sort_input: LineEdit = _inputs.get("sort_order")
	data[String(_editing)] = {
		"display_name": (_inputs["display_name"] as LineEdit).text,
		"short_description": (_inputs["short_description"] as LineEdit).text,
		"accent_color": "#" + _accent.to_html(false),
		"enabled": enabled.on if enabled != null else true,
		"sort_order": int(sort_input.text) if sort_input != null and sort_input.text.is_valid_int() else 0,
		"weekly_tiers": tiers,
		"social_links": links,
	}
	CommunityRepository.save_overrides(data)
	CommunityRepository.reload_overrides()
	if ShellUI.instance != null:
		ShellUI.instance.refresh()
	Toasts.show_message("Community saved")
	_rebuild()

func _on_reset() -> void:
	CommunityRepository.clear_overrides()
	CommunityRepository.reload_overrides()
	Toasts.show_message("Community overrides cleared")
	_rebuild()
