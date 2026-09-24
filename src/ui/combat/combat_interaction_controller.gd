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
signal move_to_requested
signal spellbook_requested(actor_id: String, options: Array[InteractionRequestValue.CastOption])
signal spellbook_closed
signal items_requested
signal inventory_targeting_started
signal layout_changed


var _component: BattleInteraction
var _dock: FastSpellDock
var _dock_host: Node
var _dock_scene: PackedScene
var _stage_rect := Rect2()
var _spellbook_open := false
var _weapon_aim_body: CombatRequestBody
var _weapon_aim_mode: StringName
var _weapon_preparation: StringName
var _weapon_ability_body: CombatRequestBody
var _weapon_ability_id := ""
var inspector: CombatInspectionCard


func configure(dock_host: Node, dock_scene: PackedScene) -> void:
	assert(dock_host != null, "Combat interaction requires a Fast Spell dock host.")
	assert(dock_scene != null, "Combat interaction requires the authored Fast Spell dock scene.")
	_dock_host = dock_host
	_dock_scene = dock_scene


func bind(component: BattleInteraction, body: CombatRequestBody, game_view: GameView, media: ClassicMediaCatalog) -> void:
	assert(component != null, "Combat interaction requires a battle component.")
	_component = component
	_component.inspection_requested.connect(func(combatant: InteractionRequestValue.Combatant, pinned: bool) -> void:
		inspector.present(combatant, pinned)
	)
	_component.weapon_aim_requested.connect(func(mode: StringName, preparation: StringName) -> void:
		_weapon_aim_body = body
		_weapon_aim_mode = mode
		_weapon_preparation = preparation
	)
	_component.weapon_ability_prepared.connect(func(instance_id: String) -> void:
		_weapon_ability_body = body
		_weapon_ability_id = instance_id
	)
	_component.combat_targeting_requested.connect(func(request: CombatTargetingRequest) -> void: targeting_requested.emit(request))
	_component.combat_targeting_confirm_requested.connect(func() -> void: targeting_confirm_requested.emit())
	_component.combat_targeting_cancel_requested.connect(func() -> void: targeting_cancel_requested.emit())
	_component.combat_targeting_rotate_requested.connect(func() -> void: targeting_rotate_requested.emit())
	_component.combatant_focus_requested.connect(func(combatant_id: String, play_sound: bool) -> void: combatant_focus_requested.emit(combatant_id, play_sound))
	_component.reveal_friends_requested.connect(func() -> void: reveal_friends_requested.emit())
	_component.move_to_requested.connect(func() -> void: move_to_requested.emit())
	_component.combat_spellbook_requested.connect(func(actor_id: String, options: Array[InteractionRequestValue.CastOption]) -> void: spellbook_requested.emit(actor_id, options))
	_component.combat_spellbook_closed.connect(func() -> void: spellbook_closed.emit())
	_component.combat_items_requested.connect(func() -> void: items_requested.emit())
	_component.combat_inventory_targeting_started.connect(func() -> void: inventory_targeting_started.emit())
	_mount_fast_spell_dock(body, InteractionComponentFactory.fast_spell_animation_frames(game_view, media, body.fast_spells) if body != null else {})
	var previous := _weapon_aim_body
	var mode := _weapon_aim_mode
	var preparation := _weapon_preparation
	_weapon_aim_body = null
	if previous != null and body != null and previous.battle_id == body.battle_id and previous.round_number == body.round_number and previous.actor_id == body.actor_id and body.weapon_mode == mode and (preparation != &"prepare_projectile" or not body.actions.has("prepare_projectile")):
		_resume_weapon_aim.call_deferred(component, mode)
	var ability_previous := _weapon_ability_body
	var ability_id := _weapon_ability_id
	_weapon_ability_body = null
	if ability_previous != null and body != null and ability_previous.battle_id == body.battle_id and ability_previous.round_number == body.round_number and ability_previous.actor_id == body.actor_id:
		for option: InteractionRequestValue.CastOption in body.item_casts:
			if option.item_instance_id == ability_id and option.target_mode != &"random_power":
				_resume_weapon_ability.call_deferred(component, ability_id)
				break


func _resume_weapon_ability(component: BattleInteraction, instance_id: String) -> void:
	if is_instance_valid(component) and component == _component:
		component.open_item_from_inventory(instance_id, false, false)


func _resume_weapon_aim(component: BattleInteraction, mode: StringName) -> void:
	if is_instance_valid(component) and component == _component:
		component.aim_weapon(mode)


func clear(preserve_weapon_aim: bool = false) -> void:
	if not preserve_weapon_aim:
		_weapon_aim_body = null
		_weapon_ability_body = null
	_component = null
	if is_instance_valid(inspector):
		inspector.queue_free()
	inspector = null
	_spellbook_open = false
	spellbook_closed.emit()
	_close_fast_spell_dock()


func release() -> void:
	_weapon_aim_body = null
	_weapon_ability_body = null
	_component = null
	if is_instance_valid(inspector):
		inspector.queue_free()
	inspector = null
	_spellbook_open = false
	if is_instance_valid(_dock):
		_dock.queue_free()
	_dock = null
	_dock_host = null


func set_stage_rect(stage_rect: Rect2) -> void:
	_stage_rect = stage_rect
	if inspector != null:
		inspector.set_stage_rect(stage_rect)
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
	return _component != null and _component.accepts_spatial_input() and (inspector == null or not inspector.visible)


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


func open_combatant_inspection(combatant_id: String, pinned: bool = true) -> bool:
	return _component != null and _component.open_combatant_inspection(combatant_id, pinned)


func update_targeting(selection: CombatTargetingState) -> void:
	if _component != null:
		_component.update_battlefield_targeting(selection)


func targeting_cancelled() -> void:
	if _component != null:
		_component.battlefield_targeting_cancelled()


func cast_spell(option: InteractionRequestValue.CastOption) -> void:
	if _component != null:
		_component.cast_spell_option(option)


func open_item_from_inventory(instance_id: String, open_scrolls: bool = false) -> bool:
	return _component != null and _component.open_item_from_inventory(instance_id, open_scrolls)


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
	if is_instance_valid(inspector):
		inspector.queue_free()
	inspector = (load("res://src/ui/combat/combat_inspection_card.tscn") as PackedScene).instantiate() as CombatInspectionCard
	_dock_host.add_child(inspector)
	inspector.set_stage_rect(_stage_rect)


func _close_fast_spell_dock() -> void:
	if _dock == null:
		return
	var parent := _dock.get_parent()
	if parent != null:
		parent.remove_child(_dock)
	_dock.queue_free()
	_dock = null
