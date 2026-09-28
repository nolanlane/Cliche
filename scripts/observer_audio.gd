extends AudioStreamPlayer3D
## Positional breath and irregular dragging footfalls, synthesized without a music cue.
var playback: AudioStreamGeneratorPlayback
var presence := 0.0
var speed := 0.0
var hunting := false
var clock := 0.0
var stride := 0.0
var foot := 0.0
var low_noise := 0.0
var body_noise := 0.0
var gain := 0.0
var rng := RandomNumberGenerator.new()

func _ready() -> void:
	name = "BreathAndFootsteps"
	position.y = 1.4
	unit_size = 4.0
	max_distance = 26.0
	volume_db = -7.0
	var generator := AudioStreamGenerator.new()
	generator.mix_rate = 16000.0
	generator.buffer_length = 0.16
	stream = generator
	rng.randomize()
	play()
	playback = get_stream_playback() as AudioStreamGeneratorPlayback

func set_threat(amount: float, move_speed: float, is_hunting: bool) -> void:
	presence = amount
	speed = minf(move_speed, 5.0)
	hunting = is_hunting

func _process(_delta: float) -> void:
	if playback == null: return
	for _frame in range(playback.get_frames_available()):
		var dt := 1.0 / 16000.0
		clock += dt
		gain = move_toward(gain, presence * (0.80 if hunting else 0.32), dt * 2.0)
		var noise := rng.randf_range(-1.0, 1.0)
		low_noise = lerpf(low_noise, noise, 0.045)
		body_noise = lerpf(body_noise, noise, 0.23)
		var breath := pow(maxf(0.0, sin(clock * (3.2 if hunting else 1.45))), 2.4)
		var rasp := (body_noise - low_noise) * (0.24 + breath * 0.95)
		var throat := low_noise * (0.55 + 0.25 * sin(clock * 94.0)) * breath
		stride += dt * speed * 0.64
		if stride >= 1.0:
			stride -= 1.0
			foot = 1.0
		foot = maxf(0.0, foot - dt * 8.0)
		var contact := (low_noise * 1.2 + sin(clock * 310.0) * 0.12) * foot * foot
		var sample := clampf((rasp + throat + contact) * gain, -0.8, 0.8)
		playback.push_frame(Vector2(sample, sample))
