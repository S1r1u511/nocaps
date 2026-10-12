extends RefCounted
class_name RunState

## Authoritative per-run facts. Presentation reads from this; it never mutates it.
## The readable score is combo-multiplied points (docs/01_GDD.md §8).

var score: int = 0
var landings: int = 0
var combo: int = 0
var mult: int = 1
## Currency collected this run. Never part of `score` or contribution.
var coins: int = 0
var distance: float = 0.0
var elapsed: float = 0.0
var alive: bool = true
var fail_reason: String = ""

func reset() -> void:
	score = 0
	landings = 0
	combo = 0
	mult = 1
	coins = 0
	distance = 0.0
	elapsed = 0.0
	alive = true
	fail_reason = ""

func meter() -> float:
	return distance / 100.0

## A successful own-mascot landing: extends the combo and adds base × multiplier.
func register_landing(base_points: int = Scoring.PERFECT_POINTS) -> void:
	combo += 1
	mult = Scoring.mult_for(combo)
	score += base_points * mult
	landings += 1

## A bump on your own mascot's body: worth a little, breaks the combo.
func register_bump() -> void:
	score += Scoring.BUMP_POINTS
	combo = 0
	mult = 1

## Passing your own crew's mascot without landing: -1 score, floored at zero.
## Combo and multiplier are untouched; this is a score-only fairness nudge.
func register_skip() -> void:
	score = maxi(score - 1, 0)

func fail(reason: String) -> void:
	if not alive:
		return
	alive = false
	fail_reason = reason
