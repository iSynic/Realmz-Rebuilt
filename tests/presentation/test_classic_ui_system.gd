extends RealmzTestCase

const SaveSlotPreviewScript := preload("res://src/infrastructure/saves/save_slot_preview.gd")
const ApplicationLifecycleScript := preload("res://src/app/application_lifecycle.gd")
const LifecycleInteractionScript := preload("res://src/presentation/interaction_components/lifecycle_interaction.gd")


func run() -> void:
	_test_route_catalog()
	_test_layout_profiles()
	_test_settings_schema_and_migration()
	_test_movement_input()
	_test_safe_item_display()
	_test_action_availability()
	_test_fixture_gallery_coverage()
	_test_interaction_identity()
	_test_lifecycle_interaction()
	_test_classic_choice_context()
	_test_battle_weapon_mode_component()
	_test_shop_component()
	_test_temple_component()
	_test_bank_component()
	_test_money_workspace_audio()
	_test_classic_asset_catalog()
	_test_stone_surface_tiling()
	_test_spatial_stage_visibility()
	_test_battlefield_presenter()
	_test_automatic_workflow_routes()
	_test_character_creator_workflow()
	_test_character_vault_workspace()
	_test_field_spell_workspace()
	_test_inventory_workspace()
	_test_money_workspace()
	_test_party_order_workspace()
	_test_character_sheet_workspace()
	_test_party_roster()
	_test_scene_composition()
	_test_save_preview_workspace()


func _test_save_preview_workspace() -> void:
	var view := GameView.new(3, true, null)
	view.campaign_id = "preview-campaign"
	view.rules_version = "realmz-classic-1"
	var current := SaveSlotPreviewScript.new("quick", SaveSlotPreviewScript.PRIMARY, SaveSlotPreviewScript.VALID)
	current.rules_version = view.rules_version
	current.package_hash = "1".repeat(64)
	current.realmz_day = 2
	current.realmz_hour = 7
	current.realmz_minute = 15
	current.map_id = "land:4"
	current.coordinate = Vector2i(12, 9)
	current.character_names = ["Mira", "Borin"]
	current.can_load = true
	var backup := SaveSlotPreviewScript.new("quick", SaveSlotPreviewScript.BACKUP, SaveSlotPreviewScript.VALID)
	backup.rules_version = view.rules_version
	backup.can_load = true
	var corrupt := SaveSlotPreviewScript.new("broken", SaveSlotPreviewScript.PRIMARY, SaveSlotPreviewScript.CORRUPT)
	corrupt.error_message = "This save is corrupt or uses an unsupported schema."
	var router := ClassicScreenRouter.new()
	router._body = VBoxContainer.new()
	router._content_parent = router._body
	router.add_child(router._body)
	router._view = view
	router._save_previews = [current, backup, corrupt]
	var actions: Array[Dictionary] = []
	router.system_action_requested.connect(func(action: StringName, value: Variant) -> void: actions.append({"action": action, "value": value}))
	router._render_system()
	var buttons: Array[Button] = []
	var labels: Array[String] = []
	for node: Node in router.find_children("*", "Button", true, false):
		buttons.append(node as Button)
	for node: Node in router.find_children("*", "Label", true, false):
		labels.append((node as Label).text)
	assert_true(labels.any(func(text: String) -> bool: return text.contains("Day 2") and text.contains("land:4 12,9")), "valid save previews expose detached time and location facts")
	assert_true(labels.any(func(text: String) -> bool: return text.contains("Mira, Borin")), "valid save previews expose detached party identity")
	var current_load := buttons.filter(func(button: Button) -> bool: return button.text == "Load save")[0] as Button
	var backup_load := buttons.filter(func(button: Button) -> bool: return button.text == "Load backup")[0] as Button
	var disabled_loads := buttons.filter(func(button: Button) -> bool: return button.text == "Load save" and button.disabled)
	assert_equal(disabled_loads.size(), 1, "corrupt records remain visible with a disabled operation")
	assert_true(disabled_loads[0].tooltip_text.contains("corrupt"), "the corrupt record exposes an exact reason")
	current_load.pressed.emit()
	backup_load.pressed.emit()
	assert_equal(actions, [{"action": &"load", "value": "quick"}, {"action": &"load_backup", "value": "quick"}], "current and backup previews emit distinct host operations")
	router.free()


func _test_battle_weapon_mode_component() -> void:
	var request := InteractionRequest.new("battle.weapon-mode", &"combat_action", {
		"round": 2,
		"actorId": "character.archer",
		"actions": ["switch_weapon", "cast_spell", "use_item", "finish", "defend", "retreat"],
		"weaponMode": "missile",
		"weaponSwitch": {"enabled": true, "targetMode": "melee", "reason": ""},
		"rangedAttack": {"enabled": false, "reason": "Missile range, line of sight, and projectile resolution are unavailable."},
		"retreat": {"enabled": false, "reason": "An enemy is too close.", "nearestEnemyRange": 1},
		"targets": [{"id": "monster.target", "name": "Target", "currentHealth": 5, "maximumHealth": 5}],
		"spellCasts": [
			{"spellId": "spell.flame", "spellName": "Flame", "power": 2, "cost": 4, "targetId": "monster.target", "targetName": "Target", "targetCurrentHealth": 5, "targetMaximumHealth": 5},
			{"spellId": "spell.wave", "spellName": "Wave", "power": 1, "cost": 3, "targetId": "", "targetName": "Everybody", "targetCurrentHealth": -1, "targetMaximumHealth": -1},
			{"spellId": "spell.burst", "spellName": "Burst", "power": 3, "cost": 6, "targetId": "", "targetName": "Choose battlefield point", "targetCurrentHealth": -1, "targetMaximumHealth": -1, "targetMode": "area", "areaShape": 3, "defaultTargetCoordinate": [45, 45], "areaOffsets": [[0, -1], [-1, 0], [0, 0], [1, 0], [0, 1]]},
			{"spellId": "spell.darts", "spellName": "Darts", "power": 3, "cost": 6, "targetId": "", "targetName": "Choose up to 3 actors", "targetCurrentHealth": -1, "targetMaximumHealth": -1, "targetMode": "sequence", "maximumTargets": 3, "targetCandidates": [
				{"id": "monster.target", "kind": "monster", "name": "Target", "currentHealth": 5, "maximumHealth": 5},
				{"id": "character.ally", "kind": "character", "name": "Ally", "currentHealth": 8, "maximumHealth": 10},
			]},
		],
		"itemCasts": [
			{"itemInstanceId": "item.wand.instance", "itemId": "item.wand", "itemName": "Runed Wand", "charges": 3, "spellId": "spell.flame", "spellName": "Flame", "power": 2, "targetId": "monster.target", "targetName": "Target", "targetCurrentHealth": 5, "targetMaximumHealth": 5, "targetMode": "combatant"},
		],
		"movement": [
			{"direction": [0, -1], "destination": [45, 44], "cost": 1, "enabled": true, "reason": ""},
			{"direction": [1, 0], "destination": [46, 45], "cost": 1, "enabled": false, "reason": "Destination occupied."},
			{"direction": [-1, 0], "destination": [1, 45], "cost": 0, "enabled": true, "reason": "", "retreat": true, "forcedRetreat": false},
		],
	})
	var component := BattleInteraction.new()
	var submitted: Array[Dictionary] = []
	component.payload_submitted.connect(func(payload: Dictionary) -> void: submitted.append(payload))
	component.build(request)
	var buttons: Array[Button] = []
	for child: Node in component.find_children("*", "Button", true, false):
		buttons.append(child as Button)
	assert_false(buttons.any(func(button: Button) -> bool: return button.text.begins_with("Attack ")), "missile mode renders no melee attack target buttons")
	var fire_button: Button = null
	var switch_button: Button = null
	var move_button: Button = null
	var edge_button: Button = null
	var finish_button: Button = null
	var escape_button: Button = null
	var cast_button: Button = null
	var use_item_button: Button = null
	var add_target_button: Button = null
	for button: Button in buttons:
		if button.text == "Fire missile unavailable":
			fire_button = button
		elif button.text == "Switch to melee":
			switch_button = button
		elif button.text.begins_with("N "):
			move_button = button
		elif button.text == "Leave W":
			edge_button = button
		elif button.text == "Finish turn":
			finish_button = button
		elif button.text == "Escape":
			escape_button = button
		elif button.text == "Cast selected spell":
			cast_button = button
		elif button.text == "Use selected item":
			use_item_button = button
		elif button.text == "Add target":
			add_target_button = button
	assert_not_null(fire_button, "the unresolved ranged action remains visible instead of silently disappearing")
	assert_true(fire_button.disabled and not fire_button.tooltip_text.is_empty(), "the disabled Fire action exposes the typed tactical blocker")
	assert_not_null(switch_button, "the source-backed no-cost mode toggle remains available")
	assert_not_null(move_button, "the typed battle component exposes a source-probed tactical step")
	assert_not_null(edge_button, "the typed battle component distinguishes edge Escape from ordinary movement")
	assert_equal(move_button.tooltip_text, "Move N • 1 MP", "compact movement labels retain their complete directional and movement-point meaning")
	assert_equal(edge_button.tooltip_text, "Leave battle W", "compact edge movement retains its complete battle-exit meaning")
	assert_not_null(finish_button, "the Classic Finish command remains distinct from Defend")
	assert_true(escape_button != null and escape_button.disabled and escape_button.tooltip_text == "An enemy is too close.", "the explicit Escape control exposes the core-owned unavailable reason")
	assert_not_null(cast_button, "the battle component exposes a core-proven spell, power, and target option")
	assert_not_null(use_item_button, "the battle component exposes a core-proven charged item, power, and target option")
	assert_not_null(add_target_button, "the battle component exposes an explicit ordered repeated-target selection control")
	assert_true(finish_button.get_parent().get_index() < move_button.get_parent().get_index(), "primary turn controls precede the compact movement chooser in the bottom command deck")
	var spell_picker := component.get_children().filter(func(child: Node) -> bool: return child is OptionButton)[0] as OptionButton
	assert_equal(spell_picker.get_item_text(1), "Wave • P1 • 3 SP → Everybody", "automatic group spells render their typed label without fabricating one target's HP")
	switch_button.pressed.emit()
	move_button.pressed.emit()
	edge_button.pressed.emit()
	cast_button.pressed.emit()
	spell_picker.select(2)
	spell_picker.item_selected.emit(2)
	var coordinate_inputs := component.find_children("*", "SpinBox", true, false)
	assert_equal(coordinate_inputs.size(), 2, "area spell presentation exposes one typed battlefield coordinate pair")
	(coordinate_inputs[0] as SpinBox).value = 47
	(coordinate_inputs[1] as SpinBox).value = 43
	cast_button.pressed.emit()
	spell_picker.select(3)
	spell_picker.item_selected.emit(3)
	var option_pickers := component.get_children().filter(func(child: Node) -> bool: return child is OptionButton)
	var sequence_target_picker := option_pickers[1] as OptionButton
	sequence_target_picker.select(1)
	add_target_button.pressed.emit()
	sequence_target_picker.select(0)
	add_target_button.pressed.emit()
	cast_button.pressed.emit()
	use_item_button.pressed.emit()
	assert_equal(submitted, [
		{"actorId": "character.archer", "action": "switch_weapon", "targetId": ""},
		{"actorId": "character.archer", "action": "move", "targetId": "", "destination": [45, 44]},
		{"actorId": "character.archer", "action": "retreat_edge", "targetId": "", "destination": [1, 45], "forced": false},
		{"actorId": "character.archer", "action": "cast_spell", "targetId": "monster.target", "spellId": "spell.flame", "power": 2},
		{"actorId": "character.archer", "action": "cast_spell", "targetId": "", "spellId": "spell.burst", "power": 3, "targetCoordinate": [47, 43], "rotation": 0},
		{"actorId": "character.archer", "action": "cast_spell", "targetId": "", "spellId": "spell.darts", "power": 3, "targetIds": ["character.ally", "monster.target"]},
		{"actorId": "character.archer", "action": "use_item", "targetId": "monster.target", "itemInstanceId": "item.wand.instance"},
	], "the presenter emits typed switch, movement, combatant, battlefield-coordinate, ordered repeated-target spell, and charged-item responses")
	component.free()

	var melee_request := InteractionRequest.new("battle.collision-melee", &"combat_action", {
		"actorId": "character.fighter",
		"actions": ["finish", "defend"],
		"weaponMode": "melee",
		"meleeAttackReason": "",
		"targets": [{"id": "monster.contact", "name": "Ogre", "currentHealth": 12, "maximumHealth": 12}],
		"movement": [{"direction": [1, 0], "destination": [46, 45], "cost": 3, "enabled": true, "reason": "", "attackTargetId": "monster.contact", "attackTargetName": "Ogre"}],
	})
	var melee_component := BattleInteraction.new()
	var melee_submitted: Array[Dictionary] = []
	melee_component.payload_submitted.connect(func(payload: Dictionary) -> void: melee_submitted.append(payload))
	melee_component.build(melee_request)
	var melee_buttons: Array[Node] = melee_component.find_children("*", "Button", true, false)
	var collision_button: Button = melee_buttons.filter(func(button: Button) -> bool: return button.text == "Attack E")[0]
	assert_not_null(collision_button, "melee renders the hostile occupied direction as the attack command")
	assert_equal(collision_button.tooltip_text, "Attack Ogre to the E • 3 MP", "collision melee exposes its target, direction, and source-owned movement cost")
	assert_false(melee_buttons.any(func(button: Button) -> bool: return button.text.begins_with("Attack Ogre")), "melee does not duplicate Castle's collision command with a separate target button")
	collision_button.pressed.emit()
	assert_equal(melee_submitted, [{"actorId": "character.fighter", "action": "move", "targetId": "", "destination": [46, 45]}], "collision melee remains a typed directional response and lets the core resolve occupancy")
	melee_component.free()


func _test_shop_component() -> void:
	var request := InteractionRequest.new("shop.fixture", InteractionRequest.SHOP, {
		"partyGold": 19,
		"inflationPercent": 125,
		"identifyPrice": 20,
		"characters": [{"id": "character.one", "name": "Hero", "inventory": [
			{"instanceId": "item.unknown", "name": "Runed wand", "sellPrice": 0, "identified": false, "canSell": true, "sellReason": "", "canIdentify": false, "identifyReason": "Identification costs 20 gold."},
			{"instanceId": "item.equipped", "name": "Sword", "sellPrice": 25, "identified": true, "canSell": false, "sellReason": "Unequip this item before selling it.", "canIdentify": false, "identifyReason": "This item is already identified."},
		]}],
		"stock": [{"stockKey": "buyback:classic.item.5", "index": -1, "name": "Dagger", "buyPrice": 40, "quantity": 1, "canBuy": false, "buyReason": "The party cannot afford this item."}],
	})
	var component := ShopInteraction.new()
	component.build(request)
	var buttons: Array[Button] = []
	for child: Node in component.get_children():
		if child is Button:
			buttons.append(child)
	var buy_button: Button = null
	var unknown_sell: Button = null
	var identify_button: Button = null
	var equipped_sell: Button = null
	for button: Button in buttons:
		if button.text.begins_with("Dagger"):
			buy_button = button
		elif button.text.begins_with("Sell Runed wand"):
			unknown_sell = button
		elif button.text.begins_with("Identify Runed wand"):
			identify_button = button
		elif button.text.begins_with("Sell Sword"):
			equipped_sell = button
	assert_not_null(buy_button, "shop buyback stock renders through the typed component")
	assert_true(buy_button.disabled and buy_button.tooltip_text.contains("afford"), "unaffordable stock exposes its core-owned reason")
	assert_not_null(unknown_sell, "unidentified inventory uses the player-knowable item name")
	assert_not_null(identify_button, "unknown items expose paid shop identification")
	assert_true(identify_button.disabled and identify_button.tooltip_text.contains("20 gold"), "paid identification exposes the exact affordability blocker")
	assert_not_null(equipped_sell, "equipped items remain visible in the sale list")
	assert_true(equipped_sell.disabled and equipped_sell.tooltip_text.contains("Unequip"), "ordinary sale cannot bypass the equipment workflow")
	component.free()


func _test_temple_component() -> void:
	var request := InteractionRequest.new("temple.fixture", InteractionRequest.TEMPLE, {
		"costPercent": 125,
		"selectedCharacterId": "character.two",
		"pooledWealth": {"gold": 100, "gems": 0, "jewelry": 0},
		"characters": [
			{"id": "character.one", "name": "Hero", "currentHealth": 4, "maximumHealth": 12, "personalGold": 300, "availableGold": 400, "load": 20, "maximumLoad": 100, "conditions": [{"index": 9, "name": "Poisoned", "value": 3}]},
			{"id": "character.two", "name": "Poor Hero", "currentHealth": -12, "maximumHealth": 10, "personalGold": 0, "availableGold": 100, "load": 0, "maximumLoad": 100, "conditions": []},
		],
		"services": [
			{"id": "heal-small", "label": "Heal Small Wounds", "description": "Restore 1-8 stamina.", "cost": 312},
			{"id": "revive-dead", "label": "Revive Dead", "description": "Restore an eligible dead character.", "cost": 1875},
		],
	})
	var component := TempleInteraction.new()
	var submitted: Array[Dictionary] = []
	component.payload_submitted.connect(func(payload: Dictionary) -> void: submitted.append(payload))
	component.build(request)
	var buttons: Array[Button] = []
	for child: Node in component.get_children():
		if child is Button:
			buttons.append(child)
	var heal_button: Button = buttons.filter(func(button: Button) -> bool: return button.text.begins_with("Heal Small Wounds"))[0]
	var revive_button: Button = buttons.filter(func(button: Button) -> bool: return button.text.begins_with("Revive Dead"))[0]
	assert_true(heal_button.disabled, "the request's selected character identity is restored before affordability is rendered")
	assert_true(revive_button.disabled and revive_button.tooltip_text.contains("1875 gold"), "unaffordable temple services remain visible with the exact blocker")
	var picker := component.get_children().filter(func(child: Node) -> bool: return child is OptionButton)[0] as OptionButton
	assert_equal(String(picker.get_selected_metadata()), "character.two", "the presenter preserves the save-owned selected temple character")
	var summary := component.get_children().filter(func(child: Node) -> bool: return child is Label and child.text.contains("Poor Hero"))[0] as Label
	assert_true(summary.text.contains("HP -12/10"), "the temple summary exposes the selected character's source health state")
	picker.select(0)
	picker.item_selected.emit(0)
	assert_false(heal_button.disabled, "changing the selected character recalculates affordability from detached values")
	heal_button.pressed.emit()
	var pool_button: Button = buttons.filter(func(button: Button) -> bool: return button.text == "Pool party wealth")[0]
	pool_button.pressed.emit()
	assert_equal(submitted, [
		{"action": "service", "serviceId": "heal-small", "characterId": "character.one"},
		{"action": "pool", "selectedCharacterId": "character.one"},
	], "the temple presenter emits typed service and wealth responses with the current stable character identity")
	component.free()


func _test_bank_component() -> void:
	var request := InteractionRequest.new("bank.fixture", InteractionRequest.BANK, {
		"selectedCharacterId": "character.one",
		"pooledWealth": {"gold": 35, "gems": 2, "jewelry": 1},
		"bankedWealth": {"gold": 0, "gems": 0, "jewelry": 0},
		"pool": {"enabled": true, "reason": ""},
		"share": {"enabled": false, "reason": "No adventurer can carry another pooled denomination."},
		"characters": [{
			"id": "character.one",
			"name": "Hero",
			"wealth": {"gold": 10, "gems": 1, "jewelry": 0},
			"load": 11,
			"maximumLoad": 20,
			"transfers": [
				{"denomination": "gold", "amount": 5, "toPool": {"enabled": true, "reason": ""}, "toCharacter": {"enabled": true, "reason": ""}},
				{"denomination": "gems", "amount": 1, "toPool": {"enabled": true, "reason": ""}, "toCharacter": {"enabled": true, "reason": ""}},
				{"denomination": "jewelry", "amount": 1, "toPool": {"enabled": false, "reason": "Hero does not carry that amount."}, "toCharacter": {"enabled": false, "reason": "Hero cannot carry that denomination."}},
			],
		}],
	})
	var component := BankInteraction.new()
	var submitted: Array[Dictionary] = []
	component.payload_submitted.connect(func(payload: Dictionary) -> void: submitted.append(payload))
	component.build(request)
	var buttons: Array[Button] = []
	for node: Node in component.find_children("*", "Button", true, false):
		buttons.append(node as Button)
	var labels: Array[String] = []
	for node: Node in component.find_children("*", "Label", true, false):
		labels.append((node as Label).text)
	assert_true(labels.any(func(text: String) -> bool: return text.contains("35 gold") and text.contains("2 gems") and text.contains("1 jewelry")), "bank workspace renders every pooled denomination")
	var share_button: Button = buttons.filter(func(button: Button) -> bool: return button.text == "Share pooled wealth")[0]
	assert_true(share_button.disabled and share_button.tooltip_text.contains("can carry"), "bank workspace displays the core-owned Share blocker")
	var to_character: Array[Button] = buttons.filter(func(button: Button) -> bool: return button.text == "To Hero")
	assert_equal(to_character.size(), 3, "bank-backed Swap exposes all three Classic denomination transfers")
	assert_true(to_character[2].disabled and to_character[2].tooltip_text.contains("cannot carry"), "bank presentation does not duplicate jewelry capacity rules")
	to_character[0].pressed.emit()
	var leave_button: Button = buttons.filter(func(button: Button) -> bool: return button.text == "Done")[0]
	leave_button.pressed.emit()
	assert_equal(submitted, [
		{"action": "to-character", "characterId": "character.one", "denomination": "gold", "amount": 5},
		{"action": "leave"},
	], "bank presenter emits exact typed Swap and Done responses")
	component.free()

	var departure_request := InteractionRequest.new("departure.fixture", InteractionRequest.POOLED_WEALTH_DEPARTURE, request.payload.merged({"mode": "departure"}, true))
	var departure_component := BankInteraction.new()
	var departure_payloads: Array[Dictionary] = []
	departure_component.payload_submitted.connect(func(payload: Dictionary) -> void: departure_payloads.append(payload))
	departure_component.build(departure_request)
	var departure_labels: Array[String] = []
	for node: Node in departure_component.find_children("*", "Label", true, false):
		departure_labels.append((node as Label).text)
	assert_true(departure_labels.any(func(text: String) -> bool: return text.contains("Distribute pooled wealth before leaving")), "pooled departure renders its distinct Classic workflow heading")
	assert_true(departure_labels.any(func(text: String) -> bool: return text.contains("continues this movement attempt")), "pooled departure explains the ordinary checkmoneypool Done outcome")
	assert_false(departure_labels.any(func(text: String) -> bool: return text.contains("Deposited until departure")), "pooled departure does not present bank-only state as part of no-bank Swap")
	var departure_done := departure_component.find_children("*", "Button", true, false).filter(func(button: Node) -> bool: return (button as Button).text == "Done")[0] as Button
	departure_done.pressed.emit()
	assert_equal(departure_payloads, [{"action": "leave"}], "pooled departure emits the same exact typed Done payload as Swap")
	var typed_response := InteractionPresenter.response_for(departure_request, departure_payloads[0])
	assert_equal([typed_response.request_id, typed_response.kind, typed_response.payload], ["departure.fixture", InteractionRequest.POOLED_WEALTH_DEPARTURE, {"action": "leave"}], "pooled departure preserves request identity through the typed presenter boundary")
	departure_component.free()


func _test_money_workspace_audio() -> void:
	var router := ClassicScreenRouter.new()
	var view := GameView.new(1, true, null)
	router._view = view
	var sounds: Array[Dictionary] = []
	router.presentation_sound_requested.connect(func(sound_id: int, wait_for_completion: bool, stop_existing: bool) -> void: sounds.append({"soundId": sound_id, "waitForCompletion": wait_for_completion, "stopExisting": stop_existing}))
	router._sync_ordinary_money_workspace_audio(&"services")
	router._sync_ordinary_money_workspace_audio(&"services")
	router._sync_ordinary_money_workspace_audio(&"exploration")
	assert_equal(sounds, [
		{"soundId": 141, "waitForCompletion": false, "stopExisting": false},
		{"soundId": 3003, "waitForCompletion": false, "stopExisting": true},
		{"soundId": 141, "waitForCompletion": false, "stopExisting": false},
	], "ordinary Swap route requests the source button, quiet-and-open, and Done sequence without duplicates")
	view.pending_interaction = InteractionRequest.new("shop.audio", InteractionRequest.SHOP, {"prompt": "Shop"})
	router._sync_ordinary_money_workspace_audio(&"services")
	assert_equal(sounds.size(), 3, "a Services route opened for a typed location service does not masquerade as ordinary Swap")
	var audio := ClassicAudioPresenter.new()
	var observed: Array[int] = []
	audio.sound_observed.connect(func(sound_id: int) -> void: observed.append(sound_id))
	audio._processing_sounds = true
	audio._pending_sounds.append({"stream": null, "waitForCompletion": true})
	audio.present_sound(3003, null, false, true)
	assert_equal([audio.last_sound_id, observed], [3003, [3003]], "presentation-owned workspace audio uses the same explicit audio presenter path as session events")
	assert_false(audio._processing_sounds, "quiet-and-open cancels an in-flight wait state instead of deadlocking the sound queue")
	assert_true(audio._pending_sounds.is_empty(), "quiet-and-open discards pre-modal queued sounds")
	audio.free()
	router.free()


func _test_route_catalog() -> void:
	assert_equal(UiRouteCatalog.ROUTES.size(), 9, "the canonical route registry contains all nine workspaces")
	var ids: Dictionary = {}
	var shortcuts: Dictionary = {}
	var primary_count: int = 0
	for route: Dictionary in UiRouteCatalog.ROUTES:
		ids[route["id"]] = true
		shortcuts[route["shortcut"]] = true
		primary_count += 1 if bool(route["primary"]) else 0
		assert_false(String(route.get("description", "")).is_empty(), "every route has presentation guidance")
		assert_true(ResourceLoader.exists(String(route.get("scene", "")), "PackedScene"), "every route owns a scene-backed workspace")
	assert_equal(ids.size(), 9, "route identifiers are unique")
	assert_equal(shortcuts.size(), 9, "route shortcuts are unique")
	assert_equal(primary_count, 6, "compact and standard layouts keep six primary workspaces")


func _test_layout_profiles() -> void:
	assert_equal(UiLayoutProfile.for_viewport(Vector2(800, 600), PresentationSettings.UI_SCALE_AUTO).id, UiLayoutProfile.COMPACT, "800x600 uses compact layout")
	assert_equal(UiLayoutProfile.for_viewport(Vector2(960, 600), PresentationSettings.UI_SCALE_AUTO).id, UiLayoutProfile.STANDARD, "960x600 uses standard layout")
	assert_equal(UiLayoutProfile.for_viewport(Vector2(1280, 720), PresentationSettings.UI_SCALE_AUTO).id, UiLayoutProfile.WIDE, "1280x720 uses wide layout")
	assert_equal(UiLayoutProfile.for_viewport(Vector2(1920, 1080), PresentationSettings.UI_SCALE_AUTO).id, UiLayoutProfile.WIDE, "1920x1080 remains wide after automatic density")
	assert_equal(UiLayoutProfile.scale_for(Vector2(800, 600), PresentationSettings.UI_SCALE_125), 1.25, "explicit interface density is independent of viewport")
	assert_equal(UiLayoutProfile.scale_for(Vector2(800, 600), PresentationSettings.UI_SCALE_150), 1.5, "150 percent interface density is supported")
	var compact := UiLayoutProfile.for_viewport(Vector2(800, 600), PresentationSettings.UI_SCALE_AUTO)
	assert_equal(compact.party_width, 208.0, "compact Classic roster uses the specified width")
	assert_equal(compact.bottom_height, 156.0, "compact Classic textbox uses the specified height")
	var standard := UiLayoutProfile.for_viewport(Vector2(960, 600), PresentationSettings.UI_SCALE_AUTO)
	assert_equal(standard.party_width, 256.0, "standard Classic roster uses the specified width")
	assert_equal(standard.bottom_height, 176.0, "standard Classic textbox uses the specified height")
	assert_equal(UiLayoutProfile.for_viewport(Vector2(1600, 900), PresentationSettings.UI_SCALE_AUTO).bitmap_scale, 2, "large automatic layouts may use exact 2x bitmap controls")
	assert_equal(UiLayoutProfile.for_viewport(Vector2(1599, 899), PresentationSettings.UI_SCALE_AUTO).bitmap_scale, 1, "bitmap controls remain 1x below the approved threshold")


func _test_settings_schema_and_migration() -> void:
	var settings := PresentationSettings.new()
	settings.ui_scale_mode = PresentationSettings.UI_SCALE_125
	settings.window_mode = PresentationSettings.BORDERLESS_FULLSCREEN
	settings.text_scale = 1.5
	var restored := PresentationSettings.from_data(settings.to_data())
	assert_not_null(restored, "schema-three presentation settings round-trip")
	assert_equal(restored.ui_scale_mode, PresentationSettings.UI_SCALE_125, "interface density persists separately")
	assert_equal(restored.window_mode, PresentationSettings.BORDERLESS_FULLSCREEN, "window mode persists")
	assert_equal(restored.text_scale, 1.5, "text scale remains independent")
	var version_two := PresentationSettings.from_data({"kind": "realmz2.presentation-settings", "schemaVersion": 2, "masterVolume": 0.5, "topologyDebug": false, "textScale": 1.0, "reducedMotion": false, "dungeon3d": true})
	assert_not_null(version_two, "schema-two settings migrate")
	assert_equal(version_two.ui_scale_mode, PresentationSettings.UI_SCALE_AUTO, "migrated settings default to automatic interface density")
	assert_equal(version_two.window_mode, PresentationSettings.WINDOWED, "migrated settings retain windowed behavior")


func _test_movement_input() -> void:
	UiInputActions.ensure_defaults()
	var expected: Dictionary = {
		&"realmz_move_up": Vector2i.UP,
		&"realmz_move_up_right": Vector2i(1, -1),
		&"realmz_move_right": Vector2i.RIGHT,
		&"realmz_move_down_right": Vector2i(1, 1),
		&"realmz_move_down": Vector2i.DOWN,
		&"realmz_move_down_left": Vector2i(-1, 1),
		&"realmz_move_left": Vector2i.LEFT,
		&"realmz_move_up_left": Vector2i(-1, -1),
	}
	for action: StringName in expected:
		var event := InputEventAction.new()
		event.action = action
		event.pressed = true
		assert_equal(UiInputActions.movement_direction(event), expected[action], "%s resolves to its complete movement vector" % action)
	var keypad_bindings: Dictionary = {}
	for definition: Dictionary in UiInputActions.DEFINITIONS:
		keypad_bindings[definition["id"]] = definition["keys"]
	assert_true(KEY_KP_7 in keypad_bindings[&"realmz_move_up_left"], "keypad 7 owns northwest land movement")
	assert_true(KEY_KP_9 in keypad_bindings[&"realmz_move_up_right"], "keypad 9 owns northeast land movement")
	assert_true(KEY_KP_1 in keypad_bindings[&"realmz_move_down_left"], "keypad 1 owns southwest land movement")
	assert_true(KEY_KP_3 in keypad_bindings[&"realmz_move_down_right"], "keypad 3 owns southeast land movement")


func _test_safe_item_display() -> void:
	var definition := ItemDefinition.new("classic.item.607", 607, "Improvement", "Potion", "Raises a random attribute.")
	definition.icon_id = 555
	definition.cost = 7500
	definition.initial_charges = 1
	definition.item_type = 21
	definition.cursed_item_id = "classic.item.608"
	var hidden := ItemView.new(ItemInstance.new("item-607", definition.id, 1, false, false), definition)
	assert_equal(hidden.name, "Potion", "unidentified items expose only the player-knowable name")
	assert_false(hidden.description.contains("random attribute"), "unidentified items do not leak effect text")
	assert_equal(hidden.value, 0, "unidentified items do not leak identified value")
	assert_equal(hidden.definition_id, "", "unidentified items do not leak stable definition identity")
	assert_equal(hidden.classic_id, 0, "unidentified items do not leak Classic item identity")
	assert_equal(hidden.icon_id, 555, "the authored content icon identity remains available to presentation")
	assert_equal(hidden.icon_resource_type, "CICN", "item icons carry an exact resource type for collision-free lookup")
	assert_equal(hidden.item_type, 21, "the player-visible item type remains available while identity is hidden")
	var known := ItemView.new(ItemInstance.new("item-607", definition.id, 1, false, true), definition)
	assert_equal(known.name, "Improvement", "identified items expose their identified name")
	assert_contains(known.description, "random attribute", "identified items expose their description")
	assert_equal(known.definition_id, definition.id, "identified items expose their stable definition identity")
	definition.hands = 1
	definition.damage_bonus = 2
	definition.vs_small = 6
	definition.magic_resistance_bonus = 5
	definition.heat = 4
	definition.special_1 = 121
	known = ItemView.new(ItemInstance.new("item-607", definition.id, 1, false, true), definition)
	assert_true(known.facts.any(func(fact: ItemFactView) -> bool: return fact.label == "Damage" and fact.value == "3–8"), "identified Describe facts preserve Castle's damage-range convention")
	assert_true(known.facts.any(func(fact: ItemFactView) -> bool: return fact.label == "Magic resistance" and fact.value == "+5"), "identified Describe facts expose source-backed magical modifiers")
	assert_true(known.properties.any(func(property: String) -> bool: return property.contains("special damage")), "identified Describe facts expose Castle's special-damage notice")
	assert_true(known.properties.any(func(property: String) -> bool: return property.contains("to-hit bonus")), "identified Describe facts expose Castle's penetration-weapon explanation")
	var still_hidden := ItemView.new(ItemInstance.new("item-607", definition.id, 1, false, false), definition)
	assert_false(still_hidden.facts.any(func(fact: ItemFactView) -> bool: return fact.label == "Magic resistance"), "unidentified Describe facts do not reveal identified-only modifiers")
	assert_true(still_hidden.facts.any(func(fact: ItemFactView) -> bool: return fact.label == "Damage"), "Castle's always-visible damage range remains visible before identification")
	var decoy := ItemDefinition.new("classic.item.608", 608, "Fine Blade", "Sword", "A finely balanced sword.")
	decoy.icon_id = 999
	decoy.damage_bonus = 1
	decoy.vs_small = 4
	var cursed := ItemDefinition.new("classic.item.609", 609, "Cursed Blade", "Sword", "The revealed blade drains its bearer.")
	cursed.icon_id = 555
	cursed.damage_bonus = -2
	cursed.vs_small = 8
	cursed.cursed_item_id = decoy.id
	var content := RealmzContent.new("item-display", "0".repeat(64), "item-display", "realmz-classic-1", "", Vector2i.ZERO, WorldDefinition.new([]), ScenarioDefinition.new([], []), [], [], [], [], [], [decoy, cursed])
	var bearer := CharacterState.new("item-display.character", "Bearer", 10, 10)
	bearer.set_inventory([ItemInstance.new("item-display.curse", cursed.id, 0, false, true)])
	var concealed := CharacterView.new(bearer, content).items[0]
	assert_equal([concealed.name, concealed.icon_id, concealed.definition_id], [decoy.name, cursed.icon_id, decoy.id], "an unworn cursed item uses Castle's linked decoy record while retaining the original icon")
	assert_false(concealed.curse_revealed, "the detached view does not disclose an unworn curse")
	bearer.inventory()[0].equipped = true
	var revealed := CharacterView.new(bearer, content).items[0]
	assert_equal([revealed.name, revealed.icon_id, revealed.definition_id], [cursed.name, cursed.icon_id, cursed.id], "wearing a cursed item reveals the original record Castle actually applies")
	assert_true(revealed.curse_revealed and revealed.properties.any(func(property: String) -> bool: return property.contains("cannot be removed")), "a revealed curse explains its source-backed removal restriction")


func _test_action_availability() -> void:
	var view := GameView.new(1, true, null)
	view.set_action_availability(&"search", true)
	assert_true(view.availability(&"search").enabled, "declared available actions are enabled")
	assert_equal(view.availability(&"search").reason, "", "enabled actions carry no misleading disabled reason")
	var unknown := view.availability(&"imaginary_action")
	assert_false(unknown.enabled, "undeclared actions remain disabled")
	assert_contains(unknown.reason, "unavailable", "undeclared actions explain their state")


func _test_fixture_gallery_coverage() -> void:
	assert_equal(ClassicUiFixtureGallery.screen_cases().size(), 81, "all nine screens have nine fixture states")
	assert_equal(ClassicUiFixtureGallery.interaction_cases().size(), 144, "all sixteen interaction kinds have nine fixture states")
	for interaction: StringName in ClassicUiFixtureGallery.INTERACTIONS:
		assert_true(ClassicUiFixtureGallery.request_for(interaction).is_supported_kind(), "gallery interaction %s is a supported typed request" % interaction)
	var age_component := AgeUpdateInteraction.new()
	age_component.build(ClassicUiFixtureGallery.request_for(InteractionRequest.AGE_UPDATE))
	assert_true(age_component.get_child_count() >= 4, "the Classic age update renders identity, band, changed statistics, and a response")
	assert_true(age_component.get_children().any(func(child: Node) -> bool: return child is Button and child.text == "Continue"), "the blocking age update exposes one keyboard-focusable continuation")
	age_component.free()
	var recovery_component := TreasureDistributionInteraction.new()
	recovery_component.build(ClassicUiFixtureGallery.request_for(InteractionRequest.TREASURE_DISTRIBUTION, &"missing_media"))
	assert_equal(recovery_component.get_child_count(), 3, "battle recovery renders item detail, an eligible recipient, and leave-behind action")
	assert_true(recovery_component.get_children().any(func(child: Node) -> bool: return child is Label and child.text.contains("7 charges")), "battle recovery exposes the exact preserved charge count")
	assert_true(recovery_component.get_children().any(func(child: Node) -> bool: return child is Button and child.text == "Give to Hero" and not child.disabled), "nominal battle recovery exposes its rules-authorized recipient as an active control")
	recovery_component.free()
	var ordinary_component := TreasureDistributionInteraction.new()
	ordinary_component.build(ClassicUiFixtureGallery.request_for(InteractionRequest.TREASURE_DISTRIBUTION))
	assert_true(ordinary_component.get_children().any(func(child: Node) -> bool: return child is Label and child.text.contains("125 gold")), "ordinary booty exposes the detached pooled denominations")
	assert_true(ordinary_component.get_children().any(func(child: Node) -> bool: return child is Button and child.text == "Give to Hero" and not child.disabled), "ordinary booty exposes rules-owned exact-item assignment")
	assert_true(ordinary_component.get_children().any(func(child: Node) -> bool: return child is Button and child.text == "Done"), "ordinary booty has one typed completion path")
	ordinary_component.free()
	var capacity_component := TreasureDistributionInteraction.new()
	capacity_component.build(ClassicUiFixtureGallery.request_for(InteractionRequest.TREASURE_DISTRIBUTION, &"unavailable"))
	assert_true(capacity_component.get_children().any(func(child: Node) -> bool: return child is Button and child.text == "Give to Hero" and child.disabled and child.tooltip_text.contains("full")), "capacity-blocked booty retains the core-provided disabled reason")
	capacity_component.free()
	var level_component := LevelUpInteraction.new()
	level_component.build(ClassicUiFixtureGallery.request_for(InteractionRequest.LEVEL_UP))
	assert_true(level_component.get_children().any(func(child: Node) -> bool: return child is Label and child.text.contains("level 5")), "the level result presents its committed character level")
	assert_true(level_component.get_children().any(func(child: Node) -> bool: return child is Button and child.text == "Continue"), "the level result exposes one typed acknowledgement")
	level_component.free()
	var spell_component := LevelUpInteraction.new()
	spell_component.build(ClassicUiFixtureGallery.request_for(InteractionRequest.LEVEL_UP, &"unidentified"))
	assert_true(spell_component.get_children().any(func(child: Node) -> bool: return child is ItemList and child.item_count == 4), "the level spell stage renders the complete detached candidate list")
	assert_true(spell_component.get_children().any(func(child: Node) -> bool: return child is Button and child.text == "Confirm spell selection"), "the spell stage exposes one typed confirmation")
	spell_component.free()


func _test_interaction_identity() -> void:
	var request := InteractionRequest.yes_no("request-identity", "Proceed?", "Yes", "No")
	var response := InteractionPresenter.response_for(request, {"accepted": true})
	assert_equal(response.request_id, request.request_id, "interaction response preserves request identity")
	assert_equal(response.kind, request.kind, "interaction response preserves request kind")
	assert_equal(response.payload, {"accepted": true}, "interaction response preserves the exact selected payload")


func _test_lifecycle_interaction() -> void:
	var request := ApplicationLifecycleScript.end_adventure_request(false)
	assert_equal([request.kind, request.payload["inCombat"], request.payload["options"].size()], [InteractionRequest.SESSION_LIFECYCLE, false, 3], "field End Adventure exposes explicit save, discard, and cancel operations")
	assert_not_null(InteractionRequest.from_data(request.to_data()), "the typed lifecycle request retains the established interaction wire shape")
	var component := LifecycleInteractionScript.new()
	var submitted: Array[Dictionary] = []
	component.payload_submitted.connect(func(payload: Dictionary) -> void: submitted.append(payload))
	component.build(request)
	var buttons: Array[Button] = []
	for node: Node in component.find_children("*", "Button", true, false):
		buttons.append(node as Button)
	assert_equal(buttons.map(func(button: Button) -> String: return button.text), ["Save and end adventure", "End adventure without saving", "Cancel"], "the dedicated presenter does not reinterpret lifecycle choices as scenario options")
	buttons[2].pressed.emit()
	assert_equal(submitted, [{"action": &"cancel"}], "Cancel emits one typed host response")
	assert_equal(ApplicationLifecycleScript.response_action(request, InteractionResponse.new(request.request_id, request.kind, submitted[0])), &"cancel", "the host accepts only an action declared by its request")
	assert_equal(ApplicationLifecycleScript.response_action(request, InteractionResponse.new(request.request_id, request.kind, {"action": "invented"})), &"", "undeclared lifecycle actions fail explicitly")
	assert_false(ApplicationLifecycleScript.allows_close(&"save-and-end", false), "a rejected save cannot close the active session")
	assert_true(ApplicationLifecycleScript.allows_close(&"save-and-end", true), "a validated save permits the requested close")
	assert_true(ApplicationLifecycleScript.allows_close(&"end-without-saving"), "explicit discard permits close without a repository write")
	assert_false(ApplicationLifecycleScript.allows_close(&"cancel"), "Cancel never closes the active session")
	var operation_order: Array[String] = []
	var failed_save := ApplicationLifecycleScript.execute(&"save-and-end", func() -> bool: operation_order.append("save"); return false, func() -> SessionStep: operation_order.append("close"); return SessionStep.completed(1))
	assert_equal([failed_save["state"], operation_order], [&"save-failed", ["save"]], "save failure suppresses close instead of tearing down the active session")
	operation_order.clear()
	var discarded := ApplicationLifecycleScript.execute(&"end-without-saving", func() -> bool: operation_order.append("save"); return true, func() -> SessionStep: operation_order.append("close"); return SessionStep.completed(2))
	assert_equal([discarded["state"], operation_order], [&"closed", ["close"]], "explicit discard closes once without touching the save repository")
	operation_order.clear()
	var cancelled := ApplicationLifecycleScript.execute(&"cancel", func() -> bool: operation_order.append("save"); return true, func() -> SessionStep: operation_order.append("close"); return SessionStep.completed(3))
	assert_equal([cancelled["state"], operation_order], [&"cancelled", []], "Cancel invokes neither persistence nor session teardown")
	component.free()
	var combat_request := ApplicationLifecycleScript.end_adventure_request(true)
	assert_equal(combat_request.payload["options"].size(), 2, "battle End Adventure never offers an invalid combat save")
	assert_false(combat_request.payload["options"].any(func(option: Dictionary) -> bool: return StringName(option["action"]) == &"save-and-end"), "battle End Adventure follows Castle's no-save branch")


func _test_classic_choice_context() -> void:
	var classic_request := InteractionRequest.new("classic-choice", InteractionRequest.YES_NO, {"yesLabel": "Yes", "noLabel": "No"})
	assert_equal(InteractionPresenter._prompt_for(classic_request, "Will you enter the ruined keep?"), "Will you enter the ruined keep?", "a label-only Classic choice retains its source-authored textbox context")
	assert_equal(InteractionPresenter._prompt_for(classic_request, ""), "Choose Yes or No to continue.", "a context-free Classic choice explains the required decision without presenting button labels as a prompt")
	var explicit_request := InteractionRequest.yes_no("explicit-choice", "Enter battle?", "Fight", "Avoid")
	assert_equal(InteractionPresenter._prompt_for(explicit_request, "Stale textbox text"), "Enter battle?", "an explicit typed prompt remains authoritative over prior Classic textbox context")


func _test_classic_asset_catalog() -> void:
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://src/presentation/assets/classic-ui-assets.json"))
	assert_equal(manifest["source_commit"], "86cf2bf391ef0c43ba31c1633ddd63b7e67e3d61", "Classic controls retain exact Remake commit provenance")
	assert_equal(manifest["assets"].size(), 61, "the curated Classic UI and map-marker corpus is complete")
	var ids: Dictionary = {}
	for entry: Dictionary in manifest["assets"]:
		ids[entry["id"]] = true
		assert_true(ResourceLoader.exists(entry["path"], "Texture2D"), "Classic bitmap exists: %s" % entry["id"])
		var texture := load(entry["path"]) as Texture2D
		assert_equal(texture.get_width(), int(entry["native_width"]), "Classic bitmap width is unchanged: %s" % entry["id"])
		assert_equal(texture.get_height(), int(entry["native_height"]), "Classic bitmap height is unchanged: %s" % entry["id"])
		assert_equal(_sha256(entry["path"]), entry["sha256"], "Classic bitmap hash is unchanged: %s" % entry["id"])
		assert_equal(entry["rendering"]["allowed_scales"], [1.0, 2.0], "Classic bitmap scaling remains integral")
		assert_false(bool(entry["rendering"]["source_pixels_modified"]), "Classic source pixels are never repainted")
	assert_equal(ids.size(), manifest["assets"].size(), "Classic semantic asset IDs are unique")
	assert_not_null(ClassicUiAssetCatalog.texture(&"command.camp"), "runtime asset catalog resolves the Camp bitmap")
	assert_not_null(ClassicUiAssetCatalog.texture(&"command.rest"), "runtime asset catalog resolves the separate held-Rest bitmap")
	var party_marker := ClassicUiAssetCatalog.definition(ClassicMapPresenter.PARTY_MARKER_ASSET_ID)
	assert_not_null(ClassicUiAssetCatalog.texture(ClassicMapPresenter.PARTY_MARKER_ASSET_ID), "the land presenter resolves the built-in mounted Classic party CICN")
	assert_equal(ClassicUiAssetCatalog.native_size(ClassicMapPresenter.PARTY_MARKER_ASSET_ID), Vector2i(32, 32), "the mounted party CICN retains its native map-cell dimensions")
	assert_equal(party_marker["source_path"], "base/Realmz/Data Files/The Family Jewels.rsrc", "party-marker bytes come from the pinned base-game resource fork rather than a scenario-local CICN collision")
	assert_equal(party_marker["source_resource_type"], "cicn", "party-marker provenance records its Classic resource type")
	assert_equal(int(party_marker["source_resource_id"]), 186, "party-marker provenance records the exact built-in CICN ID")
	assert_equal(party_marker["source_file_sha256"], "8dbae6c6a418c82250dca93937c5958dacea9874d654c62da4e4dafa184dc85c", "party-marker provenance pins the complete resource-fork bytes")
	assert_equal(party_marker["classic_evidence"]["status"], "source-control-flow", "party-marker semantics are labeled from Castle source rather than inferred from a filename")
	assert_equal(party_marker["classic_evidence"]["commit"], "491816ad60037394f92c428e99c004494d3c28b3", "party-marker behavior retains its pinned Castle evidence commit")
	var fonts: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://src/presentation/assets/fonts/font-assets.json"))
	assert_equal(fonts["source_commit"], "2d85e20401920891efb7cd6272d6339685df2820", "bundled fonts retain pinned source provenance")
	for entry: Dictionary in fonts["assets"]:
		assert_equal(_sha256(entry["path"]), entry["sha256"], "bundled font or license hash matches: %s" % entry["id"])


func _sha256(path: String) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(FileAccess.get_file_as_bytes(path))
	return context.finish().hex_encode()


func _test_stone_surface_tiling() -> void:
	var tile_path := "res://src/presentation/assets/ui/classic-charcoal-slate-tile.png"
	var tile_texture := load(tile_path) as Texture2D
	var tile_image := tile_texture.get_image()
	assert_not_null(tile_image, "the derived seamless stone tile loads")
	assert_equal(tile_image.get_size(), Vector2i(512, 512), "the tiled surface retains the selected 512-pixel texture scale")
	var horizontal_edges_match := true
	var vertical_edges_match := true
	for coordinate: int in range(tile_image.get_height()):
		horizontal_edges_match = horizontal_edges_match and tile_image.get_pixel(0, coordinate) == tile_image.get_pixel(tile_image.get_width() - 1, coordinate)
	for coordinate: int in range(tile_image.get_width()):
		vertical_edges_match = vertical_edges_match and tile_image.get_pixel(coordinate, 0) == tile_image.get_pixel(coordinate, tile_image.get_height() - 1)
	assert_true(horizontal_edges_match, "the derived stone tile has identical left and right edge pixels")
	assert_true(vertical_edges_match, "the derived stone tile has identical top and bottom edge pixels")
	var application_scene := load("res://src/presentation/realmz_application.tscn") as PackedScene
	var application := application_scene.instantiate() as Control
	var stone := application.get_node("StoneTexture") as TextureRect
	assert_equal(stone.texture.resource_path, tile_path, "the application background uses the seamless derived tile")
	assert_equal(int(stone.stretch_mode), 1, "the application background tiles instead of scaling")
	assert_equal(int(stone.texture_repeat), 2, "the application background enables texture repeat sampling")
	var stage_frame := application.get_node("ClassicShell/StageFrame") as NinePatchRect
	assert_equal(int(stage_frame.axis_stretch_horizontal), 1, "stage-frame horizontal edges tile instead of stretching")
	assert_equal(int(stage_frame.axis_stretch_vertical), 1, "stage-frame vertical edges tile instead of stretching")
	assert_equal(stage_frame.patch_margin_right, 0, "the stage frame leaves its shared roster boundary open")
	assert_true(stage_frame.texture is AtlasTexture and (stage_frame.texture as AtlasTexture).region.size.x == 520.0, "the open-right stage frame crops only the source texture's eight-pixel right edge")
	application.free()
	var ui_theme := load("res://src/presentation/classic_ui_theme.tres") as Theme
	var menu_normal := ui_theme.get_stylebox("normal", "MenuButton")
	for menu_state: StringName in [&"hover", &"pressed", &"disabled"]:
		var menu_style := ui_theme.get_stylebox(menu_state, "MenuButton")
		for side: int in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
			assert_equal(menu_style.get_content_margin(side), menu_normal.get_content_margin(side), "MenuButton %s keeps the measured text margins on every side" % menu_state)
	var open_right_style := ui_theme.get_stylebox("panel", "ClassicOpenRight") as StyleBoxTexture
	assert_true(open_right_style != null and open_right_style.get_texture_margin(SIDE_RIGHT) == 0.0, "shared-stage panels use the open-right frame variation instead of drawing a vertical seam")
	assert_true(ui_theme.get_stylebox("panel", "ClassicSharedStone") is StyleBoxEmpty, "stage overlays expose the already aligned root stone instead of restarting the texture inside another panel")
	var tiled_styles: Array[StyleBox] = [
		ui_theme.get_stylebox("panel", "PanelContainer"),
		ui_theme.get_stylebox("panel", "ClassicInset"),
		ui_theme.get_stylebox("normal", "Button"),
		ui_theme.get_stylebox("hover", "Button"),
		ui_theme.get_stylebox("pressed", "Button"),
		ui_theme.get_stylebox("disabled", "Button"),
	]
	for style: StyleBox in tiled_styles:
		assert_true(style is StyleBoxTexture, "stone-backed panels and buttons use texture styleboxes")
		if style is StyleBoxTexture:
			assert_equal(int(style.axis_stretch_horizontal), 1, "stone stylebox centers tile horizontally")
			assert_equal(int(style.axis_stretch_vertical), 1, "stone stylebox centers tile vertically")


func _test_spatial_stage_visibility() -> void:
	var active_view := GameView.new(1, true, null)
	assert_true(PresentationCoordinator.should_show_spatial_stage(&"exploration", active_view, true), "the map may render only inside an active Explore play stage")
	assert_false(PresentationCoordinator.should_show_spatial_stage(&"exploration", active_view, false), "full-stage campaign and party-setup overlays suppress the map beneath their shared-stone surface")
	assert_false(PresentationCoordinator.should_show_spatial_stage(&"inventory", active_view, true), "non-Explore workspaces suppress spatial renderers")
	assert_false(PresentationCoordinator.should_show_spatial_stage(&"exploration", GameView.new(0, false, null), true), "an inactive session cannot expose a stale map")
	assert_false(PresentationCoordinator.should_show_battle_stage(&"combat", active_view, true), "the battle stage does not appear without detached battlefield facts")
	var tiles: Array[int] = []
	tiles.resize(BattlefieldState.CELL_COUNT)
	tiles.fill(1)
	var battlefield := BattlefieldState.new("land:0", tiles)
	var combat := CombatState.new("classic.battle.visibility", [], 0, battlefield)
	active_view.combat_view = CombatView.new(combat)
	assert_true(PresentationCoordinator.should_show_battle_stage(&"combat", active_view, true), "the tactical board appears only on the active combat route")
	assert_false(PresentationCoordinator.should_show_battle_stage(&"exploration", active_view, true), "combat facts do not replace the exploration map outside the combat route")
	assert_false(PresentationCoordinator.should_show_battle_stage(&"combat", active_view, false), "full-stage overlays suppress the tactical board")


func _test_battlefield_presenter() -> void:
	var tiles: Array[int] = []
	tiles.resize(BattlefieldState.CELL_COUNT)
	tiles.fill(232)
	var battlefield := BattlefieldState.new("land:0", tiles)
	assert_true(battlefield.place_character("hero", Vector2i(45, 45)), "battlefield presenter fixture places its active character")
	var monster := MonsterState.new("monster", "classic.monster.1", "Goblin", 4, 4)
	assert_true(battlefield.place_monster(monster.id, Vector2i(47, 45), 0), "battlefield presenter fixture places its target")
	var combat := CombatState.new("classic.battle.presenter", [monster], 0, battlefield)
	combat.set_turn_order(["hero", "monster"])
	var character := CharacterState.new("hero", "Hero", 10, 10)
	var character_views: Array[CharacterView] = [CharacterView.new(character)]
	var combat_view := CombatView.new(combat, [character])
	assert_equal(ClassicBattlefieldPresenter.actor_position(combat_view, character_views, "hero"), Vector2i(45, 45), "the camera reads the active character's detached battlefield coordinate")
	assert_equal(ClassicBattlefieldPresenter.actor_position(combat_view, character_views, "monster"), Vector2i(47, 45), "monster turns use the same detached battlefield coordinate source")
	assert_equal(ClassicBattlefieldPresenter.actor_name(combat_view, character_views, "monster"), "Goblin", "the tactical header resolves actor names from detached combatants")
	assert_equal(ClassicBattlefieldPresenter.viewport_cells_for(Vector2(704.0, 396.0)), Vector2i(16, 11), "the Classic tactical viewport keeps native 32-pixel cells and bounds its visible window")
	assert_equal(ClassicBattlefieldPresenter.camera_top_left(Vector2i(45, 45), Vector2i(16, 14)), Vector2i(37, 38), "the active actor remains centered in the ordinary battlefield window")
	assert_equal(ClassicBattlefieldPresenter.camera_top_left(Vector2i(1, 1), Vector2i(16, 14)), Vector2i.ZERO, "battlefield camera centering clamps safely at the 90 by 90 edge")
	assert_true(ClassicBattlefieldPresenter.coordinate_is_visible(Vector2i(45, 45), Vector2i(37, 38), Vector2i(16, 14)), "the active actor lies inside its centered tactical camera")


func _test_character_creator_workflow() -> void:
	var router := ClassicScreenRouter.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(router)
	router._body_frame = PanelContainer.new()
	router.add_child(router._body_frame)
	router._build_campaign_overlay()
	router._build_setup_overlay()
	var view := GameView.new(1, true, null)
	view.campaign_id = "fixture-creator"
	view.party_setup_available = true
	view.campaign_summary = CampaignSummaryView.new()
	view.campaign_summary.title = "Creator Fixture"
	view.campaign_summary.maximum_party_size = 6
	view.campaign_summary.maximum_level = 7
	view.race_options = [DefinitionOptionView.new("race.human", "Human", "Adaptable.", ["caste.sorcerer"])]
	view.caste_options = [DefinitionOptionView.new("caste.sorcerer", "Sorcerer", "Arcane caster.", ["race.human"])]
	view.portrait_options = [CharacterAppearanceOptionView.new(CharacterAppearanceDefinition.new("portrait.human.1", "Human 1", CharacterAppearanceDefinition.PORTRAIT, 257, ["race.human"]))]
	view.combat_icon_options = [CharacterAppearanceOptionView.new(CharacterAppearanceDefinition.new("icon.human.1", "Human 1", CharacterAppearanceDefinition.COMBAT_ICON, 9000, ["race.human"]))]
	var setup_member := CharacterState.new("party.setup.inspection", "Iris", 9, 9)
	setup_member.race_id = "race.human"
	setup_member.caste_id = "caste.sorcerer"
	view.party_members = [CharacterView.new(setup_member)]
	for action_id: StringName in [&"generate_character_draft", &"cancel_character_draft", &"set_character_draft_spells", &"finalize_character", &"import_vault_character", &"begin_adventure", &"remove_party_member"]:
		view.set_action_availability(action_id, action_id in [&"generate_character_draft", &"import_vault_character"], "Unavailable in this fixture state.")
	var intents: Array[PlayerIntent] = []
	router.intent_submitted.connect(func(intent: PlayerIntent) -> void: intents.append(intent))
	router.present(view)
	var inspect_setup := router._party_list.find_children("*", "Button", true, false).filter(func(button: Button) -> bool: return button.text == "Inspect")[0] as Button
	inspect_setup.pressed.emit()
	assert_true(router._setup_inspection_overlay.visible, "party setup can open a complete detached character inspection surface before play")
	assert_not_null(router._setup_inspection_overlay.find_child("PartySetupCharacterSheet", true, false), "setup inspection reuses the complete Classic character sheet instead of a second summary path")
	assert_equal(intents.size(), 0, "opening and browsing setup inspection cannot mutate the session")
	assert_true(router.handle_back(), "Back closes setup character inspection before leaving party setup")
	assert_false(router._setup_inspection_overlay.visible, "closing inspection restores the creator and party assembly surface")
	assert_equal(router._creator_step, 0, "party setup opens on Identity rather than mounting all five creator pages")
	assert_not_null(router._creator_page.get_node_or_null("CharacterName"), "Identity alone owns the character-name field")
	var starting_level := router._creator_page.get_node_or_null("StartingLevel") as OptionButton
	assert_not_null(starting_level, "Identity exposes the Classic starting-level boundary instead of silently omitting it")
	assert_equal([starting_level.get_item_id(0), starting_level.get_item_id(1), starting_level.get_item_id(2), starting_level.get_item_id(3)], [1, 3, 5, 7], "Identity exposes Castle's fixed choices only through the campaign's maximum level")
	assert_false(starting_level.disabled, "source-backed higher-level creation is an ordinary selectable campaign workflow")
	starting_level.select(starting_level.get_item_index(3))
	assert_equal(router._creator_page.find_children("*", "ItemList", true, false).size(), 0, "Identity does not spill race, class, or spell lists into the same viewport")
	router._draft_name = "Mira"
	router._name_edit.text = "Mira"
	router._creator_next()
	assert_equal(router._creator_step, 1, "Continue advances from Identity to Race and Class")
	assert_equal([router._race_list.get_item_text(0), router._caste_list.get_item_text(0)], ["Human", "Sorcerer"], "Race renders on the left and filters the class list on the right")
	var compact := UiLayoutProfile.for_viewport(Vector2(800, 600), PresentationSettings.UI_SCALE_AUTO)
	router._apply_creator_layout(compact.id)
	assert_true(router._creator.vertical and router._race_class_columns.vertical, "compact setup stacks both the creator-party split and Race-Class columns instead of clipping them")
	router._creator_next()
	assert_equal(router._creator_step, 2, "Race and Class advances to the dedicated Appearance page")
	router._creator_next()
	assert_equal(router._creator_step, 3, "Appearance advances to Review only after requesting a core-owned roll")
	assert_equal(intents[-1].kind, PlayerIntent.Kind.GENERATE_CHARACTER_DRAFT, "Review is populated through the typed draft-generation intent")
	assert_equal([intents[-1].party_members[0].portrait_id, intents[-1].party_members[0].combat_icon_id], ["portrait.human.1", "icon.human.1"], "Appearance emits stable package identities rather than filenames or numeric widget IDs")
	assert_equal(intents[-1].party_members[0].starting_level, 3, "the selected fixed level crosses the typed intent boundary without presentation-side leveling")
	var generated := CharacterState.new("party.character.1", "Mira", 8, 8)
	generated.race_id = "race.human"
	generated.caste_id = "caste.sorcerer"
	generated.gender = 2
	generated.brawn = 11
	generated.knowledge = 17
	generated.judgment = 14
	generated.agility = 13
	generated.vitality = 12
	generated.luck = 9
	generated.maximum_spell_points = 21
	generated.spell_points = 21
	generated.spellcaster_type = 1
	generated.two_hand = 34
	view.character_draft = CharacterView.new(generated)
	view.character_draft_spell_points_total = 4
	view.character_draft_spell_points_remaining = 4
	var spell := SpellDefinition.new("classic.spell.1101", 1101, "Flame")
	view.character_draft_spell_options = [CharacterSpellOptionView.new(spell, 1, false)]
	view.set_action_availability(&"finalize_character", true)
	router.present(view)
	assert_true(router._review_label.text.contains("Brawn 11") and router._review_label.text.contains("SP 21/21") and router._review_label.text.contains("Two-Hand 34"), "Review renders the generated character and its source-owned combat statistics rather than a pre-roll placeholder")
	assert_equal(router._setup_message.text, "Review or reroll the generated Classic character.", "the setup guidance advances with the asynchronously populated Review page")
	router._creator_next()
	assert_equal(router._creator_step, 4, "Review advances to the dedicated starting-spell page")
	assert_equal(router._spell_list.item_count, 1, "the spell page renders core-provided Classic options and selection costs")
	router._creator_next()
	assert_equal(intents[-1].kind, PlayerIntent.Kind.FINALIZE_CHARACTER, "Add to party accepts the reviewed draft without carrying another creation specification")
	router.free()


func _test_character_vault_workspace() -> void:
	var source_character := CharacterState.new("vault.hero", "Mira", 10, 10)
	source_character.level = 3
	source_character.race_id = "classic.race.1"
	source_character.caste_id = "classic.caste.6"
	var source_record := CharacterVaultRecord.new(source_character.id, "realmz-classic-1", "source-campaign", "b".repeat(64), source_character)
	source_record.revision_hash = "a".repeat(64)
	var source_eligibility := CharacterVaultEligibility.new()
	source_eligibility.reasons.append("Source-backed mismatch reason")
	var detached_revision := CharacterVaultRevisionView.from_record(source_record, source_eligibility, true, false)
	assert_equal(detached_revision.eligibility_reasons, ["Source-backed mismatch reason"], "vault eligibility converts into a typed detached reason array")
	var router := ClassicScreenRouter.new()
	router._body = VBoxContainer.new()
	router._content_parent = router._body
	router.add_child(router._body)
	var view := GameView.new(3, true, null)
	view.campaign_id = "fixture-vault"
	view.campaign_summary = CampaignSummaryView.new()
	view.campaign_summary.title = "Vault Campaign"
	view.set_action_availability(&"import_vault_character", true)
	router._view = view
	router._vault_return_to_setup = true
	var current := CharacterVaultRevisionView.new()
	current.character_id = "vault.hero"
	current.revision_hash = "a".repeat(64)
	current.name = "Mira"
	current.level = 3
	current.race_id = "classic.race.1"
	current.caste_id = "classic.caste.6"
	current.portrait_id = "realmz-portrait-257"
	current.source_campaign_id = "source-campaign"
	current.source_package_hash = "b".repeat(64)
	current.publication_label = "Created after the first expedition"
	current.is_current = true
	current.eligible = true
	current.character = CharacterView.new(source_character)
	var archived := CharacterVaultRevisionView.new()
	archived.character_id = current.character_id
	archived.revision_hash = "c".repeat(64)
	archived.name = current.name
	archived.level = 2
	archived.race_id = current.race_id
	archived.caste_id = current.caste_id
	archived.source_campaign_id = current.source_campaign_id
	archived.source_package_hash = current.source_package_hash
	archived.archived = true
	archived.eligibility_reasons = ["Item 'classic.item.missing' is not defined by this campaign."]
	archived.character = CharacterView.new(source_character)
	router.set_vault_revisions([current, archived])
	router._render_vault()
	var labels: Array[String] = []
	for node: Node in router.find_children("*", "Label", true, false):
		labels.append((node as Label).text)
	assert_true(labels.any(func(text: String) -> bool: return text.contains("Eligibility for Vault Campaign")), "the vault states which campaign owns the current eligibility decision")
	assert_true(labels.any(func(text: String) -> bool: return text.contains("classic.item.missing")), "an ineligible revision exposes its exact package mismatch")
	var restore_events: Array[Array] = []
	router.vault_restore_requested.connect(func(character_id: String, revision_hash: String) -> void: restore_events.append([character_id, revision_hash]))
	var import_buttons: Array[Button] = []
	var inspect_buttons: Array[Button] = []
	var back_button: Button
	var archive_button: Button
	var restore_button: Button
	for node: Node in router.find_children("*", "Button", true, false):
		var button := node as Button
		if button.text == "Back to party setup":
			back_button = button
		elif button.text == "Import this revision":
			import_buttons.append(button)
		elif button.text == "Inspect character":
			inspect_buttons.append(button)
		elif button.text == "Archive character":
			archive_button = button
		elif button.text == "Restore as current":
			restore_button = button
	assert_equal(import_buttons.size(), 2, "each immutable revision renders its own import decision")
	assert_equal(inspect_buttons.size(), 2, "eligible and ineligible vault revisions both expose mutation-free inspection")
	assert_not_null(back_button, "vault entry from party setup exposes a visible return action")
	assert_true(import_buttons.any(func(button: Button) -> bool: return not button.disabled), "the current eligible revision can be imported")
	assert_true(import_buttons.any(func(button: Button) -> bool: return button.disabled and button.tooltip_text.contains("Restore")), "archived revisions must be restored before import")
	assert_not_null(archive_button, "the current revision exposes recoverable archive rather than delete")
	assert_not_null(restore_button, "archived history exposes an explicit recovery action")
	inspect_buttons[-1].pressed.emit()
	assert_not_null(router._body.find_child("VaultCharacterSheet", true, false), "vault inspection reuses the complete detached character sheet")
	var inspection_labels := router._body.find_children("*", "Label", true, false)
	assert_true(inspection_labels.any(func(label: Label) -> bool: return label.text.contains("Not eligible") or label.text.contains("classic.item.missing")), "ineligible inspection keeps exact campaign mismatch reasons visible")
	var inspection_back := router._body.find_children("*", "Button", true, false).filter(func(button: Button) -> bool: return button.text == "Back to character vault")[0] as Button
	inspection_back.pressed.emit()
	assert_true(router._body.find_children("*", "Button", true, false).any(func(button: Button) -> bool: return button.text == "Inspect character"), "Back returns from vault inspection to the revision list")
	if restore_button != null:
		restore_button.pressed.emit()
	assert_equal(restore_events, [[archived.character_id, archived.revision_hash]], "recovery identifies the exact immutable revision")
	router.free()


func _test_field_spell_workspace() -> void:
	var router := ClassicScreenRouter.new()
	router._body = VBoxContainer.new()
	router._content_parent = router._body
	router.add_child(router._body)
	var view := GameView.new(5, true, null)
	view.party_summary = PartySummaryView.new()
	view.party_summary.camping = false
	var character := CharacterState.new("field.caster", "Aster", 12, 12)
	character.spell_points = 12
	character.maximum_spell_points = 12
	var character_view := CharacterView.new(character)
	var definition := SpellDefinition.new("classic.spell.field", 1101, "Field Bolt", "A bounded source-backed field spell.")
	definition.cost = 2
	definition.in_camp = true
	var spell_view := SpellView.new(definition)
	spell_view.power_levels = [1, 2]
	spell_view.field_cast = ActionAvailabilityView.new(&"cast_spell", true)
	spell_view.scroll_power_levels = [1, 2]
	spell_view.make_scroll = ActionAvailabilityView.new(&"cast_spell", true)
	character_view.spells.append(spell_view)
	character.write_scroll(0, definition.id, 2)
	character_view.scrolls = [SpellScrollView.new(0, character.scroll_at(0), definition)]
	character_view.scrolls[0].use = ActionAvailabilityView.new(&"cast_spell", true)
	view.party_members = [character_view]
	view.set_action_availability(&"cast_spell", true)
	router._view = view
	var intents: Array[PlayerIntent] = []
	router.intent_submitted.connect(func(intent: PlayerIntent) -> void: intents.append(intent))
	router._render_spells()
	var cast_power_two: Button = null
	var make_power_two: Button = null
	var use_scroll: Button = null
	var scroll_slot_label: Label = null
	for label: Label in router._body.find_children("*", "Label", true, false):
		if label.text.begins_with("Slot 1"):
			scroll_slot_label = label
			break
	for button: Button in router._body.find_children("*", "Button", true, false):
		if button.text == "Cast P2 (4 SP)":
			cast_power_two = button
		if button.text == "Make P2 Scroll (8 SP)":
			make_power_two = button
		if button.text == "Use":
			use_scroll = button
	assert_not_null(cast_power_two, "the field spell workspace renders explicit power and cost choices")
	assert_not_null(make_power_two, "the field spell workspace renders source-backed scroll scribing cost choices")
	assert_not_null(use_scroll, "the field spell workspace renders the character's fixed scroll-case slots")
	assert_not_null(scroll_slot_label, "the field spell workspace labels each fixed scroll slot")
	if scroll_slot_label != null:
		assert_true(scroll_slot_label.get_parent() is HBoxContainer, "scroll-slot identity and action share one fixed row instead of reflowing into narrow columns")
		assert_equal(scroll_slot_label.size_flags_horizontal, Control.SIZE_EXPAND_FILL, "scroll-slot text receives the row's available width at the minimum viewport")
	if cast_power_two != null:
		cast_power_two.pressed.emit()
	if make_power_two != null:
		make_power_two.pressed.emit()
	if use_scroll != null:
		use_scroll.pressed.emit()
	assert_equal(intents.size(), 3, "field cast, scroll scribing, and scroll use each emit one intent")
	if intents.size() == 3:
		assert_equal([intents[0].kind, intents[0].power_level], [PlayerIntent.Kind.CAST_SPELL, 2], "the selected field power crosses the typed intent boundary")
		assert_equal([intents[1].action, intents[1].power_level], [&"make-scroll", 2], "scroll scribing crosses the same typed spell intent boundary")
		assert_equal([intents[2].action, intents[2].quantity], [&"use-scroll", 0], "scroll use carries the exact fixed slot through the typed intent boundary")
	router.free()


func _test_inventory_workspace() -> void:
	var definition := ItemDefinition.new("classic.item.inventory-ui", 10, "Longsword", "Sword", "A balanced one-handed sword.")
	definition.icon_id = 321
	definition.item_type = 2
	definition.weight = 12
	definition.cost = 45
	definition.damage_bonus = 2
	definition.vs_small = 6
	var source := CharacterState.new("inventory.ui.source", "Alis", 10, 10)
	source.maximum_load = 100
	source.carried_load = 12
	source.set_inventory([ItemInstance.new("inventory.ui.item", definition.id, 0, false, true)])
	var destination := CharacterState.new("inventory.ui.destination", "Borin", 10, 10)
	destination.maximum_load = 100
	var source_view := CharacterView.new(source)
	source_view.items.clear()
	var item_view := ItemView.new(source.inventory()[0], definition)
	item_view.actions.equip = ActionAvailabilityView.new(&"equip_item", true)
	item_view.actions.use = ActionAvailabilityView.new(&"use_item", false, "This item's use effect is not implemented.")
	item_view.actions.drop = ActionAvailabilityView.new(&"drop_item", true)
	item_view.actions.trade = ActionAvailabilityView.new(&"trade_item", true)
	item_view.actions.trade_targets.append(ItemTransferTargetView.new(destination.id, destination.name, true))
	source_view.items.append(item_view)
	var view := GameView.new(4, true, null)
	view.party_members = [source_view, CharacterView.new(destination)]
	var router := ClassicScreenRouter.new()
	router._body = VBoxContainer.new()
	router._content_parent = router._body
	router.add_child(router._body)
	router._view = view
	var intents: Array[PlayerIntent] = []
	router.intent_submitted.connect(func(intent: PlayerIntent) -> void: intents.append(intent))
	router._render_inventory()
	var buttons: Array[BaseButton] = []
	var labels: Array[String] = []
	for node: Node in router.find_children("*", "BaseButton", true, false):
		buttons.append(node as BaseButton)
	for node: Node in router.find_children("*", "Label", true, false):
		labels.append((node as Label).text)
	assert_true(buttons.any(func(button: BaseButton) -> bool: return button is Button and (button as Button).text.contains("Alis") and (button as Button).text.contains("12/100")), "inventory workspace selects a character before an item")
	assert_true(buttons.any(func(button: BaseButton) -> bool: return button is Button and (button as Button).text.contains("Longsword")), "inventory workspace renders a selectable carried-item list")
	assert_true(buttons.any(func(button: BaseButton) -> bool: return button is Button and (button as Button).text == "Equip" and not button.disabled), "an action without donor bitmap art remains visible as a labeled typed control")
	var trade_button: BaseButton = null
	for button: BaseButton in buttons:
		if button is Button and (button as Button).text == "Give to Borin":
			trade_button = button
	assert_not_null(trade_button, "inventory workspace exposes each typed trade recipient")
	assert_true(trade_button != null and not trade_button.disabled, "a rules-authorized trade recipient is actionable")
	assert_false(buttons.any(func(button: BaseButton) -> bool: return (button is Button and (button as Button).text == "Store") or button.tooltip_text == "Store"), "ordinary inventory does not invent Remake's non-Classic player stash")
	assert_true(labels.any(func(text: String) -> bool: return text.contains("opcode 36 equipment escrow")), "the workspace explains why scenario-owned equipment escrow is not a stash")
	assert_true(labels.any(func(text: String) -> bool: return text == "Classic record"), "inventory inspection presents the source-backed item record as a distinct section")
	assert_true(labels.any(func(text: String) -> bool: return text == "Damage"), "inventory inspection presents Castle's damage record")
	assert_true(labels.any(func(text: String) -> bool: return text.contains("Use — This item's use effect is not implemented")), "disabled item actions remain readable without relying on hover tooltips")
	assert_true(buttons.any(func(button: BaseButton) -> bool: return button.tooltip_text.contains("use effect") and button.tooltip_text.contains("not implemented")), "unsafe item use remains visible with an exact disabled reason")
	if trade_button != null:
		trade_button.pressed.emit()
	assert_equal(intents.size(), 1, "trade emits exactly one typed intent")
	if not intents.is_empty():
		assert_equal(intents[0].kind, PlayerIntent.Kind.TRADE_ITEM, "trade never mutates gameplay from presentation")
		assert_equal(intents[0].secondary_target_id, destination.id, "trade intent carries the stable recipient identity")
	router.free()


func _test_money_workspace() -> void:
	var source := CharacterState.new("money.ui.source", "Alis", 10, 10)
	source.money = WealthState.new(10, 2, 1)
	source.carried_load = 27
	source.maximum_load = 100
	var destination := CharacterState.new("money.ui.destination", "Borin", 10, 10)
	destination.maximum_load = 100
	var workspace := MoneyWorkspaceView.new()
	workspace.pooled_gold = 15
	workspace.pooled_gems = 1
	workspace.pooled_jewelry = 1
	workspace.banked_gold = 50
	workspace.pool = ActionAvailabilityView.new(&"money_action", true)
	workspace.share = ActionAvailabilityView.new(&"money_action", false, "No adventurer can carry another pooled denomination.")
	var source_view := MoneyCharacterView.new(source)
	source_view.transfers = [
		MoneyTransferView.new(&"gold", 5, ActionAvailabilityView.new(&"money_action", true), ActionAvailabilityView.new(&"money_action", true)),
		MoneyTransferView.new(&"gems", 1, ActionAvailabilityView.new(&"money_action", true), ActionAvailabilityView.new(&"money_action", true)),
		MoneyTransferView.new(&"jewelry", 1, ActionAvailabilityView.new(&"money_action", true), ActionAvailabilityView.new(&"money_action", false, "Alis cannot carry that denomination.")),
	]
	var destination_view := MoneyCharacterView.new(destination)
	workspace.characters = [source_view, destination_view]
	var view := GameView.new(5, true, null)
	view.money_workspace = workspace
	view.set_action_availability(&"money_action", true)
	view.set_action_availability(&"service_action", false, "No location service is available.")
	var router := ClassicScreenRouter.new()
	router._body = VBoxContainer.new()
	router._content_parent = router._body
	router.add_child(router._body)
	router._view = view
	var intents: Array[PlayerIntent] = []
	router.intent_submitted.connect(func(intent: PlayerIntent) -> void: intents.append(intent))
	router._render_services()
	var buttons: Array[Button] = []
	var labels: Array[String] = []
	for node: Node in router.find_children("*", "Button", true, false):
		buttons.append(node as Button)
	for node: Node in router.find_children("*", "Label", true, false):
		labels.append((node as Label).text)
	assert_true(labels.any(func(text: String) -> bool: return text.contains("15 gold") and text.contains("1 jewelry")), "money workspace renders every detached pooled denomination")
	assert_true(labels.any(func(text: String) -> bool: return text.contains("Banked: 50 gold")), "banked wealth remains visible without being merged into ordinary Swap")
	var pool_button: Button = buttons.filter(func(button: Button) -> bool: return button.text == "Pool party wealth")[0]
	var share_button: Button = buttons.filter(func(button: Button) -> bool: return button.text == "Share pooled wealth")[0]
	assert_false(pool_button.disabled, "core-authorized Pool is actionable")
	assert_true(share_button.disabled and share_button.tooltip_text.contains("No adventurer can carry"), "core-owned Share blocker remains visible")
	var to_pool_buttons := buttons.filter(func(button: Button) -> bool: return button.text == "To pool")
	var to_character_buttons := buttons.filter(func(button: Button) -> bool: return button.text == "To Alis")
	assert_equal([to_pool_buttons.size(), to_character_buttons.size()], [3, 3], "Swap presents all three Classic denominations for the selected character")
	assert_true(to_character_buttons[2].disabled and to_character_buttons[2].tooltip_text.contains("cannot carry"), "presentation does not recreate jewelry capacity rules")
	pool_button.pressed.emit()
	to_pool_buttons[0].pressed.emit()
	to_character_buttons[0].pressed.emit()
	assert_equal(intents.size(), 3, "money controls emit exactly one typed intent per mutation")
	assert_equal([intents[0].kind, intents[0].action], [PlayerIntent.Kind.MONEY_ACTION, &"pool"], "Pool crosses the typed money boundary")
	assert_equal([intents[1].action, intents[1].actor_id, intents[1].target_id, intents[1].amount], [&"to-pool", source.id, "gold", 5], "character-to-pool Swap carries stable identity and exact Classic increment")
	assert_equal([intents[2].action, intents[2].actor_id, intents[2].target_id, intents[2].amount], [&"to-character", source.id, "gold", 5], "pool-to-character Swap carries stable identity and exact Classic increment")
	assert_true(buttons.any(func(button: Button) -> bool: return button.text == "Done"), "Swap has a presentation-only cancellation path with no gameplay mutation")
	var scroll := ScrollContainer.new()
	scroll.scroll_horizontal = 37
	scroll.scroll_vertical = 542
	router._body_scroll = scroll
	router._restore_focus(true)
	assert_equal([scroll.scroll_horizontal, scroll.scroll_vertical], [0, 0], "a newly mounted route resets focus-driven scroll so Money remains visible at the top")
	router._restore_focus(false, 37, 100)
	assert_equal([scroll.scroll_horizontal, scroll.scroll_vertical], [37, 100], "a same-route money mutation preserves the player's prior scroll instead of jumping to the final control")
	scroll.free()
	router.free()


func _test_party_order_workspace() -> void:
	var alis := CharacterState.new("party.order.alis", "Alis", 10, 10)
	alis.level = 2
	alis.caste_id = "fighter"
	var borin := CharacterState.new("party.order.borin", "Borin", 12, 12)
	borin.level = 3
	borin.caste_id = "priest"
	var cerys := CharacterState.new("party.order.cerys", "Cerys", 8, 8)
	cerys.level = 4
	cerys.caste_id = "sorcerer"
	var view := GameView.new(8, true, null)
	view.campaign_id = "party-order-fixture"
	view.party_members = [CharacterView.new(alis), CharacterView.new(borin), CharacterView.new(cerys)]
	view.set_action_availability(&"reorder_party", true)
	var router := ClassicScreenRouter.new()
	var workspace := (load("res://src/presentation/screens/character_screen.tscn") as PackedScene).instantiate() as ClassicRouteScreen
	workspace.scroll = workspace.get_node("WorkspaceColumn/ScreenBodyScroll") as ScrollContainer
	workspace.body = workspace.get_node("WorkspaceColumn/ScreenBodyScroll/ScreenBody") as VBoxContainer
	workspace._header = workspace.get_node("WorkspaceColumn/WorkspaceHeader") as BoxContainer
	router._workspace_view = workspace
	router._body_frame = workspace
	router._body_scroll = workspace.scroll
	router._body = workspace.body
	router.add_child(workspace)
	router._campaign_overlay = PanelContainer.new()
	router._setup_overlay = PanelContainer.new()
	router.add_child(router._campaign_overlay)
	router.add_child(router._setup_overlay)
	router._screen_id = &"character"
	var intents: Array[PlayerIntent] = []
	router.intent_submitted.connect(func(intent: PlayerIntent) -> void: intents.append(intent))
	router.present(view)
	assert_equal(router._party_order_draft_ids, [alis.id, borin.id, cerys.id], "the Party Order workspace starts from detached session order")
	var buttons: Array[Button] = []
	for node: Node in router.find_children("*", "Button", true, false):
		buttons.append(node as Button)
	var first_down: Button = buttons.filter(func(button: Button) -> bool: return button.text == "Move Down" and not button.disabled)[0]
	first_down.pressed.emit()
	assert_equal(router._party_order_draft_ids, [borin.id, alis.id, cerys.id], "Move Down changes presentation-owned draft order only")
	assert_equal(intents.size(), 0, "staging a slot move cannot mutate the session")
	buttons.clear()
	for node: Node in router.find_children("*", "Button", true, false):
		buttons.append(node as Button)
	var cancel: Button = buttons.filter(func(button: Button) -> bool: return button.text == "Cancel Order Changes")[0]
	assert_false(cancel.disabled, "a changed draft exposes safe cancellation")
	cancel.pressed.emit()
	assert_equal(router._party_order_draft_ids, [alis.id, borin.id, cerys.id], "Cancel restores detached order without reproducing Castle's cleared-track write")
	assert_equal(intents.size(), 0, "Cancel emits no gameplay intent")
	buttons.clear()
	for node: Node in router.find_children("*", "Button", true, false):
		buttons.append(node as Button)
	first_down = buttons.filter(func(button: Button) -> bool: return button.text == "Move Down" and not button.disabled)[0]
	first_down.pressed.emit()
	buttons.clear()
	for node: Node in router.find_children("*", "Button", true, false):
		buttons.append(node as Button)
	var apply: Button = buttons.filter(func(button: Button) -> bool: return button.text == "Apply Party Order")[0]
	assert_false(apply.disabled, "a changed complete permutation can be applied")
	apply.pressed.emit()
	assert_equal(intents.size(), 1, "Apply emits exactly one typed mutation")
	assert_equal([intents[0].kind, intents[0].selected_ids], [PlayerIntent.Kind.REORDER_PARTY, [borin.id, alis.id, cerys.id]], "the presenter emits the complete stable-ID permutation")
	view.set_action_availability(&"reorder_party", false, "Party order is unavailable during battle.")
	router.present(view)
	buttons.clear()
	for node: Node in router.find_children("*", "Button", true, false):
		buttons.append(node as Button)
	var blocked_move: Button = buttons.filter(func(button: Button) -> bool: return button.text == "Move Down")[0]
	assert_true(blocked_move.disabled and blocked_move.tooltip_text.contains("battle"), "unavailable Party Order remains visible with the core-owned reason")
	router.free()


func _test_character_sheet_workspace() -> void:
	var character := CharacterState.new("character.sheet", "A Character Name Long Enough To Exercise Responsive Wrapping", -10, 18)
	character.level = 7
	character.experience = 12_345
	character.age_days = 37 * 365
	character.age_group = 3
	character.race_id = "classic.race.1"
	character.caste_id = "classic.caste.2"
	character.gender = 2
	character.brawn = 17
	character.knowledge = 14
	character.judgment = 13
	character.agility = 16
	character.vitality = 15
	character.luck = 12
	character.to_hit = 28
	character.dodge = 31
	character.missile = 24
	character.two_hand = 9
	character.hand_to_hand = 4
	character.damage_bonus = 3
	character.armor = 42
	character.magic_resistance = 11
	character.normal_attacks = 2
	character.attack_bonus = 1
	character.spell_points = 9
	character.maximum_spell_points = 22
	character.maximum_movement = 14
	character.carried_load = 63
	character.maximum_load = 120
	character.money.gold = 77
	character.money.gems = 2
	character.money.jewelry = 1
	character.portrait_id = "portrait.257"
	character.combat_icon_id = "combat-icon.9000"
	character.conditions.set_value(ConditionRules.TANGLED, 4)
	character.conditions.set_value(ConditionRules.SHIELD_FROM_HITS, 2)
	character.conditions.set_value(9, 3)
	character.conditions.set_value(ConditionRules.STRONG, 1)
	character.conditions.set_value(26, -1)
	character.conditions.set_value(ConditionRules.HINDERED_ATTACKS, 3)
	character.conditions.set_value(ConditionRules.HINDERED_DEFENSE, 2)
	character.conditions.set_value(ConditionRules.DEFENSE_BONUS, 5)
	character.set_save_value(0, 61)
	character.set_special_value(1, -2)
	character.set_ability_value(4, 35)
	character.set_ability_value(13, 18)
	var changes: Array[PackedInt32Array] = []
	for band_index: int in 5:
		var row := PackedInt32Array()
		row.resize(15)
		row.fill(0)
		row[band_index] = band_index + 1
		changes.append(row)
	var race := RaceDefinition.new(character.race_id, 1, "Human", [], [], [], [], [], [Vector2i(10, 19), Vector2i(20, 29), Vector2i(30, 39), Vector2i(40, 49), Vector2i(50, 59)], changes, 90, false, 12, 5, 3, 4, 2, 5, true, 0, 0, 0, 0, "A long source-backed race description used to prove wrapping.")
	var caste := CasteDefinition.new(character.caste_id, 2, "Fighter", [], [], [], [], Vector2i.ZERO, Vector2i.ZERO, Vector2i.ZERO, Vector2i.ZERO, Vector2i.ZERO, [], [], [], 1, 2, 1, 2, 3, 4, 1, 5, 0, true, true, 0, 0, 0, Vector2i.ZERO, "A source-backed class description.")
	var content := RealmzContent.new("character-sheet", "0".repeat(64), "sheet", "realmz-classic-1", "", Vector2i.ZERO, WorldDefinition.new([]), ScenarioDefinition.new([], []), [], [], [], [race], [caste])
	var character_view := CharacterView.new(character, content)
	assert_equal([character_view.gender_name, character_view.attacks_per_round, character_view.attack_bonus, character_view.defense_bonus, character_view.gold, character_view.gems, character_view.jewelry], ["Female", "3/2", 36, 45, 77, 2, 1], "the detached sheet preserves Castle identity, computed display bonuses, attack cadence, and three personal money denominations")
	assert_true(character_view.conditions.any(func(metric: CharacterMetricView) -> bool: return metric.name == "Poisoned"), "conditions use Castle names instead of leaking raw slots into presentation")
	assert_true(character_view.conditions.any(func(metric: CharacterMetricView) -> bool: return metric.name == "Turned to Stone" and metric.detail == "Permanent"), "signed permanent conditions remain explicit")
	assert_equal([character_view.saving_throws.size(), character_view.saving_throws[0].name, character_view.saving_throws[0].value], [8, "Charm", 61], "all eight Classic saving throws are detached with stable labels")
	assert_equal([character_view.special_modifiers[0].name, character_view.special_modifiers[0].value, character_view.abilities[0].name, character_view.abilities[1].name], ["Undead", -2, "Detect Secret", "Turn Undead"], "source-backed special and ability identities remain distinct")
	assert_equal([character_view.age_bands.size(), character_view.age_bands[2].active, character_view.age_bands[2].changes[2].value], [5, true, 3], "the read model derives the active age band without mutating session state")
	assert_equal(character.age_group, 3, "opening character details cannot reproduce Castle's inspection-time age-group write")
	assert_false(character_view.record_available, "untracked lifetime prestige history remains explicitly unavailable")
	assert_true(character_view.record_unavailable_reason.to_lower().contains("lifetime combat history"), "the prestige gap has a concrete player-facing reason")
	var sheet := ClassicCharacterSheet.new()
	var selections: Array[String] = []
	var appearance_changes: Array[Dictionary] = []
	sheet.character_selected.connect(func(character_id: String) -> void: selections.append(character_id))
	sheet.appearance_change_requested.connect(func(character_id: String, appearance_kind: StringName, appearance_id: String) -> void: appearance_changes.append({"characterId": character_id, "kind": appearance_kind, "appearanceId": appearance_id}))
	var portrait_options: Array[CharacterAppearanceOptionView] = [
		CharacterAppearanceOptionView.new(CharacterAppearanceDefinition.new("portrait.257", "Portrait 257", CharacterAppearanceDefinition.PORTRAIT, 257, [character.race_id])),
		CharacterAppearanceOptionView.new(CharacterAppearanceDefinition.new("portrait.258", "Portrait 258 with a deliberately long package label", CharacterAppearanceDefinition.PORTRAIT, 258, [character.race_id])),
	]
	var icon_options: Array[CharacterAppearanceOptionView] = [
		CharacterAppearanceOptionView.new(CharacterAppearanceDefinition.new("combat-icon.9000", "Combat icon 9000", CharacterAppearanceDefinition.COMBAT_ICON, 9000, [character.race_id])),
		CharacterAppearanceOptionView.new(CharacterAppearanceDefinition.new("combat-icon.9001", "Combat icon 9001", CharacterAppearanceDefinition.COMBAT_ICON, 9001, [character.race_id])),
	]
	sheet.present([character_view], character_view.id, {}, 1.0, &"overview", portrait_options, icon_options, ActionAvailabilityView.new(&"change_character_appearance", true))
	var buttons: Array[Button] = []
	for node: Node in sheet.find_children("*", "Button", true, false):
		buttons.append(node as Button)
	assert_true(buttons.any(func(button: Button) -> bool: return button.text == "Overview"), "the sheet exposes a bounded overview tab")
	assert_true(buttons.any(func(button: Button) -> bool: return button.text == "Conditions & Saves"), "the sheet exposes conditions and all saves without raw indices")
	assert_true(buttons.any(func(button: Button) -> bool: return button.text == "Equipment"), "the sheet retains the Classic equipment subworkspace")
	assert_true(buttons.any(func(button: Button) -> bool: return button.text == "Abilities"), "the sheet retains source special and ability values")
	assert_true(buttons.any(func(button: Button) -> bool: return button.text == "Spells"), "the sheet exposes known spells and scroll slots")
	assert_true(buttons.any(func(button: Button) -> bool: return button.text == "Appearance"), "the sheet exposes the separate Classic portrait and tactical-icon workspace")
	assert_true(buttons.any(func(button: Button) -> bool: return button.text == "Race, Class & Aging"), "the sheet exposes source-backed definitions and all five age bands")
	assert_true(buttons.any(func(button: Button) -> bool: return button.text == "Lifetime Record"), "the missing prestige record remains visible rather than silently omitted")
	var equipment_button := buttons.filter(func(button: Button) -> bool: return button.text == "Equipment")[0] as Button
	equipment_button.pressed.emit()
	var equipment_heading_detail := sheet.find_child("HeadingDetail", true, false) as Label
	assert_not_null(equipment_heading_detail, "the equipment heading exposes its slot-count detail")
	assert_equal(equipment_heading_detail.size_flags_horizontal, Control.SIZE_EXPAND_FILL, "heading details reserve horizontal space instead of collapsing into one-character columns at 960x600")
	var record_button := sheet.find_children("*", "Button", true, false).filter(func(button: Button) -> bool: return button.text == "Lifetime Record")[0] as Button
	record_button.pressed.emit()
	var labels := sheet.find_children("*", "Label", true, false)
	assert_true(labels.any(func(label: Label) -> bool: return label.text.to_lower().contains("lifetime combat history")), "the Record tab explains why Castle prestige cannot yet be calculated")
	assert_equal(selections.size(), 0, "tab navigation is presentation-owned and cannot mutate the session")
	var appearance_button := sheet.find_children("*", "Button", true, false).filter(func(button: Button) -> bool: return button.text == "Appearance")[0] as Button
	appearance_button.pressed.emit()
	var portrait_picker := sheet.find_child("PortraitPicker", true, false) as OptionButton
	assert_not_null(portrait_picker, "the Appearance tab mounts a package-backed portrait picker")
	assert_equal(portrait_picker.item_count, 2, "the picker exposes every detached portrait option")
	portrait_picker.select(1)
	portrait_picker.item_selected.emit(1)
	assert_equal(appearance_changes.size(), 0, "previewing a portrait remains presentation-only")
	var apply_portrait := sheet.find_children("*", "Button", true, false).filter(func(button: Button) -> bool: return button.text == "Apply Portrait")[0] as Button
	assert_false(apply_portrait.disabled, "a changed portrait enables the explicit commit action")
	apply_portrait.pressed.emit()
	assert_equal(appearance_changes, [{"characterId": character_view.id, "kind": CharacterAppearanceDefinition.PORTRAIT, "appearanceId": "portrait.258"}], "Apply emits one typed stable-ID portrait request")
	var icon_picker := sheet.find_child("CombaticonPicker", true, false) as OptionButton
	assert_not_null(icon_picker, "the Appearance tab keeps combat-icon selection independent")
	icon_picker.select(1)
	icon_picker.item_selected.emit(1)
	var discard := sheet.find_children("*", "Button", true, false).filter(func(button: Button) -> bool: return button.text == "Discard Appearance Changes")[0] as Button
	discard.pressed.emit()
	assert_equal(appearance_changes.size(), 1, "Discard restores local previews without emitting another mutation")
	sheet.free()


func _test_party_roster() -> void:
	var roster_scene := load("res://src/presentation/screens/classic_party_roster.tscn") as PackedScene
	var roster := roster_scene.instantiate() as ClassicPartyRoster
	roster._heading = roster.get_node("RosterColumn/Heading") as Label
	roster._party_list = roster.get_node("RosterColumn/PartyScroll/PartyList") as VBoxContainer
	var character := CharacterState.new("party.roster", "Mira", 10, 10)
	character.race_id = "classic.race.1"
	character.caste_id = "classic.caste.6"
	var view := GameView.new(1, true, null)
	view.party_members = [CharacterView.new(character)]
	roster.present(view)
	var rows := roster.find_children("*", "Button", true, false)
	assert_equal(rows.size(), 1, "the populated roster creates one character control")
	if not rows.is_empty():
		var row := rows[0] as Button
		assert_equal(row.get_theme_constant("icon_max_width"), 42, "portrait width uses the supported Button theme constant")
	roster.free()


func _test_scene_composition() -> void:
	var shell_scene := load("res://src/presentation/classic_application_shell.tscn") as PackedScene
	var shell := shell_scene.instantiate() as ClassicApplicationShell
	assert_not_null(shell, "the canonical application shell is scene-backed")
	var router := shell.get_node("ScreenRouter") as Control
	var roster := shell.get_node("PartyRoster") as Control
	var bottom_region := shell.get_node("BottomRegion") as Control
	assert_not_null(router, "the shell owns one workspace router")
	assert_not_null(shell.get_node("PartyRoster"), "the shell owns the persistent six-slot roster")
	assert_true((roster as PanelContainer).get_theme_stylebox("panel") is StyleBoxEmpty, "the roster shares the uninterrupted root stone surface instead of restarting a second framed tile at the stage boundary")
	assert_equal((bottom_region as PanelContainer).theme_type_variation, &"ClassicOpenRight", "the bottom narrative region also leaves the shared roster boundary open")
	assert_not_null(shell.get_node("BottomRegion/BottomRow/NarrativeWell"), "the shell owns a Classic narrative well")
	assert_not_null(shell.get_node("BottomRegion/BottomRow/CommandPanel"), "the shell owns a contextual command deck")
	var picture_backing := shell.get_node("PictureStage/PictureBacking") as TextureRect
	var picture_frame := shell.get_node("PictureStage/PictureFrame") as NinePatchRect
	assert_equal(int(picture_backing.stretch_mode), TextureRect.STRETCH_TILE, "scenario-picture stone fills the complete overlay without stretching")
	assert_equal(int(picture_backing.texture_repeat), CanvasItem.TEXTURE_REPEAT_ENABLED, "scenario-picture backing repeats seamlessly beneath transparent bevel pixels")
	assert_false(picture_frame.draw_center, "the scenario-picture bevel is an overlay around the independently filled stone center")
	assert_true(picture_frame.get_index() > shell.get_node("PictureStage/PictureMargin").get_index(), "the bevel draws over the filled picture surface without exposing the map between layers")
	assert_equal(shell.mouse_filter, Control.MOUSE_FILTER_IGNORE, "the structural shell cannot mask earlier root-level interaction controls")
	assert_equal(router.mouse_filter, Control.MOUSE_FILTER_IGNORE, "the full-window router cannot mask menus or sibling controls")
	assert_true(router.get_index() > roster.get_index() and router.get_index() > bottom_region.get_index(), "modal router children are ordered above roster and textbox input regions")
	for viewport_size: Vector2 in [Vector2(800, 600), Vector2(960, 600), Vector2(1280, 720), Vector2(1920, 1080)]:
		var profile := UiLayoutProfile.for_viewport(viewport_size, PresentationSettings.UI_SCALE_AUTO)
		var campaign_rect := ClassicScreenRouter.campaign_rect_for(profile, viewport_size)
		var stage_width := viewport_size.x - profile.party_width
		assert_true(campaign_rect.position.x >= 0.0 and campaign_rect.position.x + campaign_rect.size.x <= stage_width, "campaign controls stay out of the roster hit region at %s" % str(viewport_size))
		assert_true(campaign_rect.position.y >= profile.menu_height and campaign_rect.position.y + campaign_rect.size.y <= viewport_size.y, "campaign controls stay inside the viewport at %s" % str(viewport_size))
	assert_false(shell.has_node("TopBar"), "the dashboard title bar is removed")
	assert_false(shell.has_node("RightPanel"), "the persistent Chronicle column is removed")
	shell.free()
	var application_scene := load("res://src/presentation/realmz_application.tscn") as PackedScene
	var application := application_scene.instantiate() as Control
	assert_true(application.get_node("InteractionPanel").get_index() > application.get_node("ClassicShell").get_index(), "AP and encounter presenter controls are ordered above the shell for mouse input")
	assert_true(application.get_node("BattlefieldMap") is ClassicBattlefieldPresenter, "the root application owns one detached tactical battlefield presenter")
	var interaction := application.get_node("InteractionPanel") as InteractionPresenter
	var standard_textbox_rect := RealmzApplication.classic_textbox_rect(Rect2(0.0, 28.0, 704.0, 396.0), 176.0)
	assert_equal(standard_textbox_rect, Rect2(0.0, 424.0, 704.0, 176.0), "textbox interactions replace the complete shell bottom region without exposing an inset frame")
	assert_true(InteractionPresenter.uses_textbox_region(InteractionRequest.acknowledge("edge-to-edge", "Continue")), "Classic acknowledgements use the edge-to-edge textbox surface")
	assert_true(InteractionPresenter.uses_textbox_region(ClassicUiFixtureGallery.request_for(InteractionRequest.COMBAT)), "battle controls occupy the bottom Classic control region without covering the tactical board")
	assert_false(InteractionPresenter.uses_textbox_region(ClassicUiFixtureGallery.request_for(InteractionRequest.SHOP)), "stage interactions retain their independent inset frame")
	assert_equal(interaction.custom_minimum_size, Vector2.ZERO, "textbox interactions may shrink to the bottom-region rectangle instead of retaining a stage-modal minimum")
	assert_equal(InteractionPresenter._heading_for_kind(&"acknowledge"), "", "ordinary narrative text does not label itself Classic Textbox")
	assert_false((interaction.get_node("InteractionScroll/InteractionContent/InteractionHeading") as Label).visible, "the unused narrative heading consumes no textbox height")
	application.free()
	var texture_path := "res://src/presentation/assets/ui/classic-charcoal-slate.png"
	assert_true(ResourceLoader.exists(texture_path, "Texture2D"), "the selected low-contrast stone texture imports as a Godot texture")
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://src/presentation/assets/ui/spritecook-assets.json"))
	assert_equal(manifest["selected_asset"]["asset_id"], "3f355030-0f8c-4d4e-b079-26ba8d3dbc32", "the committed texture retains selected SpriteCook provenance")
	assert_equal(manifest["files"].size(), 4, "the selected surface, seamless tile, and two deterministic frames ship together")
	for entry: Dictionary in manifest["files"]:
		assert_equal(_sha256(entry["path"]), entry["sha256"], "generated stone surface hash matches its manifest: %s" % entry["path"])
		var texture := load(entry["path"]) as Texture2D
		assert_equal(texture.get_width(), int(entry["width"]), "generated stone surface width matches its manifest: %s" % entry["path"])
		assert_equal(texture.get_height(), int(entry["height"]), "generated stone surface height matches its manifest: %s" % entry["path"])


func _test_automatic_workflow_routes() -> void:
	var view := GameView.new(1, true, null)
	view.combat_view = CombatView.new(CombatState.new("classic.battle.route"))
	assert_equal(ClassicApplicationShell.automatic_workflow_route(&"exploration", view), &"combat", "battle setup opens the tactical workspace")
	assert_equal(ClassicApplicationShell.automatic_workflow_route(&"inventory", view), &"inventory", "battle setup does not replace a workspace the player deliberately opened")
	view.combat_view = null
	assert_equal(ClassicApplicationShell.automatic_workflow_route(&"combat", view), &"exploration", "completed battle cleanup returns the ordinary shell to exploration")
	assert_equal(ClassicApplicationShell.automatic_workflow_route(&"inventory", view), &"inventory", "ordinary non-combat workspaces remain presentation-owned")
	view.pending_interaction = InteractionRequest.new("shop.route", InteractionRequest.SHOP, {"prompt": "Shop"})
	assert_equal(ClassicApplicationShell.automatic_workflow_route(&"exploration", view), &"services", "application services open their dedicated workspace")
