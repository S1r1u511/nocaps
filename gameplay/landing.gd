extends RefCounted
class_name Landing

## Pure landing resolution between the cap and a mascot. Returns an outcome; the
## run applies score, bounce, or failure. The head band depth is authored per
## mascot. Resolution includes a small grace above the head top and a head-top
## crossing check so fast falls cannot tunnel through the band.
## See docs/01_GDD.md §3.3–3.4 and §4.

enum Outcome { NONE, SCORE, BUMP, FAIL }

## Extra forgiveness above the head top, in pixels.
const HEAD_TOP_GRACE := 5.0

static func resolve(
	cap_position: Vector2,
	prev_cap_y: float,
	cap_velocity_y: float,
	cap_radius: float,
	mascot: MascotActor
) -> Outcome:
	if mascot.claimed:
		return Outcome.NONE

	var band_top := mascot.head_top_y()
	var band_bottom := band_top + mascot.head_band_depth()
	var probe := cap_position.y + cap_radius
	var prev_probe := prev_cap_y + cap_radius
	var descending := cap_velocity_y > 0.0
	var within_head := absf(cap_position.x - mascot.head_center_x()) <= mascot.head_half_width()
	var in_band := probe >= band_top - HEAD_TOP_GRACE and probe <= band_bottom
	var crossed := prev_probe < band_top and probe >= band_top

	if descending and within_head and (in_band or crossed):
		return Outcome.SCORE if mascot.is_target else Outcome.FAIL

	if cap_position.distance_to(mascot.position) <= cap_radius + mascot.body_radius:
		return Outcome.BUMP if mascot.is_target else Outcome.FAIL

	return Outcome.NONE
