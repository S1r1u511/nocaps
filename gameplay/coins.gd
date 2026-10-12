extends Node2D
class_name Coins

## In-game coins. Coins are currency only: collecting one never adds score or
## crew contribution (docs/01_GDD.md §8). Each eligible gap between two mascots
## can carry one short pattern; the pattern set widens as the run goes on so the
## opening stays readable and later gaps reward skill:
##   ARC          the bounce path between two heads (always available)
##   STAIRS_UP    a rising line toward a flap
##   STAIRS_DOWN  a falling line from a flap back to the next head
##   HIGH         a flat line above a bounce apex (bounce + one flap)
##   DIP          a U below the mascot line (risky: the ground is below)
##   WAVE         a longer sine across a wide gap
##   RIVAL_HOP    an arc over a rival mascot's head (clean jumps pay)
## A coin is never on a mascot's head, never inside a hazard, and the node
## scrolls with the world. Collecting a whole pattern is a "set": the run plays
## a rising chime and a ring. Nothing here decides score or failure.

enum Pattern { ARC, STAIRS_UP, STAIRS_DOWN, HIGH, DIP, WAVE, RIVAL_HOP }

const INK := Color("1d1033")
const GOLD := Color("ffd23f")
const GOLD_LIGHT := Color("ffe98a")
const BOB_AMPLITUDE := 4.0
const BOB_SPEED := 2.6
const PRUNE_BEHIND := 160.0
## Coins are cleared this far from any live hazard center/edge.
const HAZARD_CLEARANCE := 14.0
## Coins over a mascot keep at least this much air above its head top.
const HEAD_AIR := 70.0

var _tuning: RunTuning
var _rng := RandomNumberGenerator.new()
var _coins: Array = []
var _clock: float = 0.0
var _last_mascot: MascotActor
var _last_pattern: int = -1
var _next_group: int = 0
## group id -> {"size": int, "left": int, "broken": bool}
var _groups: Dictionary = {}
## Pattern counts this run (tests / tuning).
var pattern_counts: Dictionary = {}

func configure(tuning: RunTuning) -> void:
	_tuning = tuning

## Starts a fresh run. `run_seed` mirrors RunTuning.run_seed: 0 means a new
## random roll, anything else is fixed for tests and the DEV panel.
func reset(run_seed: int = 0) -> void:
	_coins.clear()
	_groups.clear()
	pattern_counts.clear()
	_last_mascot = null
	_last_pattern = -1
	_next_group = 0
	_rng.seed = run_seed if run_seed != 0 else randi()
	_clock = 0.0
	queue_redraw()

func coin_count() -> int:
	return _coins.size()

## World positions of the live coins (tests and debug).
func positions() -> Array[Vector2]:
	var out: Array[Vector2] = []
	for coin in _coins:
		out.append(coin["pos"])
	return out

## Moves the coins with the world; anything scrolled off behind the cap is gone
## (and its set can no longer be completed).
func scroll(step: float) -> void:
	if _coins.is_empty():
		return
	var kept: Array = []
	for coin in _coins:
		var pos: Vector2 = coin["pos"]
		pos.x -= step
		if pos.x >= -PRUNE_BEHIND:
			coin["pos"] = pos
			kept.append(coin)
		else:
			_break_group(int(coin["group"]))
	_coins = kept

## Processes freshly spawned mascots (one pattern per eligible gap) and clears
## any coin a hazard now covers.
func update(delta: float, director: SpawnDirector) -> void:
	_clock += delta
	if _tuning == null or not _tuning.coins_enabled:
		return
	var mascots: Array[MascotActor] = director.mascots
	var first_fresh := 1
	if _last_mascot != null and is_instance_valid(_last_mascot):
		first_fresh = mascots.find(_last_mascot) + 1
	elif not mascots.is_empty():
		first_fresh = mascots.size()
	for index in range(maxi(first_fresh, 1), mascots.size()):
		var previous: MascotActor = mascots[index - 1]
		var current: MascotActor = mascots[index]
		if is_instance_valid(previous) and is_instance_valid(current):
			_spawn_pattern(director, previous, current)
	if not mascots.is_empty():
		_last_mascot = mascots.back()
	_prune_hazards(director.hazards)
	queue_redraw()

func _prune_hazards(hazards: Array[Hazard]) -> void:
	if _coins.is_empty() or hazards.is_empty():
		return
	var kept: Array = []
	for coin in _coins:
		var covered := false
		for hazard in hazards:
			if is_instance_valid(hazard) and hazard_covers(hazard, coin["pos"], _tuning.coin_radius):
				covered = true
				break
		if covered:
			_break_group(int(coin["group"]))
		else:
			kept.append(coin)
	_coins = kept

func _break_group(group: int) -> void:
	if _groups.has(group):
		_groups[group]["broken"] = true

## Which patterns this moment of the run may use.
func _available(rival_next: bool) -> Array[int]:
	var out: Array[int] = [Pattern.ARC]
	if not _tuning.coin_pattern_variety:
		return out
	if _clock >= _tuning.coin_unlock_early_s:
		out.append_array([Pattern.STAIRS_UP, Pattern.STAIRS_DOWN, Pattern.HIGH])
	if _clock >= _tuning.coin_unlock_late_s:
		out.append_array([Pattern.DIP, Pattern.WAVE])
		if rival_next:
			# Over a rival is the most interesting spot; weight it up.
			out.append_array([Pattern.RIVAL_HOP, Pattern.RIVAL_HOP])
	return out

func _pick(rival_next: bool) -> int:
	var options := _available(rival_next)
	if options.size() > 1 and _last_pattern != -1:
		var filtered: Array[int] = []
		for p in options:
			if p != _last_pattern:
				filtered.append(p)
		if not filtered.is_empty():
			options = filtered
	return options[_rng.randi_range(0, options.size() - 1)]

## Places one pattern between two mascots when the gap is wide enough.
func _spawn_pattern(director: SpawnDirector, previous: MascotActor, current: MascotActor) -> void:
	if _rng.randf() > _tuning.coin_arc_chance:
		return
	var margin := maxf(previous.body_radius, current.body_radius) + 70.0
	var x0 := previous.position.x + margin
	var x1 := current.position.x - margin
	var span := x1 - x0
	var rival_next := not current.is_target
	var pattern := _pick(rival_next)
	if pattern != Pattern.RIVAL_HOP and span < _tuning.coin_spacing * 2.0:
		return
	var line := _tuning.mascot_line_y
	var base_y := line - 30.0
	var points: Array[Vector2] = []
	match pattern:
		Pattern.ARC:
			var lift := _tuning.coin_arc_lift * _rng.randf_range(0.85, 1.35)
			points = _curve(x0, x1, _count(span, _tuning.coin_arc_min, _tuning.coin_arc_max),
				func(t: float) -> float: return base_y - sin(PI * t) * lift)
		Pattern.STAIRS_UP:
			var top := line - _tuning.coin_high_lift * 0.85
			points = _curve(x0, x1, _count(span, 4, 5),
				func(t: float) -> float: return lerpf(base_y - 40.0, top, t))
		Pattern.STAIRS_DOWN:
			var top2 := line - _tuning.coin_high_lift * 0.85
			points = _curve(x0, x1, _count(span, 4, 5),
				func(t: float) -> float: return lerpf(top2, base_y - 40.0, t))
		Pattern.HIGH:
			var y := line - _tuning.coin_high_lift
			points = _curve(x0 + span * 0.1, x1 - span * 0.1, _count(span * 0.8, 3, 5),
				func(_t: float) -> float: return y)
		Pattern.DIP:
			var depth := _tuning.coin_dip_depth
			points = _curve(x0, x1, _count(span, 4, 5),
				func(t: float) -> float: return base_y + sin(PI * t) * depth)
		Pattern.WAVE:
			if span < _tuning.coin_spacing * 5.0:
				pattern = Pattern.ARC
				points = _curve(x0, x1, _count(span, 3, 5),
					func(t: float) -> float: return base_y - sin(PI * t) * _tuning.coin_arc_lift)
			else:
				var amp := _tuning.coin_wave_amp
				var mid := base_y - _tuning.coin_arc_lift * 0.8
				points = _curve(x0, x1, _count(span, 5, _tuning.coin_pattern_max),
					func(t: float) -> float: return mid - sin(TAU * 1.5 * t) * amp)
		Pattern.RIVAL_HOP:
			var cx := current.head_center_x()
			var top_y := current.head_top_y() - _tuning.coin_rival_hop_lift
			var half := current.body_radius + 70.0
			points = _curve(cx - half, cx + half, 5,
				func(t: float) -> float: return top_y - sin(PI * t) * 60.0 + 60.0)
	_last_pattern = pattern
	_place(director, points, pattern)

## Evenly spaced points along `y_of(t)` for t in [0, 1].
func _curve(x0: float, x1: float, count: int, y_of: Callable) -> Array[Vector2]:
	var out: Array[Vector2] = []
	for i in range(count):
		var t := 0.5 if count == 1 else float(i) / float(count - 1)
		out.append(Vector2(lerpf(x0, x1, t), float(y_of.call(t))))
	return out

## Coin count that keeps neighbours at least `coin_spacing` apart.
func _count(span: float, lo: int, hi: int) -> int:
	var fit := int(floor(span / _tuning.coin_spacing)) + 1
	return clampi(_rng.randi_range(lo, hi), mini(lo, fit), maxi(mini(hi, fit), 1))

func _place(director: SpawnDirector, points: Array[Vector2], pattern: int) -> void:
	var group := _next_group
	_next_group += 1
	var added := 0
	for pos in points:
		if _blocked(director, pos):
			continue
		_coins.append({"pos": pos, "phase": _rng.randf() * TAU, "group": group, "index": added})
		added += 1
	if added == 0:
		return
	_groups[group] = {"size": added, "left": added, "broken": added < points.size()}
	pattern_counts[pattern] = int(pattern_counts.get(pattern, 0)) + 1

## A coin may not sit inside a hazard or on/inside a mascot.
func _blocked(director: SpawnDirector, pos: Vector2) -> bool:
	for hazard in director.hazards:
		if is_instance_valid(hazard) and hazard_covers(hazard, pos, _tuning.coin_radius):
			return true
	for mascot in director.mascots:
		if is_instance_valid(mascot) and blocks_coin(mascot, pos, _tuning.coin_radius):
			return true
	return false

## True when `pos` is on a mascot's head or body: inside its head band without
## enough air above the head top, or inside the body circle.
static func blocks_coin(mascot: MascotActor, pos: Vector2, coin_radius: float) -> bool:
	if pos.distance_to(mascot.position) <= mascot.body_radius + coin_radius:
		return true
	var in_band := absf(pos.x - mascot.head_center_x()) < mascot.head_half_width() + coin_radius
	return in_band and pos.y > mascot.head_top_y() - HEAD_AIR

## Cap contact: removes and returns every collected coin position. The run turns
## the returned positions into sparkles and sound and banks the currency.
func collect(cap_position: Vector2, cap_radius: float) -> Array[Vector2]:
	var picked: Array[Vector2] = []
	for event in collect_events(cap_position, cap_radius):
		picked.append(event["pos"])
	return picked

## Like `collect`, with set info per coin: {pos, index, size, completed}.
## `completed` is true on the coin that finishes an unbroken pattern.
func collect_events(cap_position: Vector2, cap_radius: float) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if _coins.is_empty():
		return events
	var reach := cap_radius + _tuning.coin_radius + _tuning.coin_pickup_padding
	var kept: Array = []
	for coin in _coins:
		var pos: Vector2 = coin["pos"]
		if cap_position.distance_to(pos) <= reach:
			var group := int(coin["group"])
			var info: Dictionary = _groups.get(group, {"size": 1, "left": 1, "broken": true})
			info["left"] = int(info["left"]) - 1
			var done := int(info["left"]) <= 0 and not bool(info["broken"]) and int(info["size"]) >= 3
			events.append({
				"pos": pos,
				"index": int(info["size"]) - int(info["left"]) - 1,
				"size": int(info["size"]),
				"completed": done,
			})
			if int(info["left"]) <= 0:
				_groups.erase(group)
		else:
			kept.append(coin)
	if not events.is_empty():
		_coins = kept
		queue_redraw()
	return events

## True when a hazard's lethal volume contains `pos`. Mirrors Run's hit shapes
## with the coin's own radius added, so it is also the visual clearance rule.
static func hazard_covers(hazard: Hazard, pos: Vector2, coin_radius: float) -> bool:
	match hazard.kind:
		Hazard.Kind.SPIKE, Hazard.Kind.SAW:
			return pos.distance_to(hazard.position) <= hazard.radius + coin_radius + HAZARD_CLEARANCE
		Hazard.Kind.CLOUD:
			var rect := Rect2(
				hazard.position - Vector2(hazard.size.x * 0.42, hazard.size.y * 0.40),
				Vector2(hazard.size.x * 0.84, hazard.size.y * 0.78)
			)
			return rect.grow(coin_radius + HAZARD_CLEARANCE).has_point(pos)
		Hazard.Kind.CEIL:
			if hazard.ext < 0.4:
				return false
			var band := Rect2(
				Vector2(hazard.position.x - hazard.ceiling_width * 0.5, hazard.position.y),
				Vector2(hazard.ceiling_width, hazard.ceiling_height * hazard.ext)
			)
			return band.grow(coin_radius + HAZARD_CLEARANCE).has_point(pos)
	return false

## Sticker-style gold coin: ink outline, gold face, inner shine (matches the
## `coin` icon treatment in ui/icon.gd) at ~44 px diameter.
func _draw() -> void:
	var radius := _tuning.coin_radius if _tuning != null else 22.0
	for coin in _coins:
		var pos: Vector2 = coin["pos"] \
			+ Vector2(0.0, sin(_clock * BOB_SPEED + float(coin["phase"])) * BOB_AMPLITUDE)
		draw_circle(pos, radius, INK)
		draw_circle(pos, maxf(radius - 3.0, 1.0), GOLD)
		draw_circle(pos, radius * 0.34, Color(GOLD_LIGHT.r, GOLD_LIGHT.g, GOLD_LIGHT.b, 0.55))
		draw_arc(pos, radius * 0.64, -0.42 * PI, 0.42 * PI, 18, GOLD_LIGHT, 2.6, true)
