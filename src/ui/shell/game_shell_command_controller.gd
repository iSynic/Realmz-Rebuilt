## Builds the exploration command deck and owns held-command presentation state.
class_name GameShellCommandController
extends RefCounted

const HELD_COMMAND_INTERVAL := 1.0 / 60.0
const HELD_COMMAND_START_SOUND_IDS: Dictionary = {&"area_search": 6001, &"rest": 6001, &"heal": 10105}
const CONTEXTUAL_CONTROL_SOUND_ID := 141

var _owner_ref: WeakRef
var _buttons: Dictionary = {}
var _fixed_buttons: Dictionary = {}
var _modular_buttons: Dictionary = {}
var _bound_modular := false
var _configured_definitions: Dictionary = {}
var _held_command: StringName = &""
var _held_command_source: StringName = &""
var _held_command_keycode: int = KEY_NONE
var _held_command_screen: StringName = &""
var _timer: Timer
var party_effect_playback := false:
	set(value):
		party_effect_playback = value
		update_availability()


func _init(owner: Control) -> void:
	_owner_ref = weakref(owner)


func _owner() -> GameShell:
	return _owner_ref.get_ref()


func initialize() -> void:
	_timer = Timer.new()
	_timer.wait_time = HELD_COMMAND_INTERVAL
	_timer.timeout.connect(_on_timeout)
	_owner().add_child(_timer)
	for node: Node in _owner().find_children("*", "BaseButton", true, false):
		if not node.has_meta("shell_command_id"):
			continue
		var button := node as BaseButton
		var command_id := StringName(button.get_meta("shell_command_id"))
		var deck := _modular_buttons if _owner().hud.is_ancestor_of(button) else _fixed_buttons
		deck[command_id] = button
		button.set_meta("focus_key", "command:%s" % command_id)
		if bool(ClassicCommandCatalog.command(command_id).get("hold_repeat", false)):
			button.button_down.connect(_begin_held_command.bind(command_id))
			button.button_up.connect(_on_button_up)
		else:
			button.connect("command_requested", activate)
	_buttons = _fixed_buttons


func present(game_view: GameView) -> void:
	if not _held_command.is_empty() and not _held_command_is_valid(_owner(), game_view):
		_stop_held_command()


func rebuild() -> void:
	var owner := _owner()
	if not owner.is_node_ready() or owner.layout_profile == null:
		return
	if _bound_modular != owner.hud.active:
		_stop_held_command()
		_bound_modular = owner.hud.active
		_buttons = _modular_buttons if _bound_modular else _fixed_buttons
		_configured_definitions.clear()
	for button: BaseButton in _buttons.values():
		button.hide()
	var context: StringName = owner.navigator.current_screen()
	if owner.hud.active: context = &"exploration"
	var world_command_count := 0
	for definition: Dictionary in ClassicCommandCatalog.for_context(context):
		definition = presentation_definition(definition)
		var command_id := StringName(definition["id"])
		var button := _buttons[command_id] as BaseButton
		button.show()
		if button is ClassicBitmapButton:
			var bitmap := button as ClassicBitmapButton
			if _configured_definitions.get(command_id) != definition:
				bitmap.configure(definition, owner.layout_profile.bitmap_scale)
				_configured_definitions[command_id] = definition.duplicate(true)
			else:
				bitmap.set_art_scale(owner.layout_profile.bitmap_scale)
		if button.has_method("set_command_title_visible"):
			var show_command_title: bool = not owner.hud.active and (context != &"exploration" or owner.settings.show_overworld_command_titles)
			button.call("set_command_title_visible", show_command_title, not owner.hud.active and owner.settings.integer_fit_hidden_commands)
		if not owner.hud.active and button.has_method("set_modular_icon_layout"):
			button.call("set_modular_icon_layout", 0, 0)
		var group := StringName(definition.get("group", &"party"))
		var target_grid: Control = owner.command_grid
		if command_id == &"torch":
			target_grid = owner.command_grid if owner.hud.active else owner.torch_dock
		elif group == &"world" and owner.world_command_panel.visible:
			target_grid = owner.world_command_grid if owner.hud.active or world_command_count < 4 else owner.world_command_lower_grid
			world_command_count += 1
		if button.get_parent() != target_grid:
			button.reparent(target_grid, false)
		target_grid.move_child(button, target_grid.get_child_count() - 1)
	if owner.hud.active:
		owner.command_grid.move_child(_buttons[&"torch"], owner.command_grid.get_child_count() - 1)
	update_availability()


func update_availability() -> void:
	var owner := _owner()
	for command_id: StringName in _buttons:
		var button := _buttons[command_id] as BaseButton
		var definition := presentation_definition(ClassicCommandCatalog.command(command_id))
		var availability_id := StringName(definition.get("availability", &""))
		var reason := ""
		if owner.current_view == null or not owner.current_view.session_started:
			reason = "Begin a campaign first."
		elif party_effect_playback:
			reason = "" if command_id == &"settings" else "Wait for the current effect to finish."
		elif owner.current_view.pending_interaction != null and not String(command_id).begins_with("encounter_"):
			reason = "Resolve the current interaction first."
		elif String(command_id).begins_with("encounter_"):
			reason = "Choose from the active encounter response controls."
		elif not availability_id.is_empty():
			reason = GameShellAvailability.action_reason(owner.current_view, availability_id)
		if bool(button.get_meta("search_animation", false)):
			var summary: PartySummaryView = owner.current_view.party_summary if owner.current_view != null else null
			button.call("sync_status", false if summary == null else summary.searching, reason.is_empty(), reason)
		elif bool(button.get_meta("torch_meter", false)):
			var summary: PartySummaryView = owner.current_view.party_summary if owner.current_view != null else null
			button.call("sync_status", 0 if summary == null else summary.light_remaining, false if summary == null else summary.has_classic_torch, reason.is_empty(), reason)
		else:
			button.disabled = not reason.is_empty()
			if button is ClassicBitmapButton:
				(button as ClassicBitmapButton).set_visual_pressed(_is_visually_pressed(command_id))
		button.set_meta("command_unavailable_reason", reason)
		if not bool(button.get_meta("torch_meter", false)) and not bool(button.get_meta("search_animation", false)):
			button.tooltip_text = String(definition["label"]) + ("\n" + reason if not reason.is_empty() else "")
		button.queue_redraw()


func pause_contains_point(point: Vector2) -> bool:
	var button := _buttons.get(&"settings") as BaseButton
	return button != null and button.is_visible_in_tree() and not button.disabled and button.get_global_rect().has_point(point)


func selected_fast_spell(slot_index: int) -> Dictionary:
	var owner := _owner()
	if owner.current_view == null or slot_index < 0 or slot_index >= 10:
		return {}
	var character: CharacterView = null
	for candidate: CharacterView in owner.current_view.party_members:
		if candidate.id == owner.selected_character_id:
			character = candidate
			break
	if character == null and not owner.current_view.party_members.is_empty():
		character = owner.current_view.party_members[0]
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


func controller_entries() -> Array[ControllerRadialEntry]:
	var owner := _owner()
	var result: Array[ControllerRadialEntry] = []
	var context: StringName = owner.navigator.current_screen()
	for source: Dictionary in ClassicCommandCatalog.for_context(context):
		var definition := presentation_definition(source)
		var command_id := StringName(definition["id"])
		var button := _buttons.get(command_id) as BaseButton
		var reason := ""
		if button != null and button.disabled:
			reason = String(button.get_meta("command_unavailable_reason", ""))
		elif button == null and String(command_id).begins_with("encounter_"):
			reason = "Choose from the active encounter response controls."
		result.append(ControllerRadialEntry.new(command_id, String(definition["label"]), reason.is_empty(), reason, controller_icon(command_id), _fallback_symbol(command_id)))
	return result


func controller_icon(command_id: StringName) -> Texture2D:
	var button := _buttons.get(command_id) as ClassicBitmapButton
	if button != null:
		if not button.has_visual_art():
			button.configure(presentation_definition(ClassicCommandCatalog.command(command_id)))
		return button.radial_art_texture()
	var definition := presentation_definition(ClassicCommandCatalog.command(command_id))
	if definition.is_empty():
		return null
	return ClassicUiAssetCatalog.texture(StringName(definition.get("asset_id", &"")))


static func _fallback_symbol(command_id: StringName) -> String:
	return {&"torch": "✦", &"character": "♟", &"exploration": "✥"}.get(command_id, "")


func activate_controller(command_id: StringName) -> bool:
	var button := _buttons.get(command_id) as BaseButton
	if button == null or button.disabled:
		return false
	if bool(ClassicCommandCatalog.command(command_id).get("hold_repeat", false)):
		_begin_held_command(command_id, &"controller")
	else:
		activate(command_id)
	return true


func _is_visually_pressed(command_id: StringName) -> bool:
	var owner := _owner()
	var party_summary: PartySummaryView = owner.current_view.party_summary if owner.current_view != null else null
	if command_id == &"camp":
		return party_summary != null and party_summary.camping
	if command_id == _held_command:
		return true
	return command_route(command_id) == owner.navigator.current_screen()


static func command_route(command_id: StringName) -> StringName:
	return {&"money": &"services", &"inventory": &"inventory", &"spells": &"spells", &"maps": &"journal", &"settings": &"system"}.get(command_id, &"")


func activate(command_id: StringName, held_repeat: bool = false) -> void:
	var owner := _owner()
	var start_sound_id := command_activation_sound_id(command_id, held_repeat)
	if command_id == &"heal" and (owner.current_view == null or owner.current_view.character_spellcasting_blocked or not owner.current_view.availability(&"heal").enabled):
		start_sound_id = 0
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
		&"money": owner.navigator.open_screen(&"services")
		&"inventory": owner.navigator.open_screen(&"inventory")
		&"spells": owner.navigator.open_screen(&"spells")
		&"maps": owner.navigator.open_screen(&"journal")
		&"settings": owner.open_system_workspace()
		&"save": owner.save_requested.emit("quick")


func presentation_definition(definition: Dictionary) -> Dictionary:
	var owner := _owner()
	var result := definition.duplicate()
	var command_id := StringName(definition.get("id", &""))
	if command_id == &"search_mode" and owner.current_view != null and owner.current_view.party_summary != null and owner.current_view.party_summary.searching:
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
	var owner := _owner()
	if owner.current_view == null:
		return null
	for service: ServiceView in owner.current_view.services:
		if service.service_kind in [&"shop", &"temple"] and not service.actions.is_empty():
			return service
	return null


func begin_keyboard_hold(command_id: StringName, keycode: int) -> bool:
	if keycode == KEY_NONE or not bool(ClassicCommandCatalog.command(command_id).get("hold_repeat", false)):
		return false
	var owner := _owner()
	if owner == null:
		return false
	var button := _buttons.get(command_id) as BaseButton
	if button == null or button.disabled or not _held_command_is_available(owner, owner.current_view, command_id):
		return false
	if _held_command_source == &"keyboard" and _held_command == command_id and _held_command_keycode == keycode:
		return true
	_stop_held_command()
	_begin_held_command(command_id, &"keyboard", keycode)
	return true


func release_keyboard_hold(keycode: int) -> void:
	if _held_command_source == &"keyboard" and keycode != KEY_NONE and _held_command_keycode == keycode:
		_stop_held_command()


func release_pointer_hold() -> void:
	if _held_command_source == &"pointer":
		_stop_held_command()


func _begin_held_command(command_id: StringName, source: StringName = &"pointer", keycode: int = KEY_NONE) -> void:
	if not _held_command.is_empty():
		_stop_held_command()
	_held_command = command_id
	_held_command_source = source
	_held_command_keycode = keycode
	_held_command_screen = _owner().navigator.current_screen()
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
	_held_command_source = &""
	_held_command_keycode = KEY_NONE
	_held_command_screen = &""
	if _timer != null:
		_timer.stop()
	update_availability()


func _on_button_up() -> void:
	if _held_command_source == &"pointer" and should_stop_held_command_on_button_up(Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)):
		_stop_held_command()


static func should_stop_held_command_on_button_up(left_mouse_pressed: bool) -> bool:
	return not left_mouse_pressed


func release() -> void:
	_stop_held_command()


func release_controller_hold() -> void:
	if _held_command_source == &"controller":
		_stop_held_command()


func _on_timeout() -> void:
	var owner := _owner()
	if _held_command.is_empty():
		_stop_held_command()
		return
	if not _held_command_is_valid(owner, owner.current_view):
		_stop_held_command()
		return
	if owner.status.is_field_time_playback_active():
		return
	activate(_held_command, true)


func _held_command_is_valid(owner: Variant, game_view: GameView) -> bool:
	return not _held_command.is_empty() and _held_command_is_available(owner, game_view, _held_command) and owner.navigator.current_screen() == _held_command_screen


func _held_command_is_available(owner: Variant, game_view: GameView, command_id: StringName) -> bool:
	return owner != null and game_view != null and game_view.session_started and game_view.pending_interaction == null and not owner.pause_active and not owner.navigator.full_stage_overlay_visible and game_view.availability(command_id).enabled
