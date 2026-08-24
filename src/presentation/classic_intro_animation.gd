class_name ClassicIntroAnimation
extends VideoStreamPlayer

const INTRO_STREAM_PATH := "res://src/presentation/assets/ui/intro/rebuilt-intro.ogv"
const INTRO_SOUNDTRACK_PATH := "res://src/presentation/assets/ui/intro/rebuilt-intro-soundtrack.mp3"

var audio_enabled: bool = false
var _master_volume: float = 1.0
var _soundtrack: AudioStreamPlayer


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	expand = true
	autoplay = false
	loop = true
	tooltip_text = "Click to turn intro audio on"
	_apply_audio_volume()


func _ready() -> void:
	_ensure_soundtrack_player()
	activate()


func activate() -> void:
	_ensure_soundtrack_player()
	if stream == null:
		stream = ResourceLoader.load(INTRO_STREAM_PATH, "VideoStream", ResourceLoader.CACHE_MODE_IGNORE) as VideoStream
	_load_soundtrack()
	if is_inside_tree() and stream != null and not is_playing():
		play()
	if is_inside_tree() and audio_enabled and _soundtrack.stream != null and not _soundtrack.playing:
		_soundtrack.play()


func deactivate() -> void:
	stop()
	stream = null
	if _soundtrack != null:
		_soundtrack.stop()
		_soundtrack.stream = null


func set_master_volume(value: float) -> void:
	_master_volume = clampf(value, 0.0, 1.0)
	_apply_audio_volume()


func toggle_audio() -> void:
	audio_enabled = not audio_enabled
	tooltip_text = "Click to mute intro audio" if audio_enabled else "Click to turn intro audio on"
	_ensure_soundtrack_player()
	_load_soundtrack()
	if audio_enabled and is_inside_tree() and _soundtrack.stream != null and not _soundtrack.playing:
		_soundtrack.play()
	_apply_audio_volume()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		toggle_audio()
		accept_event()


func _apply_audio_volume() -> void:
	volume_db = -80.0
	if _soundtrack == null:
		return
	var value := _master_volume if audio_enabled else 0.0
	_soundtrack.volume_db = -80.0 if value <= 0.0 else linear_to_db(value)


func _ensure_soundtrack_player() -> void:
	if _soundtrack != null:
		return
	_soundtrack = AudioStreamPlayer.new()
	_soundtrack.name = "RealmzIntroSoundtrack"
	_soundtrack.autoplay = false
	add_child(_soundtrack)
	_apply_audio_volume()


func _load_soundtrack() -> void:
	_ensure_soundtrack_player()
	if _soundtrack.stream != null:
		return
	var soundtrack := ResourceLoader.load(INTRO_SOUNDTRACK_PATH, "AudioStream", ResourceLoader.CACHE_MODE_IGNORE) as AudioStreamMP3
	if soundtrack == null:
		return
	soundtrack.loop = true
	_soundtrack.stream = soundtrack
