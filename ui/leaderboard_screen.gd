extends UiScreen

## Board: today's live community race. "LIVE · TODAY" chip, "THE RACE" title, the
## top-3 podium (crown on 1st, YOUR CREW tag under the player's crew), the leaders
## card, the rank 4+ list, and the play CTA. Standings come only from
## `Standings.communities_today` (backend-backed, local fallback), refreshed every
## 10 s with a tween whenever the ranking changes. See docs/UI_V2_BRIEF.md §6.

const BATTLE_REFRESH_SECONDS := 20
const BATTLE_DISCOVERY_SECONDS := 60

var _scroll: ScrollContainer
var _board: VBoxContainer
var _score_labels: Dictionary = {}
var _lead_title: Label
var _lead_sub: Label
var _play_community: CommunityDefinition
var _order_ids: Array = []
var _refresh_timer: Timer
var _seen_version: int = -1
var _watch_ticks: int = 0
var _chip_dot: Icon
var _connection_label: Label
## Event-aware lower half (docs/15 §3): per-row arrows/momentum/highlight, the
## "LAST 30 MIN" feed, and the UTC countdown. All hidden when their trigger is off.
var _arrow_labels: Dictionary = {}
var _momentum_labels: Dictionary = {}
var _highlight_labels: Dictionary = {}
var _feed_card: PanelContainer
var _feed_box: VBoxContainer
var _countdown_panel: PanelContainer
var _countdown_clock: Label
var _countdown_caption: Label
var _race: Race

func setup(_payload: Dictionary) -> void:
	_build_scaffold()
	_build_board()
	_start_refresh_timer()

# ---------------------------------------------------------------------------
# Scaffold
# ---------------------------------------------------------------------------

func _build_scaffold() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()

	_scroll = ScrollContainer.new()
	_scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.scroll_deadzone = DRAG_DEADZONE
	add_child(_scroll)
	var scrollbar := _scroll.get_v_scroll_bar()
	for style_name in ["scroll", "grabber", "grabber_highlight", "grabber_pressed"]:
		scrollbar.add_theme_stylebox_override(style_name, StyleBoxEmpty.new())

	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_theme_constant_override("margin_top", int(px(26) + ShellUI.safe_top))
	_scroll.add_child(margin)

	_board = VBoxContainer.new()
	_board.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_board.add_theme_constant_override("separation", 0)
	margin.add_child(_board)

# ---------------------------------------------------------------------------
# Build
# ---------------------------------------------------------------------------

func _build_board() -> void:
	for child in _board.get_children():
		_board.remove_child(child)
		child.queue_free()
	_score_labels.clear()
	_arrow_labels.clear()
	_momentum_labels.clear()
	_highlight_labels.clear()
	_feed_card = null
	_feed_box = null
	_countdown_panel = null
	_countdown_clock = null
	_countdown_caption = null
	_lead_title = null
	_lead_sub = null
	_play_community = null
	_chip_dot = null
	_connection_label = null

	var rows := Standings.communities_today(save_manager)
	_order_ids.clear()
	for row in rows:
		_order_ids.append(String(row["id"]))

	_board.add_child(_build_top())
	if not rows.is_empty():
		_board.add_child(_build_podium(rows))
	_board.add_child(_build_section(rows))

func _build_top() -> VBoxContainer:
	var top := VBoxContainer.new()
	top.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_theme_constant_override("separation", 0)
	top.add_child(_live_chip())
	top.add_child(_spacer(px(10)))
	var title := outlined_title("THE RACE", CREAM, int(px(46)))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	top.add_child(title)
	return top

func _live_chip() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.name = "BoardLiveChip"
	panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = CARD
	style.border_color = INK
	style.set_border_width_all(6)
	style.border_width_bottom = 12
	style.set_corner_radius_all(999)
	style.content_margin_left = 32.0
	style.content_margin_right = 32.0
	style.content_margin_top = 13.0
	style.content_margin_bottom = 19.0
	panel.add_theme_stylebox_override("panel", style)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", int(px(8)))
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(row)
	_chip_dot = connection_dot(px(9))
	row.add_child(_chip_dot)
	_connection_label = _text(_connection_text(), int(px(14)), CREAM)
	row.add_child(_connection_label)
	return panel

## Chip copy for the current `Standings.connection_state()`.
func _connection_text() -> String:
	match Standings.connection_state():
		"live":
			return "LIVE · TODAY"
		"connecting":
			# Last session's rows are already on screen; only the refresh is pending.
			return "UPDATING…" if Standings.has_rows() else "CONNECTING…"
	return "OFFLINE · LAST SCORES" if Standings.has_rows() else "OFFLINE · SAVED LOCALLY"

func _refresh_connection() -> void:
	update_connection_dot(_chip_dot)
	if _connection_label != null:
		_connection_label.text = _connection_text()

# ---------------------------------------------------------------------------
# Podium (2nd · 1st · 3rd), centered and bottom-aligned
# ---------------------------------------------------------------------------

func _build_podium(rows: Array) -> Control:
	var wrap := MarginContainer.new()
	wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wrap.add_theme_constant_override("margin_top", int(px(18)))
	wrap.add_theme_constant_override("margin_left", int(px(14)))
	wrap.add_theme_constant_override("margin_right", int(px(14)))
	var row := HBoxContainer.new()
	row.name = "BoardPodium"
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", int(px(8)))
	wrap.add_child(row)
	for place in [1, 0, 2]:
		if place >= rows.size():
			continue
		row.add_child(_race_column(rows[place], place))
	return wrap

func _race_column(row: Dictionary, place: int) -> VBoxContainer:
	var mascot_sizes := [226.0, 192.0, 178.0]
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.size_flags_vertical = Control.SIZE_FILL
	column.alignment = BoxContainer.ALIGNMENT_END
	column.add_theme_constant_override("separation", int(px(4)))

	if place == 0:
		var crown := CrownIcon.new()
		crown.custom_minimum_size = Vector2(px(44), px(30))
		crown.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		column.add_child(crown)

	var community: CommunityDefinition = row.get("community")
	if community != null and community.mascot != null and community.mascot.idle_texture != null:
		var preview := MascotPreview.new()
		preview.setup(community, mascot_sizes[place])
		preview.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		column.add_child(preview)

	column.add_child(_podium_block(row, place))
	return column

func _podium_block(row: Dictionary, place: int) -> PanelContainer:
	var colors := [GOLD, SILVER, BRONZE]
	var heights := [315.0, 222.0, 167.0]
	var rank_sizes := [70, 56, 48]
	var name_sizes := [33, 30, 28]
	var score_sizes := [30, 28, 26]

	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.custom_minimum_size = Vector2(0, heights[place])
	var style := StyleBoxFlat.new()
	style.bg_color = colors[place]
	style.border_color = INK
	style.set_border_width_all(7)
	style.border_width_bottom = 0
	style.set_corner_radius_all(30)
	style.corner_radius_bottom_left = 0
	style.corner_radius_bottom_right = 0
	style.content_margin_left = 7.0
	style.content_margin_right = 7.0
	style.content_margin_top = int(px(8) + 7)
	style.content_margin_bottom = 7.0
	panel.add_theme_stylebox_override("panel", style)

	var column := VBoxContainer.new()
	column.alignment = BoxContainer.ALIGNMENT_BEGIN
	column.add_theme_constant_override("separation", int(px(3)))
	panel.add_child(column)
	column.add_child(_text(str(int(row.get("rank", place + 1))), rank_sizes[place], INK))
	var podium_name := _text(String(row.get("name", "")), name_sizes[place], INK)
	_ellipsis(podium_name)
	column.add_child(podium_name)
	var score := _text(fmt(int(row.get("score", 0))), score_sizes[place], INK)
	column.add_child(score)
	_score_labels[String(row.get("id", ""))] = score
	if _selected_id() != &"" and StringName(row.get("id", "")) == _selected_id():
		column.add_child(_spacer(px(8)))
		column.add_child(_yours_tag())
	return panel

func _yours_tag() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var style := StyleBoxFlat.new()
	style.bg_color = INK
	style.set_corner_radius_all(999)
	style.content_margin_left = 18.0
	style.content_margin_right = 18.0
	style.content_margin_top = 4.0
	style.content_margin_bottom = 4.0
	panel.add_theme_stylebox_override("panel", style)
	panel.add_child(_text("YOUR CREW", 22, YOURS))
	return panel

# ---------------------------------------------------------------------------
# Leaders card + ALL CREWS list + CTA
# ---------------------------------------------------------------------------

func _build_section(rows: Array) -> PanelContainer:
	var section := PanelContainer.new()
	section.name = "BoardSection"
	section.mouse_filter = Control.MOUSE_FILTER_IGNORE
	section.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var style := StyleBoxFlat.new()
	style.bg_color = CARD
	style.border_color = INK
	style.set_border_width_all(0)
	style.border_width_top = 9
	style.set_corner_radius_all(0)
	style.content_margin_left = 30.0
	style.content_margin_right = 30.0
	style.content_margin_top = 30.0
	style.content_margin_bottom = int(137.0 + ShellUI.safe_bottom + 30.0)
	section.add_theme_stylebox_override("panel", style)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 0)
	section.add_child(column)

	var events := _events(rows)

	if not rows.is_empty():
		column.add_child(_build_lead_card(rows))
		column.add_child(_spacer(px(10)))

	column.add_child(_all_crews_header(events))
	column.add_child(_spacer(px(10)))

	var rows_box := VBoxContainer.new()
	rows_box.add_theme_constant_override("separation", int(px(10)))
	column.add_child(rows_box)
	for i in range(3, rows.size()):
		rows_box.add_child(_build_crew_row(rows[i], events))
	if rows.size() <= 3:
		var empty := _text("No other crews yet — invite one.", 26, Color(CREAM, 0.7))
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		rows_box.add_child(empty)

	column.add_child(_spacer(px(10)))
	_feed_card = _build_feed_card()
	column.add_child(_feed_card)
	column.add_child(_spacer(px(8)))
	column.add_child(_build_play_button(rows))
	_apply_events(events)
	return section

func _build_lead_card(rows: Array) -> PanelContainer:
	var leader: Dictionary = rows[0]
	var second := int(rows[1]["score"]) if rows.size() > 1 else 0
	var gap := int(leader["score"]) - second
	var community: CommunityDefinition = leader.get("community")

	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var style := StyleBoxFlat.new()
	style.bg_color = CARD_INNER
	style.border_color = INK
	style.set_border_width_all(6)
	style.border_width_bottom = 13
	style.set_corner_radius_all(33)
	style.content_margin_left = 32.0
	style.content_margin_right = 32.0
	style.content_margin_top = 24.0
	style.content_margin_bottom = 31.0
	panel.add_theme_stylebox_override("panel", style)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 22)
	panel.add_child(row)

	if community != null and community.mascot != null and community.mascot.idle_texture != null:
		row.add_child(_avatar(community, px(44), 22, community.id == _selected_id()))

	var texts := VBoxContainer.new()
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	texts.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	texts.add_theme_constant_override("separation", 4)
	row.add_child(texts)
	_lead_title = _text("%s leads by %s" % [String(leader["name"]), fmt(gap)], 30, CREAM)
	_lead_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_ellipsis(_lead_title)
	texts.add_child(_lead_title)
	_lead_sub = _text(_you_added_text(), 24, Color(CREAM, 0.85))
	_lead_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_ellipsis(_lead_sub)
	texts.add_child(_lead_sub)
	return panel

func _all_crews_header(_events: Dictionary) -> Control:
	var wrap := MarginContainer.new()
	wrap.add_theme_constant_override("margin_top", int(px(6)))
	wrap.add_theme_constant_override("margin_left", int(px(4)))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	wrap.add_child(row)
	var label := _text("ALL CREWS", int(px(14)), Color(CREAM, 0.7))
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(label)
	_countdown_panel = _build_countdown()
	row.add_child(_countdown_panel)
	return wrap

## "TODAY ENDS h:mm:ss" pill; hidden until a scoreboard event is live (or the
## final UTC hour), red in the last 60 min (docs/15 §3).
func _build_countdown() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", _countdown_style(false))
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 0)
	panel.add_child(column)
	_countdown_caption = _text("TODAY ENDS", 20, LILAC)
	column.add_child(_countdown_caption)
	_countdown_clock = _text("0:00:00", 30, CREAM)
	column.add_child(_countdown_clock)
	panel.visible = false
	return panel

func _countdown_style(last_hour: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = LIVE if last_hour else CARD
	style.border_color = INK
	style.set_border_width_all(6)
	style.border_width_bottom = 11
	style.set_corner_radius_all(22)
	style.content_margin_left = 18.0
	style.content_margin_right = 18.0
	style.content_margin_top = 8.0
	style.content_margin_bottom = 12.0
	return style

func _build_crew_row(row: Dictionary, events: Dictionary) -> Control:
	var community: CommunityDefinition = row.get("community")
	var id := String(row["id"])
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var style := StyleBoxFlat.new()
	style.bg_color = CARD_INNER
	style.border_color = INK
	style.set_border_width_all(6)
	style.border_width_bottom = 12
	style.set_corner_radius_all(30)
	style.content_margin_left = 28.0
	style.content_margin_right = 28.0
	style.content_margin_top = 21.0
	style.content_margin_bottom = 27.0
	panel.add_theme_stylebox_override("panel", style)

	var inner := HBoxContainer.new()
	inner.add_theme_constant_override("separation", 22)
	panel.add_child(inner)

	var rank := _text(str(int(row["rank"])), 33, CREAM)
	rank.custom_minimum_size = Vector2(48.0, 0.0)
	rank.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	inner.add_child(rank)

	if community != null and community.mascot != null and community.mascot.idle_texture != null:
		var tile := _avatar(community, 74.0, 22, community.id == _selected_id())
		tile.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		inner.add_child(tile)

	var texts := VBoxContainer.new()
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	texts.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	texts.add_theme_constant_override("separation", 3)
	inner.add_child(texts)

	var name_label := _text(String(row["name"]), 30, CREAM)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_ellipsis(name_label)
	texts.add_child(name_label)

	var momentum := _text("", 24, CORAL)
	momentum.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_ellipsis(momentum)
	momentum.visible = false
	texts.add_child(momentum)
	_momentum_labels[id] = momentum

	var highlight := _text("", 24, GOLD)
	highlight.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_ellipsis(highlight)
	highlight.visible = false
	texts.add_child(highlight)
	_highlight_labels[id] = highlight

	var right := VBoxContainer.new()
	right.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	right.add_theme_constant_override("separation", 2)
	inner.add_child(right)

	var score := _text(fmt(int(row["score"])), 30, CREAM)
	score.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	right.add_child(score)
	_score_labels[id] = score

	var arrow := _text("", 24, YOURS)
	arrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	arrow.visible = false
	right.add_child(arrow)
	_arrow_labels[id] = arrow

	make_tappable(panel, func() -> void:
		navigate.emit(&"community_detail", {"community_id": id}))
	return panel

## "LAST 30 MIN" feed card; hidden while there are no events.
func _build_feed_card() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var style := StyleBoxFlat.new()
	style.bg_color = CARD
	style.border_color = LILAC
	style.set_border_width_all(6)
	style.set_corner_radius_all(30)
	style.content_margin_left = 28.0
	style.content_margin_right = 28.0
	style.content_margin_top = 20.0
	style.content_margin_bottom = 24.0
	panel.add_theme_stylebox_override("panel", style)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	panel.add_child(column)
	var title := _text("LAST 30 MIN", 24, Color(CREAM, 0.8))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	column.add_child(title)
	_feed_box = VBoxContainer.new()
	_feed_box.add_theme_constant_override("separation", 4)
	column.add_child(_feed_box)
	panel.visible = false
	return panel

# ---------------------------------------------------------------------------
# Event data + application (docs/15 §3)
# ---------------------------------------------------------------------------

## One place that reads `meta/race.gd` and the board moments for a rows snapshot.
func _events(rows: Array) -> Dictionary:
	var race := _race_instance()
	var now := Time.get_unix_time_from_system()
	Moments.observe_board(save_manager, race, rows, now)

	var arrows: Dictionary = race.rank_arrows(rows, now)
	var momentum: Dictionary = {}
	for entry in race.momentum_line(now):
		momentum[String(entry.get("id", ""))] = {
			"gain": int(entry.get("gain", 0)),
			"minutes": maxi(2, int(float(entry.get("span_seconds", 0)) / 60.0)),
		}

	var gap: Dictionary = {}
	var my_id := String(_selected_id())
	if not my_id.is_empty():
		var target: Variant = race.gap_to_pass(rows, my_id)
		if target is Dictionary and not target.is_empty():
			var target_rank := 1
			for row in rows:
				if String(row.get("id", "")) == my_id:
					target_rank = maxi(int(row.get("rank", 1)) - 1, 1)
					break
			target["target_rank"] = target_rank
			gap[my_id] = target

	return {
		"arrows": arrows,
		"momentum": momentum,
		"gap": gap,
		"feed": _feed_lines(race, rows, now),
		"ending": race.day_ending(now),
	}

## Applies an event snapshot to the already-built labels/feed/countdown.
func _apply_events(events: Dictionary) -> void:
	_refresh_feed(events.get("feed", []))
	_refresh_countdown(events.get("ending", {}), _has_events(events))
	for id in _momentum_labels:
		var label: Label = _momentum_labels[id]
		var momentum: Variant = events.momentum.get(id)
		if momentum == null:
			label.visible = false
			continue
		label.visible = true
		label.text = "surging · +%d in %d min" % [int(momentum["gain"]), int(momentum["minutes"])]
	for id in _arrow_labels:
		var label: Label = _arrow_labels[id]
		var delta := int(events.arrows.get(id, 0))
		label.visible = delta != 0
		if delta != 0:
			label.text = ("▲%d" if delta > 0 else "▼%d") % absi(delta)
			label.add_theme_color_override("font_color", YOURS if delta > 0 else CORAL)
	for id in _highlight_labels:
		var label: Label = _highlight_labels[id]
		var gap: Variant = events.gap.get(id)
		if gap == null:
			label.visible = false
			continue
		label.visible = true
		label.text = "%s to #%d" % [fmt(int(gap["gap"])), int(gap.get("target_rank", 1))]

func _refresh_feed(feed: Array) -> void:
	if _feed_card == null or _feed_box == null:
		return
	for child in _feed_box.get_children():
		_feed_box.remove_child(child)
		child.queue_free()
	_feed_card.visible = not feed.is_empty()
	for line in feed:
		var text := String(line.get("title", ""))
		var detail := String(line.get("detail", ""))
		if not detail.is_empty():
			text += " · " + detail
		var label := _text(text, 26, CREAM)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_feed_box.add_child(label)

func _refresh_countdown(ending: Dictionary, has_events: bool) -> void:
	if _countdown_panel == null:
		return
	var last_hour := bool(ending.get("last_hour", false))
	_countdown_panel.visible = has_events or last_hour
	_countdown_panel.add_theme_stylebox_override("panel", _countdown_style(last_hour))
	if _countdown_clock != null:
		_countdown_clock.text = String(ending.get("clock", "0:00:00"))
		_countdown_clock.add_theme_color_override("font_color", INK if last_hour else CREAM)
	if _countdown_caption != null:
		_countdown_caption.add_theme_color_override("font_color", INK if last_hour else LILAC)

func _has_events(events: Dictionary) -> bool:
	for id in events.arrows:
		if int(events.arrows[id]) != 0:
			return true
	if not events.momentum.is_empty() or not events.gap.is_empty():
		return true
	return not (events.feed as Array).is_empty()

## Up to five "LAST 30 MIN" lines. The window and content come from
## `Race.recent_events`; the display copy is taken from the matching
## `peek_rows("board_row")` moment when one exists.
func _feed_lines(race: Race, rows: Array, now: float) -> Array:
	var lines: Array = []
	var names := _name_map(rows)
	var moments := _feed_moment_text(now)
	for event in race.recent_events(now):
		if not event is Dictionary:
			continue
		var by := String(event.get("by", ""))
		var over := String(event.get("over", ""))
		var key := "feed:%s:%s:%d" % [by, over, int(float(event.get("t", 0.0)))]
		var moment: Variant = moments.get(key)
		var title := String(moment["title"]) if moment != null \
			else "%s overtook %s" % [_name_or(names, by), _name_or(names, over)]
		var detail := String(moment["detail"]) if moment != null \
			else "%d min ago" % maxi(1, int((now - float(event.get("t", now))) / 60.0))
		lines.append({"title": title, "detail": detail})
		if lines.size() >= 5:
			break
	return lines

func _feed_moment_text(now: float) -> Dictionary:
	var out: Dictionary = {}
	for moment in Moments.peek_rows(&"board_row", now):
		if String(moment.get("id", "")) != "overtake_feed":
			continue
		out[String(moment.get("key", ""))] = {
			"title": String(moment.get("title", "")),
			"detail": String(moment.get("detail", "")),
		}
	return out

func _race_instance() -> Race:
	if _race == null:
		_race = Standings.race_state()
	return _race

func _name_map(rows: Array) -> Dictionary:
	var out: Dictionary = {}
	for row in rows:
		if row is Dictionary:
			out[String(row.get("id", ""))] = String(row.get("name", ""))
	return out

func _name_or(names: Dictionary, id: String) -> String:
	return String(names.get(id, id))

func _build_play_button(rows: Array) -> Control:
	var wrap := MarginContainer.new()
	wrap.add_theme_constant_override("margin_top", int(px(8)))
	_play_community = _pick_play_community(rows)
	if _play_community != null:
		var button := primary_button(
			"PLAY FOR %s" % _play_community.display_name.to_upper(),
			_on_play,
			115.0,
			44
		)
		button.name = "BoardPlayCta"
		wrap.add_child(button)
	return wrap

func _pick_play_community(rows: Array) -> CommunityDefinition:
	var selected := _selected_id()
	for row in rows:
		var community: CommunityDefinition = row.get("community")
		if community != null and community.id == selected:
			return community
	if rows.is_empty():
		return null
	return rows[0].get("community")

func _on_play() -> void:
	if _play_community == null:
		return
	if save_manager != null and save_manager.selected_community_id != _play_community.id:
		save_manager.set_selected_community(_play_community.id)
		Toasts.show_message("Representing %s" % _play_community.display_name)
		if ShellUI.instance != null:
			ShellUI.instance.refresh()
	navigate.emit(&"run", {})

# ---------------------------------------------------------------------------
# Live refresh: values update in place; rank changes crossfade the board
# ---------------------------------------------------------------------------

func _refresh() -> void:
	if _board == null:
		return
	_refresh_connection()
	var rows := Standings.communities_today(save_manager)
	var ids: Array = []
	for row in rows:
		ids.append(String(row["id"]))
	if ids != _order_ids:
		_order_ids = ids
		var tween := create_tween()
		tween.tween_property(_board, "modulate:a", 0.0, 0.12)
		tween.tween_callback(_build_board)
		tween.tween_property(_board, "modulate:a", 1.0, 0.18)
		return
	_update_values(rows)
	_apply_events(_events(rows))

func _update_values(rows: Array) -> void:
	for row in rows:
		var label: Label = _score_labels.get(String(row["id"]))
		if label != null:
			label.text = fmt(int(row["score"]))
	if _lead_title != null and not rows.is_empty():
		var second := int(rows[1]["score"]) if rows.size() > 1 else 0
		_lead_title.text = "%s leads by %s" % [
			String(rows[0]["name"]),
			fmt(int(rows[0]["score"]) - second),
		]
	if _lead_sub != null:
		_lead_sub.text = _you_added_text()

## No timed polling (Oct 10, fundamentals E10). A cheap 1 s watch re-renders only
## when Standings has new data (a fetch finished: screen open, resume, after a run),
## and refreshes on a timer only while a battle is live (BATTLE_REFRESH_SECONDS).
## Looking for a newly started battle costs one small query a minute.
func _start_refresh_timer() -> void:
	if is_instance_valid(_refresh_timer):
		return
	_seen_version = Standings.version()
	_refresh_timer = Timer.new()
	_refresh_timer.wait_time = 1.0
	_refresh_timer.timeout.connect(_on_watch_tick)
	add_child(_refresh_timer)
	_refresh_timer.start()

func _on_watch_tick() -> void:
	_watch_ticks += 1
	var battle := BattleService.is_live() or BattleService.in_countdown()
	if battle and _watch_ticks % BATTLE_REFRESH_SECONDS == 0:
		BattleService.refresh_boards()
	if Standings.version() != _seen_version or (battle and _watch_ticks % BATTLE_REFRESH_SECONDS == 0):
		_seen_version = Standings.version()
		_refresh()
	elif _watch_ticks % BATTLE_DISCOVERY_SECONDS == 0:
		BattleService.refresh()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_RESUMED and is_inside_tree():
		_refresh()

# ---------------------------------------------------------------------------
# Small helpers
# ---------------------------------------------------------------------------

func _avatar(community: CommunityDefinition, size: float, radius: int, mine: bool) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.custom_minimum_size = Vector2(size, size)
	var style := StyleBoxFlat.new()
	style.bg_color = CARD
	style.set_corner_radius_all(radius)
	style.set_border_width_all(6)
	style.border_color = YOURS if mine else INK
	style.content_margin_left = 0.0
	style.content_margin_right = 0.0
	style.content_margin_top = 0.0
	style.content_margin_bottom = 0.0
	panel.add_theme_stylebox_override("panel", style)
	var preview := MascotPreview.new()
	preview.setup(community, size)
	panel.add_child(preview)
	return panel

func _text(value: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = value
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_override("font", _bold())
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	return label

## Long crew names and event lines are trimmed to an ellipsis instead of spilling
## out of their row and over a neighbouring row or the score column.
func _ellipsis(label: Label) -> Label:
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.custom_minimum_size.x = 0.0
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	label.clip_text = true
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	return label

func _spacer(height: float) -> Control:
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0.0, height)
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return spacer

func _selected_id() -> StringName:
	if save_manager == null:
		return &""
	return save_manager.selected_community_id

func _you_added() -> int:
	var id := _selected_id()
	if save_manager == null or id == &"":
		return 0
	return save_manager.day_total(id)

## Guest empty state: without a represented crew there is nothing "you added"
## yet, so the line invites a first run instead of showing a zero.
func _you_added_text() -> String:
	if _selected_id() == &"":
		return "Play for a crew to join the race"
	return "You added %s today" % fmt(_you_added())

# ---------------------------------------------------------------------------
# Crown (mockup's zigzag, exact shape; drawn locally to keep it independent)
# ---------------------------------------------------------------------------

class CrownIcon extends Control:
	const FILL := Color("ffd23f")
	const INK := Color("1d1033")

	func _draw() -> void:
		var w := size.x
		var h := size.y
		var points := PackedVector2Array([
			Vector2(w * 0.056, h * 0.857),
			Vector2(w * 0.111, h * 0.214),
			Vector2(w * 0.333, h * 0.500),
			Vector2(w * 0.500, h * 0.071),
			Vector2(w * 0.667, h * 0.500),
			Vector2(w * 0.889, h * 0.214),
			Vector2(w * 0.944, h * 0.857),
		])
		draw_colored_polygon(points, FILL)
		var outline := PackedVector2Array(points)
		outline.append(points[0])
		draw_polyline(outline, INK, maxf(3.0, w * 0.06), true)
