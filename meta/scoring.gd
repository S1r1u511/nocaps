extends RefCounted
class_name Scoring

## Pure scoring math. The readable score uses landing-quality tiers on top of the
## combo streak: a centered ("perfect") head landing is worth 5 × multiplier, an
## edge-of-head landing 2 × multiplier, and a Bump on your own mascot's body is a
## flat +1 that resets the combo. Contribution points equal the run score.
## See docs/01_GDD.md §8.

const MULT_COLORS := {
	1: Color("ffe36e"),
	2: Color("ff9d2e"),
	3: Color("ff5d8f"),
	4: Color("5ee0ff"),
}

const PERFECT_POINTS := 5
const EDGE_POINTS := 2
const BUMP_POINTS := 1

## Multiplier for a combo streak: x2 / x3 / x4 at 5 / 10 / 20 consecutive landings.
static func mult_for(combo: int) -> int:
	if combo >= 20:
		return 4
	if combo >= 10:
		return 3
	if combo >= 5:
		return 2
	return 1

static func color_for(mult: int) -> Color:
	return MULT_COLORS.get(clampi(mult, 1, 4), MULT_COLORS[1])

## --- Streak and weekly tiers (Phase 4, TESTING values) ---

const STREAK_BONUS_PER_DAY := 0.05
const STREAK_BONUS_CAP := 0.25

## Multiplier applied when a run is banked: +5% per consecutive day played,
## capped at +25%. The streak is per player, not per community (GDD §8.3).
static func streak_multiplier(streak_days: int) -> float:
	return 1.0 + minf(STREAK_BONUS_CAP, float(maxi(streak_days, 1) - 1) * STREAK_BONUS_PER_DAY)

## Contribution points banked for a run: run score scaled by the streak bonus.
static func contribution_for(score: int, streak_days: int) -> int:
	return int(round(float(score) * streak_multiplier(streak_days)))

## Number of weekly tiers crossed for a contribution total.
static func tier_index(total: int, tiers: PackedInt32Array) -> int:
	var crossed := 0
	for i in range(tiers.size()):
		if total >= tiers[i]:
			crossed = i + 1
	return crossed

## The next tier's total, or -1 when every tier is crossed.
static func next_tier_total(total: int, tiers: PackedInt32Array) -> int:
	for i in range(tiers.size()):
		if total < tiers[i]:
			return tiers[i]
	return -1

## Progress (0–1) from the previous crossed tier toward the next; 1.0 when done.
static func tier_progress(total: int, tiers: PackedInt32Array) -> float:
	var next := next_tier_total(total, tiers)
	if next < 0:
		return 1.0
	var previous := 0
	for i in range(tiers.size()):
		if total >= tiers[i]:
			previous = tiers[i]
	return clampf(float(total - previous) / float(maxi(next - previous, 1)), 0.0, 1.0)

