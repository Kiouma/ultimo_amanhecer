extends Node
## Efeitos sonoros (autoload "Sfx"), sintetizados por código: o projeto ainda não tem
## arquivos de áudio (GDD 15.3). Cada som é gerado uma vez (AudioStreamWAV) e tocado
## com posição no mundo (play) ou sem posição (play_ui).
## Para trocar por áudio de verdade depois: basta pôr o arquivo em SOUND_FILES.

const RATE := 22050
## Arquivos de áudio que substituem o som sintetizado (nome → caminho), quando existirem.
const SOUND_FILES := {}

var volume := 1.0:
	set(value):
		volume = clampf(value, 0.0, 1.0)
		AudioServer.set_bus_volume_db(0, linear_to_db(maxf(volume, 0.0001)))

var _cache := {}


## Toca `name` no ponto `at` (some com a distância).
func play(sound: String, at: Vector3, volume_db := 0.0, pitch_jitter := 0.08) -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	var player := AudioStreamPlayer3D.new()
	player.stream = _stream(sound)
	player.volume_db = volume_db
	player.unit_size = 6.0
	player.max_distance = 70.0
	player.pitch_scale = 1.0 + randf_range(-pitch_jitter, pitch_jitter)
	scene.add_child(player)
	player.global_position = at
	player.finished.connect(player.queue_free)
	player.play()


## Som sem posição (interface, coisas do próprio jogador).
func play_ui(sound: String, volume_db := 0.0) -> void:
	var player := AudioStreamPlayer.new()
	player.stream = _stream(sound)
	player.volume_db = volume_db
	add_child(player)
	player.finished.connect(player.queue_free)
	player.play()


func _stream(sound: String) -> AudioStream:
	if _cache.has(sound):
		return _cache[sound]
	var stream: AudioStream = null
	if SOUND_FILES.has(sound) and ResourceLoader.exists(SOUND_FILES[sound]):
		stream = load(SOUND_FILES[sound])
	else:
		stream = _synth(sound)
	_cache[sound] = stream
	return stream


# --- Síntese -------------------------------------------------------------------------

func _synth(sound: String) -> AudioStreamWAV:
	match sound:
		"bow": return _make(0.28, func(t: float, _r: float) -> float:
			return sin(TAU * lerpf(260.0, 110.0, t / 0.28) * t) * exp(-t * 14.0) * 0.7)
		"gunshot": return _make(0.35, func(t: float, r: float) -> float:
			return (r * exp(-t * 22.0) + sin(TAU * 70.0 * t) * exp(-t * 12.0)) * 0.9)
		"hit": return _make(0.1, func(t: float, r: float) -> float:
			return (r * 0.6 + sin(TAU * 140.0 * t) * 0.5) * exp(-t * 40.0))
		"swing": return _make(0.18, func(t: float, r: float) -> float:
			return r * sin(PI * t / 0.18) * 0.35)
		"groan": return _make(0.9, func(t: float, r: float) -> float:
			var f := 85.0 + sin(TAU * 5.0 * t) * 8.0 - t * 20.0
			var tone := sin(TAU * f * t) + 0.5 * sin(TAU * f * 2.0 * t) + 0.25 * sin(TAU * f * 3.0 * t)
			return (tone * 0.3 + r * 0.08) * sin(PI * t / 0.9))
		"explosion": return _make(1.2, func(t: float, r: float) -> float:
			return (r * 0.8 + sin(TAU * 45.0 * t) * 0.6) * exp(-t * 4.0))
		"spell": return _make(0.4, func(t: float, _r: float) -> float:
			return (sin(TAU * 660.0 * t) + sin(TAU * 990.0 * t) * 0.5 + sin(TAU * 1320.0 * t) * 0.25) * exp(-t * 7.0) * 0.35)
		"thunder": return _make(2.2, func(t: float, r: float) -> float:
			return r * exp(-t * 1.6) * (0.6 + 0.4 * sin(TAU * 3.0 * t)) * 0.9)
		"step": return _make(0.06, func(t: float, r: float) -> float:
			return r * exp(-t * 60.0) * 0.25)
		"build": return _make(0.25, func(t: float, r: float) -> float:
			var knock := exp(-t * 45.0) + (exp(-(t - 0.12) * 45.0) if t > 0.12 else 0.0)
			return (r * 0.4 + sin(TAU * 180.0 * t) * 0.6) * knock * 0.7)
		"pickup": return _make(0.12, func(t: float, _r: float) -> float:
			return sin(TAU * (880.0 if t < 0.06 else 1320.0) * t) * 0.3 * exp(-t * 10.0))
		"door": return _make(0.4, func(t: float, r: float) -> float:
			return (sin(TAU * (220.0 + 80.0 * sin(TAU * 7.0 * t)) * t) * 0.3 + r * 0.05) * sin(PI * t / 0.4))
	return _make(0.05, func(_t: float, _r: float) -> float: return 0.0)


## Gera um som de `seconds`: f(tempo, ruído aleatório -1..1) → amostra -1..1.
func _make(seconds: float, f: Callable) -> AudioStreamWAV:
	var count := int(seconds * RATE)
	var data := PackedByteArray()
	data.resize(count * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1234
	var smooth := 0.0
	for i in count:
		var t := float(i) / RATE
		# Ruído "marrom" leve (menos chiado que branco).
		smooth = lerpf(smooth, rng.randf_range(-1.0, 1.0), 0.35)
		var v := clampf(float(f.call(t, smooth * 1.6)), -1.0, 1.0)
		data.encode_s16(i * 2, int(v * 32000.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	wav.data = data
	return wav
