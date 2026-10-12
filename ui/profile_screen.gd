extends UiScreen

## Profile — v2 "arcade sticker" (docs/UI_V2_BRIEF.md §5–6, docs/mockups/profile.html).
## Identity header (editable name), wallet card, 2×2 stats, your caps, rewards,
## crew history, settings collapsible, and a `nocaps_dev`-only editor entry.

## TODO(ui-v2 kit): pieces with no §2 component are composed locally from kit
## tokens: `gold_card`, pill/button fill variants, `icon_button`, `cap_tile`, and
## a value-color override for `make_stat`. Fold them into `ui/ui_screen.gd` later.
## Bright gold for the RARE cap variant: factors keep the #ffd23f ratio while
## lifting the dark cap art into readable gold (values over 1 brighten).
const GOLD_TINT := Color(4.6, 3.8, 1.1)
const GOLD_DEEP := Color("4a2f7a")

var _edit_open: bool = false
var _claimed: Dictionary = {}
var _claim_needs_wallet: bool = false
var _reset_armed: bool = false
var _reset_button: Button
var _name_input: LineEdit
## Connected wallet card starts as one compact row; tapping it expands the
## details. A new connection (address change) always starts collapsed again.
var _wallet_expanded: bool = false
var _last_wallet_address: String = ""

func setup(_payload: Dictionary) -> void:
	var page := build_page()
	_build_header(page)
	_build_wallet(page)
	_build_stats(page)
	_build_caps(page)
	# Preview rewards hidden until rewards are real (Oct 10, fundamentals D8).
	_build_history(page)
	_build_settings(page)
	if OS.has_feature("nocaps_dev"):
		_build_dev(page)
	_build_feedback(page)
	_build_version_footer(page)
	if _edit_open and _name_input != null:
		_name_input.call_deferred("grab_focus")

# ---------------------------------------------------------------------------
# Header
# ---------------------------------------------------------------------------

func _build_header(page: VBoxContainer) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", int(px(14)))
	page.add_child(row)

	var community := _represented_community()
	var selected := _selected_community()
	if community != null and community.mascot != null:
		var tile := avatar_tile(community, px(92), selected != null)
		tile.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(tile)

	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	column.add_theme_constant_override("separation", int(px(6)))
	row.add_child(column)

	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", int(px(8)))
	column.add_child(name_row)
	var name_label := outlined_title(_display_name(), CREAM, int(px(32)))
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	name_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	name_row.add_child(name_label)
	name_row.add_child(_icon_button(&"edit", _toggle_edit, px(30), px(14)))
	name_row.add_child(_expander())

	var tags := HBoxContainer.new()
	tags.add_theme_constant_override("separation", int(px(6)))
	column.add_child(tags)
	if selected != null:
		tags.add_child(_pill("REPPING %s" % selected.display_name.to_upper(), YOURS))
	var connected := not _wallet_address().is_empty()
	var verified := connected and _wallet_verified(_wallet_address())
	tags.add_child(_pill("WALLET ✓" if verified else ("WALLET" if connected else "GUEST"), YOURS if verified else LILAC))

	# Full-width row under the header (not squeezed next to the avatar), so the
	# input and SAVE always fit on a phone.
	if _edit_open:
		page.add_child(_name_editor())

func _name_editor() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", int(px(8)))
	_name_input = make_input("Your name", save_manager.display_name if save_manager != null else "", PlayerName.MAX_LENGTH)
	_name_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_input.name = "ProfileNameInput"
	# The keyboard's Done/✓ key saves too (on Android it was a no-op).
	_name_input.text_submitted.connect(func(_text: String) -> void: _save_name())
	row.add_child(_name_input)
	var save := light_button("SAVE", _save_name, SIZE_SMALL, px(40))
	save.name = "ProfileNameSave"
	# Without a minimum width the expanding input squeezed SAVE to a sliver.
	save.custom_minimum_size.x = px(150)
	row.add_child(save)
	return row

func _toggle_edit() -> void:
	_edit_open = not _edit_open
	_rebuild()

func _save_name() -> void:
	if save_manager == null or _name_input == null:
		return
	var name := PlayerName.sanitize(_name_input.text)
	var problem := PlayerName.problem(name)
	if not problem.is_empty():
		Toasts.show_message(problem)
		return
	save_manager.display_name = name
	save_manager.save_data()
	if ShellUI.instance != null:
		ShellUI.instance.refresh()
	Toasts.show_message("Name saved")
	_edit_open = false
	_rebuild()

func _display_name() -> String:
	if save_manager == null:
		return "Guest"
	return PlayerName.board_name(save_manager)

# ---------------------------------------------------------------------------
# Wallet
# ---------------------------------------------------------------------------

func _build_wallet(page: VBoxContainer) -> void:
	var address := _wallet_address()
	if address != _last_wallet_address:
		_wallet_expanded = false
	_last_wallet_address = address
	if address.is_empty():
		var panel := PanelContainer.new()
		panel.name = "ProfileWallet"
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_theme_stylebox_override("panel", _panel_style(GOLD, 4, 22, 5, 14))
		page.add_child(panel)

		var column := VBoxContainer.new()
		column.add_theme_constant_override("separation", int(px(8)))
		panel.add_child(column)

		var header := HBoxContainer.new()
		header.add_theme_constant_override("separation", int(px(10)))
		column.add_child(header)
		var icon := Icon.new()
		icon.setup(&"wallet", INK, px(26))
		icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		header.add_child(icon)
		var title := _make_base_label("Connect your wallet", int(px(20)), INK)
		title.add_theme_font_override("font", _bold())
		header.add_child(title)

		var body := _make_base_label("Connect a wallet to be prize-eligible.", int(px(14)), INK)
		body.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		column.add_child(body)

		# Only surface the queue when there is actually something waiting.
		var pending := int(RunSubmission.status(save_manager).get("pending", 0))
		if pending > 0:
			column.add_child(_pending_banner(_pending_text(pending)))

		column.add_child(_chunky_button("CONNECT WALLET", INK, GOLD, int(px(20)), px(56), 18, 4, 5, _connect_wallet))
		return

	if not _wallet_expanded:
		_build_wallet_collapsed(page, address)
		return
	_build_wallet_expanded(page, address)

## Connected but collapsed: one compact tappable row. Tapping expands the card.
func _build_wallet_collapsed(page: VBoxContainer, address: String) -> void:
	var card := sticker_card(page, 0, Color.TRANSPARENT, 14)
	card.name = "ProfileWallet"
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", int(px(10)))
	card.add_child(row)
	var label := _plain_label("%s · %s" % ["WALLET ✓" if _wallet_verified(address) else "WALLET · not verified", _short_address(address)], int(px(16)), CREAM, true)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	var chevron := Icon.new()
	chevron.setup(&"chevron", CREAM, px(18))
	chevron.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chevron.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(chevron)
	make_tappable(card, _expand_wallet)

## Expanded connected card: full details and a working Disconnect. Tapping the
## row (outside the button) collapses it again.
func _build_wallet_expanded(page: VBoxContainer, address: String) -> void:
	var card := sticker_card(page, 14)
	card.name = "ProfileWallet"
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", int(px(12)))
	card.add_child(row)
	row.add_child(_check_badge(px(34)))
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	column.add_theme_constant_override("separation", 2)
	row.add_child(column)
	column.add_child(_left_label(_short_address(address), int(px(16)), CREAM, true))
	var status := "Verified · prize-eligible" if _wallet_verified(address) else "Not verified yet · disconnect and connect again"
	column.add_child(_left_label(status, int(px(12)), Color(CREAM.r, CREAM.g, CREAM.b, 0.8), false))
	var disconnect := Button.new()
	disconnect.text = "Disconnect"
	disconnect.focus_mode = Control.FOCUS_NONE
	disconnect.add_theme_font_override("font", _bold())
	disconnect.add_theme_font_size_override("font_size", int(px(14)))
	disconnect.add_theme_color_override("font_color", LILAC)
	disconnect.add_theme_color_override("font_hover_color", GOLD)
	disconnect.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	disconnect.add_theme_stylebox_override("hover", StyleBoxEmpty.new())
	disconnect.add_theme_stylebox_override("pressed", StyleBoxEmpty.new())
	disconnect.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	bind_press(disconnect, _disconnect_wallet)
	row.add_child(disconnect)
	make_tappable(card, _collapse_wallet)

func _expand_wallet() -> void:
	_wallet_expanded = true
	_rebuild()

func _collapse_wallet() -> void:
	_wallet_expanded = false
	_rebuild()

func _disconnect_wallet() -> void:
	var wallet := get_node_or_null("/root/WalletService")
	if wallet != null and wallet.has_method("disconnect_wallet"):
		wallet.call("disconnect_wallet")

func _pending_banner(text: String) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", _panel_style(INK, 0, 12, 0, 6))
	var label := _make_base_label(text, int(px(13)), GOLD)
	label.add_theme_font_override("font", _bold())
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	panel.add_child(label)
	return panel

func _pending_text(pending: int) -> String:
	if pending == 1:
		return "1 run waiting to be verified"
	return "%d runs waiting to be verified" % pending

func _connect_wallet() -> void:
	var wallet := get_node_or_null("/root/WalletService")
	if wallet != null and wallet.has_method("connect_wallet"):
		wallet.call("connect_wallet")
		return
	Toasts.show_message("Wallet isn't available on this build")

## Wallet address once `platform/wallet_service.gd` exposes one; empty = guest.
## True when the server verified this address for this player (linkWallet, Oct 10).
func _wallet_verified(address: String) -> bool:
	return save_manager != null and not address.is_empty() and save_manager.verified_wallet == address

func _wallet_address() -> String:
	var wallet := get_node_or_null("/root/WalletService")
	if wallet == null:
		return ""
	for key in ["wallet_address", "address"]:
		var value: Variant = wallet.get(key)
		if value is String and not String(value).is_empty():
			return String(value)
	return ""

func _short_address(address: String) -> String:
	if address.length() <= 9:
		return address
	return "%s…%s" % [address.left(4), address.right(4)]

# ---------------------------------------------------------------------------
# Stats
# ---------------------------------------------------------------------------

func _build_stats(page: VBoxContainer) -> void:
	if save_manager == null:
		return
	var grid := GridContainer.new()
	grid.name = "ProfileStats"
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", int(px(10)))
	grid.add_theme_constant_override("v_separation", int(px(10)))
	page.add_child(grid)
	grid.add_child(_stat_tile(fmt(save_manager.best_score), "Best score", GOLD))
	grid.add_child(_stat_tile(_time_text(save_manager.best_time), "Best time"))
	grid.add_child(_stat_tile(fmt(_coins_total()), "Coins"))
	grid.add_child(_stat_tile(str(save_manager.games_played), "Games played"))
	grid.add_child(_stat_tile(fmt(_total_points()), "Points for crews"))
	var days := save_manager.streak_days
	grid.add_child(_stat_tile("%d day%s" % [days, "" if days == 1 else "s"], "Streak"))

## Best-survival label; "—" until a run has recorded a time.
func _time_text(seconds: float) -> String:
	if seconds <= 0.0:
		return "—"
	var total := int(seconds)
	return "%d:%02d" % [total / 60, total % 60]

## Coins earned across runs. `SaveManager.coins_total` is the single source; the
## run end banks this run's coins there before Result/Profile render.
func _coins_total() -> int:
	if save_manager == null:
		return 0
	return save_manager.coins_total

func _stat_tile(value: String, label_text: String, value_color: Color = CREAM) -> PanelContainer:
	var stat := make_stat(value, label_text)
	if value_color != CREAM:
		var column := stat.get_child(0) as VBoxContainer
		if column != null and column.get_child_count() > 0:
			(column.get_child(0) as Label).add_theme_color_override("font_color", value_color)
	return stat

func _total_points() -> int:
	var total := 0
	for value in _contribution_totals().values():
		total += int(value)
	return total

# ---------------------------------------------------------------------------
# Your caps
# ---------------------------------------------------------------------------

func _build_caps(page: VBoxContainer) -> void:
	var card := sticker_card(page, 18)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", int(px(8)))
	card.add_child(header)
	var title := make_h2("Your caps", int(px(18)))
	title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(title)
	header.add_child(_expander())
	var total := 0
	var owned := 0
	var tiles: Array = []
	for community in _communities():
		var joined := _has_cap(community.id)
		total += 1
		if joined:
			owned += 1
		tiles.append({"community": community, "rare": false, "unlocked": joined, "hint": "Join %s" % community.display_name})
		if joined:
			var rare_owned := _has_rare_cap(community.id)
			total += 1
			if rare_owned:
				owned += 1
			tiles.append({"community": community, "rare": true, "unlocked": rare_owned, "hint": "%s T3" % community.display_name})
	header.add_child(_plain_label("%d / %d" % [owned, total], int(px(13)), Color(CREAM.r, CREAM.g, CREAM.b, 0.8), true))

	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", int(px(8)))
	grid.add_theme_constant_override("v_separation", int(px(8)))
	card.add_child(grid)
	for tile in tiles:
		grid.add_child(_cap_tile(tile["community"], bool(tile["rare"]), bool(tile["unlocked"]), String(tile["hint"])))

	card.add_child(_left_label("Join a crew to get its cap. Hit weekly tiers for rare ones.", int(px(12)), Color(CREAM.r, CREAM.g, CREAM.b, 0.75), false))

func _cap_tile(community: CommunityDefinition, rare: bool, unlocked: bool, hint: String) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.custom_minimum_size = Vector2(0.0, px(84))
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", _panel_style(GOLD_DEEP if rare and unlocked else CARD_INNER, 3, 16, 0, 6, -1, GOLD if rare and unlocked else INK))
	if not unlocked:
		panel.modulate = Color(1, 1, 1, 0.85)

	var column := VBoxContainer.new()
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 2)
	panel.add_child(column)
	if rare and unlocked:
		column.add_child(_pill("RARE", GOLD))

	var cap: CapDefinition = CommunityRepository.resolve_cap(community)
	if cap != null and cap.side_texture != null:
		var texture := TextureRect.new()
		texture.texture = cap.side_texture
		texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		texture.custom_minimum_size = Vector2(px(60), px(40))
		texture.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		texture.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if not unlocked:
			texture.modulate = Color.BLACK
		elif rare:
			texture.modulate = GOLD_TINT
		column.add_child(texture)

	var label_text := community.display_name
	var label_color := CREAM
	if rare and unlocked:
		label_text = "Gold %s" % community.display_name
		label_color = GOLD
	elif not unlocked:
		label_text = hint
		label_color = LILAC
	var label := _center_label(label_text, int(px(11)), label_color, true)
	label.clip_text = true
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.custom_minimum_size.x = 0.0
	column.add_child(label)

	return panel

func _has_cap(id: StringName) -> bool:
	if save_manager == null:
		return false
	return save_manager.unlocked_caps.has(String(id)) or save_manager.total_contribution(id) > 0

func _has_rare_cap(id: StringName) -> bool:
	return save_manager != null and save_manager.rare_caps.has(String(id))

# ---------------------------------------------------------------------------
# Rewards
# ---------------------------------------------------------------------------

func _build_rewards(page: VBoxContainer) -> void:
	var card := sticker_card(page, 14)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", int(px(8)))
	card.add_child(header)
	var title := make_h2("Rewards", int(px(18)))
	title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(title)
	header.add_child(_expander())
	header.add_child(_pill("PREVIEW", LILAC))

	var any := false
	for community in _communities():
		var reached := _tier_reached(community.id)
		for tier in range(reached, 0, -1):
			any = true
			card.add_child(_tier_row(community, tier))
		if community.has_featured_campaign():
			any = true
			card.add_child(_campaign_row(community))
	if not any:
		card.add_child(make_sub("Reach a weekly tier to earn crew rewards.", SIZE_SMALL))
	var note := make_sub("Early beta preview: rewards aren't paid out yet. Claims are saved on this device and carry over when rewards go live.", SIZE_SMALL - 4)
	note.name = "RewardsPreviewNote"
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	card.add_child(note)
	if _claim_needs_wallet:
		var hint := PanelContainer.new()
		hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hint.add_theme_stylebox_override("panel", _panel_style(GOLD, 3, 12, 0, 6))
		var hint_label := _make_base_label("Connect your wallet to claim", int(px(13)), INK)
		hint_label.add_theme_font_override("font", _bold())
		hint.add_child(hint_label)
		card.add_child(hint)

func _tier_row(community: CommunityDefinition, tier: int) -> PanelContainer:
	var reward_text := community.campaign_value("reward_text")
	var row := _reward_row(community, "%s · Tier %d" % [community.display_name, tier], reward_text)
	var key := "%s:%d" % [community.id, tier]
	if _is_claimed(key):
		row.get_child(0).add_child(_plain_label("CLAIMED", int(px(13)), YOURS, true))
	else:
		row.get_child(0).add_child(_chunky_button("CLAIM", GOLD, INK, int(px(14)), px(36), 12, 3, 3, func() -> void: _claim(key), false))
	return row

func _campaign_row(community: CommunityDefinition) -> PanelContainer:
	var row := _reward_row(community, community.campaign_value("title", community.display_name), community.campaign_value("reward_text"))
	row.modulate = Color(1, 1, 1, 0.7)
	row.get_child(0).add_child(_plain_label("LOCKED", int(px(13)), CREAM, true))
	return row

func _reward_row(community: CommunityDefinition, title: String, sub: String) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", _panel_style(CARD_INNER, 3, 16, 0, 10))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", int(px(10)))
	panel.add_child(row)
	if community.mascot != null:
		var tile := avatar_tile(community, px(40), false)
		tile.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(tile)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	column.add_theme_constant_override("separation", 2)
	row.add_child(column)
	column.add_child(_plain_label(title, int(px(15)), CREAM, true))
	if not sub.is_empty():
		column.add_child(_plain_label(sub, int(px(12)), Color(CREAM.r, CREAM.g, CREAM.b, 0.8), false))
	return panel

func _claim(key: String) -> void:
	if _wallet_address().is_empty():
		_claim_needs_wallet = true
		_rebuild()
		return
	_claimed[key] = true
	if save_manager != null:
		save_manager.reward_claims[key] = int(Time.get_unix_time_from_system())
		save_manager.save_data()
	Toasts.show_message("Saved: pays out when rewards go live")
	_rebuild()

func _is_claimed(key: String) -> bool:
	return _claimed.has(key) or (save_manager != null and save_manager.reward_claims.has(key))

func _tier_reached(id: StringName) -> int:
	if save_manager == null:
		return 0
	return int(save_manager.tiers_reached.get(String(id), 0))

# ---------------------------------------------------------------------------
# Crew history
# ---------------------------------------------------------------------------

func _build_history(page: VBoxContainer) -> void:
	var card := sticker_card(page, 14)
	card.add_child(make_h2("Crew history", int(px(18))))
	var totals := _contribution_totals()
	var top := 0
	for value in totals.values():
		top = maxi(top, int(value))
	for community in _communities():
		var total := int(totals.get(String(community.id), 0))
		if total <= 0:
			continue
		card.add_child(_history_row(community, total, top))
	card.add_child(_left_label("Points stay with the crew you earned them for.", int(px(12)), Color(CREAM.r, CREAM.g, CREAM.b, 0.75), false))

func _history_row(community: CommunityDefinition, total: int, top: int) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", int(px(10)))
	if community.mascot != null:
		var tile := avatar_tile(community, px(36), community.id == _selected_id())
		tile.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(tile)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	column.add_theme_constant_override("separation", int(px(2)))
	row.add_child(column)
	var line := HBoxContainer.new()
	column.add_child(line)
	var name_label := _plain_label(community.display_name, int(px(14)), CREAM, true)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(name_label)
	line.add_child(_plain_label(fmt(total), int(px(14)), CREAM, true))
	var ratio := 0.0 if top <= 0 else float(total) / float(top)
	column.add_child(race_bar(ratio, YOURS if community.id == _selected_id() else LILAC, px(10)))
	return row

func _contribution_totals() -> Dictionary:
	if save_manager == null:
		return {}
	return save_manager.contribution_by_community

# ---------------------------------------------------------------------------
# Settings
# ---------------------------------------------------------------------------

func _build_settings(page: VBoxContainer) -> void:
	if save_manager == null:
		return
	var body := collapsible_section(page, "Settings", &"", false)
	body.add_child(_toggle_row("Sound", not save_manager.muted, _on_sound))
	body.add_child(_toggle_row("Haptics", save_manager.haptics_enabled, _on_haptics))
	body.add_child(_toggle_row("Reduced motion", save_manager.reduced_motion, _on_reduced))
	var reset := light_button("RESET LOCAL DATA", _on_reset, SIZE_SMALL, px(40))
	reset.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(reset)
	_reset_button = reset

func _toggle_row(label_text: String, value: bool, on_toggle: Callable) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", _panel_style(CARD_INNER, 3, 16, 0, 10))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", int(px(10)))
	panel.add_child(row)
	var label := _make_base_label(label_text, int(px(15)), CREAM)
	label.add_theme_font_override("font", _bold())
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(label)
	row.add_child(_expander())
	var toggle := ToggleSwitch.new()
	toggle.setup(value)
	toggle.custom_minimum_size = Vector2(px(52), px(30))
	toggle.switched.connect(on_toggle)
	row.add_child(toggle)
	return panel

func _on_reset() -> void:
	if save_manager == null or not is_instance_valid(_reset_button):
		return
	if not _reset_armed:
		_reset_armed = true
		_reset_button.text = "TAP AGAIN TO CONFIRM"
		var timer := get_tree().create_timer(3.0)
		timer.timeout.connect(func() -> void:
			if is_instance_valid(_reset_button):
				_reset_armed = false
				_reset_button.text = "RESET LOCAL DATA")
		return
	save_manager.reset_all()
	SoundService.is_sound_enabled = true
	Haptics.enabled = true
	Toasts.show_message("Local data reset")
	navigate.emit(&"home", {})

func _on_sound(enabled: bool) -> void:
	if save_manager == null:
		return
	save_manager.muted = not enabled
	save_manager.save_data()
	SoundService.is_sound_enabled = enabled

func _on_haptics(enabled: bool) -> void:
	if save_manager == null:
		return
	save_manager.haptics_enabled = enabled
	save_manager.save_data()
	Haptics.enabled = enabled

func _on_reduced(enabled: bool) -> void:
	if save_manager == null:
		return
	save_manager.reduced_motion = enabled
	save_manager.save_data()

# ---------------------------------------------------------------------------
# DEV
# ---------------------------------------------------------------------------

func _build_dev(page: VBoxContainer) -> void:
	var card := sticker_card(page, 14)
	card.add_child(make_kicker("DEV"))
	card.add_child(secondary_button("COMMUNITY DATA EDITOR", func() -> void:
		navigate.emit(&"community_editor", {}), px(54), int(px(18))))

# ---------------------------------------------------------------------------
# Shared pieces
# ---------------------------------------------------------------------------

## Early Beta card: where feedback goes (Discord).
func _build_feedback(page: VBoxContainer) -> void:
	page.add_child(make_spacer(px(12)))
	var card := sticker_card(page, 12)
	card.name = "ProfileFeedback"
	var title := _make_base_label("Early beta: tell us what you think", int(px(18)), CREAM)
	title.add_theme_font_override("font", _bold())
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	card.add_child(title)
	var sub := make_sub("Bugs, ideas, your crew: drop it in our Discord. Scores may reset while we build.")
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	card.add_child(sub)
	var join := secondary_button("JOIN OUR DISCORD", func() -> void: Links.open(Links.DISCORD), px(54), px(18))
	join.name = "ProfileDiscord"
	card.add_child(join)

## Tiny low-contrast build label in the bottom corner of the page, below every
## card and above the tab-bar safe area, so it never overlaps the UI.
func _build_version_footer(page: VBoxContainer) -> void:
	page.add_child(make_spacer(px(8)))
	var footer := _make_base_label(AppVersion.label(), int(px(11)),
		Color(CREAM.r, CREAM.g, CREAM.b, 0.45))
	footer.name = "ProfileVersion"
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	footer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.add_child(footer)

func _communities() -> Array[CommunityDefinition]:
	return CommunityRepository.enabled_sorted(CommunityRepository.load_roster())

func _selected_id() -> StringName:
	return save_manager.selected_community_id if save_manager != null else &""

## The represented community, or null for guests (no selection).
func _selected_community() -> CommunityDefinition:
	if _selected_id() == &"":
		return null
	return CommunityRepository.by_id(CommunityRepository.load_roster(), _selected_id())

## Avatar fallback only: the represented crew, else the first enabled crew.
func _represented_community() -> CommunityDefinition:
	var selected := _selected_community()
	if selected != null:
		return selected
	var communities := _communities()
	return communities[0] if not communities.is_empty() else null

func _left_label(text: String, size: int, color: Color, bold: bool) -> Label:
	var label := _make_base_label(text, size, color)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if bold:
		label.add_theme_font_override("font", _bold())
	return label

## Centered tile caption (cap tiles); long names clip instead of widening.
func _center_label(text: String, size: int, color: Color, bold: bool) -> Label:
	var label := _make_base_label(text, size, color)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	if bold:
		label.add_theme_font_override("font", _bold())
	return label

## Single-line label that never wraps (counts, scores, buttons in rows).
func _plain_label(text: String, size: int, color: Color, bold: bool) -> Label:
	var label := _make_base_label(text, size, color)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	if bold:
		label.add_theme_font_override("font", _bold())
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return label

func _check_badge(size: float) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.custom_minimum_size = Vector2(size, size)
	var style := StyleBoxFlat.new()
	style.bg_color = YOURS
	style.set_corner_radius_all(999)
	style.set_border_width_all(int(px(3)))
	style.border_color = INK
	panel.add_theme_stylebox_override("panel", style)
	panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var icon := Icon.new()
	icon.setup(&"check", INK, size * 0.45)
	panel.add_child(icon)
	return panel

## Sticker card with an arbitrary fill/ledge; `pad_bottom` can differ from `pad`.
func _panel_style(fill: Color, border: int, radius: int, ledge: int, pad: int, pad_bottom: int = -1, border_color: Color = INK) -> StyleBoxFlat:
	var style := _ledge(fill, int(px(border)), int(px(radius)), int(px(ledge)), border_color)
	style.content_margin_left = px(pad)
	style.content_margin_right = px(pad)
	style.content_margin_top = px(pad)
	style.content_margin_bottom = px(pad_bottom if pad_bottom >= 0 else pad)
	return style

## Pill tag matching the mockups (INK text by default).
func _pill(text: String, fill: Color, text_color: Color = INK, font_size: int = -1) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := _ledge(fill, 4, 999, 0)
	style.content_margin_left = px(8)
	style.content_margin_right = px(8)
	style.content_margin_top = 2.0
	style.content_margin_bottom = 6.0
	panel.add_theme_stylebox_override("panel", style)
	panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var label := _make_base_label(text, font_size if font_size > 0 else int(px(11)), text_color)
	label.add_theme_font_override("font", _bold())
	panel.add_child(label)
	return panel

## Ledge button with an arbitrary fill (kit buttons are GOLD/CARD/CREAM only).
func _chunky_button(text: String, fill: Color, text_color: Color, font_size: int, height: float, radius: int, border: int, ledge: int, action: Callable, fill_width: bool = true) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(0.0, height)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL if fill_width else Control.SIZE_SHRINK_END
	button.add_theme_font_override("font", _bold())
	button.add_theme_font_size_override("font_size", font_size)
	button.add_theme_stylebox_override("normal", _button_style(fill, border, radius, ledge, false))
	button.add_theme_stylebox_override("hover", _button_style(fill.lightened(0.06), border, radius, ledge, false))
	button.add_theme_stylebox_override("pressed", _button_style(fill.darkened(0.06), border, radius, ledge, true))
	button.add_theme_stylebox_override("focus", _button_style(fill, border, radius, ledge, false))
	button.add_theme_color_override("font_color", text_color)
	button.add_theme_color_override("font_hover_color", text_color)
	button.add_theme_color_override("font_pressed_color", text_color)
	bind_press(button, action)
	return button

func _button_style(fill: Color, border: int, radius: int, ledge: int, pressed: bool) -> StyleBoxFlat:
	var style := _panel_style(fill, border, radius, 0 if pressed else ledge, 0)
	style.content_margin_left = px(10)
	style.content_margin_right = px(10)
	style.content_margin_top = px(6) + (px(ledge) if pressed else 0.0)
	style.content_margin_bottom = px(6)
	return style

## Square CARD button with a code-drawn glyph (edit pencil).
func _icon_button(kind: StringName, action: Callable, size: float, icon_size: float) -> Button:
	var button := Button.new()
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(size, size)
	button.add_theme_stylebox_override("normal", _panel_style(CARD, 3, 10, 0, 0))
	button.add_theme_stylebox_override("hover", _panel_style(CARD.lightened(0.06), 3, 10, 0, 0))
	button.add_theme_stylebox_override("pressed", _panel_style(CARD.darkened(0.06), 3, 10, 0, 0))
	button.add_theme_stylebox_override("focus", _panel_style(CARD, 3, 10, 0, 0))
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(center)
	var icon := Icon.new()
	icon.setup(kind, CREAM, icon_size)
	center.add_child(icon)
	bind_press(button, action)
	return button

func _rebuild() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_page_root = null
	_reset_button = null
	_name_input = null
	setup({})
