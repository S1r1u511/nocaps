extends Resource
class_name RunTuning

## Authored tuning for the tap-to-fly run. Values are TESTING starting points
## adapted from the `cappycap` reference and rescaled for the portrait baseline.
## See docs/07_TUNING_GUIDE.md. Rules (physics feel, landing-quality score,
## wrong mascot/hazard/ground failure) live in the GDD; only numbers live here.

@export_group("Cap")
@export var cap_x: float = 190.0
@export var start_y: float = 600.0
@export var gravity: float = 2600.0
@export var flap_impulse: float = 880.0
@export var max_fall_speed: float = 1550.0
## Bounce apex is intentionally higher than flap apex so chaining heads pays off.
@export var bounce_impulse: float = 1040.0
@export var cap_radius: float = 20.0
## Tilt limits in radians: rising (negative rotation) and diving (positive).
@export var tilt_up: float = 0.5
@export var tilt_down: float = 1.0
## Rotation easing rate (per second) toward the tilt target.
@export var rotation_follow: float = 13.0
@export var flap_rotation_snap: float = 0.45
@export var land_rotation_snap: float = 0.62

@export_group("World")
## Fallback ground line; the live ground is the viewport bottom minus `ground_inset`.
@export var ground_y: float = 1150.0
@export var ground_inset: float = 4.0
@export var base_scroll_speed: float = 300.0
## Fraction of the base speed added per successful landing (score-first ramp).
@export var speed_gain_per_landing: float = 0.05
## Fraction of the base speed added per second of run time.
@export var speed_gain_per_second: float = 0.002
@export var max_scroll_multiplier: float = 2.04
## Ease-in (playtest_v05): the first `speed_ease_in_seconds` scale the speed from
## `speed_ease_in_start` up to 1.0 with a smoothstep, so the opening is easy.
@export var speed_ease_in_seconds: float = 20.0
@export var speed_ease_in_start: float = 0.8
## 0 = a fresh random spawn sequence each run; any other value is a fixed seed
## (used by tests and the DEV panel).
@export var run_seed: int = 0

@export_group("Camera")
## World zoom-out: 1.0 keeps the viewport framing; lower values scale the
## gameplay world down (more lookahead) while the HUD stays fixed. The cap's x
## and the mascot line stay pinned on screen, so the ground sits slightly above
## the viewport bottom. playtest_v05 uses 0.88.
@export_range(0.6, 1.0, 0.01) var camera_zoom: float = 0.88

@export_group("Mascots")
@export var mascot_line_y: float = 840.0
## The target varies less than rivals so its head stays readable and reachable.
@export var target_line_variance: float = 30.0
@export var rival_line_variance: float = 70.0
## Mascot rendered size: the larger of its opaque content dimensions, in pixels.
@export var mascot_world_size: float = 150.0
## Rival/body collision radius as a fraction of the rendered mascot size.
@export_range(0.1, 0.6, 0.01) var mascot_body_radius_ratio: float = 0.42
@export var target_accent: Color = Color("ffe15a")
@export var rival_color: Color = Color("ff5d73")

@export_group("Spacing")
## Seconds between mascots (center-to-center) per phase; spacing is converted to
## pixels with the current scroll speed so it grows as the world speeds up.
@export var gap_time_opening_min: float = 2.6
@export var gap_time_opening_max: float = 3.2
@export var gap_time_early_min: float = 2.0
@export var gap_time_early_max: float = 2.5
@export var gap_time_mid_min: float = 1.7
@export var gap_time_mid_max: float = 2.1
@export var gap_time_late_min: float = 1.3
@export var gap_time_late_max: float = 1.7
## Successful landings at which the mid / late spacing phases start.
@export var gap_phase_mid_landings: int = 5
@export var gap_phase_late_landings: int = 10

@export_group("Target cadence")
## Own-community mascots guaranteed back-to-back at the very start of a run.
@export var opening_targets: int = 3
## Max consecutive rivals between targets, by spacing phase.
@export var max_rivals_early: int = 1
@export var max_rivals_mid: int = 2
@export var max_rivals_late: int = 2
## Safety cap: at least one target within this time / distance.
@export var target_max_interval: float = 4.5
@export var target_max_distance: float = 3200.0

@export_group("Hazards")
@export var hazard_start_delay: float = 5.0
## Seconds after activation over which the cadence tightens.
@export var hazard_ramp_seconds: float = 30.0
## Seconds between hazard spawns; tightens over `hazard_ramp_seconds`.
@export var hazard_interval_min: float = 1.6
@export var hazard_interval_min_tight: float = 0.8
@export var hazard_interval_max: float = 2.6
@export var hazard_interval_max_tight: float = 1.2
## Concurrency cap at full ramp (`3 + time/10` up to this).
@export var hazard_max_concurrent: int = 6
@export var hazard_radius: float = 22.0
@export var hazard_color: Color = Color("ff3b3b")
## Clearance rules keep traps readable and fair; clearance is measured from the
## mascot's edge (mascot body radius is added at runtime).
@export var hazard_clear_from_mascots: float = 110.0
@export var hazard_clear_from_next_spawn: float = 150.0
@export var hazard_min_spacing_x: float = 130.0
@export var hazard_min_spacing_y: float = 110.0
## Hazard-free window after each landing spot, as a time budget converted with
## the current scroll speed (like mascot spacing). Every landing leaves at least
## this much room before the next hazard; hazards keep the base clearance on both
## sides, which includes the corridor directly above/below a landing spot.
@export var hazard_safe_after_mascot: float = 0.5

@export_group("Coins")
## Coins are in-game currency only: they never add score or crew contribution.
## Short arcs of 3–5 coins follow the bounce path between two mascots; density is
## the chance that an eligible gap carries an arc. See docs/01_GDD.md §8.
@export var coins_enabled: bool = true
@export_range(0.0, 1.0, 0.05) var coin_arc_chance: float = 0.65
@export var coin_arc_min: int = 3
@export var coin_arc_max: int = 5
## Rendered coin diameter is 2 × `coin_radius` (~44 px).
@export var coin_radius: float = 22.0
@export var coin_value: int = 1
## Minimum center spacing required before a gap can carry an arc.
@export var coin_spacing: float = 86.0
## Height of the arc's midpoint above the mascot line, inside a bounce apex.
@export var coin_arc_lift: float = 130.0
## Extra forgiveness on the cap-contact pickup radius.
@export var coin_pickup_padding: float = 12.0
## Pattern variety (gameplay/coins.gd). Patterns unlock with run time so the
## opening stays simple: arcs first, then stairs / high lines, then dips, waves
## and hops over rival mascots.
@export var coin_pattern_variety: bool = true
@export var coin_unlock_early_s: float = 8.0
@export var coin_unlock_late_s: float = 22.0
## High line: needs a bounce plus a flap. Height above the mascot line.
@export var coin_high_lift: float = 330.0
## Dip: drops below the mascot line between heads (risk: the ground).
@export var coin_dip_depth: float = 170.0
## Wave amplitude around the bounce midline.
@export var coin_wave_amp: float = 85.0
## Rival hop: arc over a rival mascot's head, this far above its head top.
@export var coin_rival_hop_lift: float = 150.0
## Longest pattern (waves / lines can run past `coin_arc_max`).
@export var coin_pattern_max: int = 7

@export_group("Surprise ceiling")
## Top fraction of the screen that counts as "hugging the ceiling".
@export_range(0.05, 0.4, 0.01) var surprise_ceiling_zone: float = 0.15
## Seconds the cap must stay in that zone before the spike is triggered.
@export var surprise_ceiling_dwell: float = 0.4
## Fairness window: the spike peeks and shakes before it slams.
@export var surprise_ceiling_telegraph: float = 0.35
## Seconds before another surprise spike can trigger.
@export var surprise_ceiling_cooldown: float = 4.0

@export_group("Fairness")
## Passing an own-crew mascot without landing costs one score point (never below
## zero) so ignoring your own crew is never free; combo is untouched.
@export var skip_penalty_enabled: bool = true
## Seconds at the start of a run in which the skip penalty never applies.
@export var skip_penalty_grace: float = 10.0

@export_group("Feel")
## Seconds the failure beat plays before the Result screen appears.
@export var fail_delay: float = 0.75
@export var shake_strength: float = 14.0
@export var shake_time: float = 0.35
@export_range(0.0, 0.5, 0.01) var flap_stretch: float = 0.16
@export_range(0.0, 0.5, 0.01) var land_squash: float = 0.26
@export var haptic_light_ms: int = 12
@export var haptic_heavy_ms: int = 55
## Fraction of the head half-width that counts as a centered ("perfect") landing.
@export_range(0.1, 1.0, 0.05) var perfect_head_ratio: float = 0.36
