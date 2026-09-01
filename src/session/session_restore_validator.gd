class_name SessionRestoreValidator
extends RefCounted

const ClassicPickLockRulesScript := preload("res://src/core/rules/classic_pick_lock_rules.gd")

static func validate(content: RealmzContent, snapshot: SessionSnapshot) -> SessionRestoreResult:
	if content == null or content.scenario == null or snapshot == null:
		return SessionRestoreResult.failed(&"invalid_restore", "Validated content and save data are required.")
	if snapshot.campaign_id != content.campaign_id or snapshot.package_hash != content.package_hash:
		return SessionRestoreResult.failed(&"package_mismatch", "The save belongs to a different package build.")
	if snapshot.rules_version != content.rules_version:
		return SessionRestoreResult.failed(&"rules_mismatch", "The save uses a different Realmz rules version.")
	var saved_map := content.world.map_by_id(snapshot.game_state.party.map_id)
	if saved_map == null or saved_map.topology.cell_at(snapshot.game_state.party.coordinate) == null:
		return SessionRestoreResult.failed(&"invalid_saved_location", "The saved party location is unavailable.")
	var replacement_rng := RealmzRng.new()
	if not replacement_rng.restore(snapshot.rng_state):
		return SessionRestoreResult.failed(&"invalid_rng_state", "The saved random state is invalid.")
	var replacement_state := GameState.from_data(snapshot.game_state.to_data())
	var replacement_action_state := ScenarioActionState.from_data(snapshot.scenario_action_state.to_data())
	if replacement_state == null or replacement_action_state == null:
		return SessionRestoreResult.failed(&"invalid_game_state", "The saved game or Scenario Action state is invalid.")
	if not content.available_monster_sets().has(replacement_state.monster_set):
		return SessionRestoreResult.failed(&"invalid_game_state", "The saved game selects a monster set unavailable in this package.")
	if replacement_state.party_setup_completed and replacement_state.experience_multiplier < 0.0:
		replacement_state.experience_multiplier = LifecyclePartyWorkflow.party_experience_multiplier(replacement_state.party.characters(), replacement_state.difficulty, content.campaign_definition())
	if replacement_state.combat != null:
		for item: ItemInstance in replacement_state.combat.fumbled_items():
			if content.item_by_id(item.definition_id) == null:
				return SessionRestoreResult.failed(&"invalid_game_state", "The saved fumble queue references unavailable item content.")
		for monster: MonsterState in replacement_state.combat.monsters():
			for item_id: String in monster.loot_item_ids():
				if not item_id.is_empty() and content.item_by_id(item_id) == null:
					return SessionRestoreResult.failed(&"invalid_game_state", "The saved monster loot references unavailable item content.")
	var replacement_rules := RealmzRules.new()
	_normalize_age_groups(replacement_state, content, replacement_rules)
	if not _party_inventory_is_valid(content, replacement_state, replacement_rules):
		return SessionRestoreResult.failed(&"invalid_game_state", "The saved party inventory or carried load is invalid for this package.")
	if not _combat_staged_item_is_valid(content, replacement_state, replacement_rules):
		return SessionRestoreResult.failed(&"invalid_game_state", "The saved combat item staging state is invalid for this package.")
	if not _party_fast_spells_are_valid(content, replacement_state):
		return SessionRestoreResult.failed(&"invalid_game_state", "The saved Fast Spell bindings reference unavailable package content.")
	if not _party_appearance_is_valid(content, replacement_state):
		return SessionRestoreResult.failed(&"invalid_game_state", "The saved party appearance references unavailable package content.")
	if not _shop_state_is_valid(content, replacement_state):
		return SessionRestoreResult.failed(&"invalid_game_state", "The saved shop state references unavailable package content.")
	if not _location_notes_are_valid(content, replacement_state):
		return SessionRestoreResult.failed(&"invalid_game_state", "The saved location notes reference unavailable maps, cells, or invalid Classic note data.")
	if not _journal_messages_are_valid(content, replacement_state):
		return SessionRestoreResult.failed(&"invalid_game_state", "The saved journal references unavailable or unrepresentable Classic messages.")
	if not _acquired_player_maps_are_valid(content, replacement_state):
		return SessionRestoreResult.failed(&"invalid_game_state", "The saved acquired maps reference unavailable package content.")
	if not _boat_overlays_are_valid(content, replacement_state):
		return SessionRestoreResult.failed(&"invalid_game_state", "The saved boat overlays reference unavailable land cells.")
	if replacement_state.has_saved_party_position():
		var bookmark_map := content.world.map_by_id(replacement_state.saved_party_map_id)
		if bookmark_map == null or bookmark_map.level_type != replacement_state.saved_party_level_type or bookmark_map.topology.cell_at(replacement_state.saved_party_coordinate) == null:
			return SessionRestoreResult.failed(&"invalid_game_state", "The saved party-position bookmark references an unavailable map or cell.")
	if not LifecyclePartyWorkflow.character_draft_is_valid(content, replacement_state, replacement_rules):
		return SessionRestoreResult.failed(&"invalid_character_draft", "The saved character-creation draft is invalid for this campaign.")
	var replacement_vm := ScenarioVm.new()
	replacement_vm.configure(content.scenario)
	if not replacement_vm.restore(snapshot.scenario_vm):
		return SessionRestoreResult.failed(&"invalid_vm_state", "The saved Scenario VM state is invalid.")
	if not _valid_vm_reward_continuation(content, replacement_state, replacement_vm):
		return SessionRestoreResult.failed(&"invalid_vm_state", "The saved Scenario VM reward continuation is invalid.")
	if not _valid_player_map_vm_continuation(content, replacement_state, replacement_vm):
		return SessionRestoreResult.failed(&"invalid_vm_state", "The saved Scenario VM player-map continuation is invalid.")
	if not _valid_thief_vm_continuation(content, replacement_state, replacement_rng.snapshot(), replacement_vm):
		return SessionRestoreResult.failed(&"invalid_vm_state", "The saved Scenario VM Thief Encounter continuation is invalid.")
	if not _valid_combat_vm_request(content, replacement_state, replacement_rng, replacement_rules, replacement_action_state, replacement_vm.pending_request()):
		return SessionRestoreResult.failed(&"invalid_vm_state", "The saved combat request does not match authoritative combat state.")
	var replacement_continuation := SessionContinuation.new() if snapshot.continuation == null else SessionContinuation.from_data(snapshot.continuation.to_data())
	if replacement_continuation == null:
		return SessionRestoreResult.failed(&"invalid_session_continuation", "The saved session continuation is invalid.")
	var replacement_battle_return := SessionContinuation.new() if snapshot.battle_return_continuation == null else SessionContinuation.from_data(snapshot.battle_return_continuation.to_data())
	if replacement_battle_return == null:
		return SessionRestoreResult.failed(&"invalid_battle_return_continuation", "The saved battle return continuation is invalid.")
	if replacement_state.combat == null and not replacement_battle_return.is_empty():
		return SessionRestoreResult.failed(&"invalid_battle_return_continuation", "A battle return continuation requires an active battle.")
	if replacement_state.combat != null and not replacement_battle_return.is_empty():
		var battle_exploration := replacement_battle_return.exploration()
		if replacement_battle_return.kind != &"post-clock" or battle_exploration == null or battle_exploration.resume_kind != &"move" or not _valid_post_time_continuation(content, replacement_state, replacement_battle_return, null, null):
			return SessionRestoreResult.failed(&"invalid_battle_return_continuation", "The saved battle return references an unavailable exploration continuation.")
	var replacement_session_interaction: InteractionRequest = null
	if snapshot.session_interaction != null:
		replacement_session_interaction = InteractionRequest.from_data(snapshot.session_interaction.to_data())
		if replacement_session_interaction == null:
			return SessionRestoreResult.failed(&"invalid_session_interaction", "The saved session interaction is invalid.")
	if not replacement_continuation.is_empty() and not _valid_session_continuation(content, replacement_state, replacement_continuation, replacement_vm.pending_request(), replacement_session_interaction):
		return SessionRestoreResult.failed(&"invalid_session_continuation", "The saved session continuation is invalid.")
	if replacement_continuation.is_empty() and replacement_session_interaction != null:
		return SessionRestoreResult.failed(&"invalid_session_interaction", "The saved session interaction has no owning continuation.")
	return SessionRestoreResult.succeeded(SessionRestoreCandidate.new(
		replacement_state,
		replacement_rng,
		replacement_rules,
		replacement_action_state,
		replacement_vm,
		replacement_continuation,
		replacement_battle_return,
		replacement_session_interaction,
		snapshot.view_revision,
	))


static func _normalize_age_groups(state: GameState, content: RealmzContent, rules: RealmzRules) -> void:
	for character: CharacterState in state.party.characters():
		var race := content.race_by_id(character.race_id)
		var caste := content.caste_by_id(character.caste_id)
		if race != null and caste != null:
			rules.characters.ensure_age_group(character, race, caste)


static func _party_inventory_is_valid(content: RealmzContent, state: GameState, rules: RealmzRules) -> bool:
	if content == null or state == null or rules == null:
		return false
	var definitions := content.item_definitions()
	for character: CharacterState in state.party.characters():
		if rules.inventory.calculated_load(character, definitions) != character.carried_load:
			return false
		for scroll: SpellScrollState in character.scroll_case():
			if not scroll.is_empty() and content.spell_by_id(scroll.spell_id) == null:
				return false
	return true


static func _combat_staged_item_is_valid(content: RealmzContent, state: GameState, rules: RealmzRules) -> bool:
	if state.combat == null or state.combat.staged_random_item_instance_id().is_empty():
		return true
	var actor_id := state.combat.active_actor_id()
	var character := state.party.character_by_id(actor_id)
	var instance_id := state.combat.staged_random_item_instance_id()
	if character == null or state.combat.completed or state.combat.staged_random_item_power(actor_id, instance_id) not in range(1, 8):
		return false
	var instance: ItemInstance = null
	for candidate: ItemInstance in character.inventory():
		if candidate.id == instance_id:
			instance = candidate
			break
	var item := content.item_by_id(instance.definition_id) if instance != null else null
	var spell := content.spell_by_classic_id(item.special_2) if item != null else null
	if item == null or spell == null or absi(item.special_1) != 8:
		return false
	var use_probe := rules.inventory.classic_spell_item_probe(character, instance, item, spell, content.race_by_id(character.race_id), content.caste_by_id(character.caste_id), true)
	if not use_probe.allowed or ClassicSpellCapabilityCatalog.combat_item_disposition(spell) != ClassicSpellCapabilityCatalog.DISPOSITION_EXECUTABLE:
		return false
	return true


static func _valid_combat_vm_request(content: RealmzContent, state: GameState, rng: RealmzRng, rules: RealmzRules, action_state: ScenarioActionState, request: InteractionRequest) -> bool:
	if request == null or request.kind != InteractionRequest.COMBAT:
		return true
	if state.combat == null or state.combat.completed:
		return false
	var expected := RealmzRuntimeApi.new(content, state, rng, action_state, rules).active_combat_request(request.request_id)
	return expected != null and expected.to_data() == request.to_data()


static func _party_fast_spells_are_valid(content: RealmzContent, state: GameState) -> bool:
	if content == null or state == null:
		return false
	for character: CharacterState in state.party.characters():
		for binding: FastSpellBindingState in character.fast_spells():
			if binding.is_empty():
				continue
			var spell := content.spell_by_id(binding.spell_id)
			if spell == null or not character.known_spells().has(binding.spell_id) or binding.power < 1 or binding.power > 7 or spell.cost < 0 and binding.power != 1:
				return false
	return true


static func _party_appearance_is_valid(content: RealmzContent, state: GameState) -> bool:
	if content == null or state == null:
		return false
	if not content.has_character_appearance_catalog():
		return true
	for character: CharacterState in state.party.characters():
		if not character.portrait_id.is_empty():
			var portrait := content.appearance_by_id(character.portrait_id)
			if portrait == null or portrait.kind != CharacterAppearanceDefinition.PORTRAIT:
				return false
		if not character.combat_icon_id.is_empty():
			var icon := content.appearance_by_id(character.combat_icon_id)
			if icon == null or icon.kind != CharacterAppearanceDefinition.COMBAT_ICON:
				return false
	return true


static func _shop_state_is_valid(content: RealmzContent, state: GameState) -> bool:
	if content == null or state == null:
		return false
	if not state.active_shop_id.is_empty() and content.shop_by_id(state.active_shop_id) == null:
		return false
	for shop_id: Variant in state.shop_buyback_overrides():
		var shop := content.shop_by_id(String(shop_id))
		if shop == null:
			return false
		var occupied_slots: Dictionary = {}
		for index: int in shop.item_ids().size():
			if state.shop_quantity(shop, index) > 0: occupied_slots[shop.stock_slot(index)] = true
		for item_id: Variant in state.shop_buyback_overrides()[shop_id]:
			var item := content.item_by_id(String(item_id))
			var slot := state.shop_buyback_slot(String(shop_id), String(item_id))
			if item == null or slot < 0 or slot > 999 or slot / 200 != item.classic_id / 200 or occupied_slots.has(slot):
				return false
			occupied_slots[slot] = true
	return true


static func _location_notes_are_valid(content: RealmzContent, state: GameState) -> bool:
	if content == null or state == null:
		return false
	var counts: Dictionary = {}
	var ordinals: Dictionary = {}
	for note: LocationNoteState in state.world.location_notes():
		var map := content.world.map_by_id(note.map_id)
		if map == null or map.level_type != note.map_kind or map.level_index != note.level_index or note.native_location_id != LocationNoteState.native_id_for(map.level_index, note.coordinate) or map.topology.cell_at(note.coordinate) == null or note.text.is_empty() or not LocationNoteState.text_is_valid(note.text):
			return false
		counts[note.map_kind] = int(counts.get(note.map_kind, 0)) + 1
		var ordinal_key := "%s:%d" % [String(note.map_kind), note.record_ordinal]
		if ordinals.has(ordinal_key):
			return false
		ordinals[ordinal_key] = true
		if int(counts[note.map_kind]) > LocationNoteState.MAX_NOTES_PER_MAP_KIND:
			return false
	return true


static func _boat_overlays_are_valid(content: RealmzContent, state: GameState) -> bool:
	if content == null or state == null:
		return false
	for key_value: Variant in state.world.boat_presence_overrides().keys():
		var key := String(key_value)
		var separator := key.rfind(":")
		if separator <= 0:
			return false
		var map := content.world.map_by_id(key.left(separator))
		var components := key.substr(separator + 1).split(",", false, 1)
		if map == null or map.level_type != &"land" or components.size() != 2 or not components[0].is_valid_int() or not components[1].is_valid_int() or map.topology.cell_at(Vector2i(int(components[0]), int(components[1]))) == null:
			return false
	return true


static func _journal_messages_are_valid(content: RealmzContent, state: GameState) -> bool:
	for message_id: int in state.journal_message_ids():
		if not GameState.journal_message_id_is_valid(message_id) or content.message_by_id(message_id) == null:
			return false
	return true


static func _acquired_player_maps_are_valid(content: RealmzContent, state: GameState) -> bool:
	if content == null or state == null:
		return false
	for player_map_id: String in state.world.acquired_map_ids():
		if content.world.player_map_by_id(player_map_id) == null:
			return false
	return true


static func _valid_session_continuation(content: RealmzContent, state: GameState, continuation: SessionContinuation, vm_interaction: InteractionRequest, session_interaction: InteractionRequest) -> bool:
	if continuation == null or continuation.is_empty():
		return false
	match continuation.kind:
		&"boat-choice":
			return _valid_boat_continuation(content, state, continuation, vm_interaction, session_interaction)
		&"application-hook":
			var application := continuation.application()
			if application == null or vm_interaction == null or session_interaction != null or application.program_id.is_empty():
				return false
			if content.scenario.application_hook_program_id(application.hook) != application.program_id or content.scenario.program_by_id(application.program_id) == null:
				return false
			match application.resume_kind:
				&"begin-adventure":
					return application.hook == ScenarioApplicationHooks.START_GAME and application.service_id.is_empty() and state.party_setup_completed and not state.party.characters().is_empty()
				&"service":
					return application.hook in [ScenarioApplicationHooks.SHOP, ScenarioApplicationHooks.TEMPLE] and not application.service_id.is_empty() and ((application.service_id == state.active_shop_id and content.shop_by_id(application.service_id) != null) or (application.service_id == "realmz.service.temple" and state.temple_available))
				&"end-adventure":
					return application.hook == ScenarioApplicationHooks.END_ADVENTURE and application.service_id.is_empty()
				&"end-adventure-close":
					return application.hook == ScenarioApplicationHooks.PARTY_DEATH and application.service_id.is_empty()
				&"party-defeat":
					return application.hook == ScenarioApplicationHooks.PARTY_DEATH and application.service_id.is_empty() and state.combat != null and state.combat.completed and state.combat.outcome == &"defeat"
				&"scenario-party-defeat":
					if application.hook != ScenarioApplicationHooks.PARTY_DEATH or not application.service_id.is_empty() or application.suspended_owner == null:
						return false
					var saved := application.suspended_vm
					return ScenarioVm.handoff_is_valid(application.vm_handoff, saved) and RealmzRuntimeApi.party_defeat_handoff_is_valid(content, state, application.vm_handoff.runtime) and suspended_scenario_owner_is_valid(content, state, application.suspended_owner, saved)
			return false
		&"pooled-wealth-departure":
			var service := continuation.service()
			if service == null or vm_interaction != null or session_interaction == null or state.party == null or state.bank_available:
				return false
			var departure_probe := content.world.probe_movement(state.party.map_id, state.party.coordinate, service.direction, state.world, state.party_in_boat)
			if not departure_probe.allowed and departure_probe.reason == &"invalid_direction":
				return false
			if service.stage == &"warning":
				return SessionInteractionFactory.has_pooled_wealth(state.party) and session_interaction.to_data() == SessionInteractionFactory.pooled_wealth_departure_warning(session_interaction.request_id).to_data()
			if service.stage == &"distribution":
				var bank_body := session_interaction.body as InteractionRequest.BankRequestBody
				return session_interaction.kind == InteractionRequest.POOLED_WEALTH_DEPARTURE and bank_body != null and bank_body.mode == &"departure" and state.party.character_by_id(bank_body.selected_character_id) != null and session_interaction.to_data() == SessionInteractionFactory.pooled_wealth_departure_distribution(state, session_interaction.request_id, bank_body.selected_character_id).to_data()
			return false
		&"service-interaction":
			var service := continuation.service()
			if service == null or vm_interaction != null or session_interaction == null:
				return false
			var runtime := service.runtime_continuation
			if runtime == null:
				return false
			var runtime_body := runtime.body as ScenarioRuntimeContinuation.ServiceBody
			var selected_temple_character := "" if runtime_body == null else runtime_body.selected_character_id
			match runtime.kind:
				&"classic-shop":
					return service.service_id == state.active_shop_id and not service.service_id.is_empty() and content.shop_by_id(service.service_id) != null and session_interaction.kind == InteractionRequest.SHOP
				&"classic-temple":
					var temple_body := session_interaction.body as InteractionRequest.TempleRequestBody
					return runtime_body != null and service.service_id == "realmz.service.temple" and state.temple_available and runtime_body.cost_percent == state.temple_cost_percent and runtime_body.bank_available == state.bank_available and state.party.character_by_id(selected_temple_character) != null and session_interaction.kind == InteractionRequest.TEMPLE and temple_body != null and temple_body.selected_character_id == selected_temple_character
				&"classic-temple-exit":
					return runtime_body != null and service.service_id == "realmz.service.temple" and state.temple_available and not state.bank_available and runtime_body.cost_percent == state.temple_cost_percent and not runtime_body.bank_available and state.party.character_by_id(selected_temple_character) != null and session_interaction.kind == InteractionRequest.YES_NO
				&"classic-banking":
					return service.service_id == "realmz.service.bank" and state.bank_available and session_interaction.kind == InteractionRequest.BANK
			return false
		&"drop-item-confirmation", &"item-use-target-selection", &"field-spell-target-selection", &"scroll-target-selection", &"scroll-discard-confirmation":
			return _valid_targeting_continuation(content, state, continuation, vm_interaction, session_interaction)
		&"item-xap":
			return _valid_item_xap_continuation(content, state, continuation, vm_interaction, session_interaction)
		&"character-spell-confirmation":
			var application := continuation.application()
			if application == null or vm_interaction != null or session_interaction == null or state.party_setup_completed or state.character_draft == null or state.character_draft.generated_character == null:
				return false
			var character := state.character_draft.generated_character
			if application.character_id != character.id or application.remaining < 1:
				return false
			var rules := RealmzRules.new()
			var spent := 0
			for spell_id: String in character.known_spells():
				spent += rules.characters.spell_selection_cost(content.spell_by_id(spell_id))
			var remaining := maxi(0, rules.characters.spell_selection_total(character, content.caste_by_id(character.caste_id)) - spent)
			return remaining == application.remaining and session_interaction.to_data() == SessionInteractionFactory.character_spell_confirmation(session_interaction.request_id, remaining).to_data()
		&"character-vault-publication":
			var application := continuation.application()
			if application == null or vm_interaction != null or session_interaction == null or state.party_setup_completed:
				return false
			var character := state.party.character_by_id(application.character_id)
			return character != null and session_interaction.to_data() == SessionInteractionFactory.character_vault_confirmation(session_interaction.request_id, character.name).to_data()
		&"combat-retreat-confirmation":
			return _valid_combat_retreat(continuation, state, vm_interaction, session_interaction)
		&"combat-friendly-collision":
			return _valid_friendly_collision(continuation, state, vm_interaction, session_interaction)
		&"age-updates":
			var age := continuation.age()
			if age == null or vm_interaction != null or session_interaction == null or session_interaction.kind != InteractionRequest.AGE_UPDATE or age.updates.is_empty() or age.index < 1 or age.index > age.updates.size():
				return false
			for update: InteractionRequest.AgeUpdateBody in age.updates:
				if not _valid_age_update_payload(state, update):
					return false
			var current_update: InteractionRequest.AgeUpdateBody = age.updates[age.index - 1]
			var expected_age_request := InteractionRequest.age_update_body("validation.age-update", current_update)
			var actual_age_body := session_interaction.body as InteractionRequest.AgeUpdateBody
			var expected_age_body: InteractionRequest.AgeUpdateBody = null if expected_age_request == null else expected_age_request.body as InteractionRequest.AgeUpdateBody
			if actual_age_body == null or not actual_age_body.same_values(expected_age_body):
				return false
			if age.resume_kind == &"completed":
				return age.resume_continuation == null
			if age.resume_kind == &"combat-monster-turns":
				return age.resume_continuation == null and state.combat != null and not state.combat.completed and state.combat.pending_monster_attack != null
			if age.resume_kind == &"post-clock":
				return _valid_post_time_continuation(content, state, age.resume_continuation, vm_interaction, null)
			return age.resume_kind == &"post-move" and _valid_ready_post_move_continuation(content, state, age.resume_continuation)
		&"combat-death-macro":
			var combat := continuation.combat()
			if combat == null or session_interaction != null or vm_interaction == null or state.combat == null or state.combat.battle_id != combat.battle_id:
				return false
			var death_monster := state.combat.monster_by_id(combat.combatant_id)
			if death_monster == null or content.scenario.program_by_id(combat.program_id) == null:
				return false
			var queued_id := state.combat.pending_spell_death_macro_id()
			if not queued_id.is_empty():
				var definition := content.monster_by_id(death_monster.definition_id)
				return queued_id == combat.combatant_id and not combat.reset_traitor_on_complete and definition != null and combat.program_id == "xap:%d" % definition.death_macro
			return combat.reset_traitor_on_complete
		&"combat-ally-selection":
			var combat := continuation.combat()
			return combat != null and vm_interaction == null and session_interaction != null and session_interaction.kind == &"ally_selection" and state.combat != null and state.combat.completed and state.combat.battle_id == combat.battle_id
		&"combat-fumble-recovery":
			var combat := continuation.combat()
			if combat == null or vm_interaction != null or session_interaction == null or session_interaction.kind != InteractionRequest.TREASURE_DISTRIBUTION or state.combat == null or not state.combat.completed or state.combat.battle_id != combat.battle_id or state.combat.fumbled_items().is_empty():
				return false
			var expected_fumble_request := InteractionRequest.from_payload("validation.fumble-recovery", InteractionRequest.TREASURE_DISTRIBUTION, RealmzRules.new().combat_flow.fumble_recovery_payload(state, content))
			var actual_fumble_body := session_interaction.body as InteractionRequest.TreasureRequestBody
			var expected_fumble_body: InteractionRequest.TreasureRequestBody = null if expected_fumble_request == null else expected_fumble_request.body as InteractionRequest.TreasureRequestBody
			return actual_fumble_body != null and actual_fumble_body.same_fumble_values(expected_fumble_body)
		&"combat-reward":
			var reward_body := continuation.reward()
			if reward_body == null or vm_interaction != null:
				return false
			var runtime := reward_body.runtime_continuation
			var runtime_body := runtime.body as ScenarioRuntimeContinuation.RewardBody if runtime != null and runtime.kind == ScenarioRuntimeContinuation.CLASSIC_REWARD else null
			var reward := runtime_body.state if runtime_body != null else null
			return reward != null and reward.origin == &"battle" and reward.source_id == reward_body.battle_id and _valid_reward_continuation(content, state, reward, session_interaction)
		&"post-clock":
			return _valid_post_time_continuation(content, state, continuation, vm_interaction, session_interaction)
		&"post-move":
			return _valid_post_move_continuation(content, state, continuation, vm_interaction, session_interaction)
	return false


static func _valid_friendly_collision(continuation: SessionContinuation, state: GameState, vm_interaction: InteractionRequest, session_interaction: InteractionRequest) -> bool:
	var combat := continuation.combat()
	if combat == null or combat.mode != &"friendly" or vm_interaction != null or session_interaction == null or session_interaction.to_data() != SessionInteractionFactory.friendly_collision(session_interaction.request_id).to_data():
		return false
	if state.combat == null or state.combat.completed or state.combat.battle_id != combat.battle_id or state.combat.active_actor_id() != combat.actor_id:
		return false
	return not RealmzRules.new().combat_flow.friendly_collision_target_id(state, combat.actor_id, combat.destination).is_empty()


static func _valid_combat_retreat(continuation: SessionContinuation, state: GameState, vm_interaction: InteractionRequest, session_interaction: InteractionRequest) -> bool:
	var combat := continuation.combat()
	if combat == null or combat.mode not in [&"explicit", &"edge"] or vm_interaction != null or session_interaction == null or session_interaction.to_data() != SessionInteractionFactory.retreat_confirmation(session_interaction.request_id).to_data():
		return false
	if state.combat == null or state.combat.completed or state.combat.battle_id != combat.battle_id or state.combat.active_actor_id() != combat.actor_id:
		return false
	var rules := RealmzRules.new()
	var probe: Variant = rules.combat_flow.probe_character_retreat(state.combat, state.party.characters(), combat.actor_id) if combat.mode == &"explicit" else rules.combat_flow.probe_edge_retreat(state.combat, combat.actor_id, combat.destination)
	return probe.allowed and not probe.forced


static func _valid_item_xap_continuation(content: RealmzContent, state: GameState, continuation: SessionContinuation, vm_interaction: InteractionRequest, session_interaction: InteractionRequest) -> bool:
	var item_body := continuation.item_xap_body()
	if item_body == null or vm_interaction == null or session_interaction != null or state.party.character_by_id(item_body.character_id) == null:
		return false
	var item := content.item_by_id(item_body.item_id)
	if item == null or item_body.program_id != "xap:%d" % item.special_5 or content.scenario.program_by_id(item_body.program_id) == null or absi(item.item_type) != 23 and item.special_1 != -23:
		return false
	return item_body.source_battle_id.is_empty() or state.combat != null and state.combat.battle_id == item_body.source_battle_id


static func _valid_boat_continuation(content: RealmzContent, state: GameState, continuation: SessionContinuation, vm_interaction: InteractionRequest, session_interaction: InteractionRequest) -> bool:
	var boat := continuation.boat()
	var prompt: InteractionRequest.YesNoRequestBody = null
	if session_interaction != null:
		prompt = session_interaction.body as InteractionRequest.YesNoRequestBody
	if boat == null or vm_interaction != null or session_interaction == null or session_interaction.kind != InteractionRequest.YES_NO or prompt == null or state.party.map_id != boat.source_map_id or state.party.coordinate != boat.source_coordinate:
		return false
	var movement := content.world.probe_movement(boat.source_map_id, boat.source_coordinate, boat.direction, state.world, state.party_in_boat)
	if movement.target_map == null or movement.target_map.id != boat.target_map_id or movement.target_coordinate != boat.target_coordinate:
		return false
	if boat.action == &"board":
		return not state.party_in_boat and movement.reason == &"board_boat" and prompt.prompt == "Board this boat?" and prompt.yes_label == "Board" and prompt.no_label == "Stay ashore"
	if boat.action == &"disembark":
		return state.party_in_boat and movement.reason == &"boat_shore" and prompt.prompt == "Leave the boat here and go ashore?" and prompt.yes_label == "Leave boat" and prompt.no_label == "Remain aboard"
	return false


static func _valid_targeting_continuation(content: RealmzContent, state: GameState, continuation: SessionContinuation, vm_interaction: InteractionRequest, session_interaction: InteractionRequest) -> bool:
	var targeting := continuation.targeting()
	if targeting == null or vm_interaction != null or session_interaction == null:
		return false
	var character := state.party.character_by_id(targeting.character_id)
	if continuation.kind == &"scroll-discard-confirmation":
		var scroll := character.scroll_at(targeting.scroll_slot) if character != null else null
		var discard_spell := content.spell_by_id(targeting.spell_id)
		if scroll == null or discard_spell == null or scroll.spell_id != discard_spell.id or scroll.power != targeting.power or discard_spell.in_camp or character.current_health < 1 or character.conditions.is_active(ConditionRules.ANIMATED):
			return false
		var equipped_case := false
		for carried: ItemInstance in character.inventory():
			var carried_definition := content.item_by_id(carried.definition_id)
			if carried.equipped and carried_definition != null and absi(carried_definition.item_type) == 13:
				equipped_case = true
				break
		return equipped_case and session_interaction.to_data() == InventoryMagicServicesWorkflow.scroll_discard_request(session_interaction.request_id, discard_spell.name).to_data()
	if continuation.kind == &"drop-item-confirmation":
		var instance := _item_instance_for_state(character, targeting.instance_id)
		var definition: ItemDefinition = null if instance == null else content.item_by_id(instance.definition_id)
		if character == null or instance == null or definition == null or not RealmzRules.new().inventory.classic_drop_probe(character, instance).allowed:
			return false
		var display_name := definition.name if instance.identified else definition.unidentified_name
		return session_interaction.to_data() == SessionInteractionFactory.drop_item_confirmation(session_interaction.request_id, display_name).to_data()
	if session_interaction.kind != InteractionRequest.CHARACTER_SELECTION or state.combat != null or character == null:
		return false
	var spell := content.spell_by_id(targeting.spell_id)
	if spell == null or targeting.power < 1 or targeting.power > 7:
		return false
	if continuation.kind == &"item-use-target-selection":
		var instance := _item_instance_for_state(character, targeting.instance_id)
		var definition: ItemDefinition = null if instance == null else content.item_by_id(instance.definition_id)
		if instance == null or definition == null or definition.special_2 != spell.classic_id or instance.charges != targeting.starting_charges:
			return false
		var authored_power := absi(definition.special_1)
		var expected_count := state.party.characters().size() if spell.target_type > 2 else mini(targeting.power, state.party.characters().size()) if spell.target_type == 0 else 1
		var probe := RealmzRules.new().inventory.classic_spell_item_probe(character, instance, definition, spell, content.race_by_id(character.race_id), content.caste_by_id(character.caste_id), false)
		var supported := spell.special == 0 and absi(spell.damage_type) >= 1 and absi(spell.damage_type) <= 6 and absi(spell.spell_class) != 9 or absi(spell.special) == 57
		return (authored_power == 8 or targeting.power == authored_power) and targeting.target_count == expected_count and spell.target_type not in [5, 7] and spell.target_type >= 0 and spell.target_type <= 12 and probe.allowed and supported and session_interaction.to_data() == InventoryMagicServicesWorkflow.item_target_request(session_interaction.request_id, character, instance.id, definition, spell, targeting.power, expected_count, state.party.characters()).to_data()
	if continuation.kind == &"field-spell-target-selection":
		if not character.known_spells().has(spell.id) or character.spell_points != targeting.starting_spell_points or state.character_spellcasting_blocked or character.current_health < 1 or character.spell_points < absi(spell.cost * targeting.power) or not spell.in_camp or spell.cost < 0 and targeting.power != 1:
			return false
		for condition: int in [ConditionRules.CONFUSED, ConditionRules.SILENCED, ConditionRules.HELPLESS, ConditionRules.STUPID, ConditionRules.ANIMATED]:
			if character.conditions.is_active(condition):
				return false
	else:
		var scroll := character.scroll_at(targeting.scroll_slot)
		if scroll == null or scroll.spell_id != spell.id or scroll.power != targeting.power or character.current_health < 1 or character.conditions.is_active(ConditionRules.ANIMATED) or not spell.in_camp:
			return false
		var has_case := false
		for carried: ItemInstance in character.inventory():
			var carried_definition := content.item_by_id(carried.definition_id)
			if carried.equipped and carried_definition != null and absi(carried_definition.item_type) == 13:
				has_case = true
				break
		if not has_case:
			return false
	var supported := ClassicSpellCapabilityCatalog.field_character_disposition(spell) == ClassicSpellCapabilityCatalog.DISPOSITION_EXECUTABLE
	var expected_count := mini(targeting.power, state.party.characters().size()) if spell.target_type == 0 else 1
	if targeting.target_count != expected_count or spell.target_type < 0 or spell.target_type > 2 or not supported:
		return false
	return session_interaction.to_data() == (InventoryMagicServicesWorkflow.field_spell_target_request(session_interaction.request_id, character, spell, targeting.power, expected_count, state.party.characters()).to_data() if continuation.kind == &"field-spell-target-selection" else InventoryMagicServicesWorkflow.scroll_target_request(session_interaction.request_id, character, targeting.scroll_slot, spell, targeting.power, expected_count, state.party.characters()).to_data())


static func _item_instance_for_state(character: CharacterState, instance_id: String) -> ItemInstance:
	if character == null:
		return null
	for carried: ItemInstance in character.inventory():
		if carried.id == instance_id:
			return carried
	return null


static func _valid_post_move_continuation(content: RealmzContent, state: GameState, continuation: SessionContinuation, vm_interaction: InteractionRequest, session_interaction: InteractionRequest) -> bool:
	var exploration := continuation.exploration()
	if continuation.kind != &"post-move" or exploration == null or exploration.action_point_destination_depth < 0 or exploration.action_point_destination_depth > 1:
		return false
	var map := content.world.map_by_id(exploration.map_id)
	var cell: MapCell = null if map == null else map.topology.cell_at(exploration.coordinate)
	if cell == null or state.party.map_id != map.id or state.party.coordinate != exploration.coordinate or exploration.trigger_ids != ExplorationTimeWorkflow.selected_placed_trigger_ids(content, cell, state.world) or exploration.random_region_ids != state.world.random_region_ids_at(map, exploration.coordinate):
		return false
	if exploration.random_region_index < -1 or exploration.random_region_index >= exploration.random_region_ids.size():
		return false
	if session_interaction != null:
		return vm_interaction == null and exploration.active_trigger_id.is_empty() and exploration.active_random_program_id.is_empty() and exploration.random_battle_stage == &"surprise-choice" and session_interaction.kind == InteractionRequest.YES_NO and exploration.random_region_index >= 0 and exploration.random_region_ids[exploration.random_region_index] == exploration.active_random_region_id and map.random_region_by_id(exploration.active_random_region_id) != null
	if vm_interaction == null or not exploration.random_battle_stage.is_empty() or not exploration.active_random_region_id.is_empty():
		return false
	if not exploration.active_random_program_id.is_empty():
		return exploration.active_trigger_id.is_empty() and content.scenario.program_by_id(exploration.active_random_program_id) != null
	return exploration.trigger_index >= 0 and exploration.trigger_index < exploration.trigger_ids.size() and not exploration.active_trigger_id.is_empty() and exploration.trigger_ids[exploration.trigger_index] == exploration.active_trigger_id and content.trigger_by_id(exploration.active_trigger_id) != null


static func suspended_scenario_owner_is_valid(content: RealmzContent, state: GameState, owner: SessionContinuation, saved: ScenarioVmSnapshot) -> bool:
	if owner == null or owner.kind not in [&"post-clock", &"post-move", &"item-xap"] or saved == null or saved.halted or saved.frames.is_empty() or saved.pending_request != null or saved.pending_continuation != null:
		return false
	var test_vm := ScenarioVm.new()
	test_vm.configure(content.scenario)
	if not test_vm.restore(saved):
		return false
	var sentinel := InteractionRequest.acknowledge("internal.suspended-scenario", "Suspended scenario validation")
	return _valid_session_continuation(content, state, owner, sentinel, null)


static func _valid_post_time_continuation(content: RealmzContent, state: GameState, continuation: SessionContinuation, vm_interaction: InteractionRequest, session_interaction: InteractionRequest) -> bool:
	if continuation == null or continuation.kind != &"post-clock":
		return false
	var exploration := continuation.exploration()
	if exploration == null or exploration.timed_day < 0 or exploration.timed_encounter_index < 0 or exploration.timed_encounter_index > content.timed_encounters().size() or exploration.resume_kind not in [&"completed", &"move", &"post-move", &"attempt-search-completed", &"attempt-search-post-move", &"area-search-second", &"camp-entry-second", &"rest-second", &"camp-departure-second", &"heal"]:
		return false
	var map := content.world.map_by_id(exploration.map_id)
	var cell: MapCell = null if map == null else map.topology.cell_at(exploration.coordinate)
	if cell == null or state.party.map_id != map.id or state.party.coordinate != exploration.coordinate or exploration.random_region_ids != state.world.random_region_ids_at(map, exploration.coordinate) or exploration.random_region_index < -1 or exploration.random_region_index >= exploration.random_region_ids.size() or exploration.direction.x < -1 or exploration.direction.x > 1 or exploration.direction.y < -1 or exploration.direction.y > 1:
		return false
	if exploration.resume_kind in [&"completed", &"post-move", &"attempt-search-completed", &"attempt-search-post-move", &"area-search-second", &"camp-entry-second", &"rest-second", &"heal"] and exploration.direction != Vector2i.ZERO or exploration.resume_kind in [&"move", &"camp-departure-second"] and exploration.direction == Vector2i.ZERO:
		return false
	if session_interaction != null:
		return vm_interaction == null and exploration.active_random_program_id.is_empty() and exploration.random_battle_stage == &"surprise-choice" and session_interaction.kind == InteractionRequest.YES_NO and exploration.random_region_index >= 0 and exploration.random_region_ids[exploration.random_region_index] == exploration.active_random_region_id and map.random_region_by_id(exploration.active_random_region_id) != null
	if vm_interaction != null:
		if not exploration.active_timed_program_id.is_empty():
			return exploration.active_random_program_id.is_empty() and content.scenario.program_by_id(exploration.active_timed_program_id) != null
		return exploration.random_battle_stage.is_empty() and exploration.active_random_region_id.is_empty() and not exploration.active_random_program_id.is_empty() and content.scenario.program_by_id(exploration.active_random_program_id) != null
	return exploration.random_battle_stage.is_empty() and exploration.active_random_region_id.is_empty() and exploration.active_random_program_id.is_empty() and exploration.active_timed_program_id.is_empty()


static func _valid_vm_reward_continuation(content: RealmzContent, state: GameState, vm: ScenarioVm) -> bool:
	var snapshot := vm.snapshot()
	if snapshot.pending_continuation == null:
		return true
	var runtime := snapshot.pending_continuation.runtime
	if runtime == null or runtime.kind != ScenarioRuntimeContinuation.CLASSIC_REWARD:
		return true
	var runtime_body := runtime.body as ScenarioRuntimeContinuation.RewardBody
	var reward := runtime_body.state if runtime_body != null else null
	return reward != null and _valid_reward_continuation(content, state, reward, vm.pending_request())


static func _valid_player_map_vm_continuation(content: RealmzContent, state: GameState, vm: ScenarioVm) -> bool:
	var snapshot := vm.snapshot()
	if snapshot.pending_continuation == null:
		return true
	var runtime := snapshot.pending_continuation.runtime
	if runtime == null or runtime.kind != ScenarioRuntimeContinuation.CLASSIC_PLAYER_MAP:
		return true
	var request := vm.pending_request()
	var runtime_body := runtime.body as ScenarioRuntimeContinuation.TextBody
	var player_map_id := "" if runtime_body == null else runtime_body.player_map_id
	var body: InteractionRequest.AcknowledgeBody = null
	if request != null:
		body = request.body as InteractionRequest.AcknowledgeBody
	return request != null and request.kind == InteractionRequest.ACKNOWLEDGE and body != null and body.presentation == &"player-map" and body.player_map_id == player_map_id and body.has_presentation and body.has_player_map_id and not body.has_message_id and not body.has_journal_state and not body.has_sound_id and content.world.player_map_by_id(player_map_id) != null and state.world.has_map(player_map_id)


static func _valid_thief_vm_continuation(content: RealmzContent, state: GameState, rng_state: RealmzRngState, vm: ScenarioVm) -> bool:
	var snapshot := vm.snapshot()
	if snapshot.pending_continuation == null:
		return true
	var runtime := snapshot.pending_continuation.runtime
	if runtime == null or runtime.kind not in [ScenarioRuntimeContinuation.CLASSIC_THIEF_ENCOUNTER, ScenarioRuntimeContinuation.CLASSIC_PICK_LOCK, ScenarioRuntimeContinuation.CLASSIC_THIEF_RESOLUTION]:
		return true
	var owner := runtime.body as ScenarioRuntimeContinuation.ThiefBody
	var encounter := content.complex_encounter_by_id(owner.encounter_id) if owner != null else null
	var thief := content.thief_encounter_by_id(encounter.thief_success) if encounter != null and encounter.thief else null
	var request := vm.pending_request()
	if owner == null or encounter == null or thief == null or request == null:
		return false
	if runtime.kind == ScenarioRuntimeContinuation.CLASSIC_THIEF_ENCOUNTER:
		var body := request.body as InteractionRequest.ThiefEncounterRequestBody
		return request.kind == InteractionRequest.THIEF_ENCOUNTER and body != null and body.encounter_id == encounter.id and _valid_thief_request(content, state, thief, body)
	if runtime.kind == ScenarioRuntimeContinuation.CLASSIC_THIEF_RESOLUTION:
		return _valid_thief_resolution_request(content, state, thief, owner, request)
	var body := request.body as InteractionRequest.PickLockRequestBody
	var character := state.party.character_by_id(owner.character_id)
	if request.kind != InteractionRequest.PICK_LOCK or body == null or owner.action_index not in [2, 4, 6, 7] or body.encounter_id != encounter.id or body.action_index != owner.action_index or body.character_id != owner.character_id or character == null or character.current_health <= 0 or character.conditions.is_active(ConditionRules.ANIMATED):
		return false
	var flags := state.thief_encounter_type_flags(thief)
	var chance := ClassicPickLockRulesScript.chance(character.ability_value(ClassicPickLockRulesScript.ability_index(owner.action_index)), thief.modifiers()[owner.action_index])
	var expected_frames := ClassicPickLockRulesScript.preview(rng_state, thief.tumblers, chance)
	return flags.size() == 10 and not flags[owner.action_index] and chance > 0 and body.action_label == ClassicPickLockRulesScript.action_label(owner.action_index) and body.character_name == character.name and body.portrait_id == character.portrait_id and body.chance_percent == chance and body.yellow_threshold == ClassicPickLockRulesScript.yellow_threshold(chance) and body.green_threshold == ClassicPickLockRulesScript.green_threshold(chance) and body.frame_rate == ClassicPickLockRulesScript.FRAME_RATE and body.time_limit_frames == ClassicPickLockRulesScript.time_limit_frames(thief.tumblers) and body.frames == expected_frames


static func _valid_thief_request(content: RealmzContent, state: GameState, thief: ThiefEncounterDefinition, body: InteractionRequest.ThiefEncounterRequestBody) -> bool:
	var prompt_id := absi(thief.prompts()[0]) if not thief.prompts().is_empty() else 0
	var message := content.message_by_id(prompt_id)
	if body.prompt != (message.text if message != null else "Choose a thief action."):
		return false
	var opening_sounds := thief.prompt_sounds()
	if body.sound_id not in [0, opening_sounds[0] if not opening_sounds.is_empty() else 0]:
		return false
	var flags := state.thief_encounter_type_flags(thief)
	var eligible: Array[CharacterState] = []
	for character: CharacterState in state.party.characters():
		if character.current_health > 0 and not character.conditions.is_active(ConditionRules.ANIMATED):
			eligible.append(character)
	if flags.size() != 10 or body.characters.size() != eligible.size():
		return false
	for index: int in eligible.size():
		var character := eligible[index]
		var detached := body.characters[index]
		if detached.id != character.id or detached.name != character.name or detached.portrait_id != character.portrait_id or detached.actions.size() != 8:
			return false
		for action_index: int in 8:
			var action := detached.actions[action_index]
			var ability := character.ability_value(ClassicPickLockRulesScript.ability_index(action_index))
			var effective := ability + thief.modifiers()[action_index]
			var expected_enabled := flags[action_index] and ability != 0 and effective > 0
			var expected_reason := "" if expected_enabled else "This action is no longer available." if not flags[action_index] else "This character lacks the required ability." if ability == 0 else "The authored modifier reduces this action below zero."
			if action.index != action_index or action.label != ClassicPickLockRulesScript.action_label(action_index) or action.value != (effective if ability != 0 else 0) or action.enabled != expected_enabled or action.reason != expected_reason:
				return false
	return true


static func _valid_thief_resolution_request(content: RealmzContent, state: GameState, thief: ThiefEncounterDefinition, owner: ScenarioRuntimeContinuation.ThiefBody, request: InteractionRequest) -> bool:
	var body := request.body as InteractionRequest.AcknowledgeBody
	var character := state.party.character_by_id(owner.character_id)
	if request.kind != InteractionRequest.ACKNOWLEDGE or body == null or character == null or owner.action_index < 0 or owner.action_index > 7 or body.presentation != &"classic-textbox" or not body.has_presentation or body.has_journal_state or body.has_player_map_id:
		return false
	var flags := state.thief_encounter_type_flags(thief)
	if flags.size() != 10:
		return false
	if owner.phase == &"trap-message":
		return owner.trap_pending and flags[9] and body.prompt == "A trap is sprung." and not body.has_message_id and not body.has_sound_id
	if owner.phase != &"action-message" or flags[owner.action_index]:
		return false
	var text_ids := thief.success_text() if owner.succeeded else thief.failure_text()
	var sound_ids := thief.success_sounds() if owner.succeeded else thief.failure_sounds()
	var signed_message_id := text_ids[owner.action_index]
	var message_id := absi(signed_message_id)
	var message := content.message_by_id(message_id)
	return signed_message_id > 0 and message != null and body.has_message_id and body.message_id == message_id and body.prompt == message.text and body.has_sound_id and body.sound_id == sound_ids[owner.action_index] and (not owner.trap_pending or not owner.succeeded and flags[9])


static func _valid_reward_continuation(content: RealmzContent, state: GameState, reward: ClassicRewardState, request: InteractionRequest) -> bool:
	if reward == null or request == null or reward.source_id.is_empty() or reward.origin not in [&"scenario", &"battle"]:
		return false
	if reward.origin == &"battle" and (state.combat == null or not state.combat.completed or not state.combat.rewards_started or state.combat.rewards_completed or state.combat.battle_id != reward.source_id):
		return false
	if (reward.origin == &"battle" and reward.battle_stage not in [ClassicRewardState.ORDINARY_BATTLE_STAGE, ClassicRewardState.BONUS_BATTLE_STAGE]) or (reward.origin != &"battle" and (reward.battle_stage != ClassicRewardState.NO_BATTLE_STAGE or reward.bonus_treasure_classic_id != 0)) or (reward.battle_stage == ClassicRewardState.BONUS_BATTLE_STAGE and reward.bonus_treasure_classic_id != 0):
		return false
	if reward.bonus_treasure_classic_id != 0 and content.treasure_by_classic_id(reward.bonus_treasure_classic_id) == null:
		return false
	for item: ItemInstance in reward.items():
		if content.item_by_id(item.definition_id) == null:
			return false
	var character_ids: Dictionary = {}
	for character_id: Variant in reward.experience_awards():
		character_ids[String(character_id)] = true
	for character_id: String in reward.level_character_ids():
		character_ids[character_id] = true
	for character_id: String in reward.spell_character_ids():
		character_ids[character_id] = true
	if not reward.pending_level_result.is_empty():
		character_ids[String(reward.pending_level_result.get("characterId", ""))] = true
	for character_id: Variant in character_ids:
		if String(character_id).is_empty() or state.party.character_by_id(String(character_id)) == null:
			return false
	if reward.phase == ClassicRewardState.ITEM_PHASE:
		var treasure_body := request.body as InteractionRequest.TreasureRequestBody
		if request.kind != InteractionRequest.TREASURE_DISTRIBUTION or treasure_body == null:
			return false
		var expected_mode := &"completion-confirmation" if reward.completion_pending else &"ordinary"
		if treasure_body.mode != expected_mode:
			return false
		if reward.completion_pending:
			return not treasure_body.has_item and not treasure_body.has_items
		var pending_items := reward.items()
		if not treasure_body.has_items or treasure_body.has_item or treasure_body.items.size() != pending_items.size():
			return false
		for index: int in pending_items.size():
			if treasure_body.items[index].instance_id != pending_items[index].id or treasure_body.items[index].definition_id != pending_items[index].definition_id:
				return false
		return true
	if reward.phase == ClassicRewardState.LEVEL_PHASE:
		var level_body := request.body as InteractionRequest.LevelUpRequestBody
		return not reward.pending_level_result.is_empty() and request.kind == InteractionRequest.LEVEL_UP and level_body != null and level_body.mode == &"result" and level_body.character_id == reward.pending_level_result.get("characterId")
	if reward.phase == ClassicRewardState.SPELL_PHASE:
		var spell_ids := reward.spell_character_ids()
		var level_body := request.body as InteractionRequest.LevelUpRequestBody
		return reward.spell_index < spell_ids.size() and request.kind == InteractionRequest.LEVEL_UP and level_body != null and level_body.mode == &"spell-selection" and level_body.character_id == spell_ids[reward.spell_index]
	return false


static func _valid_age_update_payload(state: GameState, update: InteractionRequest.AgeUpdateBody) -> bool:
	return update != null and not update.character_id.is_empty() and state.party.character_by_id(update.character_id) != null \
		and update.presentation == &"classic-age-update" \
		and update.age_group >= 1 and update.age_group <= 5 \
		and update.transition in [-1, 1] \
		and update.changes.size() == 15


static func _valid_ready_post_move_continuation(content: RealmzContent, state: GameState, continuation: SessionContinuation) -> bool:
	if continuation == null or continuation.kind != &"post-move":
		return false
	var exploration := continuation.exploration()
	if exploration == null or exploration.trigger_index != 0 or not exploration.active_trigger_id.is_empty() or not exploration.active_random_program_id.is_empty() or not exploration.active_random_region_id.is_empty() or not exploration.random_battle_stage.is_empty() or exploration.action_point_destination_depth < 0 or exploration.action_point_destination_depth > 1:
		return false
	var map := content.world.map_by_id(exploration.map_id)
	var cell: MapCell = null if map == null else map.topology.cell_at(exploration.coordinate)
	return cell != null and state.party.map_id == map.id and state.party.coordinate == exploration.coordinate \
		and exploration.trigger_ids == ExplorationTimeWorkflow.selected_placed_trigger_ids(content, cell, state.world) \
		and exploration.random_region_ids == state.world.random_region_ids_at(map, exploration.coordinate) \
		and exploration.random_region_index == exploration.random_region_ids.size() - 1
