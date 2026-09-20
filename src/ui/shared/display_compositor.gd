## Retains the application viewport while presentation scale and window size change.
class_name DisplayCompositor
extends Control

signal geometry_changed

@onready var _content: SubViewport = %Content
@onready var _filter_pass: SubViewport = %FilterPass
@onready var _filter_input: TextureRect = %FilterInput
@onready var _screen: TextureRect = %Screen

var _mode: String = PresentationSettings.DISPLAY_RESPONSIVE
var _smoothing: String = PresentationSettings.SMOOTHING_OFF
var _crt_enabled: bool = false
var _crt_shader: String = PresentationSettings.CRT_PI
var _crt_area: String = PresentationSettings.CRT_WORLD
var _geometry: Dictionary = {}
var _input_forwarder := DisplayInputForwarder.new()
var _filter_presenter := DisplayFilterPresenter.new()
var _world_region: Rect2
var _world_zoom: int = 1


func _ready() -> void:
	_screen.texture = _content.get_texture()
	_filter_input.texture = _content.get_texture()
	resized.connect(_apply_geometry)
	_apply_geometry()


func configure(mode: String, smoothing: String, crt_enabled: bool = false, crt_shader: String = PresentationSettings.CRT_PI, crt_area: String = PresentationSettings.CRT_WORLD) -> void:
	_mode = mode
	_smoothing = smoothing
	_crt_enabled = crt_enabled
	_crt_shader = crt_shader
	_crt_area = crt_area
	if is_node_ready():
		_apply_geometry()


func source_viewport() -> SubViewport:
	return _content


func geometry() -> Dictionary:
	return _geometry.duplicate()


func logical_to_window_rect(rect: Rect2) -> Rect2:
	var drawn: Rect2 = _geometry["screen_rect"]
	var factor: float = _geometry["scale"]
	return Rect2(drawn.position + rect.position * factor, rect.size * factor)


func set_world_region(region: Rect2, zoom: int) -> void:
	if _world_region == region and _world_zoom == clampi(zoom, 1, 4):
		return
	_world_region = region
	_world_zoom = clampi(zoom, 1, 4)
	_apply_filter()


func _apply_geometry() -> void:
	_geometry = DisplayScalingPolicy.geometry(Vector2i(size.round()), _mode)
	_content.size = _geometry["source_size"]
	var rect: Rect2 = _geometry["screen_rect"]
	_screen.position = rect.position
	_screen.size = rect.size
	_filter_pass.size = Vector2i(rect.size.round())
	_apply_filter()
	geometry_changed.emit()


func _apply_filter() -> void:
	_filter_presenter.apply(_screen, _content, _filter_pass, _filter_input, _smoothing, _crt_enabled, _crt_shader, _crt_area, _geometry, _world_region, _world_zoom)


func _input(event: InputEvent) -> void:
	if _input_forwarder.forward(event, _content, _geometry):
		get_viewport().set_input_as_handled()
