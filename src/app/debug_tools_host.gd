class_name DebugToolsHost
extends Node

signal status_changed(message: String, failed: bool)

var _controller: GameSessionController
var _content_provider: Callable
var _dialog: DebugToolsDialog
var _noclip: bool = false
var _recent_auto_actions: Array[String] = []


func bind(controller: GameSessionController, overlay: Control, content_provider: Callable) -> void:
	_controller = controller
	_content_provider = content_provider
	if not OS.is_debug_build():
		return
	_dialog = DebugToolsDialog.new()
	overlay.add_child(_dialog)
	_controller.step_committed.connect(_record_step)
	_dialog.command_requested.connect(_submit)
	_dialog.noclip_changed.connect(func(enabled: bool) -> void:
		_noclip = enabled
		_dialog.show_result("No clip enabled." if enabled else "No clip disabled.", false)
	)


func handle_input(event: InputEvent) -> bool:
	if _dialog == null or not event.is_action_pressed(&"realmz_debug_tools"):
		return false
	if _dialog.visible:
		_dialog.hide()
	else:
		_dialog.present(_controller.view(), _map_records(), _noclip, _recent_auto_actions)
	return true


func noclip_step(intent: PlayerIntent) -> SessionStep:
	if not _noclip or intent == null or intent.kind != PlayerIntent.Kind.MOVE:
		return null
	var view := _controller.view()
	if view == null or view.party_setup_available or view.pending_interaction != null or view.combat_view != null:
		return null
	var direction := (intent.payload as PlayerIntent.MovePayload).direction
	return _submit(SessionDebugCommand.warp(view.party_map_id, view.party_coordinate + direction))


func _submit(command: SessionDebugCommand) -> SessionStep:
	var step := _controller.apply_debug_command(command)
	var failed := step.state == SessionStep.State.FAILED
	var message := step.error_message if failed else _success_message(command)
	status_changed.emit(message, failed)
	if _dialog != null:
		_dialog.show_result(message, failed)
		if not failed and command.kind in [SessionDebugCommand.Kind.START_ENCOUNTER, SessionDebugCommand.Kind.START_BATTLE, SessionDebugCommand.Kind.WIN_BATTLE]:
			_dialog.hide()
	return step


func _map_records() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var content: RealmzContent = _content_provider.call() if _content_provider.is_valid() else null
	if content == null:
		return result
	for map_id: String in content.world.map_ids():
		var map := content.world.map_by_id(map_id)
		result.append({"id": map.id, "label": "%s %d · %s" % [String(map.level_type).capitalize(), map.level_index, map.name]})
	return result


func _record_step(step: SessionStep) -> void:
	_recent_auto_actions.append_array(auto_action_lines(step.events, _controller.view(), _content_provider.call() if _content_provider.is_valid() else null))
	while _recent_auto_actions.size() > 40:
		_recent_auto_actions.pop_front()
	if _dialog != null and _dialog.visible:
		_dialog.set_auto_actions(_recent_auto_actions)


static func auto_action_lines(events: Array[DomainEvent], view: GameView, content: RealmzContent) -> Array[String]:
	var result: Array[String] = []
	var auto_actor_ids: Dictionary = {}
	for event: DomainEvent in events:
		if event.kind == &"combat_auto_started":
			auto_actor_ids[String(event.payload.get("actorId", ""))] = true
	for event: DomainEvent in events:
		var actor_id := String(event.payload.get("actorId", ""))
		if not auto_actor_ids.has(actor_id):
			continue
		var actor_name := _actor_name(view, actor_id)
		match event.kind:
			&"combat_spell_cast":
				var spell := content.spell_by_id(String(event.payload.get("spellId", ""))) if content != null else null
				var spell_name := spell.name if spell != null else String(event.payload.get("spellId", "Unknown spell"))
				result.append("%s cast %s on %s." % [actor_name, spell_name, _spell_target_text(event, spell, view, actor_id)])
			&"combat_attack_resolved":
				var target_name := _actor_name(view, String(event.payload.get("targetId", "")))
				result.append("%s attacked %s for %d damage." % [actor_name, target_name, int(event.payload.get("damage", 0))] if bool(event.payload.get("hit", false)) else "%s missed %s." % [actor_name, target_name])
			&"combatant_moved":
				var destination: Array = event.payload.get("to", [])
				if destination.size() == 2:
					result.append("%s moved to %d,%d." % [actor_name, int(destination[0]), int(destination[1])])
			&"combatant_guarded":
				result.append("%s defended." % actor_name)
	return result


static func _spell_target_text(event: DomainEvent, spell: SpellDefinition, view: GameView, actor_id: String) -> String:
	if spell != null:
		match spell.target_type:
			9: return "all friends"
			10: return "all enemies"
			12: return "everybody"
			5: return _actor_name(view, actor_id)
	if event.payload.has("areaCenter"):
		var center: Array = event.payload.get("areaCenter", [])
		if center.size() == 2:
			return "area %d,%d" % [int(center[0]), int(center[1])]
	var target_id := String(event.payload.get("targetId", ""))
	return _actor_name(view, target_id) if not target_id.is_empty() else "its selected targets"


static func _actor_name(view: GameView, actor_id: String) -> String:
	if view != null:
		for character: CharacterView in view.party_members:
			if character.id == actor_id:
				return character.name
		for ally: MonsterView in view.party_allies:
			if ally.id == actor_id:
				return ally.name
		if view.combat_view != null:
			for monster: MonsterView in view.combat_view.monsters:
				if monster.id == actor_id:
					return monster.name
	return actor_id if not actor_id.is_empty() else "Unknown actor"


static func _success_message(command: SessionDebugCommand) -> String:
	match command.kind:
		SessionDebugCommand.Kind.WARP: return "Warped to %s at %d,%d." % [command.map_id, command.coordinate.x, command.coordinate.y]
		SessionDebugCommand.Kind.RESTORE_PARTY: return "Party HP, SP, and harmful conditions restored."
		SessionDebugCommand.Kind.START_ENCOUNTER: return "%s Encounter %d triggered." % [String(command.encounter_kind).capitalize(), command.classic_id]
		SessionDebugCommand.Kind.START_BATTLE: return "Battle %d triggered." % command.classic_id
		SessionDebugCommand.Kind.WIN_BATTLE: return "Battle victory committed through normal rewards."
	return "Debug command committed."
