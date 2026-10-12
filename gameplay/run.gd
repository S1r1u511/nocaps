extends Node2D

## One run of the tap-to-fly core loop. Thin orchestration root: it resolves the
## player's community, advances the world, delegates landing decisions to `Landing`
## and authoritative facts to `RunState`, and drives the ported cappycap-style juice
## (combo scoring, effects, flash, shake, haptics, death beat).
## See docs/01_GDD.md §3–4 and docs/03_ARCHITECTURE.md §5–7.

signal navigate(screen: StringName, payload: Dictionary)

enum Death { GROUND, HAZARD, WRONG }
enum Surprise { IDLE, TELEGRAPH, SLAM, RETRACT }

## Gameplay HUD palette (docs/UI_V2_BRIEF.md §1).
const INK := Color("1d1033")
const CARD := Color("2b1b4a")
const CARD_INNER := Color("3a2466")
const GOLD := Color("ffd23f")
const CREAM := Color("fff4dc")
const YOURS := Color("5ee08a")
const CORAL := Color("ff8a7a")
const BOLD_FONT_PATH := "res://data/fonts/fredoka_bold.tres"

## Fallback weekly crew-goal tiers used by the run HUD popup when a community
## has no authored `weekly_tiers`.
## TESTING, move to data later
const TESTING_WEEKLY_TIERS: Array[int] = [10000, 25000, 50000]

## v3 run HUD (docs/mockups/v3/README.md, approved 2026-09-29). Mockup px × 1.85
## rounded to game px. The HUD draws exactly three things: the crew tag, the
## score (plus its NEW BEST ribbon), and the crew-goal popup on run start.
const HUD_TAG_LEFT := 30.0
const HUD_TAG_TOP := 41.0
const HUD_TAG_AVATAR := 56.0
const HUD_TAG_AVATAR_RING := 4.0
## Content margins include the 6 px ink border, so the visible padding is 6 px.
const HUD_TAG_PAD_LEFT := 12.0
const HUD_TAG_PAD_RIGHT := 28.0
const HUD_TAG_PAD_Y := 11.0
const HUD_TAG_GAP := 15.0
const HUD_TAG_FONT := 24
const HUD_GOAL_GAP := 26.0
const HUD_GOAL_WIDTH := 278.0
const HUD_GOAL_HEIGHT := 92.0
const HUD_GOAL_POINTER_X := 40.0
const HUD_GOAL_HOLD := 2.5
const HUD_GOAL_FADE := 0.25
const HUD_GOAL_BAR_WIDTH := 226.0
const HUD_GOAL_BAR_HEIGHT := 15.0
const HUD_SCORE_RIGHT := 33.0
## The mockup's digits render from y 44 (its `top: 26` CSS line box hides 13 px
## of ascent above the cap), but a Godot Label draws its ascent at the rect top,
## so the rect starts 13 px higher to land the ink on the mockup's 44.
const HUD_SCORE_TOP := 13.0
const HUD_SCORE_SIZE := 118
const HUD_BEST_RIGHT := 30.0
const HUD_BEST_TOP := 163.0
## Coin chip: shares the right-hand column under the score; it takes the slot
## the NEW BEST ribbon would use, and the ribbon drops below it when both show.
const HUD_COIN_SIZE := 30
const HUD_COIN_ICON := 28.0
const HUD_COLUMN_GAP := 12.0
## The highest a feedback popup may be drawn; keeps them out of the HUD columns.
const POPUP_LANE_TOP := 730.0
const POPUP_MARGIN_X := 40.0

## Fallback in-flight cap width, as a fraction of `mascot_world_size`.
const FALLBACK_CAP_WIDTH_RATIO := 0.4
const LAND_COLORS := [
	Color("ff3b30"), Color("ffd60a"), Color("ffffff"), Color("34c759"), Color("ff9d2e"),
]
const DUST_COLORS := [Color("ffffff"), Color("cdd7e8"), Color("9fb0c9")]
const DEBRIS_COLORS := [Color("dfe7f2"), Color("9fb0c9"), Color("ff3b30"), Color("ffffff")]
const WRONG_COLORS := [Color("ff3b30"), Color("ffd60a"), Color("ffffff")]

## Onboarding hint: only the first `YOURS_TAG_HINT_COUNT` own-crew mascots of a run
## carry the YOURS tag; later ones (and every rival) never do.
const YOURS_TAG_HINT_COUNT := 3

@export var tuning: RunTuning

@onready var shake_root: Node2D = $ShakeRoot
@onready var world: Node2D = $ShakeRoot/World
@onready var cap: CapController = $ShakeRoot/Cap
@onready var effects: Effects = $ShakeRoot/Effects
@onready var mascots_root: Node2D = $ShakeRoot/World/Mascots
@onready var hazards_root: Node2D = $ShakeRoot/World/Hazards
@onready var coins: Coins = $ShakeRoot/World/Coins
@onready var background: RunBackground = $Background/BackgroundVisual
@onready var ui_layer: CanvasLayer = $UI
@onready var flash_rect: ColorRect = $UI/Flash
@onready var score_label: Label = $UI/Score
@onready var cause_label: Label = $UI/Cause
@onready var tap_prompt: Label = $UI/TapPrompt
@onready var pause_overlay: ColorRect = $UI/Pause
@onready var resume_button: Button = $UI/Pause/Panel/Resume
@onready var mute_button: Button = $UI/Pause/Panel/Mute
@onready var home_button: Button = $UI/Pause/Panel/Home

var state := RunState.new()
var target_community: CommunityDefinition

var _spawn := SpawnDirector.new()
var _save: SaveManager
var _backend: BackendClient
var _failed: bool = false
var _bump_cooldown: float = 0.0
var _paused: bool = false
var _flapped: bool = false
## True from run start until the player's first tap: nothing scrolls, spawns or
## can kill the cap before then, and "TAP TO FLY" stays up. Applies to every run.
var _waiting_for_tap: bool = false
var _flash_amount: float = 0.0
var _flash_color: Color = Color.WHITE
var _shake_power: float = 0.0
var _shake_time_left: float = 0.0
var _warned: bool = false
var _pending_payload: Dictionary = {}
var _hit_stop_until: float = 0.0
var _ground_y: float = 1150.0
var _prev_cap_y: float = 600.0
## 0 = no prompt, 1 = tap prompt, 2 = land-only prompt.
var _tutorial_stage: int = 0
var _tutorial_timer: float = 0.0
var _safe_top: float = 0.0
var _bold_font: Font
## v3 HUD nodes (docs/mockups/v3/README.md): `FOR {CREW} · m:ss` tag top-left,
## score top-right, and the first-seconds crew-goal popup under the tag.
var _tag_panel: PanelContainer
var _tag_avatar: TextureRect
var _tag_name_label: Label
var _tag_time_label: Label
var _goal_popup: Control
var _goal_fill: TextureProgressBar
var _goal_percent_label: Label
var _goal_tween: Tween
var _best_ribbon: PanelContainer
var _coin_chip: PanelContainer
var _coin_label: Label
var _dev_button: Button
var _time_shown: int = -1
## Weekly crew total snapshotted at run start for the crew-goal popup.
var _week_total: int = 0
var _perfects: int = 0
var _max_combo: int = 0
## Persisted best before this run, and whether it has been beaten live.
var _best_at_start: int = 0
var _new_best: bool = false
## Own-crew mascots that have already received the onboarding YOURS tag this run.
var _tag_hinted_targets: int = 0
var _surprise_phase: int = Surprise.IDLE
var _surprise_timer: float = 0.0
var _surprise_dwell: float = 0.0
var _surprise_cooldown: float = 0.0
var _surprise_hazard: Hazard
## DEV-only quick-test switches (`nocaps_dev` panel). Never persisted, never rules.
var dev_invincible: bool = false
var dev_surprise_enabled: bool = true
## Wrapper around `ShakeRoot` that carries the world zoom-out (camera). The HUD is
## a CanvasLayer and the background is a screen-space sibling, so both stay fixed.
var _zoom_root: Node2D

func _ready() -> void:
	Engine.time_scale = 1.0
	if tuning == null:
		tuning = load("res://data/tuning/default_run_tuning.tres") as RunTuning
	var viewport := get_viewport_rect().size
	_ground_y = viewport.y - tuning.ground_inset if viewport.y > 240.0 else tuning.ground_y
	_setup_view()
	apply_tuning()
	coins.configure(tuning)
	effects.configure(_ground_y)
	effects.set_reduced_motion(_reduced_motion())
	effects.spawn_motes(viewport)
	_spawn.configure(tuning, mascots_root, hazards_root, _ground_y, _view_top_y())
	_style_hud()
	_build_crew_tag()
	_build_goal_popup()
	_build_best_ribbon()
	_build_coin_chip()
	_build_dev_button()
	_apply_safe_area()
	resume_button.pressed.connect(_resume)
	mute_button.pressed.connect(_toggle_mute)
	home_button.pressed.connect(_go_home)
	_surface_background()
	_apply_community()
	restart()

## The shell backdrop (scenes/main.tscn) draws in the base canvas layer, above the
## run's own -2 CanvasLayer. Re-home the background into the run's base layer so the
## gameplay sky and cloud sea are actually visible during a run.
func _surface_background() -> void:
	if background == null or not background.get_parent() is CanvasLayer:
		return
	background.get_parent().remove_child(background)
	add_child(background)
	move_child(background, 0)

# ---------------------------------------------------------------------------
# Camera: world zoom-out (playtest_v05). World-only; the HUD and the
# screen-space background never move, and taps stay whole-screen.
# ---------------------------------------------------------------------------

func _setup_view() -> void:
	if _zoom_root != null and is_instance_valid(_zoom_root):
		return
	_zoom_root = Node2D.new()
	_zoom_root.name = "CameraRoot"
	add_child(_zoom_root)
	var parent := shake_root.get_parent()
	if parent != null:
		parent.remove_child(shake_root)
	_zoom_root.add_child(shake_root)
	var viewport := get_viewport()
	if viewport != null and not viewport.size_changed.is_connected(_apply_view_zoom):
		viewport.size_changed.connect(_apply_view_zoom)

## World-space offset of the zoomed canvas. The cap's x and the mascot line's y
## keep the screen positions they had at zoom 1.0 (owner decision 2026-10-01), so
## the zoom only widens the view; the ground and ceiling bands shift with them.
func _zoom_anchor() -> Vector2:
	var z := clampf(tuning.camera_zoom, 0.5, 1.0)
	return Vector2(tuning.cap_x * (1.0 - z), tuning.mascot_line_y * (1.0 - z))

## Orthographic zoom-out that keeps the mascot line where it sat at zoom 1.0, so
## gameplay math (all in unzoomed world units) is untouched and only the framing
## changes. The ground line ends up slightly above the viewport bottom, inside
## the cloud sea; the ceiling follows the visible top edge.
func _apply_view_zoom() -> void:
	if _zoom_root == null or tuning == null:
		return
	var z := clampf(tuning.camera_zoom, 0.5, 1.0)
	_zoom_root.scale = Vector2(z, z)
	_zoom_root.position = _zoom_anchor()
	_spawn.set_ceiling_y(_view_top_y())

## World y at the top edge of the viewport after the zoom (negative: the zoom
## shows air above world y = 0). Ceiling hazards anchor here instead of y = 0.
func _view_top_y() -> float:
	var z := clampf(tuning.camera_zoom, 0.5, 1.0)
	return -_zoom_anchor().y / z

func _screen_to_world_y(screen_y: float) -> float:
	var z := clampf(tuning.camera_zoom, 0.5, 1.0)
	return (screen_y - _zoom_anchor().y) / z

func _world_to_screen(pos: Vector2) -> Vector2:
	if _zoom_root == null:
		return pos
	return _zoom_root.position + pos * _zoom_root.scale.x

## Called by AppFlow so the run can use the selected community and persist the best score.
func bind_services(save_manager: SaveManager, backend: BackendClient) -> void:
	_save = save_manager
	_backend = backend
	if _save != null and _save.selected_community_id != &"":
		_apply_community()
		restart()

## Pushes the current RunTuning values into derived components. Safe to call live
## from the DEV panel; it does not restart the run.
func apply_tuning() -> void:
	cap.cap_radius = tuning.cap_radius
	cap.max_fall_speed = tuning.max_fall_speed
	cap.tilt_up = tuning.tilt_up
	cap.tilt_down = tuning.tilt_down
	cap.rotation_follow = tuning.rotation_follow
	cap.flap_rotation_snap = tuning.flap_rotation_snap
	cap.land_rotation_snap = tuning.land_rotation_snap
	cap.flap_stretch = tuning.flap_stretch
	cap.land_squash = tuning.land_squash
	_apply_view_zoom()

## Shifts the HUD clear of notches and gesture bars on mobile.
func _apply_safe_area() -> void:
	var insets := SafeArea.insets()
	_safe_top = insets.y
	if _safe_top <= 0.0:
		return
	for node in [score_label, _tag_panel, _goal_popup]:
		if node != null:
			node.position.y += _safe_top
	_layout_right_column()

## Clamps a feedback popup into the lane below every HUD element so it can never
## cover the score or the crew tag (docs/15 §3). Popups live in the zoomed world,
## so the screen-space lane bounds are converted back.
func _popup_pos(pos: Vector2) -> Vector2:
	var viewport := get_viewport_rect().size
	var z := clampf(tuning.camera_zoom, 0.5, 1.0)
	var min_y := _screen_to_world_y(POPUP_LANE_TOP + _safe_top)
	var max_y := _screen_to_world_y(maxf(POPUP_LANE_TOP + _safe_top, viewport.y - 80.0))
	return Vector2(
		clampf(pos.x, POPUP_MARGIN_X / z, viewport.x - POPUP_MARGIN_X / z),
		clampf(pos.y, min_y, max_y),
	)

## Global rects of the visible HUD zones, keyed by zone. Used by the no-overlap
## check so every band can be asserted disjoint without reading the scene. The
## score and its NEW BEST ribbon form one right-hand column, so they share a zone.
func _hud_zone_rects() -> Dictionary:
	var out: Dictionary = {}
	if _tag_panel != null and is_instance_valid(_tag_panel):
		out["tag"] = _tag_panel.get_global_rect()
	if score_label != null and is_instance_valid(score_label):
		var score_zone := score_label.get_global_rect()
		if _best_ribbon != null and is_instance_valid(_best_ribbon) and _best_ribbon.visible:
			score_zone = score_zone.merge(_best_ribbon.get_global_rect())
		if _coin_chip != null and is_instance_valid(_coin_chip) and _coin_chip.visible:
			score_zone = score_zone.merge(_coin_chip.get_global_rect())
		out["score"] = score_zone
	if _goal_popup != null and is_instance_valid(_goal_popup) and _goal_popup.visible:
		out["goal"] = _goal_popup.get_global_rect()
	return out

## Styles the v3 run HUD (docs/mockups/v3/README.md): a right-aligned score and
## nothing else on the right; the crew tag is built separately. The score keeps
## the arcade-sticker treatment — thick ink outline plus a hard ink shadow.
func _style_hud() -> void:
	_bold_font = load(BOLD_FONT_PATH) as Font
	score_label.anchor_left = 1.0
	score_label.anchor_right = 1.0
	score_label.anchor_top = 0.0
	score_label.anchor_bottom = 0.0
	score_label.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	score_label.grow_vertical = Control.GROW_DIRECTION_END
	score_label.offset_left = -HUD_SCORE_RIGHT
	score_label.offset_right = -HUD_SCORE_RIGHT
	score_label.offset_top = HUD_SCORE_TOP
	score_label.offset_bottom = HUD_SCORE_TOP
	score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	score_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	if _bold_font != null:
		score_label.add_theme_font_override("font", _bold_font)
		score_label.offset_bottom = HUD_SCORE_TOP + _bold_font.get_height(HUD_SCORE_SIZE)
	score_label.add_theme_font_size_override("font_size", HUD_SCORE_SIZE)
	score_label.add_theme_color_override("font_color", CREAM)
	score_label.add_theme_color_override("font_outline_color", INK)
	score_label.add_theme_constant_override("outline_size", 13)
	score_label.add_theme_color_override("font_shadow_color", INK)
	score_label.add_theme_constant_override("shadow_offset_x", 0)
	score_label.add_theme_constant_override("shadow_offset_y", 9)
	score_label.add_theme_constant_override("shadow_outline_size", 12)

## The v3 crew tag: [crew avatar] FOR {CREW} · m:ss in one pill, top-left
## (docs/mockups/v3/run.html). The survival time moved into this pill; the old
## rank snapshot is gone.
func _build_crew_tag() -> void:
	_tag_panel = PanelContainer.new()
	_tag_panel.name = "CrewTag"
	_tag_panel.position = Vector2(HUD_TAG_LEFT, HUD_TAG_TOP)
	_tag_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := _panel_style(CARD, 6, 999, 6)
	style.content_margin_left = HUD_TAG_PAD_LEFT
	style.content_margin_right = HUD_TAG_PAD_RIGHT
	style.content_margin_top = HUD_TAG_PAD_Y
	style.content_margin_bottom = HUD_TAG_PAD_Y
	_tag_panel.add_theme_stylebox_override("panel", style)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", int(HUD_TAG_GAP))
	_tag_panel.add_child(row)
	var avatar := PanelContainer.new()
	avatar.custom_minimum_size = Vector2(HUD_TAG_AVATAR, HUD_TAG_AVATAR)
	avatar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var avatar_style := StyleBoxFlat.new()
	avatar_style.bg_color = CARD_INNER
	avatar_style.set_corner_radius_all(999)
	avatar_style.set_border_width_all(int(HUD_TAG_AVATAR_RING))
	avatar_style.border_color = YOURS
	avatar.add_theme_stylebox_override("panel", avatar_style)
	row.add_child(avatar)
	_tag_avatar = TextureRect.new()
	_tag_avatar.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_tag_avatar.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_tag_avatar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	avatar.add_child(_tag_avatar)
	_tag_name_label = _hud_label("", HUD_TAG_FONT, CREAM)
	_tag_name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(_tag_name_label)
	row.add_child(_hud_label("·", HUD_TAG_FONT, Color(CREAM.r, CREAM.g, CREAM.b, 0.5)))
	_tag_time_label = _hud_label("0:00", HUD_TAG_FONT, Color(CREAM.r, CREAM.g, CREAM.b, 0.9))
	_tag_time_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(_tag_time_label)
	ui_layer.add_child(_tag_panel)

func _update_crew_tag() -> void:
	if _tag_panel == null:
		return
	if target_community == null:
		_tag_panel.visible = false
		return
	_tag_panel.visible = true
	_tag_name_label.text = "FOR %s" % target_community.display_name.to_upper()
	if _tag_avatar != null:
		_tag_avatar.texture = target_community.mascot.idle_texture \
			if target_community.mascot != null else null

## mm:ss survival time inside the crew tag; repaints only when the second flips.
func _update_time_label() -> void:
	if _tag_time_label == null:
		return
	var seconds := int(state.elapsed)
	if seconds == _time_shown:
		return
	_time_shown = seconds
	_tag_time_label.text = "%d:%02d" % [seconds / 60, seconds % 60]

## Shared builder for the small HUD labels so every one gets the bold font and
## the same input-transparent behavior.
func _hud_label(text: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _bold_font != null:
		label.add_theme_font_override("font", _bold_font)
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	return label

# ---------------------------------------------------------------------------
# v3 HUD: crew-goal popup, NEW BEST ribbon, DEV entry (docs/mockups/v3)
# ---------------------------------------------------------------------------

## The crew-goal popup: a sticker under the crew tag with a pointer aimed at the
## avatar, "Crew goal" + gold percent, and a dark track with a green→gold fill.
## Pops in, holds ~2.5 s, fades out; only visible in the opening seconds of a run.
func _build_goal_popup() -> void:
	_goal_popup = Control.new()
	_goal_popup.name = "CrewGoal"
	_goal_popup.position = Vector2(
		HUD_TAG_LEFT,
		HUD_TAG_TOP + _tag_panel.get_combined_minimum_size().y + HUD_GOAL_GAP
	)
	_goal_popup.size = Vector2(HUD_GOAL_WIDTH, HUD_GOAL_HEIGHT)
	_goal_popup.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var pointer := Polygon2D.new()
	pointer.polygon = PackedVector2Array([
		Vector2(HUD_GOAL_POINTER_X - 13.0, 10.0),
		Vector2(HUD_GOAL_POINTER_X + 13.0, 10.0),
		Vector2(HUD_GOAL_POINTER_X, -14.0),
	])
	pointer.color = INK
	_goal_popup.add_child(pointer)

	var sticker := PanelContainer.new()
	sticker.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	sticker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := _panel_style(CARD, 6, 26, 6)
	style.content_margin_left = 20.0
	style.content_margin_right = 20.0
	style.content_margin_top = 16.0
	style.content_margin_bottom = 16.0
	sticker.add_theme_stylebox_override("panel", style)
	_goal_popup.add_child(sticker)

	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 8)
	sticker.add_child(column)

	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(row)
	var title := _hud_label("Crew goal", 18, Color(CREAM.r, CREAM.g, CREAM.b, 0.8))
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(title)
	var spacer := Control.new()
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	_goal_percent_label = _hud_label("0%", 20, GOLD)
	_goal_percent_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_goal_percent_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(_goal_percent_label)

	var track := PanelContainer.new()
	track.custom_minimum_size = Vector2(HUD_GOAL_BAR_WIDTH, HUD_GOAL_BAR_HEIGHT)
	track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var track_style := StyleBoxFlat.new()
	track_style.bg_color = INK
	track_style.set_corner_radius_all(999)
	track.add_theme_stylebox_override("panel", track_style)
	column.add_child(track)
	_goal_fill = TextureProgressBar.new()
	_goal_fill.name = "GoalFill"
	_goal_fill.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_goal_fill.fill_mode = TextureProgressBar.FILL_LEFT_TO_RIGHT
	_goal_fill.max_value = 1.0
	_goal_fill.step = 0.001
	_goal_fill.texture_progress = _goal_bar_texture(
		int(HUD_GOAL_BAR_WIDTH), int(HUD_GOAL_BAR_HEIGHT), 0.0)
	_goal_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	track.add_child(_goal_fill)

	_goal_popup.visible = false
	ui_layer.add_child(_goal_popup)

## Green→gold fill texture with rounded caps. The ramp is normalized to the
## filled width (like the mockup's fill div), so the leading edge is GOLD at any
## progress; TextureProgressBar clips it left-to-right as the value grows.
func _goal_bar_texture(width: int, height: int, progress: float) -> ImageTexture:
	var image := Image.create(width, height, false, Image.FORMAT_RGBA8)
	var radius := float(height) * 0.5
	var ramp := maxf(1.0, progress * float(width - 1))
	for y in range(height):
		for x in range(width):
			if not _inside_rounded_rect(
				Vector2(float(x) + 0.5, float(y) + 0.5), Vector2(width, height), radius
			):
				continue
			image.set_pixel(x, y, YOURS.lerp(GOLD, clampf(float(x) / ramp, 0.0, 1.0)))
	return ImageTexture.create_from_image(image)

## Rounded-rect hit test for the generated bar texture (SDF ≤ 0 is inside).
func _inside_rounded_rect(point: Vector2, box: Vector2, radius: float) -> bool:
	var half := box * 0.5
	var d := Vector2(
		absf(point.x - half.x) - (half.x - radius),
		absf(point.y - half.y) - (half.y - radius)
	)
	var outside := Vector2(maxf(d.x, 0.0), maxf(d.y, 0.0))
	return outside.length() + minf(maxf(d.x, d.y), 0.0) - radius <= 0.0

## Pops the goal popup in (0.9→1 + fade), holds, then fades out. A new run
## restarts the timer; the old tween is killed so the states never mix.
func _show_goal_popup() -> void:
	if _goal_popup == null:
		return
	_update_goal_popup()
	if _goal_tween != null and _goal_tween.is_valid():
		_goal_tween.kill()
	_goal_popup.visible = true
	_goal_popup.pivot_offset = Vector2(HUD_GOAL_POINTER_X, 0.0)
	_goal_popup.modulate.a = 0.0
	_goal_popup.scale = Vector2(0.9, 0.9)
	_goal_tween = create_tween()
	_goal_tween.set_parallel(true)
	_goal_tween.tween_property(_goal_popup, "modulate:a", 1.0, 0.2)
	_goal_tween.tween_property(_goal_popup, "scale", Vector2.ONE, 0.2) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_goal_tween.chain().tween_interval(HUD_GOAL_HOLD)
	_goal_tween.chain().tween_property(_goal_popup, "modulate:a", 0.0, HUD_GOAL_FADE)
	_goal_tween.chain().tween_callback(_hide_goal_popup)

func _hide_goal_popup() -> void:
	if _goal_popup != null and is_instance_valid(_goal_popup):
		_goal_popup.visible = false

func _update_goal_popup() -> void:
	if _goal_popup == null:
		return
	var progress := _tier_progress(_week_total, _weekly_tiers())
	_goal_fill.texture_progress = _goal_bar_texture(
		int(HUD_GOAL_BAR_WIDTH), int(HUD_GOAL_BAR_HEIGHT), progress)
	_goal_fill.value = progress
	_goal_percent_label.text = "%d%%" % int(round(progress * 100.0))

## Tilted GOLD "NEW BEST" ribbon under the score (docs/mockups/v3/run_best.html).
func _build_best_ribbon() -> void:
	_best_ribbon = PanelContainer.new()
	_best_ribbon.name = "NewBest"
	_best_ribbon.anchor_left = 1.0
	_best_ribbon.anchor_right = 1.0
	_best_ribbon.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_best_ribbon.offset_left = -HUD_BEST_RIGHT
	_best_ribbon.offset_right = -HUD_BEST_RIGHT
	_best_ribbon.offset_top = HUD_BEST_TOP
	_best_ribbon.offset_bottom = HUD_BEST_TOP
	_best_ribbon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_best_ribbon.visible = false
	var style := _panel_style(GOLD, 6, 15, 6)
	# Content margins include the ink border, so the panel owns its full height.
	style.content_margin_left = 21.0
	style.content_margin_right = 21.0
	style.content_margin_top = 6.0
	style.content_margin_bottom = 12.0
	_best_ribbon.add_theme_stylebox_override("panel", style)
	var label := _hud_label("NEW BEST", 20, INK)
	label.add_theme_constant_override("letter_spacing", 2)
	_best_ribbon.add_child(label)
	_best_ribbon.rotation = deg_to_rad(-3.0)
	ui_layer.add_child(_best_ribbon)

## Turns the score GOLD and reveals the ribbon the first time the live score
## passes the persisted best. Fires once per run.
func _update_new_best() -> void:
	if _new_best or _save == null or state.score <= _best_at_start:
		return
	_new_best = true
	score_label.add_theme_color_override("font_color", GOLD)
	_show_best_ribbon()

func _score_base_color() -> Color:
	return GOLD if _new_best else CREAM

func _show_best_ribbon() -> void:
	if _best_ribbon == null:
		return
	_best_ribbon.visible = true
	_layout_right_column()
	_best_ribbon.pivot_offset = _best_ribbon.get_combined_minimum_size() * 0.5
	_best_ribbon.scale = Vector2(0.7, 0.7)
	_best_ribbon.modulate.a = 0.0
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(_best_ribbon, "modulate:a", 1.0, 0.14)
	tween.tween_property(_best_ribbon, "scale", Vector2.ONE, 0.2) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _reset_best_ribbon() -> void:
	_new_best = false
	if _best_ribbon != null:
		_best_ribbon.visible = false
		_best_ribbon.scale = Vector2.ONE
		_best_ribbon.modulate.a = 1.0
	if _coin_chip != null:
		_coin_chip.visible = false
		_coin_chip.scale = Vector2.ONE
		_coin_label.text = "0"
	_layout_right_column()

## Coin chip: [coin] N, a sticker pill under the score. Hidden until the first
## coin of the run so the opening HUD stays the approved v3 layout.
func _build_coin_chip() -> void:
	_coin_chip = PanelContainer.new()
	_coin_chip.name = "CoinChip"
	_coin_chip.anchor_left = 1.0
	_coin_chip.anchor_right = 1.0
	_coin_chip.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_coin_chip.offset_left = -HUD_BEST_RIGHT
	_coin_chip.offset_right = -HUD_BEST_RIGHT
	_coin_chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_coin_chip.visible = false
	var style := _panel_style(CARD, 6, 999, 6)
	style.content_margin_left = 10.0
	style.content_margin_right = 20.0
	style.content_margin_top = 6.0
	style.content_margin_bottom = 12.0
	_coin_chip.add_theme_stylebox_override("panel", style)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_coin_chip.add_child(row)
	var icon := Control.new()
	icon.custom_minimum_size = Vector2(HUD_COIN_ICON, HUD_COIN_ICON)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.draw.connect(func() -> void:
		var r := HUD_COIN_ICON * 0.5
		var c := Vector2(r, r)
		icon.draw_circle(c, r, INK)
		icon.draw_circle(c, r - 3.0, GOLD)
		icon.draw_arc(c, r * 0.6, -0.42 * PI, 0.42 * PI, 14, Color("ffe98a"), 2.4, true))
	row.add_child(icon)
	_coin_label = _hud_label("0", HUD_COIN_SIZE, CREAM)
	_coin_label.add_theme_color_override("font_outline_color", INK)
	_coin_label.add_theme_constant_override("outline_size", 8)
	row.add_child(_coin_label)
	ui_layer.add_child(_coin_chip)
	_layout_right_column()

## Stacks the right-hand column under the score: coin chip, then NEW BEST.
func _layout_right_column() -> void:
	var y := HUD_BEST_TOP + _safe_top
	if _coin_chip != null and _coin_chip.visible:
		_coin_chip.offset_top = y
		_coin_chip.offset_bottom = y
		y += _coin_chip.get_combined_minimum_size().y + HUD_COLUMN_GAP
	if _best_ribbon != null:
		_best_ribbon.offset_top = y
		_best_ribbon.offset_bottom = y

## Shows the run's coin count with a small pop on each pickup.
func _update_coin_chip() -> void:
	if _coin_chip == null:
		return
	_coin_label.text = str(state.coins)
	if not _coin_chip.visible:
		_coin_chip.visible = true
		_layout_right_column()
	_coin_chip.pivot_offset = _coin_chip.size * Vector2(1.0, 0.5)
	if _reduced_motion():
		return
	var pop := create_tween()
	pop.tween_property(_coin_chip, "scale", Vector2(1.14, 1.14), 0.07)
	pop.tween_property(_coin_chip, "scale", Vector2.ONE, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

## DEV-only entry to the tuning panel, bottom-right so it never covers the v3
## HUD. Absent from player builds (`nocaps_dev` feature).
func _build_dev_button() -> void:
	if not OS.has_feature("nocaps_dev"):
		return
	_dev_button = Button.new()
	_dev_button.name = "DevButton"
	_dev_button.text = "DEV"
	_dev_button.anchor_left = 1.0
	_dev_button.anchor_right = 1.0
	_dev_button.anchor_top = 1.0
	_dev_button.anchor_bottom = 1.0
	_dev_button.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_dev_button.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_dev_button.offset_left = -122.0
	_dev_button.offset_right = -30.0
	_dev_button.offset_top = -118.0
	_dev_button.offset_bottom = -30.0
	_dev_button.add_theme_stylebox_override("normal", _button_style(CARD, false))
	_dev_button.add_theme_stylebox_override("hover", _button_style(CARD.lightened(0.06), false))
	_dev_button.add_theme_stylebox_override("pressed", _button_style(CARD.darkened(0.06), true))
	_dev_button.add_theme_stylebox_override("focus", _button_style(CARD, false))
	if _bold_font != null:
		_dev_button.add_theme_font_override("font", _bold_font)
	_dev_button.add_theme_font_size_override("font_size", 26)
	_dev_button.add_theme_color_override("font_color", CREAM)
	_dev_button.add_theme_color_override("font_hover_color", CREAM)
	_dev_button.add_theme_color_override("font_pressed_color", CREAM)
	_dev_button.pressed.connect(_open_dev)
	ui_layer.add_child(_dev_button)

## Feeds the current run state to the moments layer. Called sparsely (run start)
## so the race ring buffer stays clean.
func _observe_moments() -> void:
	if _save == null:
		return
	Moments.observe_run(_save, {
		"community_id": _community_id(),
		"community_name": _community_name(),
		"score": state.score,
		"contribution": state.score,
	}, Standings.race_state())

## Snapshots the crew's weekly total, refreshes the goal popup, and starts its
## opening animation. Called at run start.
func _update_crew_goal() -> void:
	_week_total = _weekly_team_total()
	_update_goal_popup()
	_show_goal_popup()
	_observe_moments()

func _weekly_team_total() -> int:
	if target_community == null:
		return 0
	for row in Standings.communities_week(_save):
		if row["id"] == target_community.id:
			return int(row["score"])
	if _save != null:
		return _save.week_total(target_community.id)
	return 0

## Authored weekly tiers, or the TESTING fallback when the community has none.
func _weekly_tiers() -> Array:
	var tiers: Array = []
	if target_community != null:
		for tier in target_community.weekly_tiers:
			tiers.append(int(tier))
	if tiers.is_empty():
		tiers = TESTING_WEEKLY_TIERS.duplicate()
	tiers.sort()
	return tiers

## Progress (0–1) from the previous tier toward the next one; 1.0 past the last.
func _tier_progress(total: int, tiers: Array) -> float:
	if tiers.is_empty():
		return 0.0
	var previous := 0
	for tier in tiers:
		var value := int(tier)
		if total < value:
			if value <= previous:
				return 0.0
			return clampf(float(total - previous) / float(value - previous), 0.0, 1.0)
		previous = value
	return 1.0

func _community_id() -> String:
	return String(target_community.id) if target_community != null else ""

func _community_name() -> String:
	return target_community.display_name if target_community != null else ""

func setup(_payload: Dictionary) -> void:
	pass

func restart() -> void:
	state.reset()
	_failed = false
	_bump_cooldown = 0.0
	_flapped = false
	_paused = false
	_perfects = 0
	_max_combo = 0
	_tag_hinted_targets = 0
	pause_overlay.visible = false
	tap_prompt.visible = true
	_warned = false
	cause_label.visible = false
	cause_label.scale = Vector2.ONE
	cause_label.modulate.a = 1.0
	flash_rect.color = Color(1, 1, 1, 0)
	_flash_amount = 0.0
	shake_root.position = Vector2.ZERO
	_shake_time_left = 0.0
	effects.clear()
	effects.set_reduced_motion(_reduced_motion())
	_best_at_start = _save.best_score if _save != null else 0
	_reset_best_ribbon()
	score_label.add_theme_color_override("font_color", CREAM)
	cap.revive()
	cap.position = Vector2(tuning.cap_x, tuning.start_y)
	cap.velocity_y = -tuning.flap_impulse * 1.06
	cap.set_world_width(_cap_world_width())
	_prev_cap_y = cap.position.y
	_spawn.reset(state, tuning.run_seed)
	coins.reset(tuning.run_seed)
	_apply_yours_tag_hint()
	_surprise_phase = Surprise.IDLE
	_surprise_timer = 0.0
	_surprise_dwell = 0.0
	_surprise_cooldown = 0.0
	_surprise_hazard = null
	_tutorial_begin()
	_update_crew_tag()
	_update_crew_goal()
	_update_hud()
	_time_shown = -1
	_update_time_label()
	set_process(true)

func _tutorial_begin() -> void:
	_tutorial_timer = 0.0
	# The world waits for the player's first tap on every run; the first run then
	# adds the "land only on your mascot" hint after that tap.
	_waiting_for_tap = true
	_tutorial_stage = 0 if (_save != null and _save.tutorial_seen) else 1
	tap_prompt.text = "TAP TO FLY"
	tap_prompt.visible = true

func _finish_tutorial() -> void:
	if _tutorial_stage == 0:
		return
	_tutorial_stage = 0
	tap_prompt.visible = false
	if _save != null and not _save.tutorial_seen:
		_save.tutorial_seen = true
		_save.save_data()

func _apply_community() -> void:
	var roster := CommunityRepository.load_roster()
	var selected := &""
	if _save != null:
		selected = _save.selected_community_id
	target_community = CommunityRepository.resolve_selected(roster, selected)
	var rivals := CommunityRepository.rivals_for(roster, target_community)
	_spawn.set_communities(target_community, rivals)
	var cap_definition := CommunityRepository.resolve_cap(target_community)
	cap.set_cap(cap_definition)
	cap.set_world_width(_cap_world_width())
	background.apply(CommunityRepository.resolve_background(target_community), _ground_y)
	_update_crew_tag()

## The in-flight cap matches the target community's seated cap width, so `cap_scale`
## on the mascot is the single cap-size knob.
func _cap_world_width() -> float:
	var fallback := tuning.mascot_world_size * FALLBACK_CAP_WIDTH_RATIO
	if target_community == null or target_community.mascot == null:
		return fallback
	var seated := MascotFit.seated_cap_width(target_community.mascot, tuning.mascot_world_size)
	return seated if seated > 0.0 else fallback

## Gives the YOURS onboarding tag to the first `YOURS_TAG_HINT_COUNT` own-crew
## mascots of the run, then silences it on every later one. Rivals are never
## eligible. Safe to call repeatedly: each mascot is considered once.
func _apply_yours_tag_hint() -> void:
	for mascot in _spawn.mascots:
		if not is_instance_valid(mascot) or mascot.has_meta("nocaps_yours_hint"):
			continue
		mascot.set_meta("nocaps_yours_hint", true)
		if not mascot.is_target:
			continue
		_tag_hinted_targets += 1
		if _tag_hinted_targets > YOURS_TAG_HINT_COUNT:
			mascot.show_yours_tag = false

func _process(delta: float) -> void:
	_update_flash(delta)
	_update_shake(delta)
	_update_time_label()
	if _failed:
		_update_death(delta)
		return

	if _waiting_for_tap:
		return

	state.elapsed += delta
	_bump_cooldown = maxf(0.0, _bump_cooldown - delta)
	_update_tutorial(delta)
	var scroll_speed := Difficulty.scroll_speed(tuning, state)
	var step := scroll_speed * delta
	state.distance += step
	_prev_cap_y = cap.position.y
	cap.integrate(delta, tuning.gravity)
	cap.position.y = maxf(cap.position.y, tuning.cap_radius)
	_spawn.scroll(step)
	coins.scroll(step)
	_spawn.update(delta, step, state)
	coins.update(delta, _spawn)
	_apply_yours_tag_hint()
	background.scroll(step)
	_update_ceilings()
	_update_surprise(delta)
	_resolve_landings()
	_check_skips()
	_collect_coins()
	_resolve_hazards()
	if _failed:
		return
	_check_near_miss(scroll_speed)
	_check_ground()
	_warn_traps()

func _update_tutorial(delta: float) -> void:
	if _tutorial_stage != 2:
		return
	_tutorial_timer -= delta
	if _tutorial_timer <= 0.0:
		# Expiring counts as seen too, or the tutorial would replay every run.
		_finish_tutorial()

func _unhandled_input(event: InputEvent) -> void:
	if _failed or _paused:
		return
	var flap := false
	if event is InputEventScreenTouch and event.pressed:
		flap = true
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT and not OS.has_feature("mobile"):
		flap = true
	elif event is InputEventKey and event.pressed and not event.echo and event.keycode in [KEY_SPACE, KEY_UP, KEY_W]:
		flap = true
	if flap:
		_do_flap()

func _do_flap() -> void:
	if not _flapped:
		_flapped = true
	if _waiting_for_tap:
		_waiting_for_tap = false
		if _tutorial_stage == 1:
			_tutorial_stage = 2
			_tutorial_timer = 3.5
			tap_prompt.text = "LAND ONLY ON YOUR MASCOT"
			tap_prompt.visible = true
		else:
			tap_prompt.visible = false
	cap.flap(tuning.flap_impulse)
	SoundService.play_flap(Difficulty.scroll_speed(tuning, state) / tuning.base_scroll_speed - 1.0)
	effects.burst(cap.position + Vector2(-28.0, 16.0), 5, [Color.WHITE, Color("ffd60a")], 130.0, 3.0)

func _pause() -> void:
	if _failed or _paused:
		return
	_paused = true
	_update_mute_text()
	pause_overlay.visible = true
	set_process(false)

func _resume() -> void:
	if not _paused:
		return
	_paused = false
	pause_overlay.visible = false
	set_process(true)

## DEV builds: the top-right button pauses and opens the tuning panel instead of
## the pause overlay. Non-dev builds hide the button; back/focus loss still pause.
func _open_dev() -> void:
	if _paused:
		return
	_paused = true
	set_process(false)
	var panel := get_node_or_null("DevPanel")
	if panel != null and panel.has_method("open"):
		panel.call("open")

## Called by the DEV panel's RESUME button.
func resume_from_dev() -> void:
	var panel := get_node_or_null("DevPanel")
	if panel != null and panel.has_method("close"):
		panel.call("close")
	_paused = false
	pause_overlay.visible = false
	set_process(true)

func _toggle_mute() -> void:
	var enabled := not SoundService.is_sound_enabled
	SoundService.is_sound_enabled = enabled
	if _save != null:
		_save.muted = not enabled
		_save.save_data()
	_update_mute_text()

func _update_mute_text() -> void:
	mute_button.text = "SOUND: %s" % ("ON" if SoundService.is_sound_enabled else "OFF")

func _go_home() -> void:
	Engine.time_scale = 1.0
	navigate.emit(&"home", {})

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		if _paused:
			_resume()
		else:
			_pause()
	elif what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		if not _failed and not _paused:
			_pause()

func _resolve_landings() -> void:
	for mascot in _spawn.mascots:
		if not is_instance_valid(mascot):
			continue
		var outcome := Landing.resolve(cap.position, _prev_cap_y, cap.velocity_y, cap.cap_radius, mascot)
		match outcome:
			Landing.Outcome.SCORE:
				_land(mascot)
			Landing.Outcome.BUMP:
				if _bump_cooldown <= 0.0:
					_bump()
			Landing.Outcome.FAIL:
				_fail(Death.WRONG)
				return

## Fairness nudge: passing a mascot of the crew the player is currently
## representing without landing costs one point (floor zero). Never applied in
## the opening grace window, and other crews' mascots are never penalized.
func _check_skips() -> void:
	if not tuning.skip_penalty_enabled or state.elapsed < tuning.skip_penalty_grace:
		return
	for mascot in _spawn.mascots:
		if not is_instance_valid(mascot) or not mascot.is_target or mascot.claimed:
			continue
		if mascot.has_meta("nocaps_skip_penalized"):
			continue
		if mascot.position.x >= cap.position.x - mascot.body_radius - cap.cap_radius:
			continue
		mascot.set_meta("nocaps_skip_penalized", true)
		state.register_skip()
		effects.popup(
			_popup_pos(Vector2(mascot.position.x, mascot.head_top_y())), "-1", CORAL, 30
		)
		_update_hud()

## Cap contact with a coin arc: sparkle + tick, and the currency banks into the
## run. Coins never touch score, combo, or crew contribution (docs/01_GDD.md §8).
func _collect_coins() -> void:
	var events := coins.collect_events(cap.position, cap.cap_radius)
	if events.is_empty():
		return
	state.coins += events.size() * tuning.coin_value
	_update_coin_chip()
	for event in events:
		var pos: Vector2 = event["pos"]
		effects.starburst(pos, GOLD, 8)
		# Pitch climbs through a pattern so a clean set sounds like a run-up.
		SoundService.play_coin(int(event["index"]))
		if bool(event["completed"]):
			effects.ring(pos)
			effects.starburst(pos, GOLD, 16)
			SoundService.play_coin_set()

func _land(mascot: MascotActor) -> void:
	if mascot.claimed:
		return
	var perfect := absf(cap.position.x - mascot.head_center_x()) \
		<= mascot.head_half_width() * tuning.perfect_head_ratio
	mascot.claim(perfect)
	_finish_tutorial()
	var base_points := Scoring.PERFECT_POINTS if perfect else Scoring.EDGE_POINTS
	state.register_landing(base_points)
	if perfect:
		_perfects += 1
	_max_combo = maxi(_max_combo, state.combo)
	var mult := state.mult
	var gained := base_points * mult
	cap.bounce(tuning.bounce_impulse)
	var head := Vector2(mascot.head_center_x(), mascot.head_top_y())
	var color := Scoring.color_for(mult)
	var milestone := state.combo in [5, 10, 20]
	# Exactly one text popup per event (owner rule 2026-10-01). A perfect landing
	# reads as a single "PERFECT +N" label; combo milestones show the in-world
	# sticker near the cap; every other landing keeps the crew label.
	if perfect:
		effects.popup(_popup_pos(head - Vector2(0.0, 64.0)), "PERFECT +%d" % gained, GOLD, 32)
	elif milestone:
		# The combo sticker rides up-left of the cap (docs/mockups/v3/run.html),
		# never over the mascot's YOURS tag.
		effects.sticker_popup(
			_popup_pos(cap.position + Vector2(-52.0, -96.0)), "×%d COMBO" % mult, 32, -0.14
		)
	else:
		# Up-right of the head so it reads above the mascot (docs/mockups/v3/run.html)
		# and never sits on its face or the YOURS tag.
		effects.popup(
			_popup_pos(head + Vector2(44.0, -72.0)),
			"+%d FOR %s" % [gained, _community_name().to_upper()],
			YOURS, 26, -0.1
		)
	effects.starburst(head, Color("ffe36e") if perfect else Color("dfe7f2"), 11 if perfect else 6)
	effects.burst(head, 11 + mult * 7, LAND_COLORS, 340.0 + mult * 50.0, 7.0)
	effects.ring(head)
	if perfect:
		effects.ring(head - Vector2(0.0, 6.0))
	if milestone:
		effects.streak_burst(head, color, mult)
		SoundService.play_streak(mult)
		_flash(color, 0.5)
		_shake(12.0 + float(mult) * 2.0)
	else:
		_flash(Color("ffe36e"), (0.36 if perfect else 0.26) + 0.06 * mult)
		_shake((7.0 if perfect else 4.5) + float(mult) * 2.0)
	_hit_stop(0.38 if perfect else 0.5, 0.06)
	Haptics.light(tuning.haptic_light_ms)
	SoundService.play_land_correct(state.combo)
	_fly_score(head, "+%d" % gained, color)
	score_label.add_theme_color_override("font_color", color)
	get_tree().create_timer(0.28).timeout.connect(
		func() -> void:
			if is_instance_valid(score_label):
				score_label.add_theme_color_override("font_color", _score_base_color())
	)
	_update_hud()

## A little score token that flies from the landing spot up into the score HUD.
## It lives in the UI layer, so the world landing spot is converted to screen.
func _fly_score(from: Vector2, text: String, color: Color) -> void:
	var label := Label.new()
	label.text = text
	label.z_index = 100
	if _bold_font != null:
		label.add_theme_font_override("font", _bold_font)
	label.add_theme_font_size_override("font_size", 34)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", INK)
	label.add_theme_constant_override("outline_size", 8)
	label.position = _world_to_screen(from) - Vector2(16.0, 34.0)
	ui_layer.add_child(label)
	var target := score_label.global_position + score_label.size * 0.5
	var tween := create_tween()
	tween.tween_property(label, "position", target, 0.24).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.parallel().tween_property(label, "scale", Vector2(0.55, 0.55), 0.24)
	tween.parallel().tween_property(label, "modulate:a", 0.0, 0.24)
	tween.tween_callback(label.queue_free)

func _bump() -> void:
	_bump_cooldown = 0.45
	var had_combo := state.combo > 1
	state.register_bump()
	cap.velocity_y = minf(cap.velocity_y, -330.0)
	effects.burst(cap.position + Vector2(-6.0, 16.0), 8, [Color.WHITE, Color("cdd7e8")], 150.0, 3.4)
	# One popup per event (owner rule 2026-10-01): carry the point and the lost
	# combo in a single label instead of two stacked ones.
	if had_combo:
		effects.popup(_popup_pos(cap.position + Vector2(24.0, -30.0)), "COMBO LOST +1", Color("9fb0c9"), 26)
		effects.combo_lost(cap.position)
		SoundService.play_combo_lost()
	else:
		effects.popup(_popup_pos(cap.position + Vector2(24.0, -30.0)), "+1", Color("d7ddea"))
	_shake(4.0)
	SoundService.play_bump()
	_update_hud()

## A grazing pass by a rival at speed earns a whoosh and a small puff — pure
## feedback, never a rule. Each rival whooshes at most once.
func _check_near_miss(speed: float) -> void:
	if speed < 520.0:
		return
	for mascot in _spawn.mascots:
		if not is_instance_valid(mascot) or mascot.is_target or mascot.passed_near:
			continue
		var dx := absf(mascot.position.x - cap.position.x)
		var dy := absf(mascot.position.y - cap.position.y)
		if dx < 46.0 and dy < mascot.body_radius + 44.0:
			mascot.passed_near = true
			SoundService.play_whoosh()
			effects.burst(Vector2(cap.position.x + 34.0, cap.position.y), 5, DUST_COLORS, 150.0, 2.6)

func _resolve_hazards() -> void:
	for hazard in _spawn.hazards:
		if not is_instance_valid(hazard):
			continue
		if _hazard_hits(hazard):
			_fail(Death.HAZARD, hazard)
			return

func _hazard_hits(hazard: Hazard) -> bool:
	match hazard.kind:
		Hazard.Kind.SPIKE, Hazard.Kind.SAW:
			return cap.position.distance_to(hazard.position) <= tuning.cap_radius + hazard.radius * 1.16
		Hazard.Kind.CLOUD:
			var cloud := Rect2(
				hazard.position - Vector2(hazard.size.x * 0.42, hazard.size.y * 0.40),
				Vector2(hazard.size.x * 0.84, hazard.size.y * 0.78)
			)
			return _aabb(_cap_box(), cloud)
		Hazard.Kind.CEIL:
			if hazard.ext < 0.4:
				return false
			var band := Rect2(
				Vector2(hazard.position.x - hazard.ceiling_width * 0.5, _view_top_y()),
				Vector2(hazard.ceiling_width, hazard.ceiling_height * hazard.ext)
			)
			return _aabb(_cap_box(), band)
	return false

func _cap_box() -> Rect2:
	var half := Vector2(tuning.cap_radius * 1.1, tuning.cap_radius * 0.75)
	return Rect2(cap.position - half, half * 2.0)

func _aabb(a: Rect2, b: Rect2) -> bool:
	return a.position.x < b.position.x + b.size.x and a.position.x + a.size.x > b.position.x \
		and a.position.y < b.position.y + b.size.y and a.position.y + a.size.y > b.position.y

func _check_ground() -> void:
	if cap.position.y + cap.cap_radius >= _ground_y:
		_fail(Death.GROUND)

func _update_ceilings() -> void:
	for hazard in _spawn.hazards:
		if not is_instance_valid(hazard) or hazard.kind != Hazard.Kind.CEIL:
			continue
		if hazard.scripted:
			continue
		var near := absf(hazard.position.x - cap.position.x) < hazard.ceiling_width * 0.5 + 150.0
		hazard.ext_target = clampf(1.0 - (cap.position.y - 64.0) / 165.0, 0.0, 1.0) if near else 0.0

## Surprise ceiling spike: when the cap hugs the top of the screen for long
## enough, a ceiling hazard telegraphs above it, slams down a short distance, and
## retracts. Reuses the existing ceiling drawing and collision; only the timing is
## new. Never runs during the opening guaranteed-target window or the hazard delay.
func _update_surprise(delta: float) -> void:
	_surprise_cooldown = maxf(0.0, _surprise_cooldown - delta)
	match _surprise_phase:
		Surprise.IDLE:
			if not _surprise_ready(Difficulty.scroll_speed(tuning, state)):
				_surprise_dwell = 0.0
				return
			if _cap_hugs_ceiling():
				_surprise_dwell += delta
				if _surprise_dwell >= tuning.surprise_ceiling_dwell:
					_surprise_dwell = 0.0
					_begin_surprise()
			else:
				_surprise_dwell = 0.0
		Surprise.TELEGRAPH:
			_surprise_timer -= delta
			if is_instance_valid(_surprise_hazard):
				_surprise_hazard.ext_target = 0.18
				_surprise_hazard.position.x = cap.position.x + sin(_surprise_timer * 46.0) * 5.0
			if _surprise_timer <= 0.0:
				_surprise_phase = Surprise.SLAM
				_surprise_timer = 0.3
				if is_instance_valid(_surprise_hazard):
					_surprise_hazard.ext_target = 1.0
					_surprise_hazard.position.x = cap.position.x
				_flash(INK, 0.28)
				_shake(6.0)
		Surprise.SLAM:
			_surprise_timer -= delta
			_pin_surprise()
			if _surprise_timer <= 0.0:
				_surprise_phase = Surprise.RETRACT
				_surprise_timer = 0.45
				if is_instance_valid(_surprise_hazard):
					_surprise_hazard.ext_target = 0.0
		Surprise.RETRACT:
			_surprise_timer -= delta
			_pin_surprise()
			if _surprise_timer <= 0.0:
				_end_surprise()

func _surprise_ready(speed: float) -> bool:
	return dev_surprise_enabled \
		and _spawn.hazards_enabled \
		and not _spawn.opening_pending() \
		and state.elapsed >= tuning.hazard_start_delay \
		and _surprise_cooldown <= 0.0 \
		and _surprise_zone_clear(speed)

## The surprise slam is pinned above the cap, so it must not trigger while the cap
## is inside a landing spot's safe zone: the base clearance around any mascot
## (directly above/below a landing spot) or the safe window just after one.
func _surprise_zone_clear(speed: float) -> bool:
	var safe := _spawn.safe_after_px(speed)
	for mascot in _spawn.mascots:
		if not is_instance_valid(mascot):
			continue
		var dx := cap.position.x - mascot.position.x
		if absf(dx) < tuning.hazard_clear_from_mascots + mascot.body_radius:
			return false
		if dx >= 0.0 and dx < safe:
			return false
	return true

func _cap_hugs_ceiling() -> bool:
	return cap.position.y <= _screen_to_world_y(get_viewport_rect().size.y * tuning.surprise_ceiling_zone)

func _begin_surprise() -> void:
	var hazard := Hazard.new()
	hazard.scripted = true
	hazard.configure_ceiling(96.0, 48.0)
	hazard.position = Vector2(cap.position.x, _view_top_y())
	hazard.name = "SurpriseCeiling"
	hazards_root.add_child(hazard)
	_spawn.hazards.append(hazard)
	_surprise_hazard = hazard
	_surprise_phase = Surprise.TELEGRAPH
	_surprise_timer = tuning.surprise_ceiling_telegraph
	_flash(GOLD, 0.22)
	SoundService.play_warn()

func _pin_surprise() -> void:
	if is_instance_valid(_surprise_hazard):
		_surprise_hazard.position.x = cap.position.x

func _end_surprise() -> void:
	if is_instance_valid(_surprise_hazard):
		_spawn.hazards.erase(_surprise_hazard)
		_surprise_hazard.queue_free()
	_surprise_hazard = null
	_surprise_phase = Surprise.IDLE
	_surprise_cooldown = tuning.surprise_ceiling_cooldown

## Sound-only hazard warning: the v3 HUD has no toast row, so the cue is audio.
func _warn_traps() -> void:
	if not _warned and state.elapsed >= tuning.hazard_start_delay and not _spawn.opening_pending():
		_warned = true
		SoundService.play_warn()

func _fail(cause: int, hazard: Hazard = null) -> void:
	if _failed or dev_invincible:
		return
	_failed = true
	if _goal_tween != null and _goal_tween.is_valid():
		_goal_tween.kill()
	_hide_goal_popup()
	_hit_stop(0.3, 0.12)
	var word := "GAME OVER"
	match cause:
		Death.GROUND:
			word = "FELL"
			SoundService.play_thud()
			_shake(14.0)
			_flash(Color("ffd60a"), 0.5)
			effects.burst(Vector2(cap.position.x, _ground_y - 6.0), 24, DUST_COLORS, 260.0, 5.0)
		Death.HAZARD:
			word = _hazard_word(hazard)
			SoundService.play_hazard_hit(_hazard_sound(hazard))
			_shake(20.0)
			_flash(Color("dfe7f2"), 0.5)
			_hazard_death_effects(hazard)
			effects.popup(_popup_pos(cap.position + Vector2(40.0, 34.0)), word, Color("dfe7f2"))
		Death.WRONG:
			word = "WRONG MASCOT!"
			SoundService.play_death()
			_shake(18.0)
			_flash(Color("ff3b30"), 0.55)
			effects.burst(cap.position + Vector2(0.0, 10.0), 24, WRONG_COLORS, 280.0, 5.0)
			effects.popup(_popup_pos(cap.position + Vector2(40.0, -46.0)), word, Color("ff6b60"))
	state.fail(word)
	cap.begin_death()
	cap.velocity_y = -250.0
	cause_label.text = word
	cause_label.visible = true
	cause_label.pivot_offset = cause_label.size * 0.5
	cause_label.scale = Vector2(0.72, 0.72)
	cause_label.modulate.a = 0.0
	var cause_tween := create_tween()
	cause_tween.set_parallel(true)
	cause_tween.tween_property(cause_label, "scale", Vector2.ONE, 0.22) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	cause_tween.tween_property(cause_label, "modulate:a", 1.0, 0.12)
	Haptics.heavy(tuning.haptic_heavy_ms)
	_pending_payload = _build_result_payload(word)
	get_tree().create_timer(maxf(tuning.fail_delay, 0.0)).timeout.connect(_finish_run)

func _hazard_death_effects(hazard: Hazard) -> void:
	if hazard == null:
		effects.burst(cap.position, 22, DEBRIS_COLORS, 300.0, 5.0)
		return
	match hazard.kind:
		Hazard.Kind.SPIKE:
			effects.burst(cap.position, 26, DEBRIS_COLORS, 300.0, 5.0)
		Hazard.Kind.SAW:
			effects.starburst(cap.position, Color("ffd60a"), 18)
			effects.burst(cap.position, 20, [Color("ffd60a"), Color("ff9d2e"), Color("ffffff")], 340.0, 3.2)
		Hazard.Kind.CLOUD:
			effects.burst(cap.position, 18, [Color("dfe7f2"), Color("8b9ab6")], 240.0, 5.0)
			effects.arc(Vector2(cap.position.x, cap.position.y - 150.0))
			effects.arc(Vector2(cap.position.x - 60.0, cap.position.y - 170.0))
		Hazard.Kind.CEIL:
			effects.burst(cap.position, 24, DEBRIS_COLORS, 320.0, 4.0)

func _update_death(delta: float) -> void:
	cap.velocity_y = minf(cap.velocity_y + tuning.gravity * 1.15 * delta, cap.max_fall_speed * 1.15)
	cap.position.y += cap.velocity_y * delta
	cap.spin(delta, 7.0)
	cap.position.x += (-20.0 if cap.velocity_y < 0.0 else -52.0) * delta
	if cap.position.y + cap.cap_radius >= _ground_y:
		cap.position.y = _ground_y - cap.cap_radius
		cap.velocity_y *= -0.34
		if absf(cap.velocity_y) < 70.0:
			cap.velocity_y = 0.0

func _finish_run() -> void:
	Engine.time_scale = 1.0
	if not is_inside_tree():
		return
	if bool(_pending_payload.get("new_best", false)):
		SoundService.play_best()
	navigate.emit(&"result", _pending_payload)

func _build_result_payload(reason: String) -> Dictionary:
	var community_id := target_community.id if target_community != null else &""
	var community_name := target_community.display_name if target_community != null else ""
	var payload := {
		"score": state.score,
		"landings": state.landings,
		"perfects": _perfects,
		"max_combo": _max_combo,
		"coins": state.coins,
		"survival_seconds": state.elapsed,
		"best": state.score,
		"new_best": false,
		"reason": reason,
		"community_id": community_id,
		"community_name": community_name,
		"contribution": state.score,
		"streak": 0,
		"streak_multiplier": 1.0,
		"week_total": state.score,
		"tier_crossed": false,
		"tier_after": 0,
		"submission_state": "local_only",
		"pending_submissions": 0,
	}
	if _save == null:
		return payload
	var new_best := state.score > _save.best_score
	var tiers := PackedInt32Array()
	if target_community != null:
		tiers = target_community.weekly_tiers
	var breakdown := _save.record_run(community_id, tiers, state.score, state.landings, state.elapsed)
	for key in breakdown:
		payload[key] = breakdown[key]
	payload["best"] = _save.best_score
	payload["new_best"] = new_best
	payload["coins_total"] = _save.record_coins(state.coins)
	var record := RunSubmission.build_record(
		_save.ensure_player_id(),
		community_id,
		state.score,
		state.landings,
		int(payload.get("contribution", state.score)),
		state.elapsed,
		int(payload.get("streak", 0))
	)
	RunSubmission.enqueue(_save, record)
	payload["run_id"] = String(record.get("run_id", ""))
	payload["submission_state"] = "queued"
	payload["pending_submissions"] = _save.pending_submissions.size()
	if _backend != null and _backend.is_available():
		RunSubmission.flush_async(_save, _backend)
	return payload

func _hazard_word(hazard: Hazard) -> String:
	if hazard == null:
		return "HAZARD"
	match hazard.kind:
		Hazard.Kind.SPIKE:
			return "SPIKED!"
		Hazard.Kind.SAW:
			return "SHREDDED!"
		Hazard.Kind.CLOUD:
			return "ZAPPED!"
		Hazard.Kind.CEIL:
			return "SPIKES!"
	return "HAZARD"

func _hazard_sound(hazard: Hazard) -> String:
	if hazard == null:
		return "spike"
	match hazard.kind:
		Hazard.Kind.SPIKE:
			return "spike"
		Hazard.Kind.SAW:
			return "saw"
		Hazard.Kind.CLOUD:
			return "cloud"
		Hazard.Kind.CEIL:
			return "ceil"
	return "spike"

func _update_hud() -> void:
	score_label.text = "%d" % state.score
	score_label.pivot_offset = score_label.size * 0.5
	score_label.scale = Vector2(1.2, 1.2)
	var tween := create_tween()
	tween.tween_property(score_label, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_update_new_best()
	var aura_strength := 0.0 if state.mult <= 1 else 0.3 + 0.22 * float(state.mult - 1)
	cap.set_aura(Scoring.color_for(state.mult), aura_strength)

func _flash(color: Color, amount: float) -> void:
	_flash_color = color
	_flash_amount = maxf(_flash_amount, amount)
	_apply_flash()

func _apply_flash() -> void:
	flash_rect.color = Color(_flash_color.r, _flash_color.g, _flash_color.b, _flash_amount * 0.5)

func _update_flash(delta: float) -> void:
	if _flash_amount <= 0.0:
		return
	_flash_amount = maxf(0.0, _flash_amount - delta * 2.6)
	_apply_flash()

func _shake(power: float) -> void:
	if _reduced_motion():
		return
	_shake_power = maxf(_shake_power, power)
	_shake_time_left = 1.0

func _update_shake(delta: float) -> void:
	if _shake_time_left <= 0.0:
		return
	_shake_time_left = maxf(0.0, _shake_time_left - delta / maxf(tuning.shake_time, 0.05))
	if _shake_time_left <= 0.0:
		shake_root.position = Vector2.ZERO
		return
	var amplitude := _shake_power * _shake_time_left * (tuning.shake_strength / 14.0)
	shake_root.position = Vector2(randf_range(-amplitude, amplitude), randf_range(-amplitude, amplitude))

## Brief time-scale dip for impact (hit-stop). Uses an unscaled timer to recover.
func _hit_stop(scale: float, duration: float) -> void:
	var now := float(Time.get_ticks_msec()) / 1000.0
	if now < _hit_stop_until:
		return
	_hit_stop_until = now + duration
	Engine.time_scale = scale
	await get_tree().create_timer(duration, true, false, true).timeout
	Engine.time_scale = 1.0

func _reduced_motion() -> bool:
	return _save != null and _save.reduced_motion

# ---------------------------------------------------------------------------
# HUD style helpers (docs/UI_V2_BRIEF.md §2)
# ---------------------------------------------------------------------------

## Sticker panel: INK border + solid bottom ledge, rounded.
func _panel_style(fill: Color, border: int, radius: int, ledge: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = INK
	style.set_border_width_all(border)
	style.border_width_bottom = border + ledge
	style.set_corner_radius_all(radius)
	return style

func _button_style(fill: Color, pressed: bool) -> StyleBoxFlat:
	var style := _panel_style(fill, 6, 26, 0 if pressed else 6)
	style.content_margin_top = 6.0 + (6.0 if pressed else 0.0)
	return style
