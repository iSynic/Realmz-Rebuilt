class_name ClassicIntroAnimation
extends VideoStreamPlayer

const INTRO_STREAM := preload("res://src/presentation/assets/ui/intro/rebuilt-intro.ogv")


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	expand = true
	stream = INTRO_STREAM
	autoplay = true
	loop = true


func _ready() -> void:
	if not is_playing():
		play()
