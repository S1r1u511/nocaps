extends RefCounted
class_name SpawnDirector

## Owns mascot and hazard spawning, scrolling, and pruning for one run. Mascots
## come from the player's community (target) and the other enabled communities
## (rivals). Targets are guaranteed by mascot count (max consecutive rivals) and
## by an opening run of own-community mascots; spacing is a time budget converted
## with the current speed, so pixel gaps grow as the world speeds up.
## Nothing here decides score or failure. See docs/01_GDD.md §6.

const SPAWN_AHEAD := 960.0
const PRUNE_BEHIND := 240.0
## Placement attempts before a hazard spawn is deferred to the next retry tick.
const HAZARD_TRIES := 7
const HAZARD_RETRY := 0.18
## Seconds per step of hazard concurrency growth.
const HAZARD_CONCURRENCY_STEP := 10.0

var mascots: Array[MascotActor] = []
var hazards: Array[Hazard] = []

## DEV-only test toggles; never persisted and never part of a rule.
var force_target: bool = false
var hazards_enabled: bool = true

var _tuning: RunTuning
var _mascots_root: Node2D
var _hazards_root: Node2D
var _rng := RandomNumberGenerator.new()

var _target_community: CommunityDefinition
var _rivals: Array[CommunityDefinition] = []
var _ground_y: float = 1150.0
## Visible top of the world after the camera zoom; ceiling hazards hang from it.
var _ceiling_y: float = 0.0

var _next_mascot_x: float = 0.0
var _index: int = 0
var _opening_left: int = 0
var _rivals_since_target: int = 0
var _time_since_target: float = 0.0
var _distance_since_target: float = 0.0
var _trap_timer: float = 2.0
var _hazard_time: float = 0.0

func configure(
	tuning: RunTuning,
	mascots_root: Node2D,
	hazards_root: Node2D,
	ground_y: float = 1150.0,
	ceiling_y: float = 0.0
) -> void:
	_tuning = tuning
	_mascots_root = mascots_root
	_hazards_root = hazards_root
	_ground_y = ground_y
	_ceiling_y = ceiling_y

func set_communities(target: CommunityDefinition, rivals: Array[CommunityDefinition]) -> void:
	_target_community = target
	_rivals = rivals

## Updates the visible ceiling for future ceiling-hazard spawns (live camera
## tuning from the DEV panel); hazards already in flight keep their anchor.
func set_ceiling_y(value: float) -> void:
	_ceiling_y = value

## Starts a fresh spawn sequence. `run_seed` of 0 means a new random sequence each
## run; any other value is a fixed seed for tests and the DEV panel.
func reset(state: RunState, run_seed: int = 0) -> void:
	_clear()
	_rng.seed = run_seed if run_seed != 0 else randi()
	_index = 0
	_opening_left = _tuning.opening_targets
	_rivals_since_target = 0
	_time_since_target = 0.0
	_distance_since_target = 0.0
	_hazard_time = 0.0
	_next_mascot_x = _tuning.cap_x + 320.0
	_trap_timer = _rng.randf_range(1.2, 2.2)
	_spawn_mascot(_next_mascot_x, true)
	_opening_left = maxi(0, _opening_left - 1)
	_time_since_target = 0.0
	_distance_since_target = 0.0
	_next_mascot_x += _gap(state, _opening_left > 0)

func scroll(step: float) -> void:
	mascots = _prune_mascots(step)
	hazards = _prune_hazards(step)
	_next_mascot_x -= step

func update(delta: float, step: float, state: RunState) -> void:
	_time_since_target += delta
	_distance_since_target += step
	var limit := _tuning.cap_x + SPAWN_AHEAD
	var speed := Difficulty.scroll_speed(_tuning, state)

	while _next_mascot_x <= limit:
		var is_target := _next_mascot_is_target(state)
		_spawn_mascot(_next_mascot_x, is_target)
		if is_target:
			if _opening_left > 0:
				_opening_left -= 1
			_rivals_since_target = 0
			_time_since_target = 0.0
			_distance_since_target = 0.0
		else:
			_rivals_since_target += 1
		_next_mascot_x += _gap(state, _opening_left > 0)

	if _hazards_ready(state):
		_hazard_time += delta
		_trap_timer -= delta
		var max_traps := mini(_tuning.hazard_max_concurrent, 3 + int(_hazard_time / HAZARD_CONCURRENCY_STEP))
		if _trap_timer <= 0.0:
			if hazards.size() < max_traps and _spawn_hazard(limit, speed):
				_trap_timer = _hazard_interval()
			else:
				_trap_timer = HAZARD_RETRY

## True while the guaranteed opening targets have not all spawned yet.
func opening_pending() -> bool:
	return _opening_left > 0

func _hazards_ready(state: RunState) -> bool:
	return hazards_enabled and not opening_pending() and state.elapsed >= _tuning.hazard_start_delay

func _max_rivals(state: RunState) -> int:
	if state.landings >= _tuning.gap_phase_late_landings:
		return _tuning.max_rivals_late
	if state.landings >= _tuning.gap_phase_mid_landings:
		return _tuning.max_rivals_mid
	return _tuning.max_rivals_early

func _next_mascot_is_target(state: RunState) -> bool:
	if _opening_left > 0:
		return true
	if _unclaimed_target_ahead():
		return false
	if _time_since_target >= _tuning.target_max_interval \
			or _distance_since_target >= _tuning.target_max_distance:
		return true
	return _rivals_since_target >= _max_rivals(state)

func _unclaimed_target_ahead() -> bool:
	for mascot in mascots:
		if not is_instance_valid(mascot):
			continue
		if mascot.is_target and not mascot.claimed and mascot.position.x > _tuning.cap_x - 20.0:
			return true
	return false

func _gap(state: RunState, opening: bool) -> float:
	var speed := Difficulty.scroll_speed(_tuning, state)
	return Difficulty.mascot_gap(_tuning, state, speed, opening, _rng)

func _hazard_interval() -> float:
	var ramp := clampf(_hazard_time / maxf(_tuning.hazard_ramp_seconds, 1.0), 0.0, 1.0)
	return _rng.randf_range(
		lerpf(_tuning.hazard_interval_min, _tuning.hazard_interval_min_tight, ramp),
		lerpf(_tuning.hazard_interval_max, _tuning.hazard_interval_max_tight, ramp)
	)

func _spawn_mascot(x: float, is_target: bool) -> void:
	if force_target:
		is_target = true
	var community: CommunityDefinition = null
	if is_target:
		community = _target_community
	elif not _rivals.is_empty():
		community = _rivals[_rng.randi_range(0, _rivals.size() - 1)]

	var mascot := MascotActor.new()
	mascot.name = ("Target" if is_target else "Rival") + "%03d" % _index
	_index += 1
	var definition: MascotDefinition = community.mascot if community != null else null
	var accent := _tuning.target_accent if is_target else _tuning.rival_color
	if community != null:
		accent = community.accent_color
	mascot.setup(
		definition,
		is_target,
		accent,
		CommunityRepository.resolve_cap(community),
		_tuning.mascot_world_size,
		_tuning.mascot_body_radius_ratio
	)
	var variance := _tuning.target_line_variance if is_target else _tuning.rival_line_variance
	mascot.position = Vector2(
		x,
		_tuning.mascot_line_y + _rng.randf_range(-variance, variance)
	)
	_mascots_root.add_child(mascot)
	mascots.append(mascot)

## Places one hazard with clearance from mascots, the next mascot spawn, and
## other hazards. Returns false when no fair placement was found this tick.
func _spawn_hazard(limit: float, speed: float) -> bool:
	var safe_px := safe_after_px(speed)
	var ceilings := 0
	for hazard in hazards:
		if is_instance_valid(hazard) and hazard.kind == Hazard.Kind.CEIL:
			ceilings += 1

	for attempt in range(HAZARD_TRIES):
		var kind := _rng.randi_range(0, 3)  # spike, saw, cloud, ceil
		if kind == Hazard.Kind.CEIL and (ceilings >= 2 or _rng.randf() > 0.30):
			kind = _rng.randi_range(0, 2)

		var x := limit + 40.0 + _rng.randf_range(0.0, 120.0) + float(attempt) * 70.0
		if not _hazard_x_clear(x, kind, safe_px):
			continue

		var hazard := Hazard.new()
		if kind == Hazard.Kind.CEIL:
			hazard.configure_ceiling(96.0, 48.0)
			hazard.position.x = x
			hazard.position.y = _ceiling_y
		else:
			var y := _hazard_y()
			if not _hazard_y_clear(x, y):
				continue
			if kind == Hazard.Kind.SPIKE:
				hazard.configure_spike(_tuning.hazard_radius, y, _rng.randf_range(4.0, 12.0))
			elif kind == Hazard.Kind.SAW:
				hazard.configure_saw(25.0, y, _rng.randf_range(26.0, 60.0), _rng.randf_range(0.6, 1.05))
			else:
				hazard.configure_cloud(Vector2(74.0, 46.0), y, _rng.randf_range(8.0, 16.0))
			hazard.position.x = x

		hazard.name = "Hazard%03d" % _index
		_index += 1
		_hazards_root.add_child(hazard)
		hazards.append(hazard)
		return true
	return false

func _hazard_y() -> float:
	var top := _tuning.hazard_radius + 80.0
	var bottom := _ground_y - _tuning.hazard_radius - 80.0
	if _rng.randf() < 0.5:
		return _rng.randf_range(top, _tuning.mascot_line_y - 150.0)
	return _rng.randf_range(_tuning.mascot_line_y + 150.0, bottom)

## The hazard-free window after a landing spot, in pixels at `speed` (a time
## budget converted with the current scroll speed, like the mascot spacing).
func safe_after_px(speed: float) -> float:
	return maxf(_tuning.hazard_safe_after_mascot, 0.0) * maxf(speed, 0.0)

func _hazard_x_clear(x: float, kind: int, safe_px: float) -> bool:
	if not _spot_clear(x, _next_mascot_x, _tuning.hazard_clear_from_next_spawn, safe_px):
		return false
	for mascot in mascots:
		if not is_instance_valid(mascot):
			continue
		if not _spot_clear(x, mascot.position.x, _tuning.hazard_clear_from_mascots + mascot.body_radius, safe_px):
			return false
	for hazard in hazards:
		if not is_instance_valid(hazard):
			continue
		if absf(x - hazard.position.x) >= _tuning.hazard_min_spacing_x:
			continue
		if kind == Hazard.Kind.CEIL or hazard.kind == Hazard.Kind.CEIL:
			return false
	return true

## Shared x rule for one landing spot: the base clearance on both sides (which
## includes the corridor directly above/below the spot) plus the safe window
## after it, so a landing always leaves recovery room before the next hazard.
static func _spot_clear(x: float, spot_x: float, clear_px: float, safe_px: float) -> bool:
	var dx := x - spot_x
	if dx >= 0.0:
		return dx >= clear_px + safe_px
	return -dx >= clear_px

func _hazard_y_clear(x: float, y: float) -> bool:
	for hazard in hazards:
		if not is_instance_valid(hazard) or hazard.kind == Hazard.Kind.CEIL:
			continue
		if absf(x - hazard.position.x) < _tuning.hazard_min_spacing_x \
				and absf(y - hazard.position.y) < _tuning.hazard_min_spacing_y:
			return false
	return true

func _prune_mascots(step: float) -> Array[MascotActor]:
	var kept: Array[MascotActor] = []
	for mascot in mascots:
		if not is_instance_valid(mascot):
			continue
		mascot.position.x -= step
		if mascot.position.x < -PRUNE_BEHIND:
			mascot.queue_free()
		else:
			kept.append(mascot)
	return kept

func _prune_hazards(step: float) -> Array[Hazard]:
	var kept: Array[Hazard] = []
	for hazard in hazards:
		if not is_instance_valid(hazard):
			continue
		hazard.position.x -= step
		if hazard.position.x < -PRUNE_BEHIND:
			hazard.queue_free()
		else:
			kept.append(hazard)
	return kept

func _clear() -> void:
	for mascot in mascots:
		if is_instance_valid(mascot):
			mascot.queue_free()
	mascots.clear()
	for hazard in hazards:
		if is_instance_valid(hazard):
			hazard.queue_free()
	hazards.clear()
