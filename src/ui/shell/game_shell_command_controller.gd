## Builds the exploration command deck and owns held-command presentation state.
class_name GameShellCommandController
extends RefCounted

const HELD_COMMAND_INTERVAL := 1.0 / 60.0
const HELD_COMMAND_START_SOUND_IDS: Dictionary = {&"area_search": 6001, &"rest": 6001}
const CONTEXTUAL_CONTROL_SOUND_ID := 141
const TORCH_BUTTON_SCRIPT := preload("res://src/ui/exploration/classic_torch_command_button.gd")
const SEARCH_BUTTON_SCRIPT := preload("res://src/ui/exploration/classic_search_command_button.gd")

var _owner_ref: WeakRef
var _buttons: Dictionary = {}
var _held_command: StringName = &""
var _timer: Timer


func _init(owner: Control) -> void:
	_owner_ref = weakref(owner)


func _owner():
	return _owner_ref.get_ref()


func initialize() -> void:
	_timer = Timer.new()
	_timer.wait_time = HELD_COMMAND_INTERVAL
	_timer.timeout.connect(_on_timeout)
	_owner().add_child(_timer)


func present(game_view: GameView) -> void:
	if not _held_command.is_empty() and (game_view == null or game_view.pending_interaction != null or not game_view.availability(_held_command).enabled):
		_stop_held_command()


func rebuild() -> void:
	var owner = _owner()
	if not owner.is_node_ready() or owner._profile == null:
		return
	for grid: GridContainer in [owner._world_command_grid, owner._command_grid]:
		for child: Node in grid.get_children():
			grid.remove_child(child)
			child.queue_free()
	_buttons.clear()
	var context: StringName = owner._navigator.current_screen()
	for definition: Dictionary in ClassicCommandCatalog.for_context(context):
		definition = presentation_definition(definition)
		var button := _build_button(definition)
		button.set_meta("focus_key", "command:%s" % definition["id"])
		var group := StringName(definition.get("group", &"party"))
		var target_grid: GridContainer = owner._world_command_grid if group == &"world" and owner._world_command_panel.visible else owner._command_grid
		target_grid.add_child(button)
		_buttons[StringName(definition["id"])] = button
	update_availability()


func _build_button(definition: Dictionary) -> BaseButton:
	var owner = _owner()
	if bool(definition.get("search_animation", false)):
		var search_button := SEARCH_BUTTON_SCRIPT.new() as BaseButton
		search_button.command_requested.connect(activate)
		search_button.set_meta("search_animation", true)
		return search_button
	if bool(definition.get("torch_meter", false)):
		var torch_button := TORCH_BUTTON_SCRIPT.new() as BaseButton
		torch_button.command_requested.connect(activate)
		torch_button.set_meta("torch_meter", true)
		return torch_button
	var bitmap := ClassicBitmapButton.new()
	bitmap.configure(definition, owner._profile.bitmap_scale)
	if bool(definition.get("hold_repeat", false)):
		bitmap.button_down.connect(_begin_held_command.bind(StringName(definition["id"])))
		bitmap.button_up.connect(_on_button_up)
	else:
		bitmap.command_requested.connect(activate)
	return bitmap


func update_availability() -> void:
	var owner = _owner()
	for command_id: StringName in _buttons:
		var button := _buttons[command_id] as BaseButton
		var definition := presentation_definition(ClassicCommandCatalog.command(command_id))
		var availability_id := StringName(definition.get("availability", &""))
		var reason := ""
		if owner._current_view == null or not owner._current_view.session_started:
			reason = "Begin a campaign first."
		elif owner._current_view.pending_interaction != null and not String(command_id).begins_with("encounter_"):
			reason = "Resolve the current interaction first."
		elif String(command_id).begins_with("encounter_"):
			reason = "Choose from the active encounter response controls."
		elif not availability_id.is_empty():
			reason = GameShellAvailability.action_reason(owner._current_view, availability_id)
		if bool(button.get_meta("search_animation", false)):
			var summary: PartySummaryView = owner._current_view.party_summary if owner._current_view != null else null
			button.call("sync_status", false if summary == null else summary.searching, reason.is_empty(), reason)
		elif bool(button.get_meta("torch_meter", false)):
			var summary: PartySummaryView = owner._current_view.party_summary if owner._current_view != null else null
			button.call("sync_status", 0 if summary == null else summary.light_remaining, false if summary == null else summary.has_classic_torch, reason.is_empty(), reason)
		else:
			button.disabled = not reason.is_empty()
			button.tooltip_text = reason if not reason.is_empty() else "Break camp" if command_id == &"camp" and owner._current_view.party_summary != null and owner._current_view.party_summary.camping else String(definition.get("tooltip", ""))
			if button is ClassicBitmapButton:
				(button as ClassicBitmapButton).set_visual_pressed(_is_visually_pressed(command_id))
		button.queue_redraw()


func selected_fast_spell(slot_index: int) -> Dictionary:
	var owner = _owner()
	if owner._current_view == null or slot_index < 0 or slot_index >= 10:
		return {}
	var character: CharacterView = null
	for candidate: CharacterView in owner._current_view.party_members:
		if candidate.id == owner._selected_character_id:
			character = candidate
			break
	if character == null and not owner._current_view.party_members.is_empty():
		character = owner._current_view.party_members[0]
	if character == null or slot_index >= character.fast_spells.size():
		return {}
	var binding := character.fast_spells[slot_index]
	return {
		"characterId": character.id,
		"characterName": character.name,
		"slot": slot_index,
		"spellId": binding.spell_id,
		"spellName": binding.spell_name,
		"power": binding.power,
		"enabled": binding.activation.enabled,
		"reason": binding.activation.reason,
	}


func _is_visually_pressed(command_id: StringName) -> bool:
	var owner = _owner()
	var party_summary: PartySummaryView = owner._current_view.party_summary if owner._current_view != null else null
	if command_id == &"camp":
		return party_summary != null and party_summary.camping
	if command_id == _held_command:
		return true
	return command_route(command_id) == owner._navigator.current_screen()


static func command_route(command_id: StringName) -> StringName:
	return {&"money": &"services", &"inventory": &"inventory", &"spells": &"spells", &"maps": &"journal", &"settings": &"system"}.get(command_id, &"")


func activate(command_id: StringName, held_repeat: bool = false) -> void:
	var owner = _owner()
	var start_sound_id := command_activation_sound_id(command_id, held_repeat)
	if start_sound_id > 0:
		owner.presentation_sound_requested.emit(start_sound_id, false, false, false)
	match command_id:
		&"search_mode": owner.intent_submitted.emit(ExplorationIntents.toggle_search())
		&"area_search": owner.intent_submitted.emit(ExplorationIntents.search())
		&"torch": owner.intent_submitted.emit(ExplorationIntents.use_torch())
		&"camp": owner.intent_submitted.emit(ExplorationIntents.camp())
		&"rest": owner.intent_submitted.emit(ExplorationIntents.rest())
		&"heal": owner.intent_submitted.emit(ExplorationIntents.heal())
		&"contextual":
			var service := contextual_service()
			if service != null and not service.actions.is_empty():
				owner.intent_submitted.emit(EconomyIntents.service(service.service_id, service.actions[0]))
			else:
				owner.intent_submitted.emit(ExplorationIntents.contextual_encounter())
		&"money": owner._navigator.open_screen(&"services")
		&"inventory": owner._navigator.open_screen(&"inventory")
		&"spells": owner._navigator.open_screen(&"spells")
		&"maps": owner._navigator.open_screen(&"journal")
		&"settings": owner._navigator.open_screen(&"system")
		&"save": owner.save_requested.emit("quick")


func presentation_definition(definition: Dictionary) -> Dictionary:
	var owner = _owner()
	var result := definition.duplicate()
	var command_id := StringName(definition.get("id", &""))
	if command_id == &"search_mode" and owner._current_view != null and owner._current_view.party_summary != null and owner._current_view.party_summary.searching:
		result["label"] = "Stop Search"
		result["tooltip"] = "Stop continuous secret searching"
		return result
	if command_id != &"contextual":
		return result
	var service := contextual_service()
	if service == null:
		return result
	result["label"] = service.title
	result["tooltip"] = "Enter %s" % service.title
	result["availability"] = &"service_action"
	if service.service_kind == &"temple":
		result["asset_id"] = &"command.temple"
		result["art_region"] = [9, 2, 37, 34]
		result.erase("art_mask")
	elif service.service_kind == &"shop":
		result["asset_id"] = &""
		result["asset_path"] = "res://src/ui/shared/assets/ui/commands/shop.png"
		result.erase("art_region")
		result.erase("art_mask")
	else:
		result["asset_id"] = &""
		result.erase("art_region")
		result.erase("art_mask")
	return result


func contextual_service() -> ServiceView:
	var owner = _owner()
	if owner._current_view == null:
		return null
	for service: ServiceView in owner._current_view.services:
		if service.service_kind in [&"shop", &"temple"] and not service.actions.is_empty():
			return service
	return null


func _begin_held_command(command_id: StringName) -> void:
	_held_command = command_id
	activate(command_id)
	if not _held_command.is_empty():
		_timer.start()


static func command_activation_sound_id(command_id: StringName, held_repeat: bool) -> int:
	if held_repeat:
		return 0
	if command_id == &"contextual":
		return CONTEXTUAL_CONTROL_SOUND_ID
	return int(HELD_COMMAND_START_SOUND_IDS.get(command_id, 0))


func _stop_held_command() -> void:
	_held_command = &""
	if _timer != null:
		_timer.stop()
	update_availability()


func _on_button_up() -> void:
	if should_stop_held_command_on_button_up(Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)):
		_stop_held_command()


static func should_stop_held_command_on_button_up(left_mouse_pressed: bool) -> bool:
	return not left_mouse_pressed


func release() -> void:
	_stop_held_command()


func _on_timeout() -> void:
	var owner = _owner()
	if _held_command.is_empty():
		_stop_held_command()
		return
	if owner._current_view == null or owner._current_view.pending_interaction != null or not owner._current_view.availability(_held_command).enabled:
		_stop_held_command()
		return
	if owner.status.is_field_time_playback_active():
		return
	activate(_held_command, true)
