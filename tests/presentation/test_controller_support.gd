extends RealmzTestCase


func run() -> void:
	_test_controller_preferences_round_trip_and_migration()
	_test_controller_bindings_and_conflicts()
	_test_controller_owner_edges_hysteresis_and_takeover()


func _test_controller_preferences_round_trip_and_migration() -> void:
	var settings := PresentationSettings.new()
	settings.master_volume = 0.35
	settings.controller.prompt_family = ControllerPreferences.PROMPT_PLAYSTATION
	settings.controller.left_stick_dead_zone = 0.3
	settings.controller.repeat_initial_ms = 425
	var restored := PresentationSettings.from_data(settings.to_data())
	assert_not_null(restored, "schema-fourteen controller preferences decode")
	assert_equal([restored.master_volume, restored.controller.prompt_family, restored.controller.left_stick_dead_zone, restored.controller.repeat_initial_ms], [0.35, ControllerPreferences.PROMPT_PLAYSTATION, 0.3, 425], "controller tuning round-trips without changing existing presentation values")
	var legacy := settings.to_data()
	legacy["schemaVersion"] = 13
	legacy.erase("controller")
	var migrated := PresentationSettings.from_data(legacy)
	assert_not_null(migrated, "schema-thirteen presentation settings migrate")
	assert_equal([migrated.master_volume, migrated.controller.prompt_family, migrated.controller.left_stick_dead_zone, migrated.controller.repeat_initial_ms, migrated.controller.repeat_interval_ms], [0.35, ControllerPreferences.PROMPT_AUTO, 0.25, 350, 100], "legacy values survive while controller support receives stable defaults")
	var malformed := settings.to_data()
	malformed["controller"]["leftStickDeadZone"] = 0.02
	assert_equal(PresentationSettings.from_data(malformed), null, "current settings reject an unusable stick dead zone")
	malformed = settings.to_data()
	malformed["controller"]["bindings"] = (malformed["controller"]["bindings"] as Array).filter(func(binding: Dictionary) -> bool: return binding["action"] != "realmz_controller_confirm")
	assert_equal(PresentationSettings.from_data(malformed), null, "current settings reject a draft without required confirmation navigation")


func _test_controller_bindings_and_conflicts() -> void:
	var preferences := ControllerPreferences.new()
	assert_true(preferences.required_navigation_is_reachable() and preferences.conflicts().is_empty(), "physical-position defaults provide a conflict-free complete navigation set")
	UiInputActions.apply_controller_bindings(preferences)
	var confirm_events := InputMap.action_get_events(&"realmz_controller_confirm")
	assert_true(confirm_events.any(func(event: InputEvent) -> bool: return event is InputEventJoypadButton and (event as InputEventJoypadButton).button_index == JOY_BUTTON_A), "South is registered as the default confirm position")
	preferences.bindings.append({"action": "realmz_controller_back", "kind": "button", "code": JOY_BUTTON_A, "direction": 0})
	assert_equal(preferences.conflicts().size(), 1, "binding drafts identify a physical input assigned to two commands")


func _test_controller_owner_edges_hysteresis_and_takeover() -> void:
	var owner := ControllerInputOwner.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(owner)
	owner.configure(ControllerPreferences.new())
	var pressed: Array[StringName] = []
	var released: Array[StringName] = []
	owner.action_pressed.connect(func(action_id: StringName, _repeated: bool) -> void: pressed.append(action_id))
	owner.action_released.connect(func(action_id: StringName) -> void: released.append(action_id))
	var noise := InputEventJoypadMotion.new()
	noise.device = 2
	noise.axis = JOY_AXIS_LEFT_X
	noise.axis_value = 0.12
	assert_false(owner.handle_input(noise), "sub-dead-zone stick noise does not claim controller ownership")
	assert_equal(owner.active_device(), -1, "stick noise leaves the active controller unchanged")
	var right := InputEventJoypadMotion.new()
	right.device = 2
	right.axis = JOY_AXIS_LEFT_X
	right.axis_value = 0.26
	assert_true(owner.handle_input(right), "a deliberate stick direction is consumed by the normalized owner")
	assert_equal([owner.active_device(), pressed], [2, [&"realmz_controller_right"]], "deliberate input claims one pad and produces one direction edge")
	right.axis_value = 0.2
	owner.handle_input(right)
	assert_true(released.is_empty(), "release hysteresis retains the direction slightly below its press threshold")
	right.axis_value = 0.16
	owner.handle_input(right)
	assert_equal(released, [&"realmz_controller_right"], "crossing the hysteresis release boundary emits one release edge")
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
	owner.suspend("test")
	assert_true(owner.is_suspended(), "focus loss or disconnect suspends controller dispatch")
	south.pressed = false
	owner.handle_input(south)
	south.pressed = true
	owner.handle_input(south)
	assert_false(owner.is_suspended(), "a neutral explicit button acknowledgement resumes controller dispatch")
	owner.free()
