class_name DebugToolsHost
extends Node

signal status_changed(message: String, failed: bool)

var _controller: GameSessionController
var _content_provider: Callable
var _dialog: DebugToolsDialog
var _noclip: bool = false


func bind(controller: GameSessionController, overlay: Control, content_provider: Callable) -> void:
	_controller = controller
	_content_provider = content_provider
	if not OS.is_debug_build():
		return
	_dialog = DebugToolsDialog.new()
	overlay.add_child(_dialog)
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
		_dialog.present(_controller.view(), _map_records(), _noclip)
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


static func _success_message(command: SessionDebugCommand) -> String:
	match command.kind:
		SessionDebugCommand.Kind.WARP: return "Warped to %s at %d,%d." % [command.map_id, command.coordinate.x, command.coordinate.y]
		SessionDebugCommand.Kind.RESTORE_PARTY: return "Party HP, SP, and harmful conditions restored."
		SessionDebugCommand.Kind.START_ENCOUNTER: return "%s Encounter %d triggered." % [String(command.encounter_kind).capitalize(), command.classic_id]
		SessionDebugCommand.Kind.START_BATTLE: return "Battle %d triggered." % command.classic_id
		SessionDebugCommand.Kind.WIN_BATTLE: return "Battle victory committed through normal rewards."
	return "Debug command committed."
