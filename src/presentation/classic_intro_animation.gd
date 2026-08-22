class_name ClassicIntroAnimation
extends VideoStreamPlayer

const INTRO_STREAM := preload("res://src/presentation/assets/ui/intro/rebuilt-intro.ogv")

var audio_enabled: bool = false
var _master_volume: float = 1.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	expand = true
	stream = INTRO_STREAM
	autoplay = true
	loop = true
	tooltip_text = "Click to turn intro audio on"
	_apply_audio_volume()


func _ready() -> void:
	if not is_playing():
		play()


func set_master_volume(value: float) -> void:
	_master_volume = clampf(value, 0.0, 1.0)
	_apply_audio_volume()


func toggle_audio() -> void:
	audio_enabled = not audio_enabled
	tooltip_text = "Click to mute intro audio" if audio_enabled else "Click to turn intro audio on"
	_apply_audio_volume()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		toggle_audio()
		accept_event()


func _apply_audio_volume() -> void:
	var value := _master_volume if audio_enabled else 0.0
	volume_db = -80.0 if value <= 0.0 else linear_to_db(value)
