extends RealmzTestCase

const PERSISTENT_AUTO_COORDINATOR := preload("res://src/app/session/persistent_auto_coordinator.gd")

class RouterOverlayAccess extends RefCounted:
	func text_editor_is_open() -> bool: return false
	func radial_is_open() -> bool: return false

class RouterShellPresenter extends RefCounted:
	var controller := RouterOverlayAccess.new()

class RouterCoordinator extends RefCounted:
	func is_combat_playback_active() -> bool: return false

class RouterSessionView extends RefCounted:
	func active_interaction_request() -> InteractionRequest: return null

class RouterSessionController extends RefCounted:
	var current_view := RouterSessionView.new()
	func view() -> RouterSessionView: return current_view

class RouterDungeonPresenter extends RefCounted:
	func is_active() -> bool: return false

class RouterMovementHost extends Control:
	var presentation_coordinator := RouterCoordinator.new(); var _shell_presenter := RouterShellPresenter.new(); var session_controller := RouterSessionController.new(); var _dungeon_presenter := RouterDungeonPresenter.new(); var _held_movement := HeldMovementController.new()
	func accepts_exploration_input() -> bool: return true


func run() -> void:
	_test_controller_preferences_round_trip_and_migration()
	_test_controller_bindings_and_conflicts()
	_test_controller_owner_edges_hysteresis_and_takeover()
	await _test_normalized_direction_reaches_exploration_movement()
	_test_ordered_controller_targeting()
	await _test_focus_navigation_activation_and_prompts()
	await _test_controller_radial_pages_and_explicit_commit()
	await _test_persistent_auto_continuation()
	await _test_qwerty_draft_commit_cancel_and_layout()
	await _test_controller_settings_draft_and_embedded_file_dialog()


func _test_controller_preferences_round_trip_and_migration() -> void:
	var settings := PresentationSettings.new(); settings.master_volume = 0.35; settings.controller.prompt_family = ControllerPreferences.PROMPT_PLAYSTATION; settings.controller.left_stick_dead_zone = 0.3; settings.controller.repeat_initial_ms = 425
	var restored := PresentationSettings.from_data(settings.to_data())
	assert_not_null(restored, "schema-sixteen controller preferences decode")
	assert_equal([restored.master_volume, restored.controller.prompt_family, restored.controller.left_stick_dead_zone, restored.controller.repeat_initial_ms], [0.35, ControllerPreferences.PROMPT_PLAYSTATION, 0.3, 425], "controller tuning round-trips without changing existing presentation values")
	var legacy := settings.to_data(); legacy["schemaVersion"] = 13; legacy.erase("controller"); var migrated := PresentationSettings.from_data(legacy)
	assert_not_null(migrated, "schema-thirteen presentation settings migrate")
	assert_equal([migrated.master_volume, migrated.controller.prompt_family, migrated.controller.left_stick_dead_zone, migrated.controller.repeat_initial_ms, migrated.controller.repeat_interval_ms], [0.35, ControllerPreferences.PROMPT_AUTO, 0.25, 350, 100], "legacy values survive while controller support receives stable defaults")
	var schema_fourteen := settings.to_data(); schema_fourteen["schemaVersion"] = 14; schema_fourteen["controller"]["bindings"] = (schema_fourteen["controller"]["bindings"] as Array).filter(func(binding: Dictionary) -> bool: return binding["action"] != "realmz_controller_top_menu"); var top_menu_migrated := PresentationSettings.from_data(schema_fourteen)
	assert_true(top_menu_migrated.controller.bindings.any(func(binding: Dictionary) -> bool: return binding["action"] == "realmz_controller_top_menu" and binding["code"] == JOY_BUTTON_BACK), "schema-fourteen settings add View/Create/Minus when that physical button is unused")
	schema_fourteen["controller"]["bindings"].append({"action": "realmz_controller_inspect", "kind": "button", "code": JOY_BUTTON_BACK, "direction": 0}); var occupied_migration := PresentationSettings.from_data(schema_fourteen)
	assert_false(occupied_migration.controller.bindings.any(func(binding: Dictionary) -> bool: return binding["action"] == "realmz_controller_top_menu"), "schema-fourteen migration leaves Top Menu unbound when View/Create/Minus is already assigned")
	var malformed := settings.to_data(); malformed["controller"]["leftStickDeadZone"] = 0.02
	assert_equal(PresentationSettings.from_data(malformed), null, "current settings reject an unusable stick dead zone")
	malformed = settings.to_data(); malformed["controller"]["bindings"] = (malformed["controller"]["bindings"] as Array).filter(func(binding: Dictionary) -> bool: return binding["action"] != "realmz_controller_confirm")
	assert_equal(PresentationSettings.from_data(malformed), null, "current settings reject a draft without required confirmation navigation")


func _test_controller_bindings_and_conflicts() -> void:
	var preferences := ControllerPreferences.new(); assert_true(preferences.required_navigation_is_reachable() and preferences.conflicts().is_empty(), "physical-position defaults provide a conflict-free complete navigation set"); UiInputActions.apply_controller_bindings(preferences); var confirm_events := InputMap.action_get_events(&"realmz_controller_confirm")
	assert_true(confirm_events.any(func(event: InputEvent) -> bool: return event is InputEventJoypadButton and (event as InputEventJoypadButton).button_index == JOY_BUTTON_A), "South is registered as the default confirm position")
	assert_true(preferences.bindings.any(func(binding: Dictionary) -> bool: return binding["action"] == "realmz_controller_top_menu" and binding["code"] == JOY_BUTTON_BACK), "View/Create/Minus opens the top menu by default")
	preferences.bindings.append({"action": "realmz_controller_back", "kind": "button", "code": JOY_BUTTON_A, "direction": 0})
	assert_equal(preferences.conflicts().size(), 1, "binding drafts identify a physical input assigned to two commands")


func _test_controller_owner_edges_hysteresis_and_takeover() -> void:
	var owner := ControllerInputOwner.new(); (Engine.get_main_loop() as SceneTree).root.add_child(owner); owner.configure(ControllerPreferences.new()); assert_true(owner.active_device() < 0, "focus loss cannot create a controller-only Auto blocker before a pad has claimed input")
	var pressed: Array[StringName] = []; var released: Array[StringName] = []; var directions: Array[Vector2i] = []
	owner.action_pressed.connect(func(action_id: StringName, _repeated: bool) -> void: pressed.append(action_id))
	owner.action_released.connect(func(action_id: StringName) -> void: released.append(action_id))
	owner.direction_changed.connect(func(direction: Vector2i, _repeated: bool) -> void: directions.append(direction))
	var noise := InputEventJoypadMotion.new(); noise.device = 2; noise.axis = JOY_AXIS_LEFT_X; noise.axis_value = 0.12
	assert_false(owner.handle_input(noise), "sub-dead-zone stick noise does not claim controller ownership")
	assert_equal(owner.active_device(), -1, "stick noise leaves the active controller unchanged")
	var right := InputEventJoypadMotion.new(); right.device = 2; right.axis = JOY_AXIS_LEFT_X; right.axis_value = 0.26
	assert_true(owner.handle_input(right), "a deliberate stick direction is consumed by the normalized owner")
	assert_equal([owner.active_device(), pressed], [2, [&"realmz_controller_right"]], "deliberate input claims one pad, enables its focus-loss safety gate, and produces one direction edge")
	var down := InputEventJoypadMotion.new(); down.device = 2; down.axis = JOY_AXIS_LEFT_Y; down.axis_value = 0.26; owner.handle_input(down); owner.call("_process", 0.0); owner.call("_process", 0.0); assert_equal(directions, [Vector2i(1, 1)], "paired analog axes settle into one quantized diagonal instead of dispatching two cardinal steps"); down.axis_value = 0.0; owner.handle_input(down); released.clear()
	right.axis_value = 0.2
	owner.handle_input(right)
	assert_true(released.is_empty(), "release hysteresis retains the direction slightly below its press threshold")
	right.axis_value = 0.16
	owner.handle_input(right)
	assert_equal(released, [&"realmz_controller_right"], "crossing the hysteresis release boundary emits one release edge")
	var dpad_right := InputEventJoypadButton.new()
	dpad_right.device = 2
	dpad_right.button_index = JOY_BUTTON_DPAD_RIGHT
	dpad_right.pressed = true
	owner.handle_input(dpad_right)
	right.axis_value = 0.3
	owner.handle_input(right)
	dpad_right.pressed = false
	owner.handle_input(dpad_right)
	assert_equal(released.count(&"realmz_controller_right"), 1, "releasing one of two physical bindings does not release their still-held logical direction")
	right.axis_value = 0.0
	owner.handle_input(right)
	assert_equal(released.count(&"realmz_controller_right"), 2, "the logical direction releases after its final physical owner becomes neutral")
	var other_noise := InputEventJoypadMotion.new()
	other_noise.device = 3
	other_noise.axis = JOY_AXIS_LEFT_Y
	other_noise.axis_value = 0.1
	assert_false(owner.handle_input(other_noise), "noise from another pad cannot steal active ownership")
	var south := InputEventJoypadButton.new()
	south.device = 3
	south.button_index = JOY_BUTTON_A
	south.pressed = true
	assert_true(owner.handle_input(south) and owner.active_device() == 3, "a deliberate button press transfers single-pad ownership")
	var held_axis := InputEventJoypadMotion.new()
	held_axis.device = 3
	held_axis.axis = JOY_AXIS_LEFT_X
	held_axis.axis_value = 0.8
	owner.handle_input(held_axis)
	owner.suspend("test")
	assert_true(owner.is_suspended(), "focus loss or disconnect suspends controller dispatch")
	south.pressed = false
	owner.handle_input(south)
	south.pressed = true
	owner.handle_input(south)
	assert_true(owner.is_suspended(), "an acknowledgement cannot resume while a stick remains held")
	held_axis.axis_value = 0.0
	owner.handle_input(held_axis)
	south.pressed = false
	owner.handle_input(south)
	south.pressed = true
	owner.handle_input(south)
	assert_false(owner.is_suspended(), "a neutral explicit button acknowledgement resumes controller dispatch"); var external := InputEventKey.new(); external.pressed = true; held_axis.axis_value = 0.8; owner.handle_input(held_axis); owner.suspend("test external acknowledgement"); assert_true(owner.handle_input(external) and owner.is_suspended(), "keyboard or pointer acknowledgement is consumed but cannot resume while the controller remains held"); held_axis.axis_value = 0.0; owner.handle_input(held_axis); assert_true(owner.handle_input(external) and not owner.is_suspended(), "a deliberate keyboard or pointer press resumes suspended Auto once the controller is neutral")
	var captured: Array[Dictionary] = []
	var capture_cancelled := [false]
	owner.binding_captured.connect(func(_action_id: StringName, descriptor: Dictionary) -> void: captured.append(descriptor))
	owner.binding_capture_cancelled.connect(func() -> void: capture_cancelled[0] = true)
	assert_true(owner.begin_binding_capture(&"realmz_controller_confirm"), "binding capture claims one named controller action")
	var capture_button := InputEventJoypadButton.new()
	capture_button.device = 3
	capture_button.button_index = JOY_BUTTON_MISC1
	capture_button.pressed = true
	owner.handle_input(capture_button)
	assert_true(captured.size() == 1 and captured[0]["action"] == "realmz_controller_confirm" and captured[0]["code"] == JOY_BUTTON_MISC1, "binding capture returns one primitive physical descriptor without normal dispatch")
	owner.begin_binding_capture(&"realmz_controller_confirm")
	var cancel_capture := InputEventJoypadButton.new()
	cancel_capture.device = 3
	cancel_capture.button_index = JOY_BUTTON_B
	cancel_capture.pressed = true
	owner.handle_input(cancel_capture)
	assert_true(capture_cancelled[0], "East cancels binding capture without replacing the draft")
	owner.free()


func _test_normalized_direction_reaches_exploration_movement() -> void:
	var host := RouterMovementHost.new(); (Engine.get_main_loop() as SceneTree).root.add_child(host); var pulses: Array[Vector2i] = []
	await (Engine.get_main_loop() as SceneTree).process_frame
	host._held_movement.movement_requested.connect(func(direction: Vector2i) -> void: pulses.append(direction))
	var router := ApplicationInputRouter.new(host); router.handle_controller_direction(Vector2i(1, 1))
	assert_equal(pulses, [Vector2i(1, 1)], "the application router sends the normalized controller vector into exploration movement instead of rereading an empty legacy action cache")
	router = null; host._held_movement.free(); host.free()


func _test_ordered_controller_targeting() -> void:
	var body := InteractionResponse.CombatBody.new(&"cast_spell", "hero")
	var request := CombatTargetingRequest.new(&"sequence", body)
	request.candidate_ids.assign(["monster.one", "monster.two", "monster.three"])
	request.maximum_targets = 3
	var state := CombatTargetingState.new(request)
	assert_true(state.cycle_candidate(1) and state.select_previewed_target(), "controller target cycling previews and selects the first rules-supplied combatant")
	assert_true(state.cycle_candidate(1), "shoulders advance the preview independently of committed selections")
	assert_equal([state.previewed_candidate_id(), state.selected_ids], ["monster.two", ["monster.one"]], "cycling a candidate does not erase the ordered targets already selected")
	assert_true(state.select_previewed_target() and state.cycle_candidate(1) and state.select_previewed_target(), "South adds subsequent targets in explicit order")
	assert_equal(state.committed_body().target_ids, ["monster.one", "monster.two", "monster.three"], "West-style confirmation retains the complete ordered multi-target selection")
	var area_request := CombatTargetingRequest.new(&"area", body)
	area_request.validation_deferred = true
	area_request.default_target_coordinate = Vector2i(40, 40)
	area_request.area_rotation_offsets = [[Vector2i.ZERO], [Vector2i.ZERO, Vector2i.RIGHT]]
	var area := CombatTargetingState.new(area_request)
	assert_true(area.move_coordinate_preview(Vector2i(1, -1)) and area.hovered_coordinate == Vector2i(41, 39), "controller area targeting moves an arbitrary center over the battlefield grid")
	assert_false(area.can_confirm(), "moving an area preview does not commit it")
	assert_true(area.select_coordinate(area.hovered_coordinate) and area.rotate_area() and area.committed_body().target_coordinate == Vector2i(41, 39), "South selects and North rotates an area before explicit commit")
	var summon_request := CombatTargetingRequest.new(&"coordinate_sequence", body)
	summon_request.validation_deferred = true
	summon_request.maximum_targets = 2
	summon_request.default_target_coordinate = Vector2i(30, 30)
	var summon := CombatTargetingState.new(summon_request)
	assert_true(summon.select_coordinate(summon.hovered_coordinate) and summon.move_coordinate_preview(Vector2i.RIGHT) and summon.select_coordinate(summon.hovered_coordinate), "controller summon targeting records separate spaces in selection order")
	assert_equal(summon.committed_body().target_coordinates, [Vector2i(30, 30), Vector2i(31, 30)], "West-style summon commit preserves the ordered space sequence")


func _test_focus_navigation_activation_and_prompts() -> void:
	var root := Control.new(); root.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT); root.size = Vector2(800, 600)
	(Engine.get_main_loop() as SceneTree).root.add_child(root)
	var first := Button.new(); first.position = Vector2(40, 40); first.size = Vector2(120, 36); first.text = "First"
	first.set_meta("focus_group", "route:test"); root.add_child(first)
	var second := Button.new(); second.position = Vector2(240, 40); second.size = Vector2(120, 36); second.text = "Second"
	second.tooltip_text = "Exact focused detail"; second.set_meta("focus_group", "route:test"); root.add_child(second)
	await (Engine.get_main_loop() as SceneTree).process_frame
	var activation_state := [false]
	second.pressed.connect(func() -> void: activation_state[0] = true)
	var navigator := ControllerFocusNavigator.new()
	first.grab_focus()
	assert_equal(navigator.move(root, Vector2i.RIGHT), second, "directional navigation chooses the predictable same-group geometric neighbor")
	assert_equal(navigator.inspection_text(root), "Exact focused detail", "inspection exposes the focused control's existing explanation")
	assert_true(navigator.activate_focused(root) and activation_state[0], "South-style focus activation uses the existing control action")
	var disabled := Button.new(); disabled.position = Vector2(440, 40); disabled.size = Vector2(120, 36); disabled.text = "Unavailable"; disabled.disabled = true
	disabled.tooltip_text = "A specific rules-owned reason."; disabled.set_meta("focus_group", "route:test"); root.add_child(disabled)
	assert_equal(navigator.move(root, Vector2i.RIGHT), disabled, "disabled controls remain focusable for controller inspection")
	assert_equal(navigator.inspection_text(root), "A specific rules-owned reason.", "inspection exposes a focused unavailable action's exact reason")
	assert_false(navigator.activate_focused(root), "South cannot activate a focused disabled control")
	var toggle := CheckButton.new(); toggle.position = Vector2(40, 100); toggle.text = "Toggle"; root.add_child(toggle); toggle.grab_focus(); var toggled := [false]; toggle.toggled.connect(func(value: bool) -> void: toggled[0] = value); assert_true(navigator.activate_focused(root) and toggle.button_pressed and toggled[0], "South changes a focused toggle through its native state and signal")
	var picker := OptionButton.new(); picker.position = Vector2(200, 100); picker.add_item("First"); picker.add_item("Second"); root.add_child(picker); picker.grab_focus(); assert_true(navigator.activate_focused(root), "South opens a focused dropdown under controller ownership"); navigator.move(root, Vector2i.DOWN); assert_true(navigator.activate_focused(root) and picker.selected == 1, "direction and South select the highlighted dropdown entry through the option owner")
	var list := ItemList.new(); list.position = Vector2(380, 100); list.size = Vector2(120, 80); list.add_item("One"); list.add_item("Two"); root.add_child(list); list.grab_focus(); navigator.move(root, Vector2i.DOWN); var activated_item := [-1]; list.item_activated.connect(func(index: int) -> void: activated_item[0] = index); assert_true(navigator.activate_focused(root) and activated_item[0] == 1, "controller selection activates the exact focused list record")
	var modal := Control.new(); modal.size = Vector2(200, 100)
	root.add_child(modal)
	var modal_action := Button.new(); modal_action.text = "Modal action"; modal_action.size = Vector2(120, 36)
	modal.add_child(modal_action)
	first.grab_focus()
	assert_equal(navigator.focus_next(modal), modal_action, "modal focus traversal recovers inside its active root instead of advancing elsewhere in the viewport"); var modal_activation := [false]; modal_action.pressed.connect(func() -> void: modal_activation[0] = true); first.grab_focus(); assert_true(navigator.activate_focused(modal) and modal_activation[0], "South recovers into the active modal instead of activating stale focus from the surface beneath it")
	var prompts := load("res://src/ui/shell/controller_prompt_strip.tscn").instantiate() as ControllerPromptStrip; root.add_child(prompts)
	await (Engine.get_main_loop() as SceneTree).process_frame
	prompts.present(ControllerPreferences.PROMPT_PLAYSTATION)
	assert_contains((prompts.find_child("PromptText", true, false) as Label).text, "Cross Select", "automatic prompt presentation can show PlayStation physical labels")
	prompts.present(ControllerPreferences.PROMPT_SWITCH)
	assert_contains((prompts.find_child("PromptText", true, false) as Label).text, "B Select", "Switch prompts preserve South-position confirmation")
	var body := VBoxContainer.new(); body.name = "FocusBody"; root.add_child(body); var first_record := Button.new(); first_record.name = "Open"; first_record.set_meta("character_id", "hero.one"); body.add_child(first_record)
	var selected_record := Button.new(); selected_record.name = "Open"; selected_record.set_meta("character_id", "hero.two"); body.add_child(selected_record)
	var next_record := Button.new(); next_record.name = "Open"; next_record.set_meta("character_id", "hero.three"); body.add_child(next_record)
	var focus_memory := WorkspaceFocusController.new(); focus_memory.prepare(body, &"character"); selected_record.grab_focus(); focus_memory.store(root, body, &"character")
	body.remove_child(first_record); first_record.free(); body.remove_child(selected_record); selected_record.free(); body.remove_child(next_record); next_record.free()
	var replacement_first := Button.new(); replacement_first.name = "Open"; replacement_first.set_meta("character_id", "hero.one"); body.add_child(replacement_first)
	var replacement_next := Button.new(); replacement_next.name = "Open"; replacement_next.set_meta("character_id", "hero.three"); body.add_child(replacement_next)
	focus_memory.prepare(body, &"character"); focus_memory.restore(root, body, null, &"character", false, 0, 0)
	assert_equal(root.get_viewport().gui_get_focus_owner(), replacement_next, "when a focused record disappears, semantic restoration chooses the next surviving record before the previous one")
	root.free()


func _test_controller_radial_pages_and_explicit_commit() -> void:
	var host := Control.new(); host.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT); host.size = Vector2(800, 600)
	(Engine.get_main_loop() as SceneTree).root.add_child(host)
	var radial := load("res://src/ui/shared/controller/controller_radial_overlay.tscn").instantiate() as ControllerRadialOverlay; host.add_child(radial)
	await (Engine.get_main_loop() as SceneTree).process_frame
	var entries: Array[ControllerRadialEntry] = []; for index: int in 10:
		entries.append(ControllerRadialEntry.new(StringName("command_%d" % index), "Command %d" % index, index != 0, "Blocked by the current interaction until its complete authored response has been selected and confirmed." if index == 0 else ""))
	var selected: Array[StringName] = []
	radial.command_selected.connect(func(command_id: StringName) -> void: selected.append(command_id))
	radial.open(entries)
	assert_equal([radial.current_page_entries().size(), radial.page_count()], [8, 2], "radials retain stable ordering across pages of at most eight sectors")
	radial.confirm_selected()
	assert_true(radial.is_open() and selected.is_empty() and (radial.find_child("ReasonLabel", true, false) as Label).text.ends_with("selected and confirmed."), "confirming a disabled sector keeps the radial open with its complete untruncated explanation")
	radial.move_direction(Vector2.RIGHT)
	radial.confirm_selected()
	assert_true(not radial.is_open() and selected.size() == 1, "a highlighted enabled command executes only after explicit confirmation")
	radial.open(entries)
	radial.next_page()
	assert_equal(radial.current_page_entries().size(), 2, "the final radial page exposes only its remaining stable entries")
	var card := radial.find_child("Card", true, false) as PanelContainer
	var heading := radial.find_child("Heading", true, false) as Control; var reason_panel := radial.find_child("ReasonPanel", true, false) as Control; assert_true(host.get_global_rect().encloses(card.get_global_rect()) and card.size.x <= 120.0 and card.size.y <= 72.0 and heading.position.y + heading.size.y < card.position.y and reason_panel.position.y > card.position.y + card.size.y, "the compact radial center stays within 120 by 72 while its title and reason remain outside the wheel opening at 800 by 600")
	radial.cancel()
	assert_false(radial.is_open(), "cancel closes the radial without dispatching another command")
	var shell := load("res://src/ui/shell/game_shell.tscn").instantiate() as GameShell; host.add_child(shell); await (Engine.get_main_loop() as SceneTree).process_frame
	for shell_size: Vector2 in [Vector2(800, 600), Vector2(1280, 720)]: host.size = shell_size; await (Engine.get_main_loop() as SceneTree).process_frame; shell.controller.hide_prompts(); var stage_before := (shell.find_child("StageFrame", true, false) as Control).get_global_rect(); shell.controller.show_prompts(ControllerPreferences.PROMPT_XBOX, &"workspace"); var prompt_rect := (shell.find_child("ControllerPromptStrip", true, false) as Control).get_global_rect(); var stage_rect := (shell.find_child("StageFrame", true, false) as Control).get_global_rect(); var footer_rect := (shell.find_child("BottomRegion", true, false) as Control).get_global_rect(); assert_true(prompt_rect.intersects(stage_rect) and not prompt_rect.intersects(footer_rect) and stage_rect == stage_before, "the transient controller hint floats over the upper stage without changing shell geometry at %s" % shell_size)
	assert_true(shell.controller.open_workspace_radial(), "North opens the curated workspace wheel"); var workspace_radial := shell.find_child("ControllerRadialOverlay", true, false) as ControllerRadialOverlay; assert_equal(workspace_radial.current_page_entries().map(func(entry: ControllerRadialEntry) -> StringName: return entry.id), [&"inventory", &"spells", &"journal", &"character", &"services", &"workspace_preferences", &"workspace_save_load", &"exploration"], "the primary workspace wheel exposes the approved eight stable destinations in order"); shell.controller.cancel_radial()
	assert_true(shell.controller.open_top_menu() and shell.controller.move_top_menu(Vector2i.DOWN), "View/Create/Minus opens the scene-owned entry layer"); var menu_overlay := shell.find_child("ControllerTopMenuOverlay", true, false) as Control; assert_true(menu_overlay.visible and (menu_overlay.find_child("Reason", true, false) as Label).visible, "disabled controller entries remain inspectable with their reason"); shell.controller.confirm_top_menu(); assert_true(shell.controller.top_menu_is_open(), "South cannot execute a disabled entry"); var quit_count := [0]
	assert_true(shell.controller.back_top_menu() and shell.controller.move_top_menu(Vector2i.RIGHT) and shell.controller.move_top_menu(Vector2i.DOWN), "East returns to headings before a fresh direction opens another menu"); shell.controller.move_top_menu(Vector2i.ZERO); shell.quit_requested.connect(func() -> void: quit_count[0] += 1); for _repeat: int in 20: shell.controller.move_top_menu(Vector2i.DOWN, true)
	assert_equal(shell.controller.selected_top_menu_label(), "Quit", "held entry navigation clamps at the final command instead of wrapping")
	shell.controller.confirm_top_menu(); assert_equal([quit_count[0], shell.controller.top_menu_is_open()], [1, false], "South dispatches the selected controller menu command exactly once and releases menu ownership"); assert_true(shell.controller.open_top_menu() and shell.controller.move_top_menu(Vector2i.DOWN) and shell.controller.back_top_menu() and shell.controller.back_top_menu(), "East cancels the entry and heading levels independently")
	var activated: Array[StringName] = []; assert_true(shell.controller.open_interaction_radial([ControllerRadialEntry.new(&"speak", "Speak")], func(command_id: StringName) -> void: activated.append(command_id)), "an interaction can claim the shared action radial"); shell.controller.confirm_radial(); assert_equal(activated, [&"speak"], "confirming an interaction radial retains and invokes its interaction owner")
	var hold_view := GameView.new(1, true, null); hold_view.campaign_id = "controller-hold"; hold_view.campaign_summary = CampaignSummaryView.new(); hold_view.party_members = [CharacterView.new(CharacterState.new("hero", "Hero", 10, 10))]; hold_view.set_action_availability(&"rest", true); hold_view.set_action_availability(&"heal", true)
	var intents: Array[PlayerIntent] = []; shell.intent_submitted.connect(func(intent: PlayerIntent) -> void: intents.append(intent)); shell.present(hold_view); await (Engine.get_main_loop() as SceneTree).process_frame
	assert_true(shell.commands.activate_controller(&"rest") and intents.size() == 1 and intents[0].kind == PlayerIntent.Kind.REST, "confirming Rest through the radial begins its ordinary held-command owner with one immediate pulse"); shell.commands.call("_on_timeout"); assert_equal(intents.size(), 2, "a held radial Rest repeats through the same presentation cadence as its footer button"); shell.controller.release_controller_hold(); shell.commands.call("_on_timeout"); assert_equal(intents.size(), 2, "releasing controller Confirm ends the radial-held command without another pulse")
	assert_true(shell.commands.activate_controller(&"heal") and intents.size() == 3 and intents[-1].kind == PlayerIntent.Kind.HEAL, "confirming Heal through the radial begins its ordinary held-command owner"); shell.commands.call("_on_timeout"); shell.controller.release_controller_hold(); shell.commands.call("_on_timeout"); assert_equal([intents.size(), intents[-1].kind], [4, PlayerIntent.Kind.HEAL], "held radial Heal repeats only until controller Confirm releases")
	host.free(); await (Engine.get_main_loop() as SceneTree).process_frame


func _test_persistent_auto_continuation() -> void:
	var current: Array[GameView] = [_auto_view(10, 1, "hero")]; var blocker: Array[StringName] = [&""]; var submissions: Array[Dictionary] = []; var failures: Array[String] = []; var fail_submit: Array[bool] = [false]; var coordinator: RefCounted = PERSISTENT_AUTO_COORDINATOR.new(); var coordinator_ref: WeakRef = weakref(coordinator)
	coordinator.configure(func() -> GameView: return current[0], func() -> int: return 41, func() -> StringName: return blocker[0], func(response: InteractionResponse) -> SessionStep:
		var body := response.body as InteractionResponse.CombatBody; submissions.append({"actor": body.actor_id, "round": current[0].combat_view.round_number, "revision": current[0].revision})
		if fail_submit[0]: return SessionStep.failed(current[0].revision, &"fixture-auto-failure", "Auto activation failed visibly.")
		current[0] = _auto_view(current[0].revision + 1, current[0].combat_view.round_number + 1, "hero" if submissions.size() < 3 else "manual")
		(coordinator_ref.get_ref() as RefCounted).call("request"); return SessionStep.completed(current[0].revision), func(step: SessionStep) -> void: failures.append(step.error_message if step != null else "missing step"))
	coordinator.request(); for _frame: int in 8: await (Engine.get_main_loop() as SceneTree).process_frame
	assert_equal(submissions, [{"actor": "hero", "round": 1, "revision": 10}, {"actor": "hero", "round": 2, "revision": 11}, {"actor": "hero", "round": 3, "revision": 12}], "the application-owned continuation commits one rendered Auto activation per round and yields to a manual actor")
	current[0] = _auto_view(20, 4, "hero"); blocker[0] = &"controller-suspended"; coordinator.request(); await (Engine.get_main_loop() as SceneTree).process_frame
	assert_equal([submissions.size(), coordinator.observation()["blocker"]], [3, "controller-suspended"], "controller suspension retains the pending Auto activation without running it")
	blocker[0] = &""; coordinator.poll(); await (Engine.get_main_loop() as SceneTree).process_frame; await (Engine.get_main_loop() as SceneTree).process_frame
	assert_equal(submissions.size(), 4, "explicit acknowledgement wakes the retained Auto continuation")
	current[0] = _auto_view(30, 5, "hero"); blocker[0] = &"presentation-awaiting-draw"; coordinator.request(); current[0] = _auto_view(31, 5, "manual"); blocker[0] = &""; coordinator.poll(); await (Engine.get_main_loop() as SceneTree).process_frame
	assert_equal(submissions.size(), 4, "a session revision change discards stale continuation work before it can submit")
	assert_true(failures.is_empty(), "successful persistent Auto never enters the failure latch")
	current[0] = _auto_view(40, 6, "hero"); fail_submit[0] = true; coordinator.request(); coordinator.request(); assert_equal([submissions.size(), failures, coordinator.observation()["failedRevision"]], [5, ["Auto activation failed visibly."], 40], "a failed Auto response reports once and suppresses retries for the failed revision")
	current[0] = _auto_view(41, 6, "hero"); fail_submit[0] = false; coordinator.request(); assert_equal(submissions.size(), 6, "a later committed revision can explicitly re-arm Auto after the failed revision")
	var completed := _auto_view(42, 7, "hero"); completed.combat_view.outcome = &"victory"; current[0] = completed
	var terminal_observation: Dictionary = coordinator.observation(); assert_equal([terminal_observation["active"], terminal_observation["outcome"], terminal_observation["actor"], terminal_observation["round"]], [false, "victory", "", -1], "terminal combat observations expose the outcome without misreporting the final actor and round as a pending Auto activation")
	coordinator.invalidate(); current.clear(); coordinator = null
	await (Engine.get_main_loop() as SceneTree).process_frame


func _auto_view(revision: int, round_number: int, actor_id: String) -> GameView:
	var tiles: Array[int] = []; tiles.resize(BattlefieldGrid.CELL_COUNT); tiles.fill(0); var view := GameView.new(revision, true, null); var combat := CombatState.new("controller.auto", [], 0, BattlefieldState.new("land:0", tiles)); combat.set_turn_order([actor_id])
	view.combat_view = CombatView.new(combat); view.combat_view.round_number = round_number; view.combat_view.active_actor_id = actor_id; view.combat_view.auto_character_ids = ["hero"]; view.combat_view.outcome = &"active"
	view.combat_action_request = ClassicUiFixtureGallery.request_for(InteractionRequest.COMBAT)
	return view


func _test_qwerty_draft_commit_cancel_and_layout() -> void:
	var host := Control.new()
	host.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	host.size = Vector2(800, 600)
	(Engine.get_main_loop() as SceneTree).root.add_child(host)
	var field := LineEdit.new()
	field.text = "Ab"
	field.max_length = 4
	field.caret_column = 1
	host.add_child(field)
	var submitted := [0]
	field.text_submitted.connect(func(_value: String) -> void: submitted[0] += 1)
	var editor := load("res://src/ui/shared/controller/controller_qwerty_editor.tscn").instantiate() as ControllerQwertyEditor
	host.add_child(editor)
	await (Engine.get_main_loop() as SceneTree).process_frame
	assert_true(editor.open_for(field), "activating a LineEdit opens the controller QWERTY editor with its existing draft")
	await (Engine.get_main_loop() as SceneTree).process_frame
	var first_key := editor.get_viewport().gui_get_focus_owner()
	editor.move_direction(Vector2.DOWN)
	var moved_key := editor.get_viewport().gui_get_focus_owner()
	assert_true(moved_key != first_key and editor.is_ancestor_of(moved_key), "directional controller navigation advances between QWERTY keys without escaping the modal: %s -> %s" % [first_key, moved_key])
	var cancel_key := editor.find_child("Cancel", true, false) as Button
	var done_key := editor.find_child("Done", true, false) as Button
	cancel_key.grab_focus()
	editor.move_direction(Vector2.RIGHT)
	assert_equal(editor.get_viewport().gui_get_focus_owner(), done_key, "QWERTY action-row navigation moves predictably from Cancel to Done")
	editor.confirm_key("x")
	assert_equal(field.text, "Ab", "QWERTY edits remain draft-local before Done")
	editor.done()
	assert_equal([field.text, field.caret_column, submitted[0]], ["Axb", 2, 0], "Done returns the edited draft and caret without submitting the outer form")
	field.text = "Keep"
	field.caret_column = 2
	editor.open_for(field)
	editor.backspace()
	editor.cancel()
	assert_equal([field.text, field.caret_column], ["Keep", 2], "Cancel restores the prior field value and caret")
	var note := TextEdit.new()
	note.text = "Line"
	var note_changes := [0]
	note.text_changed.connect(func() -> void: note_changes[0] += 1)
	host.add_child(note)
	editor.open_for(note)
	editor.confirm_key("\n")
	editor.confirm_key("é")
	editor.done()
	assert_equal([note.text, note_changes[0] > 0], ["\néLine", true], "multiline and supported accented input commit through the same editor and refresh the original field's validation")
	var card := editor.find_child("Card", true, false) as PanelContainer
	assert_true(host.get_global_rect().encloses(card.get_global_rect()), "the complete QWERTY editor remains bounded at 800 by 600")
	assert_true(["Space", "Delete", "CaretLeft", "CaretRight", "Done", "Cancel"].all(func(name: String) -> bool: return editor.find_child(name, true, false) != null), "controller text shortcuts remain paired with visible keys")
	host.free()


func _test_controller_settings_draft_and_embedded_file_dialog() -> void:
	var screen := load("res://src/ui/shell/system_screen.tscn").instantiate() as SystemScreen
	(Engine.get_main_loop() as SceneTree).root.add_child(screen)
	await (Engine.get_main_loop() as SceneTree).process_frame
	var controller := SystemScreenController.new()
	var view := GameView.new(1, true, null)
	view.campaign_id = "controller.fixture"
	var settings := PresentationSettings.new()
	var captures: Array[StringName] = []
	var applied: Array[ControllerPreferences] = []
	controller.controller_binding_capture_requested.connect(func(action_id: StringName) -> void: captures.append(action_id))
	controller.setting_changed.connect(func(setting_id: StringName, value: Variant) -> void:
		if setting_id == &"controller_preferences": applied.append(value as ControllerPreferences)
	)
	controller.present(screen, view, settings)
	assert_true(controller.navigate_section(&"Controls") and controller.navigate_section(&"", 1) and (screen.find_child("SystemWorkspaceTabs", true, false) as TabContainer).current_tab == 6, "shoulders switch declared Preferences sections without walking every control")
	var confirm := screen.find_child("ControllerBinding_confirm", true, false) as Button
	confirm.pressed.emit()
	assert_equal(captures, [&"realmz_controller_confirm"], "the Controls page gives binding capture sole ownership of a named draft action")
	controller.controller.receive_binding(&"realmz_controller_confirm", {"action": "realmz_controller_confirm", "kind": "button", "code": JOY_BUTTON_MISC1, "direction": 0})
	var apply := screen.find_child("ApplyControllerBindings", true, false) as Button
	assert_false(apply.disabled, "a conflict-free reachable draft can be applied while current controls remain active")
	apply.pressed.emit()
	assert_true(applied.size() == 1 and applied[0].bindings.any(func(binding: Dictionary) -> bool: return binding["action"] == "realmz_controller_confirm" and binding["code"] == JOY_BUTTON_MISC1), "Apply emits one complete typed controller preference value")
	var campaign_panel: Control = load("res://src/ui/setup/campaign_selection_panel.tscn").instantiate() as Control
	var dialog := campaign_panel.find_child("InstallScenarioDialog", true, false) as FileDialog
	assert_true(dialog != null and not dialog.use_native_dialog, "scenario installation uses Godot's embedded controller-focusable file dialog")
	campaign_panel.free()
	screen.free()
