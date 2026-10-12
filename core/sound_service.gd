extends Node

## SoundService
## Procedural audio synthesizer and playback manager for NOCAPS.
## Synthesizes all sound effects and background ambience in code using
## mathematical wave generation packed into AudioStreamWAV buffers.

const SAMPLE_RATE: int = 22050

static var instance: Node

var _sfx_players: Array[AudioStreamPlayer] = []
var _bg_player: AudioStreamPlayer

var _clips: Dictionary = {}

var is_sound_enabled: bool = true
var is_music_enabled: bool = true


func _enter_tree() -> void:
	if instance == null:
		instance = self


func _exit_tree() -> void:
	if instance == self:
		instance = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_init_players()
	_generate_all_clips()


func _init_players() -> void:
	# Dedicated background ambience player
	_bg_player = AudioStreamPlayer.new()
	_bg_player.name = "BGPlayer"
	_bg_player.volume_db = -15.0
	add_child(_bg_player)

	# Pool of SFX players for polyphony
	for i in range(6):
		var player := AudioStreamPlayer.new()
		player.name = "SFXPlayer%d" % i
		player.volume_db = -6.0
		add_child(player)
		_sfx_players.append(player)


func _get_free_sfx_player() -> AudioStreamPlayer:
	for player in _sfx_players:
		if not player.playing:
			return player
	return _sfx_players[0]


func _play_sfx(clip_name: String, pitch_scale: float = 1.0, volume_offset_db: float = 0.0) -> void:
	if not is_sound_enabled or not _clips.has(clip_name):
		return
	var player := _get_free_sfx_player()
	player.stream = _clips[clip_name]
	player.pitch_scale = pitch_scale
	player.volume_db = -6.0 + volume_offset_db
	player.play()


static func get_instance() -> Node:
	if not is_instance_valid(instance):
		var tree := Engine.get_main_loop() as SceneTree
		if tree and tree.root:
			var existing = tree.root.get_node_or_null("SoundService")
			if is_instance_valid(existing):
				instance = existing
			else:
				var script_res = load("res://core/sound_service.gd")
				var new_instance = script_res.new()
				new_instance.name = "SoundService"
				tree.root.add_child(new_instance)
				instance = new_instance
	return instance


# --- Static Public API ---

static func play_launch() -> void:
	var inst = get_instance()
	if is_instance_valid(inst):
		inst._play_sfx("launch", randf_range(0.96, 1.04))


static func play_air_skip() -> void:
	var inst = get_instance()
	if is_instance_valid(inst):
		inst._play_sfx("air_skip", randf_range(0.97, 1.03))


static func play_rotate() -> void:
	var inst = get_instance()
	if is_instance_valid(inst):
		inst._play_sfx("rotate", randf_range(0.95, 1.05))


static func play_land_correct(combo: int = 0) -> void:
	var inst = get_instance()
	if is_instance_valid(inst):
		var pitch := 1.0 + minf(0.25, float(combo) * 0.02)
		inst._play_sfx("land_correct", pitch, 1.5)


static func play_flap(speed_ratio: float = 0.0) -> void:
	var inst = get_instance()
	if is_instance_valid(inst):
		var pitch := randf_range(0.97, 1.05) + clampf(speed_ratio, 0.0, 1.0) * 0.06
		inst._play_sfx("flap", pitch)


static func play_bump() -> void:
	var inst = get_instance()
	if is_instance_valid(inst):
		inst._play_sfx("bump", randf_range(0.96, 1.04))


static func play_whoosh() -> void:
	var inst = get_instance()
	if is_instance_valid(inst):
		inst._play_sfx("whoosh", randf_range(0.9, 1.12), -2.0)


static func play_warn() -> void:
	var inst = get_instance()
	if is_instance_valid(inst):
		inst._play_sfx("warn", 1.0, -7.0)


## Multiplier milestone (x2/x3/x4): a rising two-note streak cue.
static func play_streak(mult: int) -> void:
	var inst = get_instance()
	if is_instance_valid(inst):
		inst._play_sfx("streak", 1.0 + 0.12 * float(clampi(mult, 2, 4) - 2), 1.0)


## Broken combo: a small descending blip, deliberately quiet.
static func play_combo_lost() -> void:
	var inst = get_instance()
	if is_instance_valid(inst):
		inst._play_sfx("combo_lost", randf_range(0.97, 1.03), -3.0)


## Distinct impact per hazard: spike / saw / cloud / ceil.
static func play_hazard_hit(kind: String) -> void:
	var inst = get_instance()
	if is_instance_valid(inst):
		inst._play_sfx("hit_%s" % kind)


static func play_count() -> void:
	var inst = get_instance()
	if is_instance_valid(inst):
		inst._play_sfx("count", randf_range(0.98, 1.04), -4.0)


## Coin pickup: a short, bright two-tone tick, distinct from the result count.
## `step` is the coin's place in its pattern; the pitch climbs a little per coin.
static func play_coin(step: int = 0) -> void:
	var inst = get_instance()
	if is_instance_valid(inst):
		inst._play_sfx("coin", minf(1.0 + 0.06 * float(step), 1.5) * randf_range(0.98, 1.02), -3.0)


## Whole coin pattern collected: a brighter, higher tick.
static func play_coin_set() -> void:
	var inst = get_instance()
	if is_instance_valid(inst):
		inst._play_sfx("coin", 1.6, 0.0)


static func play_land_wrong() -> void:
	var inst = get_instance()
	if is_instance_valid(inst):
		inst._play_sfx("land_wrong", randf_range(0.95, 1.05))


static func play_hazard() -> void:
	var inst = get_instance()
	if is_instance_valid(inst):
		inst._play_sfx("hazard", 1.0, 2.0)


static func play_complete() -> void:
	var inst = get_instance()
	if is_instance_valid(inst):
		inst._play_sfx("complete", 1.0, 3.0)


static func play_ui_click() -> void:
	var inst = get_instance()
	if is_instance_valid(inst):
		inst._play_sfx("ui_click", randf_range(0.98, 1.02), -2.0)


static func play_death() -> void:
	var inst = get_instance()
	if is_instance_valid(inst):
		inst._play_sfx("death")


static func play_thud() -> void:
	var inst = get_instance()
	if is_instance_valid(inst):
		inst._play_sfx("thud")


static func play_best() -> void:
	var inst = get_instance()
	if is_instance_valid(inst):
		inst._play_sfx("best")


static func play_combo(step: int) -> void:
	var inst = get_instance()
	if is_instance_valid(inst):
		inst._play_sfx("combo%d" % clampi(step, 0, 5))


static func start_bg_ambience() -> void:
	var inst = get_instance()
	if is_instance_valid(inst):
		inst._start_bg()


static func stop_bg_ambience() -> void:
	var inst = get_instance()
	if is_instance_valid(inst):
		inst._stop_bg()


func _start_bg() -> void:
	if not is_music_enabled or _bg_player == null:
		return
	# The generated looping WAV reproducibly crashes Godot's OpenSL ES
	# AudioTrack callback on Android 16. Keep short SFX enabled and use the
	# ambience only on platforms where the in-memory loop is stable.
	if OS.has_feature("android"):
		return
	if _clips.has("bg_ambience") and not _bg_player.playing:
		_bg_player.stream = _clips["bg_ambience"]
		_bg_player.play()


func _stop_bg() -> void:
	if _bg_player != null and _bg_player.playing:
		_bg_player.stop()


# --- Procedural Waveform Generators ---

func _generate_all_clips() -> void:
	_clips["launch"] = _create_launch_clip()
	_clips["air_skip"] = _create_air_skip_clip()
	_clips["rotate"] = _create_rotate_clip()
	_clips["land_correct"] = _create_land_correct_clip()
	_clips["land_wrong"] = _create_land_wrong_clip()
	_clips["hazard"] = _create_hazard_clip()
	_clips["complete"] = _create_complete_clip()
	_clips["ui_click"] = _create_ui_click_clip()
	_clips["bg_ambience"] = _create_bg_ambience_clip()
	_clips["death"] = _create_death_clip()
	_clips["thud"] = _create_thud_clip()
	_clips["best"] = _create_best_clip()
	_clips["flap"] = _create_flap_clip()
	_clips["bump"] = _create_bump_clip()
	_clips["whoosh"] = _create_whoosh_clip()
	_clips["warn"] = _create_warn_clip()
	_clips["streak"] = _create_streak_clip()
	_clips["combo_lost"] = _create_combo_lost_clip()
	_clips["hit_spike"] = _create_hit_spike_clip()
	_clips["hit_saw"] = _create_hit_saw_clip()
	_clips["hit_cloud"] = _create_hit_cloud_clip()
	_clips["hit_ceil"] = _create_hit_ceil_clip()
	_clips["count"] = _create_count_clip()
	_clips["coin"] = _create_coin_clip()
	for step in range(6):
		_clips["combo%d" % step] = _create_combo_clip(step)


func _create_wav(samples: PackedFloat32Array, loop: bool = false) -> AudioStreamWAV:
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = SAMPLE_RATE
	wav.stereo = false
	var total_samples: int = samples.size()
	var bytes := PackedByteArray()
	bytes.resize(total_samples * 2)
	for i in range(total_samples):
		var s: float = clampf(samples[i], -1.0, 1.0)
		var int_val: int = clampi(int(s * 32767.0), -32768, 32767)
		if int_val < 0:
			int_val += 65536
		bytes[i * 2] = int_val & 0xFF
		bytes[i * 2 + 1] = (int_val >> 8) & 0xFF
	wav.data = bytes
	if loop:
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = total_samples
	return wav


## Launch sound: Snappy ascending sweep with exponential decay.
func _create_launch_clip() -> AudioStreamWAV:
	var duration := 0.11
	var count := int(duration * SAMPLE_RATE)
	var samples := PackedFloat32Array()
	samples.resize(count)
	var phase: float = 0.0
	for i in range(count):
		var t := float(i) / SAMPLE_RATE
		var progress := t / duration
		var freq: float = 220.0 + (540.0 - 220.0) * sqrt(progress)
		phase += 2.0 * PI * freq / SAMPLE_RATE
		var attack: float = minf(t / 0.005, 1.0)
		var decay: float = exp(- progress * 5.0)
		var envelope: float = attack * decay
		var sample: float = sin(phase) * 0.8 + sin(phase * 2.0) * 0.2
		samples[i] = sample * envelope
	return _create_wav(samples)


## Air skip sound: Distinct airy high chirp with rapid modulation.
func _create_air_skip_clip() -> AudioStreamWAV:
	var duration := 0.14
	var count := int(duration * SAMPLE_RATE)
	var samples := PackedFloat32Array()
	samples.resize(count)
	var phase: float = 0.0
	for i in range(count):
		var t := float(i) / SAMPLE_RATE
		var progress := t / duration
		var freq: float = 520.0 + (880.0 - 520.0) * progress + sin(t * 70.0) * 40.0
		phase += 2.0 * PI * freq / SAMPLE_RATE
		var attack: float = minf(t / 0.004, 1.0)
		var decay: float = exp(- progress * 6.5)
		var envelope: float = attack * decay
		var sample: float = sin(phase) * 0.75 + sin(phase * 3.0) * 0.25
		samples[i] = sample * envelope
	return _create_wav(samples)


## Rotate sound: Crisp subtle click/whoosh for swipe feedback.
func _create_rotate_clip() -> AudioStreamWAV:
	var duration := 0.045
	var count := int(duration * SAMPLE_RATE)
	var samples := PackedFloat32Array()
	samples.resize(count)
	var phase: float = 0.0
	for i in range(count):
		var t := float(i) / SAMPLE_RATE
		var progress := t / duration
		var freq: float = 650.0 - 320.0 * progress
		phase += 2.0 * PI * freq / SAMPLE_RATE
		var attack: float = minf(t / 0.002, 1.0)
		var decay: float = exp(- progress * 14.0)
		var noise: float = randf_range(-0.35, 0.35)
		var sample: float = sin(phase) * 0.65 + noise
		samples[i] = sample * attack * decay
	return _create_wav(samples)


## Correct landing sound: Joyful harmonic chord chime (C5 + E5 + G5 with bell ring).
func _create_land_correct_clip() -> AudioStreamWAV:
	var duration := 0.24
	var count := int(duration * SAMPLE_RATE)
	var samples := PackedFloat32Array()
	samples.resize(count)
	var freq1 := 523.25  # C5
	var freq2 := 659.25  # E5
	var freq3 := 783.99  # G5
	for i in range(count):
		var t := float(i) / SAMPLE_RATE
		var attack: float = minf(t / 0.003, 1.0)
		var decay1: float = exp(- t * 10.0)
		var decay2: float = exp(- t * 12.0)
		var decay3: float = exp(- t * 14.0)
		var s1: float = sin(2.0 * PI * freq1 * t) * decay1 * 0.40
		var s2: float = sin(2.0 * PI * freq2 * t) * decay2 * 0.35
		var s3: float = sin(2.0 * PI * freq3 * t) * decay3 * 0.30
		samples[i] = (s1 + s2 + s3) * attack
	return _create_wav(samples)


## Wrong landing sound: Soft wooden thud (harmless, distinct from correct).
func _create_land_wrong_clip() -> AudioStreamWAV:
	var duration := 0.12
	var count := int(duration * SAMPLE_RATE)
	var samples := PackedFloat32Array()
	samples.resize(count)
	var phase: float = 0.0
	for i in range(count):
		var t := float(i) / SAMPLE_RATE
		var progress := t / duration
		var freq: float = 135.0 - 70.0 * progress
		phase += 2.0 * PI * freq / SAMPLE_RATE
		var attack: float = minf(t / 0.003, 1.0)
		var decay: float = exp(- t * 24.0)
		var sample: float = sin(phase) * 0.8 + sin(phase * 3.0) * 0.2
		samples[i] = sample * attack * decay
	return _create_wav(samples)


## Hazard failure sound: Dramatic descending buzzy thud.
func _create_hazard_clip() -> AudioStreamWAV:
	var duration := 0.36
	var count := int(duration * SAMPLE_RATE)
	var samples := PackedFloat32Array()
	samples.resize(count)
	var phase: float = 0.0
	for i in range(count):
		var t := float(i) / SAMPLE_RATE
		var progress := t / duration
		var freq: float = 260.0 - 190.0 * progress
		phase += 2.0 * PI * freq / SAMPLE_RATE
		var tremolo: float = 0.7 + 0.3 * sin(2.0 * PI * 24.0 * t)
		var attack: float = minf(t / 0.004, 1.0)
		var decay: float = exp(- progress * 3.5)
		var square_val: float = 1.0 if sin(phase) > 0.0 else -1.0
		var sample: float = (sin(phase) * 0.55 + square_val * 0.45) * tremolo
		samples[i] = sample * attack * decay
	return _create_wav(samples)


## Level complete fanfare: Ascending arpeggio ringing into celebratory chord.
func _create_complete_clip() -> AudioStreamWAV:
	var duration := 0.58
	var count := int(duration * SAMPLE_RATE)
	var samples := PackedFloat32Array()
	samples.resize(count)
	var notes := [
		{"freq": 523.25, "start": 0.00},   # C5
		{"freq": 659.25, "start": 0.09},   # E5
		{"freq": 783.99, "start": 0.18},   # G5
		{"freq": 1046.50, "start": 0.27},  # C6
	]
	for i in range(count):
		var t := float(i) / SAMPLE_RATE
		var acc: float = 0.0
		for note in notes:
			if t >= note["start"]:
				var note_t: float = t - note["start"]
				var attack: float = minf(note_t / 0.004, 1.0)
				var decay: float = exp(- note_t * 6.5)
				acc += sin(2.0 * PI * note["freq"] * note_t) * attack * decay * 0.32
		samples[i] = clampf(acc, -1.0, 1.0)
	return _create_wav(samples)


## UI click: Clean soft pop.
func _create_ui_click_clip() -> AudioStreamWAV:
	var duration := 0.035
	var count := int(duration * SAMPLE_RATE)
	var samples := PackedFloat32Array()
	samples.resize(count)
	var phase: float = 0.0
	for i in range(count):
		var t := float(i) / SAMPLE_RATE
		var progress := t / duration
		var freq: float = 750.0 - 380.0 * progress
		phase += 2.0 * PI * freq / SAMPLE_RATE
		var attack: float = minf(t / 0.002, 1.0)
		var decay: float = exp(- progress * 16.0)
		samples[i] = sin(phase) * attack * decay * 0.7
	return _create_wav(samples)


## Background Ambience: Seamless procedural ocean waves surf and coastal breeze (4.0s loop).
func _create_bg_ambience_clip() -> AudioStreamWAV:
	var duration := 4.0
	var count := int(duration * SAMPLE_RATE)
	var samples := PackedFloat32Array()
	samples.resize(count)

	var lpf_low: float = 0.0
	var lpf_mid: float = 0.0

	for i in range(count):
		var t := float(i) / SAMPLE_RATE
		var cycle: float = (1.0 - cos(2.0 * PI * t / duration)) * 0.5
		var wave_swell: float = pow(cycle, 1.3)
		var white_noise: float = randf_range(-1.0, 1.0)
		lpf_low += 0.05 * (white_noise - lpf_low)
		lpf_mid += 0.22 * (white_noise - lpf_mid)
		var deep_tone: float = sin(2.0 * PI * 55.0 * t) * 0.15
		var wave_body: float = lpf_low * 0.7 + deep_tone
		var surf_foam: float = (lpf_mid - lpf_low) * 0.35 * wave_swell
		var total_sample: float = (wave_body * (0.3 + 0.7 * wave_swell) + surf_foam) * 0.40
		samples[i] = clampf(total_sample, -1.0, 1.0)

	return _create_wav(samples, true)


## Death: descending buzzy fall (saw + square).
func _create_death_clip() -> AudioStreamWAV:
	var duration := 0.5
	var count := int(duration * SAMPLE_RATE)
	var samples := PackedFloat32Array()
	samples.resize(count)
	var phase_saw: float = 0.0
	var phase_sq: float = 0.0
	for i in range(count):
		var t := float(i) / SAMPLE_RATE
		var progress := t / duration
		var f_saw: float = 300.0 - 230.0 * progress
		var f_sq: float = 160.0 - 110.0 * progress
		phase_saw += 2.0 * PI * f_saw / SAMPLE_RATE
		phase_sq += 2.0 * PI * f_sq / SAMPLE_RATE
		var attack: float = minf(t / 0.005, 1.0)
		var decay: float = exp(-progress * 3.2)
		var saw: float = (phase_saw / PI - floor(phase_saw / (2.0 * PI)) * 2.0)
		saw = (saw - 1.0)
		var square: float = 1.0 if sin(phase_sq) > 0.0 else -1.0
		samples[i] = (saw * 0.55 + square * 0.30) * attack * decay
	return _create_wav(samples)


## Ground thud: low soft impact.
func _create_thud_clip() -> AudioStreamWAV:
	var duration := 0.24
	var count := int(duration * SAMPLE_RATE)
	var samples := PackedFloat32Array()
	samples.resize(count)
	var phase: float = 0.0
	for i in range(count):
		var t := float(i) / SAMPLE_RATE
		var progress := t / duration
		var freq: float = 150.0 - 95.0 * progress
		phase += 2.0 * PI * freq / SAMPLE_RATE
		var attack: float = minf(t / 0.004, 1.0)
		var decay: float = exp(-progress * 4.5)
		samples[i] = sin(phase) * attack * decay * 0.9
	return _create_wav(samples)


## Personal best: rising celebratory arpeggio.
func _create_best_clip() -> AudioStreamWAV:
	var duration := 0.62
	var count := int(duration * SAMPLE_RATE)
	var samples := PackedFloat32Array()
	samples.resize(count)
	var notes := [660.0, 880.0, 1180.0, 1480.0]
	for i in range(count):
		var t := float(i) / SAMPLE_RATE
		var acc: float = 0.0
		for n in range(notes.size()):
			var start: float = float(n) * 0.09
			if t >= start:
				var note_t: float = t - start
				var attack: float = minf(note_t / 0.004, 1.0)
				var decay: float = exp(-note_t * 6.0)
				acc += sin(2.0 * PI * notes[n] * note_t) * attack * decay * 0.3
		samples[i] = clampf(acc, -1.0, 1.0)
	return _create_wav(samples)


## Combo step: short ascending blip, one per successive multiplier.
func _create_combo_clip(step: int) -> AudioStreamWAV:
	var freqs := [0.0, 520.0, 660.0, 820.0, 1040.0, 1320.0]
	var freq: float = freqs[clampi(step, 0, 5)]
	if freq <= 0.0:
		freq = 520.0
	var duration := 0.09
	var count := int(duration * SAMPLE_RATE)
	var samples := PackedFloat32Array()
	samples.resize(count)
	var phase: float = 0.0
	for i in range(count):
		var t := float(i) / SAMPLE_RATE
		phase += 2.0 * PI * freq / SAMPLE_RATE
		var attack: float = minf(t / 0.004, 1.0)
		var decay: float = exp(-t * 18.0)
		var square: float = 1.0 if sin(phase) > 0.0 else -1.0
		samples[i] = square * attack * decay * 0.28
	return _create_wav(samples)


## Flap: a crisp air-puff "fwip" with a fast pitch drop and a soft low body.
func _create_flap_clip() -> AudioStreamWAV:
	var duration := 0.1
	var count := int(duration * SAMPLE_RATE)
	var samples := PackedFloat32Array()
	samples.resize(count)
	var phase: float = 0.0
	var lpf: float = 0.0
	for i in range(count):
		var t := float(i) / SAMPLE_RATE
		var progress := t / duration
		var freq: float = 380.0 - 240.0 * progress
		phase += 2.0 * PI * freq / SAMPLE_RATE
		lpf += 0.5 * (randf_range(-1.0, 1.0) - lpf)
		var attack: float = minf(t / 0.002, 1.0)
		var decay: float = exp(-progress * 6.5)
		var click: float = randf_range(-1.0, 1.0) * exp(-t * 160.0) * 0.35
		samples[i] = clampf((sin(phase) * 0.5 + lpf * 0.5) * attack * decay * 1.1 + click, -1.0, 1.0)
	return _create_wav(samples)


## Bump: low soft "boop", clearly different from the death thud.
func _create_bump_clip() -> AudioStreamWAV:
	var duration := 0.1
	var count := int(duration * SAMPLE_RATE)
	var samples := PackedFloat32Array()
	samples.resize(count)
	var phase: float = 0.0
	for i in range(count):
		var t := float(i) / SAMPLE_RATE
		var progress := t / duration
		var freq: float = 190.0 - 100.0 * progress
		phase += 2.0 * PI * freq / SAMPLE_RATE
		var attack: float = minf(t / 0.004, 1.0)
		var decay: float = exp(-progress * 7.0)
		samples[i] = sin(phase) * attack * decay * 0.9
	return _create_wav(samples)


## Whoosh: airy noise sweep used for near-misses and speed lines.
func _create_whoosh_clip() -> AudioStreamWAV:
	var duration := 0.2
	var count := int(duration * SAMPLE_RATE)
	var samples := PackedFloat32Array()
	samples.resize(count)
	var lpf_a: float = 0.0
	var lpf_b: float = 0.0
	for i in range(count):
		var t := float(i) / SAMPLE_RATE
		var progress := t / duration
		var cutoff: float = 0.04 + 0.30 * (1.0 - progress)
		lpf_a += cutoff * (randf_range(-1.0, 1.0) - lpf_a)
		lpf_b += 0.08 * (lpf_a - lpf_b)
		var envelope: float = sin(PI * progress)
		samples[i] = (lpf_a - lpf_b) * envelope * 1.5
	return _create_wav(samples)


## Trap warning: a soft, low two-note chime. Informative, never an alarm.
func _create_warn_clip() -> AudioStreamWAV:
	var duration := 0.5
	var count := int(duration * SAMPLE_RATE)
	var samples := PackedFloat32Array()
	samples.resize(count)
	var notes := [{"freq": 470.0, "start": 0.0}, {"freq": 392.0, "start": 0.16}]
	for i in range(count):
		var t := float(i) / SAMPLE_RATE
		var acc: float = 0.0
		for note in notes:
			var start := float(note["start"])
			if t >= start and t < start + 0.22:
				var note_t: float = t - start
				var attack: float = minf(note_t / 0.012, 1.0)
				var decay: float = exp(-note_t * 7.0)
				acc += sin(2.0 * PI * float(note["freq"]) * note_t) * attack * decay * 0.14
		# A very quiet low bed keeps the cue grounded without sounding harsh.
		acc += sin(2.0 * PI * 120.0 * t) * exp(-t * 6.0) * 0.05
		samples[i] = acc
	return _create_wav(samples)


## Streak milestone: short rising two-note cue (a fifth), soft but celebratory.
func _create_streak_clip() -> AudioStreamWAV:
	var duration := 0.34
	var count := int(duration * SAMPLE_RATE)
	var samples := PackedFloat32Array()
	samples.resize(count)
	var notes := [{"freq": 660.0, "start": 0.0}, {"freq": 990.0, "start": 0.1}]
	for i in range(count):
		var t := float(i) / SAMPLE_RATE
		var acc: float = 0.0
		for note in notes:
			var start := float(note["start"])
			if t >= start:
				var note_t: float = t - start
				var attack: float = minf(note_t / 0.006, 1.0)
				var decay: float = exp(-note_t * 5.0)
				var f := float(note["freq"])
				acc += (sin(2.0 * PI * f * note_t) + sin(2.0 * PI * f * 2.0 * note_t) * 0.25) \
					* attack * decay * 0.22
		samples[i] = clampf(acc, -1.0, 1.0)
	return _create_wav(samples)


## Broken combo: soft descending blip.
func _create_combo_lost_clip() -> AudioStreamWAV:
	var duration := 0.18
	var count := int(duration * SAMPLE_RATE)
	var samples := PackedFloat32Array()
	samples.resize(count)
	var phase: float = 0.0
	for i in range(count):
		var t := float(i) / SAMPLE_RATE
		var progress := t / duration
		var freq: float = 520.0 - 220.0 * progress
		phase += 2.0 * PI * freq / SAMPLE_RATE
		var attack: float = minf(t / 0.005, 1.0)
		var decay: float = exp(-progress * 5.0)
		samples[i] = sin(phase) * attack * decay * 0.32
	return _create_wav(samples)


## Spike hit: metallic clang from inharmonic partials plus a noise click.
func _create_hit_spike_clip() -> AudioStreamWAV:
	var duration := 0.3
	var count := int(duration * SAMPLE_RATE)
	var samples := PackedFloat32Array()
	samples.resize(count)
	var partials := [520.0, 830.0, 1310.0, 2100.0]
	for i in range(count):
		var t := float(i) / SAMPLE_RATE
		var acc: float = 0.0
		for p in range(partials.size()):
			var decay: float = exp(-t * (7.0 + float(p) * 3.5))
			acc += sin(2.0 * PI * partials[p] * t) * decay * (0.30 / (1.0 + float(p) * 0.6))
		var click: float = randf_range(-1.0, 1.0) * exp(-t * 90.0) * 0.5
		samples[i] = clampf(acc + click, -1.0, 1.0)
	return _create_wav(samples)


## Saw hit: descending buzz with tremolo and grit.
func _create_hit_saw_clip() -> AudioStreamWAV:
	var duration := 0.32
	var count := int(duration * SAMPLE_RATE)
	var samples := PackedFloat32Array()
	samples.resize(count)
	var phase: float = 0.0
	for i in range(count):
		var t := float(i) / SAMPLE_RATE
		var progress := t / duration
		var freq: float = 150.0 - 95.0 * progress
		phase += 2.0 * PI * freq / SAMPLE_RATE
		var square: float = 1.0 if sin(phase) > 0.0 else -1.0
		var grit: float = randf_range(-0.3, 0.3)
		var tremolo: float = 0.75 + 0.25 * sin(2.0 * PI * 28.0 * t)
		var attack: float = minf(t / 0.004, 1.0)
		var decay: float = exp(-progress * 4.5)
		samples[i] = (square * 0.55 + grit) * tremolo * attack * decay
	return _create_wav(samples)


## Cloud hit: electric zap with fast noise bursts.
func _create_hit_cloud_clip() -> AudioStreamWAV:
	var duration := 0.24
	var count := int(duration * SAMPLE_RATE)
	var samples := PackedFloat32Array()
	samples.resize(count)
	var lpf: float = 0.0
	for i in range(count):
		var t := float(i) / SAMPLE_RATE
		var progress := t / duration
		var noise: float = randf_range(-1.0, 1.0)
		lpf += 0.12 * (noise - lpf)
		var crackle: float = (noise - lpf) * (0.6 + 0.4 * sin(2.0 * PI * 55.0 * t))
		var zap: float = sin(2.0 * PI * (1400.0 - 900.0 * progress) * t) * exp(-t * 16.0) * 0.25
		var attack: float = minf(t / 0.002, 1.0)
		samples[i] = clampf((crackle * 0.9 + zap) * attack * exp(-progress * 3.0), -1.0, 1.0)
	return _create_wav(samples)


## Ceiling hit: sharp snick over a short low thud.
func _create_hit_ceil_clip() -> AudioStreamWAV:
	var duration := 0.16
	var count := int(duration * SAMPLE_RATE)
	var samples := PackedFloat32Array()
	samples.resize(count)
	for i in range(count):
		var t := float(i) / SAMPLE_RATE
		var snick: float = sin(2.0 * PI * 1850.0 * t) * exp(-t * 80.0) * 0.4
		var thud: float = sin(2.0 * PI * 130.0 * t) * exp(-t * 22.0) * 0.5
		samples[i] = clampf(snick + thud, -1.0, 1.0)
	return _create_wav(samples)


## Coin pickup: two quick bright sine pings a fifth apart, very short decay.
func _create_coin_clip() -> AudioStreamWAV:
	var duration := 0.1
	var count := int(duration * SAMPLE_RATE)
	var samples := PackedFloat32Array()
	samples.resize(count)
	for i in range(count):
		var t := float(i) / SAMPLE_RATE
		var attack: float = minf(t / 0.002, 1.0)
		var ping_a: float = sin(2.0 * PI * 1490.0 * t) * exp(-t * 55.0)
		var ping_b: float = sin(2.0 * PI * 2230.0 * t) * exp(-t * 48.0) * 0.6
		samples[i] = clampf((ping_a + ping_b) * attack, -1.0, 1.0)
	return _create_wav(samples)


## Result count-up tick.
func _create_count_clip() -> AudioStreamWAV:
	var duration := 0.035
	var count := int(duration * SAMPLE_RATE)
	var samples := PackedFloat32Array()
	samples.resize(count)
	for i in range(count):
		var t := float(i) / SAMPLE_RATE
		var attack: float = minf(t / 0.002, 1.0)
		var decay: float = exp(-t * 60.0)
		samples[i] = sin(2.0 * PI * 920.0 * t) * attack * decay * 0.6
	return _create_wav(samples)
