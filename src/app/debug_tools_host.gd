class_name DebugToolsHost
extends Node

const DebugActionConsoleScript := preload("res://src/presentation/debug_action_console.gd")

signal status_changed(message: String, failed: bool)

var _controller: GameSessionController
var _content_provider: Callable
var _dialog: DebugToolsDialog
var _console: PanelContainer
var _noclip: bool = false
var _recent_auto_actions: Array[String] = []
var _action_lines: Array[String] = []
var _console_shortcut_enabled: bool = true


func bind(controller: GameSessionController, overlay: Control, content_provider: Callable) -> void:
	_controller = controller
	_content_provider = content_provider
	if not OS.is_debug_build():
		return
	_dialog = DebugToolsDialog.new()
	overlay.add_child(_dialog)
	_console = DebugActionConsoleScript.new()
	overlay.add_child(_console)
	_controller.step_committed.connect(_record_step)
	_dialog.command_requested.connect(_submit)
	_dialog.noclip_changed.connect(func(enabled: bool) -> void:
		_noclip = enabled
		_dialog.show_result("No clip enabled." if enabled else "No clip disabled.", false)
	)
	_dialog.console_requested.connect(_open_console)
	_dialog.console_shortcut_changed.connect(func(enabled: bool) -> void: _console_shortcut_enabled = enabled)
	_console.close_requested.connect(_console.close_console)
	_console.clear_requested.connect(func() -> void: _action_lines.clear(); _console.set_lines(_action_lines))


func handle_input(event: InputEvent) -> bool:
	if _dialog == null:
		return false
	if _console_shortcut_enabled and event.is_action_pressed(&"realmz_debug_console"):
		if _console.visible: _console.close_console()
		else: _open_console()
		return true
	if not event.is_action_pressed(&"realmz_debug_tools"):
		return false
	if _dialog.visible:
		_dialog.close_dialog()
	else:
		if _console.visible: _console.close_console()
		_dialog.present(_controller.view(), _map_records(), _noclip, _recent_auto_actions, _console_shortcut_enabled)
	return true


func is_open() -> bool:
	return _dialog != null and (_dialog.visible or _console != null and _console.visible)


func noclip_step(intent: PlayerIntent) -> SessionStep:
	if not _noclip or intent == null or intent.kind != PlayerIntent.Kind.MOVE:
		return null
	var view := _controller.view()
	if view == null or view.party_setup_available or view.pending_interaction != null or view.combat_view != null:
		return null
	var direction := (intent.payload as PlayerIntent.MovePayload).direction
	# Held no-clip movement is a quiet adjacent debug transaction. Repainting a
	# success message on every square made the presentation scheduler stutter.
	return _controller.apply_debug_command(SessionDebugCommand.noclip_step(direction))


func _submit(command: SessionDebugCommand) -> SessionStep:
	var step := _controller.apply_debug_command(command)
	var failed := step.state == SessionStep.State.FAILED
	var message := step.error_message if failed else _success_message(command)
	status_changed.emit(message, failed)
	if _dialog != null:
		_dialog.show_result(message, failed)
		if not failed and command.kind in [SessionDebugCommand.Kind.START_ENCOUNTER, SessionDebugCommand.Kind.START_BATTLE, SessionDebugCommand.Kind.WIN_BATTLE]:
			_dialog.close_dialog()
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
	var view := _controller.view()
	var content: RealmzContent = _content_provider.call() if _content_provider.is_valid() else null
	_action_lines.append_array(action_lines(step.events, view, content))
	while _action_lines.size() > 2000:
		_action_lines.pop_front()
	_recent_auto_actions.append_array(auto_action_lines(step.events, view, content))
	while _recent_auto_actions.size() > 40:
		_recent_auto_actions.pop_front()
	if _dialog != null and _dialog.visible:
		_dialog.set_auto_actions(_recent_auto_actions)
	if _console != null and _console.visible:
		_console.set_lines(_action_lines)


func _open_console() -> void:
	_dialog.close_dialog()
	_console.present(_action_lines)


static func action_lines(events: Array[DomainEvent], view: GameView = null, content: RealmzContent = null) -> Array[String]:
	var result: Array[String] = []
	for event: DomainEvent in events:
		var readable := _readable_event_line(event, view, content)
		if not readable.is_empty():
			result.append(readable)
			continue
		var payload := JSON.stringify(event.payload)
		result.append("[EVENT] %s%s" % [String(event.kind), " · " + payload if payload != "{}" else ""])
	return result


static func _readable_event_line(event: DomainEvent, view: GameView, content: RealmzContent) -> String:
	var actor_id := String(event.payload.get("actorId", ""))
	var target_id := String(event.payload.get("targetId", ""))
	var actor_name := _actor_name(view, actor_id)
	var target_name := _actor_name(view, target_id)
	match event.kind:
		&"combat_auto_started":
			return "── %s · Auto Turn ──" % actor_name
		&"combat_auto_completed":
			return "[COMBAT] %s finished Auto Turn (%d actions)." % [actor_name, int(event.payload.get("operations", 0))]
		&"combat_auto_choice_rejected":
			return "[COMBAT] %s could not %s: %s" % [actor_name, String(event.payload.get("action", "act")).replace("_", " "), String(event.payload.get("message", event.payload.get("reason", "unavailable")))]
		&"combatant_moved":
			var destination: Array = event.payload.get("to", [])
			return "[COMBAT] %s moved to %d,%d." % [actor_name, int(destination[0]), int(destination[1])] if destination.size() == 2 else "[COMBAT] %s moved." % actor_name
		&"combat_attack_resolved", &"combat_projectile_resolved":
			var action := String(event.payload.get("action", "attack")).replace("_", " ")
			if not bool(event.payload.get("hit", false)):
				return "[COMBAT] %s used %s on %s — miss." % [actor_name, action, target_name]
			var defeat := " — defeated" if bool(event.payload.get("defeated", false)) else ""
			return "[COMBAT] %s used %s on %s — %d damage%s." % [actor_name, action, target_name, int(event.payload.get("damage", 0)), defeat]
		&"combat_spell_cast":
			var spell := content.spell_by_id(String(event.payload.get("spellId", ""))) if content != null else null
			var spell_name := spell.name if spell != null else String(event.payload.get("spellName", event.payload.get("spellId", "Unknown spell")))
			return "[COMBAT] %s cast %s on %s." % [actor_name, spell_name, _spell_target_text(event, spell, view, actor_id)]
		&"combat_spell_resolved":
			var spell := content.spell_by_id(String(event.payload.get("spellId", ""))) if content != null else null
			var spell_name := spell.name if spell != null else String(event.payload.get("spellName", event.payload.get("spellId", "Spell")))
			var outcome := _spell_resolution_outcome(event.payload)
			return "[COMBAT] %s → %s: %s." % [spell_name, target_name if not target_id.is_empty() else _spell_target_text(event, spell, view, actor_id), outcome]
		&"combatant_guarded":
			return "[COMBAT] %s defended." % actor_name
		&"time_advanced":
			return "[TIME] +%d min · Day %d · %02d:%02d" % [int(event.payload.get("minutes", 0)), int(event.payload.get("day", 0)), int(event.payload.get("hour", 0)), int(event.payload.get("minute", 0))]
	return ""


static func _spell_resolution_outcome(payload: Dictionary) -> String:
	if bool(payload.get("resisted", false)):
		return "resisted"
	if bool(payload.get("saved", false)):
		return "saved"
	var detected_count := int(payload.get("detectedMagicItemCount", 0))
	if detected_count > 0:
		return "%d magical item%s detected" % [detected_count, "" if detected_count == 1 else "s"]
	var healing := int(payload.get("healing", 0))
	if healing > 0:
		return "%d healing" % healing
	var damage := int(payload.get("damage", 0))
	if damage > 0:
		return "%d damage" % damage
	if payload.has("appliedCondition") or payload.has("partyCondition"):
		return "condition applied"
	if int(payload.get("clearedConditionCount", 0)) > 0 or payload.has("clearedCondition"):
		return "condition cleared"
	if int(payload.get("spellPointDelta", 0)) != 0:
		return "spell points changed"
	if payload.has("transformedDefinitionAfter"):
		return "transformed"
	if bool(payload.get("allegianceChanged", false)) or payload.has("traitorAfter"):
		return "allegiance changed"
	if not String(payload.get("specialResult", "")).is_empty():
		return String(payload.get("specialResult")).replace("_", " ")
	if int(payload.get("duration", 0)) > 0:
		return "effect applied"
	return "no effect"


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
		SessionDebugCommand.Kind.NOCLIP_STEP: return "No-clip step committed."
		SessionDebugCommand.Kind.RESTORE_PARTY: return "Party HP, SP, and harmful conditions restored."
		SessionDebugCommand.Kind.START_ENCOUNTER: return "%s Encounter %d triggered." % [String(command.encounter_kind).capitalize(), command.classic_id]
		SessionDebugCommand.Kind.START_BATTLE: return "Battle %d triggered." % command.classic_id
		SessionDebugCommand.Kind.WIN_BATTLE: return "Battle victory committed through normal rewards."
	return "Debug command committed."
