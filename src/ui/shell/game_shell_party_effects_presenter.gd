## Animates and binds the shell's authored party-effect slots.
class_name GameShellPartyEffectsPresenter
extends RefCounted

const FRAME_SECONDS := 0.12

var _media: ClassicMediaCatalog
var _panel: PanelContainer
var _slots: Array[TextureRect] = []
var _texture_cache: Dictionary = {}
var _frame_index := 0
var _condition_values: Array[int] = []


func initialize(host: Node, grid: GridContainer, panel: PanelContainer, slot_scene: PackedScene) -> Array[TextureRect]:
	_panel = panel
	_slots = ClassicPartyEffects.build_slots(grid, slot_scene)
	var timer := Timer.new()
	timer.wait_time = FRAME_SECONDS
	timer.autostart = true
	timer.timeout.connect(_advance_frame)
	host.add_child(timer)
	return _slots


func set_media(media: ClassicMediaCatalog) -> void:
	if _media == media:
		return
	_media = media
	_texture_cache.clear()


func present(game_view: GameView) -> void:
	_condition_values = []
	if game_view != null and game_view.party_summary != null:
		_condition_values = game_view.party_summary.condition_values
	_panel.visible = game_view != null and game_view.session_started
	for slot_index: int in _slots.size():
		var active := _condition_values.size() > slot_index + 1 and _condition_values[slot_index + 1] != 0
		_slots[slot_index].texture = ClassicPartyEffects.texture(_media, _texture_cache, slot_index + 1, _frame_index) if active else null
		_slots[slot_index].modulate = Color.WHITE if active else Color(0.35, 0.35, 0.35, 0.35)


func _advance_frame() -> void:
	_frame_index = (_frame_index + 1) % ClassicPartyEffects.FRAME_COUNT
	for slot_index: int in _slots.size():
		if _condition_values.size() > slot_index + 1 and _condition_values[slot_index + 1] != 0:
			_slots[slot_index].texture = ClassicPartyEffects.texture(_media, _texture_cache, slot_index + 1, _frame_index)
