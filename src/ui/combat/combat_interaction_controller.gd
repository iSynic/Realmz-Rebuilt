## Binds combat-only interaction commands and the Fast Spell dock.

class_name CombatInteractionController
extends RefCounted


signal response_body_submitted(body: InteractionResponse.CombatBody)
signal targeting_requested(request: CombatTargetingRequest)
signal targeting_confirm_requested
signal targeting_cancel_requested
signal targeting_rotate_requested
signal combatant_focus_requested(combatant_id: String, play_sound: bool)
signal reveal_friends_requested
signal spellbook_requested(actor_id: String, options: Array[InteractionRequestValue.CastOption])
signal spellbook_closed
signal layout_changed


var _component: BattleInteraction
var _dock: FastSpellDock
var _dock_host: Node
var _dock_scene: PackedScene
var _stage_rect := Rect2()
var _spellbook_open := false


func configure(dock_host: Node, dock_scene: PackedScene) -> void:
	assert(dock_host != null, "Combat interaction requires a Fast Spell dock host.")
	assert(dock_scene != null, "Combat interaction requires the authored Fast Spell dock scene.")
	_dock_host = dock_host
	_dock_scene = dock_scene


func bind(component: BattleInteraction, body: CombatRequestBody, game_view: GameView, media: ClassicMediaCatalog) -> void:
	assert(component != null, "Combat interaction requires a battle component.")
	_component = component
	_component.combat_targeting_requested.connect(func(request: CombatTargetingRequest) -> void: targeting_requested.emit(request))
	_component.combat_targeting_confirm_requested.connect(func() -> void: targeting_confirm_requested.emit())
	_component.combat_targeting_cancel_requested.connect(func() -> void: targeting_cancel_requested.emit())
	_component.combat_targeting_rotate_requested.connect(func() -> void: targeting_rotate_requested.emit())
	_component.combatant_focus_requested.connect(func(combatant_id: String, play_sound: bool) -> void: combatant_focus_requested.emit(combatant_id, play_sound))
	_component.reveal_friends_requested.connect(func() -> void: reveal_friends_requested.emit())
	_component.combat_spellbook_requested.connect(func(actor_id: String, options: Array[InteractionRequestValue.CastOption]) -> void: spellbook_requested.emit(actor_id, options))
	_component.combat_spellbook_closed.connect(func() -> void: spellbook_closed.emit())
	_mount_fast_spell_dock(body, InteractionComponentFactory.fast_spell_animation_frames(game_view, media, body.fast_spells) if body != null else {})


func clear() -> void:
	_component = null
	_spellbook_open = false
	spellbook_closed.emit()
	_close_fast_spell_dock()


func release() -> void:
	_component = null
	_spellbook_open = false
	if is_instance_valid(_dock):
		_dock.queue_free()
	_dock = null
	_dock_host = null


func set_stage_rect(stage_rect: Rect2) -> void:
	_stage_rect = stage_rect
	if _dock != null:
		_dock.set_stage_rect(stage_rect)


func set_command_layout(scale: float, compact: bool) -> void:
	if _component != null:
		_component.set_command_layout(scale, compact)


func submit_body(body: InteractionResponse.CombatBody) -> bool:
	if _component == null:
		return false
	response_body_submitted.emit(body)
	return true


func accepts_spatial_input() -> bool:
	return _component != null and _component.accepts_spatial_input()


func handle_fast_spell(slot_index: int, use_spell: bool) -> bool:
	return _component != null and _component.handle_fast_spell(slot_index, use_spell)


func set_fast_spell_dock_held(held: bool) -> bool:
	return _dock != null and _dock.set_held(held)


func activate_fast_spell_from_dock(slot_index: int) -> bool:
	if _dock != null:
		_dock.set_held(false)
	return handle_fast_spell(slot_index, true)


func inspect_combatant(combatant_id: String) -> void:
	if _component != null:
		_component.inspect_combatant(combatant_id)


func open_combatant_inspection(combatant_id: String) -> bool:
	return _component != null and _component.open_combatant_inspection(combatant_id)


func update_targeting(selection: CombatTargetingState) -> void:
	if _component != null:
		_component.update_battlefield_targeting(selection)


func targeting_cancelled() -> void:
	if _component != null:
		_component.battlefield_targeting_cancelled()


func cast_spell(option: InteractionRequestValue.CastOption) -> void:
	if _component != null:
		_component.cast_spell_option(option)


func close_spellbook() -> void:
	if _component != null:
		_component.close_spellbook()


func set_spellbook_open(open: bool) -> void:
	if _spellbook_open == open:
		return
	_spellbook_open = open
	layout_changed.emit()


func is_spellbook_open() -> bool:
	return _spellbook_open


func _mount_fast_spell_dock(body: CombatRequestBody, animation_frames: Dictionary) -> void:
	_close_fast_spell_dock()
	if body == null:
		return
	_dock = _dock_scene.instantiate() as FastSpellDock
	_dock_host.add_child(_dock)
	_dock.configure(body.fast_spells, animation_frames)
	_dock.slot_activated.connect(activate_fast_spell_from_dock)
	_dock.set_stage_rect(_stage_rect)


func _close_fast_spell_dock() -> void:
	if _dock == null:
		return
	var parent := _dock.get_parent()
	if parent != null:
		parent.remove_child(_dock)
	_dock.queue_free()
	_dock = null
