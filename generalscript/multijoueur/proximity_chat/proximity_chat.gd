extends AudioStreamPlayer3D
class_name ProximityChat

## ====== Réglages (modifiables dans l'inspecteur) ======
@export var voice_threshold: float = 0.02      # seuil RMS : au-dessus, on considère que le joueur parle
@export var hangover_time: float = 0.25        # on continue d'envoyer un peu après être repassé sous le seuil (évite de couper les fins de mots)
@export var send_interval: float = 0.05        # 50 ms = ~20 paquets/seconde
@export var target_sample_rate: int = 16000    # largement suffisant pour de la voix, économise le débit
@export var mic_gain: float = 3.0

## ====== État partagé entre toutes les instances du jeu ======
static var mic_enabled: bool = true
static var _buses_ready: bool = false

const RECORD_BUS := "VoiceRecord"
const OUTPUT_BUS := "ProximityChatOut"
const CAPTURE_EFFECT_INDEX := 2  # ordre de création : highpass(0), lowpass(1), capture(2)

var _capture: AudioEffectCapture
var _mic_player: AudioStreamPlayer
var _playback: AudioStreamGeneratorPlayback
var _decimation: int = 1
var _send_timer: float = 0.0
var _hangover_timer: float = 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	ensure_audio_buses()
	_decimation = _compute_decimation()

	stream = AudioStreamGenerator.new()
	stream.mix_rate = float(AudioServer.get_mix_rate()) / float(_decimation)
	stream.buffer_length = 0.1
	bus = OUTPUT_BUS
	max_distance = 18.0   # portée du chat, à ajuster en jeu
	unit_size = 6.0        # courbe d'atténuation, à ajuster aussi

	if is_multiplayer_authority():
		_setup_microphone()
	else:
		play()
		_playback = get_stream_playback() as AudioStreamGeneratorPlayback


func _setup_microphone() -> void:
	_mic_player = AudioStreamPlayer.new()
	_mic_player.stream = AudioStreamMicrophone.new()
	_mic_player.bus = RECORD_BUS
	add_child(_mic_player)
	_mic_player.play()

	var idx := AudioServer.get_bus_index(RECORD_BUS)
	_capture = AudioServer.get_bus_effect(idx, CAPTURE_EFFECT_INDEX) as AudioEffectCapture


func _process(delta: float) -> void:
	if not is_multiplayer_authority() or _capture == null:
		return

	_send_timer += delta
	if _send_timer < send_interval:
		return
	_send_timer = 0.0

	var frames_available := _capture.get_frames_available()
	if frames_available <= 0:
		return
	
	
	
	# On vide toujours le buffer (même si on n'envoie pas), pour ne jamais accumuler de retard
	var buffer := _capture.get_buffer(frames_available)
	
	if mic_gain != 1.0:
		for i in range(buffer.size()):
			buffer[i] = buffer[i] * mic_gain

	var sum := 0.0
	for v in buffer:
		sum += v.x * v.x
	var rms := sqrt(sum / buffer.size())

	if rms >= voice_threshold:
		_hangover_timer = hangover_time
	else:
		_hangover_timer -= send_interval

	if mic_enabled and _hangover_timer > 0.0:
		_receive_voice.rpc(_encode_buffer(buffer))


func _encode_buffer(buffer: PackedVector2Array) -> PackedByteArray:
	var count := buffer.size()
	var out_count := int(ceil(float(count) / float(_decimation)))
	var samples := PackedByteArray()
	samples.resize(out_count * 2)
	var out_index := 0
	var i := 0
	while i < count:
		var v: float = clamp(buffer[i].x, -1.0, 1.0)
		samples.encode_s16(out_index * 2, int(v * 32767.0))
		out_index += 1
		i += _decimation
	return samples


@rpc("authority", "call_remote", "unreliable_ordered")
func _receive_voice(data: PackedByteArray) -> void:
	if _playback == null:
		return
	var frame_count := data.size() / 2
	var frames := PackedVector2Array()
	frames.resize(frame_count)
	for i in range(frame_count):
		var f := float(data.decode_s16(i * 2)) / 32767.0
		frames[i] = Vector2(f, f)
	if _playback.can_push_buffer(frame_count):
		_playback.push_buffer(frames)


func _compute_decimation() -> int:
	return max(1, int(round(float(AudioServer.get_mix_rate()) / float(target_sample_rate))))


static func ensure_audio_buses() -> void:
	if _buses_ready:
		return
	_buses_ready = true

	if AudioServer.get_bus_index(RECORD_BUS) == -1:
		AudioServer.add_bus()
		var idx := AudioServer.bus_count - 1
		AudioServer.set_bus_name(idx, RECORD_BUS)
		AudioServer.set_bus_mute(idx, true)  # on ne s'entend jamais soi-même

		var hp := AudioEffectHighPassFilter.new()
		hp.cutoff_hz = 100.0
		AudioServer.add_bus_effect(idx, hp)

		var lp := AudioEffectLowPassFilter.new()
		lp.cutoff_hz = 7000.0  # coupe les aigus inutiles + anti-repliement avant sous-échantillonnage
		AudioServer.add_bus_effect(idx, lp)

		var cap := AudioEffectCapture.new()
		cap.buffer_length = 0.15
		AudioServer.add_bus_effect(idx, cap)

	if AudioServer.get_bus_index(OUTPUT_BUS) == -1:
		AudioServer.add_bus()
		var idx2 := AudioServer.bus_count - 1
		AudioServer.set_bus_name(idx2, OUTPUT_BUS)
		AudioServer.set_bus_send(idx2, "Master")
