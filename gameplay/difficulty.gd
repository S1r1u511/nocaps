extends RefCounted
class_name Difficulty

## Pure difficulty math driven by the current run's score and elapsed time.
## Difficulty grows through tuning, never new mechanics (docs/01_GDD.md §7).

## Speed ramps score-first: landing raises pressure immediately, time adds a gentle
## background ramp, the result is capped so a good run stays fair, and the opening
## eases in from `speed_ease_in_start` so the first seconds are always gentle.
static func scroll_speed(tuning: RunTuning, state: RunState) -> float:
	var target := tuning.base_scroll_speed * (
		1.0
		+ tuning.speed_gain_per_landing * float(state.landings)
		+ tuning.speed_gain_per_second * state.elapsed
	)
	target = minf(target, tuning.base_scroll_speed * tuning.max_scroll_multiplier)
	return target * ease_in(tuning, state.elapsed)

## Opening ease-in multiplier: smoothstep from `speed_ease_in_start` to 1.0 over
## the first `speed_ease_in_seconds` of a run (1.0 immediately when disabled).
static func ease_in(tuning: RunTuning, elapsed: float) -> float:
	var seconds := tuning.speed_ease_in_seconds
	if seconds <= 0.0:
		return 1.0
	var t := clampf(elapsed / seconds, 0.0, 1.0)
	var smooth := t * t * (3.0 - 2.0 * t)
	return lerpf(tuning.speed_ease_in_start, 1.0, smooth)

## Seconds between mascots for the current phase, as (min, max).
static func gap_time_range(tuning: RunTuning, state: RunState, opening: bool) -> Vector2:
	if opening:
		return Vector2(tuning.gap_time_opening_min, tuning.gap_time_opening_max)
	if state.landings >= tuning.gap_phase_late_landings:
		return Vector2(tuning.gap_time_late_min, tuning.gap_time_late_max)
	if state.landings >= tuning.gap_phase_mid_landings:
		return Vector2(tuning.gap_time_mid_min, tuning.gap_time_mid_max)
	return Vector2(tuning.gap_time_early_min, tuning.gap_time_early_max)

## Center-to-center spacing in pixels: the phase's time budget times the current
## scroll speed, so spacing grows as the world speeds up and the time between
## mascots stays readable.
static func mascot_gap(
	tuning: RunTuning,
	state: RunState,
	speed: float,
	opening: bool,
	rng: RandomNumberGenerator
) -> float:
	var span := gap_time_range(tuning, state, opening)
	return rng.randf_range(span.x, span.y) * maxf(speed, 1.0)
