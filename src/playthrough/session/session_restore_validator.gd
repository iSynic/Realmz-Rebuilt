## Defines the typed session restore validator contract used by playthrough transactions.

class_name SessionRestoreValidator
extends RefCounted

## Rebuilds and validates a saved playthrough before it can replace the live one.


static func validate(content: RealmzContent, snapshot: SessionSnapshot) -> SessionRestoreResult:
	var header_error := _validate_snapshot_header(content, snapshot)
	if header_error != null:
		return header_error
	var core_result := _restore_core(content, snapshot)
	if not core_result.ok:
		return core_result
	return _restore_continuations(content, snapshot, core_result.candidate)


static func _validate_snapshot_header(content: RealmzContent, snapshot: SessionSnapshot) -> SessionRestoreResult:
	if content == null or content.scenario == null or snapshot == null:
		return SessionRestoreResult.failed(&"invalid_restore", "Validated content and save data are required.")
	if snapshot.campaign_id != content.campaign_id or snapshot.package_hash != content.package_hash:
		return SessionRestoreResult.failed(&"package_mismatch", "The save belongs to a different package build.")
	if snapshot.rules_version != content.rules_version:
		return SessionRestoreResult.failed(&"rules_mismatch", "The save uses a different Realmz rules version.")
	var saved_map := content.world.map_by_id(snapshot.game_state.party.map_id)
	if saved_map == null or saved_map.topology.cell_at(snapshot.game_state.party.coordinate) == null:
		return SessionRestoreResult.failed(&"invalid_saved_location", "The saved party location is unavailable.")
	return null


static func _restore_core(content: RealmzContent, snapshot: SessionSnapshot) -> SessionRestoreResult:
	var replacement_rng := RealmzRng.new()
	if not replacement_rng.restore(snapshot.rng_state):
		return SessionRestoreResult.failed(&"invalid_rng_state", "The saved random state is invalid.")
	var replacement_state := GameState.from_data(snapshot.game_state.to_data())
	var replacement_action_state := ScenarioActionState.from_data(snapshot.scenario_action_state.to_data())
	if replacement_state == null or replacement_action_state == null:
		return SessionRestoreResult.failed(&"invalid_game_state", "The saved game or Scenario Action state is invalid.")
	var replacement_rules := RealmzRules.new()
	var state_error := _validate_restored_state(content, replacement_state, replacement_rules)
	if state_error != null:
		return state_error
	var replacement_vm := ScenarioVm.new()
	replacement_vm.configure(content.scenario)
	if not replacement_vm.restore(snapshot.scenario_vm):
		return SessionRestoreResult.failed(&"invalid_vm_state", "The saved Scenario VM state is invalid.")
	if not SessionScenarioRestoreValidator.vm_reward_continuation_is_valid(content, replacement_state, replacement_vm):
		return SessionRestoreResult.failed(&"invalid_vm_state", "The saved Scenario VM reward continuation is invalid.")
	if not SessionScenarioRestoreValidator.player_map_vm_continuation_is_valid(content, replacement_state, replacement_vm):
		return SessionRestoreResult.failed(&"invalid_vm_state", "The saved Scenario VM player-map continuation is invalid.")
	if not SessionScenarioRestoreValidator.thief_vm_continuation_is_valid(content, replacement_state, replacement_rng.snapshot(), replacement_vm):
		return SessionRestoreResult.failed(&"invalid_vm_state", "The saved Scenario VM Thief Encounter continuation is invalid.")
	if not SessionRestoreStateValidator.combat_vm_request_is_valid(content, replacement_state, replacement_rng, replacement_rules, replacement_action_state, replacement_vm.pending_request()):
		return SessionRestoreResult.failed(&"invalid_vm_state", "The saved combat request does not match authoritative combat state.")
	return SessionRestoreResult.succeeded(SessionRestoreCandidate.new(replacement_state, replacement_rng, replacement_rules, replacement_action_state, replacement_vm, SessionContinuation.new(), SessionContinuation.new(), null, snapshot.view_revision))


static func _validate_restored_state(content: RealmzContent, replacement_state: GameState, replacement_rules: RealmzRules) -> SessionRestoreResult:
	if not content.combat.available_monster_sets().has(replacement_state.monster_set):
		return SessionRestoreResult.failed(&"invalid_game_state", "The saved game selects a monster set unavailable in this package.")
	if replacement_state.party_setup_completed and replacement_state.experience_multiplier < 0.0:
		replacement_state.experience_multiplier = LifecyclePartyWorkflow.party_experience_multiplier(replacement_state.party.characters(), replacement_state.difficulty, content.campaign)
	if replacement_state.combat != null:
		for item: ItemInstance in replacement_state.combat.dropped_items.items():
			if content.items.item_by_id(item.definition_id) == null:
				return SessionRestoreResult.failed(&"invalid_game_state", "The saved fumble queue references unavailable item content.")
		for monster: MonsterState in replacement_state.combat.roster.monsters():
			for item_id: String in monster.loot_item_ids():
				if not item_id.is_empty() and content.items.item_by_id(item_id) == null:
					return SessionRestoreResult.failed(&"invalid_game_state", "The saved monster loot references unavailable item content.")
	SessionRestoreStateValidator.normalize_age_groups(replacement_state, content, replacement_rules)
	if not SessionRestoreStateValidator.party_inventory_is_valid(content, replacement_state, replacement_rules):
		return SessionRestoreResult.failed(&"invalid_game_state", "The saved party inventory or carried load is invalid for this package.")
	if not SessionRestoreStateValidator.combat_staged_item_is_valid(content, replacement_state, replacement_rules):
		return SessionRestoreResult.failed(&"invalid_game_state", "The saved combat item staging state is invalid for this package.")
	if not SessionRestoreStateValidator.party_fast_spells_are_valid(content, replacement_state):
		return SessionRestoreResult.failed(&"invalid_game_state", "The saved Fast Spell bindings reference unavailable package content.")
	if not SessionRestoreStateValidator.party_appearance_is_valid(content, replacement_state):
		return SessionRestoreResult.failed(&"invalid_game_state", "The saved party appearance references unavailable package content.")
	if not SessionRestoreStateValidator.shop_state_is_valid(content, replacement_state):
		return SessionRestoreResult.failed(&"invalid_game_state", "The saved shop state references unavailable package content.")
	if not SessionRestoreStateValidator.location_notes_are_valid(content, replacement_state):
		return SessionRestoreResult.failed(&"invalid_game_state", "The saved location notes reference unavailable maps, cells, or invalid Classic note data.")
	if not SessionRestoreStateValidator.journal_messages_are_valid(content, replacement_state):
		return SessionRestoreResult.failed(&"invalid_game_state", "The saved journal references unavailable or unrepresentable Classic messages.")
	if not SessionRestoreStateValidator.acquired_player_maps_are_valid(content, replacement_state):
		return SessionRestoreResult.failed(&"invalid_game_state", "The saved acquired maps reference unavailable package content.")
	if not SessionRestoreStateValidator.boat_overlays_are_valid(content, replacement_state):
		return SessionRestoreResult.failed(&"invalid_game_state", "The saved boat overlays reference unavailable land cells.")
	if replacement_state.has_saved_party_position():
		var bookmark_map := content.world.map_by_id(replacement_state.saved_party_map_id)
		if bookmark_map == null or bookmark_map.level_type != replacement_state.saved_party_level_type or bookmark_map.topology.cell_at(replacement_state.saved_party_coordinate) == null:
			return SessionRestoreResult.failed(&"invalid_game_state", "The saved party-position bookmark references an unavailable map or cell.")
	if not LifecyclePartyWorkflow.character_draft_is_valid(content, replacement_state, replacement_rules):
		return SessionRestoreResult.failed(&"invalid_character_draft", "The saved character-creation draft is invalid for this campaign.")
	return null


static func _restore_continuations(content: RealmzContent, snapshot: SessionSnapshot, candidate: SessionRestoreCandidate) -> SessionRestoreResult:
	var replacement_continuation := SessionContinuation.new() if snapshot.continuation == null else SessionContinuation.from_data(snapshot.continuation.to_data())
	if replacement_continuation == null:
		return SessionRestoreResult.failed(&"invalid_session_continuation", "The saved session continuation is invalid.")
	var replacement_battle_return := SessionContinuation.new() if snapshot.battle_return_continuation == null else SessionContinuation.from_data(snapshot.battle_return_continuation.to_data())
	if replacement_battle_return == null:
		return SessionRestoreResult.failed(&"invalid_battle_return_continuation", "The saved battle return continuation is invalid.")
	if candidate.state.combat == null and not replacement_battle_return.is_empty():
		return SessionRestoreResult.failed(&"invalid_battle_return_continuation", "A battle return continuation requires an active battle.")
	if candidate.state.combat != null and not replacement_battle_return.is_empty():
		var battle_exploration := replacement_battle_return.exploration()
		if replacement_battle_return.kind != &"post-clock" or battle_exploration == null or battle_exploration.resume_kind != &"move" or not _valid_post_time_continuation(content, candidate.state, replacement_battle_return, null, null):
			return SessionRestoreResult.failed(&"invalid_battle_return_continuation", "The saved battle return references an unavailable exploration continuation.")
	var replacement_session_interaction: InteractionRequest = null
	if snapshot.session_interaction != null:
		replacement_session_interaction = InteractionRequest.from_data(snapshot.session_interaction.to_data())
		if replacement_session_interaction == null:
			return SessionRestoreResult.failed(&"invalid_session_interaction", "The saved session interaction is invalid.")
	if not replacement_continuation.is_empty() and not _valid_session_continuation(content, candidate.state, replacement_continuation, candidate.scenario_vm.pending_request(), replacement_session_interaction):
		return SessionRestoreResult.failed(&"invalid_session_continuation", "The saved session continuation is invalid.")
	if replacement_continuation.is_empty() and replacement_session_interaction != null:
		return SessionRestoreResult.failed(&"invalid_session_interaction", "The saved session interaction has no owning continuation.")
	candidate.continuation = replacement_continuation
	candidate.battle_return_continuation = replacement_battle_return
	candidate.session_interaction = replacement_session_interaction
	return SessionRestoreResult.succeeded(candidate)


static func _valid_session_continuation(content: RealmzContent, state: GameState, continuation: SessionContinuation, vm_interaction: InteractionRequest, session_interaction: InteractionRequest) -> bool:
	if continuation == null or continuation.is_empty():
		return false
	match continuation.kind:
		&"boat-choice":
			return _valid_boat_continuation(content, state, continuation, vm_interaction, session_interaction)
		&"application-hook":
			return _valid_application_continuation(content, state, continuation, vm_interaction, session_interaction)
		&"pooled-wealth-departure":
			return _valid_pooled_wealth_continuation(content, state, continuation, vm_interaction, session_interaction)
		&"service-interaction":
			return _valid_service_continuation(content, state, continuation, vm_interaction, session_interaction)
		&"drop-item-confirmation", &"item-use-target-selection", &"field-spell-target-selection", &"scroll-target-selection", &"scroll-discard-confirmation":
			return _valid_targeting_continuation(content, state, continuation, vm_interaction, session_interaction)
		&"item-xap":
			return _valid_item_xap_continuation(content, state, continuation, vm_interaction, session_interaction)
		&"character-spell-confirmation":
			return _valid_character_spell_continuation(content, state, continuation, vm_interaction, session_interaction)
		&"character-vault-publication":
			return _valid_character_vault_continuation(state, continuation, vm_interaction, session_interaction)
		&"combat-retreat-confirmation":
			return _valid_combat_retreat(continuation, state, vm_interaction, session_interaction)
		&"combat-friendly-collision":
			return _valid_friendly_collision(continuation, state, vm_interaction, session_interaction)
		&"age-updates":
			return _valid_age_continuation(content, state, continuation, vm_interaction, session_interaction)
		&"combat-death-macro":
			return _valid_combat_death_continuation(content, state, continuation, vm_interaction, session_interaction)
		&"combat-ally-selection":
			return _valid_combat_ally_continuation(state, continuation, vm_interaction, session_interaction)
		&"combat-fumble-recovery":
			return _valid_combat_fumble_continuation(content, state, continuation, vm_interaction, session_interaction)
		&"combat-reward":
			return _valid_combat_reward_continuation(content, state, continuation, vm_interaction, session_interaction)
		&"post-clock":
			return _valid_post_time_continuation(content, state, continuation, vm_interaction, session_interaction)
		&"post-move":
			return _valid_post_move_continuation(content, state, continuation, vm_interaction, session_interaction)
	return false


static func _valid_application_continuation(content: RealmzContent, state: GameState, continuation: SessionContinuation, vm_interaction: InteractionRequest, session_interaction: InteractionRequest) -> bool:
	var application := continuation.application_hook()
	if application == null or vm_interaction == null or session_interaction != null or application.program_id.is_empty():
		return false
	if content.scenario.application_hook_program_id(application.hook) != application.program_id or content.scenario.program_by_id(application.program_id) == null:
		return false
	match application.resume_kind:
		&"begin-adventure":
			return application.hook == ScenarioApplicationHooks.START_GAME and application.service_id.is_empty() and state.party_setup_completed and not state.party.characters().is_empty()
		&"service":
			return application.hook in [ScenarioApplicationHooks.SHOP, ScenarioApplicationHooks.TEMPLE] and not application.service_id.is_empty() and ((application.service_id == state.location_services.active_shop_id and content.economy.shop_by_id(application.service_id) != null) or (application.service_id == "realmz.service.temple" and state.location_services.temple_available))
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


static func _valid_pooled_wealth_continuation(content: RealmzContent, state: GameState, continuation: SessionContinuation, vm_interaction: InteractionRequest, session_interaction: InteractionRequest) -> bool:
	var service := continuation.service()
	if service == null or vm_interaction != null or session_interaction == null or state.party == null or state.location_services.bank_available:
		return false
	var departure_probe := content.world.probe_movement(state.party.map_id, state.party.coordinate, service.direction, state.world, state.party_in_boat)
	if not departure_probe.allowed and departure_probe.reason == &"invalid_direction":
		return false
	if service.stage == &"warning":
		return SessionInteractionFactory.has_pooled_wealth(state.party) and session_interaction.to_data() == SessionInteractionFactory.pooled_wealth_departure_warning(session_interaction.request_id).to_data()
	if service.stage == &"distribution":
		var bank_body := session_interaction.body as BankRequestBody
		return session_interaction.kind == InteractionRequest.POOLED_WEALTH_DEPARTURE and bank_body != null and bank_body.mode == &"departure" and state.party.character_by_id(bank_body.selected_character_id) != null and session_interaction.to_data() == SessionInteractionFactory.pooled_wealth_departure_distribution(state, session_interaction.request_id, bank_body.selected_character_id).to_data()
	return false


static func _valid_service_continuation(content: RealmzContent, state: GameState, continuation: SessionContinuation, vm_interaction: InteractionRequest, session_interaction: InteractionRequest) -> bool:
	var service := continuation.service()
	if service == null or vm_interaction != null or session_interaction == null:
		return false
	var runtime := service.runtime_continuation
	if runtime == null:
		return false
	var runtime_body := runtime.body as ScenarioServiceContinuationBody
	var selected_temple_character := "" if runtime_body == null else runtime_body.selected_character_id
	match runtime.kind:
		&"classic-shop":
			return service.service_id == state.location_services.active_shop_id and not service.service_id.is_empty() and content.economy.shop_by_id(service.service_id) != null and session_interaction.kind == InteractionRequest.SHOP
		&"classic-temple":
			var temple_body := session_interaction.body as TempleRequestBody
			return runtime_body != null and service.service_id == "realmz.service.temple" and state.location_services.temple_available and runtime_body.cost_percent == state.location_services.temple_cost_percent and runtime_body.bank_available == state.location_services.bank_available and state.party.character_by_id(selected_temple_character) != null and session_interaction.kind == InteractionRequest.TEMPLE and temple_body != null and temple_body.selected_character_id == selected_temple_character
		&"classic-temple-exit":
			return runtime_body != null and service.service_id == "realmz.service.temple" and state.location_services.temple_available and not state.location_services.bank_available and runtime_body.cost_percent == state.location_services.temple_cost_percent and not runtime_body.bank_available and state.party.character_by_id(selected_temple_character) != null and session_interaction.kind == InteractionRequest.YES_NO
		&"classic-banking":
			return service.service_id == "realmz.service.bank" and state.location_services.bank_available and session_interaction.kind == InteractionRequest.BANK
	return false


static func _valid_character_spell_continuation(content: RealmzContent, state: GameState, continuation: SessionContinuation, vm_interaction: InteractionRequest, session_interaction: InteractionRequest) -> bool:
	var application := continuation.character_spell_confirmation()
	if application == null or vm_interaction != null or session_interaction == null or state.party_setup_completed or state.character_draft == null or state.character_draft.generated_character == null:
		return false
	var character := state.character_draft.generated_character
	if application.character_id != character.id or application.remaining < 1:
		return false
	var rules := RealmzRules.new()
	var spent := 0
	for spell_id: String in character.known_spells():
		spent += rules.characters.spell_selection_cost(content.magic.spell_by_id(spell_id))
	var remaining := maxi(0, rules.characters.spell_selection_total(character, content.characters.caste_by_id(character.caste_id)) - spent)
	return remaining == application.remaining and session_interaction.to_data() == SessionInteractionFactory.character_spell_confirmation(session_interaction.request_id, remaining).to_data()


static func _valid_character_vault_continuation(state: GameState, continuation: SessionContinuation, vm_interaction: InteractionRequest, session_interaction: InteractionRequest) -> bool:
	var application := continuation.character_vault_publication()
	if application == null or vm_interaction != null or session_interaction == null or state.party_setup_completed:
		return false
	var character := state.party.character_by_id(application.character_id)
	return character != null and session_interaction.to_data() == SessionInteractionFactory.character_vault_confirmation(session_interaction.request_id, character.name).to_data()


static func _valid_age_continuation(content: RealmzContent, state: GameState, continuation: SessionContinuation, vm_interaction: InteractionRequest, session_interaction: InteractionRequest) -> bool:
	var age := continuation.age()
	if age == null or vm_interaction != null or session_interaction == null or session_interaction.kind != InteractionRequest.AGE_UPDATE or age.updates.is_empty() or age.index < 1 or age.index > age.updates.size():
		return false
	for update: AgeUpdateRequestBody in age.updates:
		if not SessionScenarioRestoreValidator.age_update_payload_is_valid(state, update):
			return false
	var current_update: AgeUpdateRequestBody = age.updates[age.index - 1]
	var expected_age_request := InteractionRequest.age_update_body("validation.age-update", current_update)
	var actual_age_body := session_interaction.body as AgeUpdateRequestBody
	var expected_age_body: AgeUpdateRequestBody = null if expected_age_request == null else expected_age_request.body as AgeUpdateRequestBody
	if actual_age_body == null or not actual_age_body.same_values(expected_age_body):
		return false
	if age.resume_kind == &"completed":
		return age.resume_continuation == null
	if age.resume_kind == &"combat-monster-turns":
		return age.resume_continuation == null and state.combat != null and not state.combat.completed and state.combat.pending_monster_attack != null
	if age.resume_kind == &"post-clock":
		return _valid_post_time_continuation(content, state, age.resume_continuation, vm_interaction, null)
	return age.resume_kind == &"post-move" and SessionScenarioRestoreValidator.ready_post_move_continuation_is_valid(content, state, age.resume_continuation)


static func _valid_combat_death_continuation(content: RealmzContent, state: GameState, continuation: SessionContinuation, vm_interaction: InteractionRequest, session_interaction: InteractionRequest) -> bool:
	var combat := continuation.combat()
	if combat == null or session_interaction != null or vm_interaction == null or state.combat == null or state.combat.battle_id != combat.battle_id:
		return false
	var death_monster := state.combat.roster.monster_by_id(combat.combatant_id)
	if death_monster == null or content.scenario.program_by_id(combat.program_id) == null:
		return false
	var queued_id := state.combat.spell_runtime.pending_death_macro_id()
	if not queued_id.is_empty():
		var definition := content.combat.monster_by_id(death_monster.definition_id)
		return queued_id == combat.combatant_id and not combat.reset_traitor_on_complete and definition != null and combat.program_id == "xap:%d" % definition.death_macro
	return combat.reset_traitor_on_complete


static func _valid_combat_ally_continuation(state: GameState, continuation: SessionContinuation, vm_interaction: InteractionRequest, session_interaction: InteractionRequest) -> bool:
	var combat := continuation.combat()
	return combat != null and vm_interaction == null and session_interaction != null and session_interaction.kind == &"ally_selection" and state.combat != null and state.combat.completed and state.combat.battle_id == combat.battle_id


static func _valid_combat_fumble_continuation(content: RealmzContent, state: GameState, continuation: SessionContinuation, vm_interaction: InteractionRequest, session_interaction: InteractionRequest) -> bool:
	var combat := continuation.combat()
	if combat == null or vm_interaction != null or session_interaction == null or session_interaction.kind != InteractionRequest.TREASURE_DISTRIBUTION or state.combat == null or not state.combat.completed or state.combat.battle_id != combat.battle_id or state.combat.dropped_items.items().is_empty():
		return false
	var expected_request := InteractionRequest.from_payload("validation.fumble-recovery", InteractionRequest.TREASURE_DISTRIBUTION, RealmzRules.new().combat_flow.rounds.fumble_recovery_payload(state, content))
	var actual_body := session_interaction.body as TreasureRequestBody
	var expected_body: TreasureRequestBody = null if expected_request == null else expected_request.body as TreasureRequestBody
	return actual_body != null and actual_body.same_fumble_values(expected_body)


static func _valid_combat_reward_continuation(content: RealmzContent, state: GameState, continuation: SessionContinuation, vm_interaction: InteractionRequest, session_interaction: InteractionRequest) -> bool:
	var reward_body := continuation.reward()
	if reward_body == null or vm_interaction != null:
		return false
	var runtime := reward_body.runtime_continuation
	var runtime_body := runtime.body as ScenarioRewardContinuationBody if runtime != null and runtime.kind == ScenarioRuntimeContinuation.CLASSIC_REWARD else null
	var reward := runtime_body.state if runtime_body != null else null
	return reward != null and reward.origin == &"battle" and reward.source_id == reward_body.battle_id and SessionScenarioRestoreValidator.reward_continuation_is_valid(content, state, reward, session_interaction)


static func _valid_friendly_collision(continuation: SessionContinuation, state: GameState, vm_interaction: InteractionRequest, session_interaction: InteractionRequest) -> bool:
	var combat := continuation.combat()
	if combat == null or combat.mode != &"friendly" or vm_interaction != null or session_interaction == null or session_interaction.to_data() != SessionInteractionFactory.friendly_collision(session_interaction.request_id).to_data():
		return false
	if state.combat == null or state.combat.completed or state.combat.battle_id != combat.battle_id or state.combat.turns.active_actor_id() != combat.actor_id:
		return false
	return not RealmzRules.new().combat_flow.reactions.friendly_collision_target_id(state, combat.actor_id, combat.destination).is_empty()


static func _valid_combat_retreat(continuation: SessionContinuation, state: GameState, vm_interaction: InteractionRequest, session_interaction: InteractionRequest) -> bool:
	var combat := continuation.combat()
	if combat == null or combat.mode not in [&"explicit", &"edge"] or vm_interaction != null or session_interaction == null or session_interaction.to_data() != SessionInteractionFactory.retreat_confirmation(session_interaction.request_id).to_data():
		return false
	if state.combat == null or state.combat.completed or state.combat.battle_id != combat.battle_id or state.combat.turns.active_actor_id() != combat.actor_id:
		return false
	var rules := RealmzRules.new()
	var probe: Variant = rules.combat_flow.reactions.probe_character_retreat(state.combat, state.party.characters(), combat.actor_id) if combat.mode == &"explicit" else rules.combat_flow.reactions.probe_edge_retreat(state.combat, combat.actor_id, combat.destination)
	return probe.allowed and not probe.forced


static func _valid_item_xap_continuation(content: RealmzContent, state: GameState, continuation: SessionContinuation, vm_interaction: InteractionRequest, session_interaction: InteractionRequest) -> bool:
	var item_body := continuation.item_xap_body()
	if item_body == null or vm_interaction == null or session_interaction != null or state.party.character_by_id(item_body.character_id) == null:
		return false
	var item := content.items.item_by_id(item_body.item_id)
	if item == null or item_body.program_id != "xap:%d" % item.special_5 or content.scenario.program_by_id(item_body.program_id) == null or absi(item.item_type) != 23 and item.special_1 != -23:
		return false
	return item_body.source_battle_id.is_empty() or state.combat != null and state.combat.battle_id == item_body.source_battle_id


static func _valid_boat_continuation(content: RealmzContent, state: GameState, continuation: SessionContinuation, vm_interaction: InteractionRequest, session_interaction: InteractionRequest) -> bool:
	var boat := continuation.boat()
	var prompt: YesNoRequestBody = null
	if session_interaction != null:
		prompt = session_interaction.body as YesNoRequestBody
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
		return _valid_scroll_discard_confirmation(content, character, targeting, session_interaction)
	if continuation.kind == &"drop-item-confirmation":
		return _valid_drop_item_confirmation(content, character, targeting, session_interaction)
	if session_interaction.kind != InteractionRequest.CHARACTER_SELECTION or state.combat != null or character == null:
		return false
	var spell := content.magic.spell_by_id(targeting.spell_id)
	if spell == null or targeting.power < 1 or targeting.power > 7:
		return false
	if continuation.kind == &"item-use-target-selection":
		return _valid_item_target_selection(content, state, character, targeting, spell, session_interaction)
	return _valid_field_magic_target_selection(content, state, character, targeting, spell, continuation.kind, session_interaction)


static func _valid_scroll_discard_confirmation(content: RealmzContent, character: CharacterState, targeting: TargetingContinuationBody, session_interaction: InteractionRequest) -> bool:
	var scroll := character.scroll_at(targeting.scroll_slot) if character != null else null
	var spell := content.magic.spell_by_id(targeting.spell_id)
	if scroll == null or spell == null or scroll.spell_id != spell.id or scroll.power != targeting.power or spell.in_camp or character.current_health < 1 or character.conditions.is_active(ConditionRules.ANIMATED):
		return false
	return _has_equipped_scroll_case(content, character) and session_interaction.to_data() == FieldMagicWorkflow.scroll_discard_request(session_interaction.request_id, spell.name).to_data()


static func _valid_drop_item_confirmation(content: RealmzContent, character: CharacterState, targeting: TargetingContinuationBody, session_interaction: InteractionRequest) -> bool:
	var instance := _item_instance_for_state(character, targeting.instance_id)
	var definition: ItemDefinition = null if instance == null else content.items.item_by_id(instance.definition_id)
	if character == null or instance == null or definition == null or not RealmzRules.new().inventory.classic_drop_probe(character, instance).allowed:
		return false
	var display_name := definition.name if instance.identified else definition.unidentified_name
	return session_interaction.to_data() == SessionInteractionFactory.drop_item_confirmation(session_interaction.request_id, display_name).to_data()


static func _valid_item_target_selection(content: RealmzContent, state: GameState, character: CharacterState, targeting: TargetingContinuationBody, spell: SpellDefinition, session_interaction: InteractionRequest) -> bool:
	var instance := _item_instance_for_state(character, targeting.instance_id)
	var definition: ItemDefinition = null if instance == null else content.items.item_by_id(instance.definition_id)
	if instance == null or definition == null or definition.special_2 != spell.classic_id or instance.charges != targeting.starting_charges:
		return false
	var authored_power := absi(definition.special_1)
	var expected_count := state.party.characters().size() if spell.target_type > 2 else mini(targeting.power, state.party.characters().size()) if spell.target_type == 0 else 1
	var probe := RealmzRules.new().inventory.classic_spell_item_probe(character, instance, definition, spell, content.characters.race_by_id(character.race_id), content.characters.caste_by_id(character.caste_id), false)
	var supported := spell.special == 0 and absi(spell.damage_type) >= 1 and absi(spell.damage_type) <= 6 and absi(spell.spell_class) != 9 or absi(spell.special) == 57
	return (authored_power == 8 or targeting.power == authored_power) and targeting.target_count == expected_count and spell.target_type not in [5, 7] and spell.target_type >= 0 and spell.target_type <= 12 and probe.allowed and supported and session_interaction.to_data() == FieldMagicTargetRequestBuilder.item_target_request(session_interaction.request_id, character, instance.id, definition, spell, targeting.power, expected_count, state.party.characters()).to_data()


static func _valid_field_magic_target_selection(content: RealmzContent, state: GameState, character: CharacterState, targeting: TargetingContinuationBody, spell: SpellDefinition, continuation_kind: StringName, session_interaction: InteractionRequest) -> bool:
	var learned_spell := continuation_kind == &"field-spell-target-selection"
	if learned_spell:
		if not character.known_spells().has(spell.id) or character.spell_points != targeting.starting_spell_points or state.character_spellcasting_blocked or character.current_health < 1 or character.spell_points < absi(spell.cost * targeting.power) or not spell.in_camp or spell.cost < 0 and targeting.power != 1:
			return false
		for condition: int in [ConditionRules.CONFUSED, ConditionRules.SILENCED, ConditionRules.HELPLESS, ConditionRules.STUPID, ConditionRules.ANIMATED]:
			if character.conditions.is_active(condition):
				return false
	else:
		var scroll := character.scroll_at(targeting.scroll_slot)
		if scroll == null or scroll.spell_id != spell.id or scroll.power != targeting.power or character.current_health < 1 or character.conditions.is_active(ConditionRules.ANIMATED) or not spell.in_camp:
			return false
		if not _has_equipped_scroll_case(content, character):
			return false
	var supported := ClassicSpellDispositionRules.field_character_disposition(spell) == ClassicSpellDispositionRules.DISPOSITION_EXECUTABLE
	var expected_count := mini(targeting.power, state.party.characters().size()) if spell.target_type == 0 else 1
	if targeting.target_count != expected_count or spell.target_type < 0 or spell.target_type > 2 or not supported:
		return false
	return session_interaction.to_data() == (FieldMagicTargetRequestBuilder.spell_target_request(session_interaction.request_id, character, spell, targeting.power, expected_count, state.party.characters()).to_data() if learned_spell else FieldMagicTargetRequestBuilder.scroll_target_request(session_interaction.request_id, character, targeting.scroll_slot, spell, targeting.power, expected_count, state.party.characters()).to_data())


static func _has_equipped_scroll_case(content: RealmzContent, character: CharacterState) -> bool:
	for carried: ItemInstance in character.inventory():
		var definition := content.items.item_by_id(carried.definition_id)
		if carried.equipped and definition != null and absi(definition.item_type) == 13:
			return true
	return false


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
	if cell == null or state.party.map_id != map.id or state.party.coordinate != exploration.coordinate or exploration.trigger_ids != ExplorationContinuationWorkflow.selected_placed_trigger_ids(content, cell, state.world) or exploration.random_region_ids != state.world.triggers.random_region_ids_at(map, exploration.coordinate):
		return false
	if exploration.random_region_index < -1 or exploration.random_region_index >= exploration.random_region_ids.size():
		return false
	if session_interaction != null:
		return vm_interaction == null and exploration.active_trigger_id.is_empty() and exploration.active_random_program_id.is_empty() and exploration.random_battle_stage == &"surprise-choice" and session_interaction.kind == InteractionRequest.YES_NO and exploration.random_region_index >= 0 and exploration.random_region_ids[exploration.random_region_index] == exploration.active_random_region_id and map.random_region_by_id(exploration.active_random_region_id) != null
	if vm_interaction == null or not exploration.random_battle_stage.is_empty() or not exploration.active_random_region_id.is_empty():
		return false
	if not exploration.active_random_program_id.is_empty():
		return exploration.active_trigger_id.is_empty() and content.scenario.program_by_id(exploration.active_random_program_id) != null
	return exploration.trigger_index >= 0 and exploration.trigger_index < exploration.trigger_ids.size() and not exploration.active_trigger_id.is_empty() and exploration.trigger_ids[exploration.trigger_index] == exploration.active_trigger_id and content.scenario_records.trigger_by_id(exploration.active_trigger_id) != null


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
	if exploration == null or exploration.timed_day < 0 or exploration.timed_encounter_index < 0 or exploration.timed_encounter_index > content.scenario_records.timed_encounters().size() or exploration.resume_kind not in [&"completed", &"move", &"post-move", &"attempt-search-completed", &"attempt-search-post-move", &"area-search-second", &"camp-entry-second", &"rest-second", &"camp-departure-second", &"heal"]:
		return false
	var map := content.world.map_by_id(exploration.map_id)
	var cell: MapCell = null if map == null else map.topology.cell_at(exploration.coordinate)
	if cell == null or state.party.map_id != map.id or state.party.coordinate != exploration.coordinate or exploration.random_region_ids != state.world.triggers.random_region_ids_at(map, exploration.coordinate) or exploration.random_region_index < -1 or exploration.random_region_index >= exploration.random_region_ids.size() or exploration.direction.x < -1 or exploration.direction.x > 1 or exploration.direction.y < -1 or exploration.direction.y > 1:
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
