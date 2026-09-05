## Builds detached service, inventory, spell, and command availability for a game view.
class_name SessionActionViewProjector
extends RefCounted

const ProjectionPolicy := preload("res://src/playthrough/session/session_view_projection_policy.gd")

static func populate_services(context: SessionWorkflowContext, result: GameView) -> void:
	if not context.state.location_services.active_shop_id.is_empty():
		var shop := context.content.economy.shop_by_id(context.state.location_services.active_shop_id)
		if shop != null:
			var shop_view := ServiceView.new()
			shop_view.service_id = shop.id
			shop_view.service_kind = &"shop"
			shop_view.title = "Shop"
			shop_view.actions = [&"enter"]
			result.services.append(shop_view)
	if context.state.location_services.temple_available:
		var temple_view := ServiceView.new()
		temple_view.service_id = "realmz.service.temple"
		temple_view.service_kind = &"temple"
		temple_view.title = "Temple"
		temple_view.actions = [&"enter"]
		result.services.append(temple_view)
	if context.state.location_services.bank_available:
		var bank_view := ServiceView.new()
		bank_view.service_id = "realmz.service.bank"
		bank_view.service_kind = &"bank"
		bank_view.title = "Bank"
		bank_view.actions = [&"enter"]
		result.services.append(bank_view)


static func populate_money_screen(context: SessionWorkflowContext, result: GameView) -> void:
	var state := context.state
	if not state.party_setup_completed:
		return
	var workspace := MoneyWorkspaceView.new()
	workspace.pooled_gold = state.party.pooled_wealth.gold
	workspace.pooled_gems = state.party.pooled_wealth.gems
	workspace.pooled_jewelry = state.party.pooled_wealth.jewelry
	workspace.banked_gold = state.party.banked_wealth.gold
	workspace.banked_gems = state.party.banked_wealth.gems
	workspace.banked_jewelry = state.party.banked_wealth.jewelry
	var pool_probe := context.rules.economy.pool_probe(state.party)
	workspace.pool = ActionAvailabilityView.new(&"money_action", pool_probe.allowed, pool_probe.reason)
	var share_probe := context.rules.economy.share_probe(state.party)
	workspace.share = ActionAvailabilityView.new(&"money_action", share_probe.allowed, share_probe.reason)
	for character: CharacterState in state.party.characters():
		var character_view := MoneyCharacterView.new(character)
		for denomination: StringName in [&"gold", &"gems", &"jewelry"]:
			var kind := ProjectionPolicy.money_kind(denomination)
			var amount := EconomyRules.classic_transfer_increment(kind as WealthState.Kind)
			var to_pool := context.rules.economy.transfer_probe(state.party, character, kind as WealthState.Kind, amount, false)
			var to_character := context.rules.economy.transfer_probe(state.party, character, kind as WealthState.Kind, amount, true)
			character_view.transfers.append(MoneyTransferView.new(denomination, amount, ActionAvailabilityView.new(&"money_action", to_pool.allowed, to_pool.reason), ActionAvailabilityView.new(&"money_action", to_character.allowed, to_character.reason)))
		workspace.characters.append(character_view)
	result.money_workspace = workspace


static func populate_action_availability(context: SessionWorkflowContext, result: GameView) -> void:
	var state := context.state
	var content := context.content
	var blocked_by_interaction := result.pending_interaction != null
	var party_setup := result.party_setup_available
	var setup_member_count := state.party.characters().size()
	var setup_member_limit := clampi(content.campaign.restrictions.maximum_party_size, 1, 6)
	var draft_active := state.character_draft != null and state.character_draft.generated_character != null
	var battle_active := result.combat_view != null and result.combat_view.outcome == &"active"
	var ordinary_reason := "Resolve the current interaction first." if blocked_by_interaction else "Complete party setup first." if party_setup else ""
	_populate_exploration_actions(context, result, blocked_by_interaction, battle_active, ordinary_reason)
	_populate_magic_actions(context, result, blocked_by_interaction, battle_active, ordinary_reason)
	_populate_setup_actions(context, result, blocked_by_interaction, party_setup, setup_member_count, setup_member_limit, draft_active, battle_active)
	_populate_inventory_and_service_actions(result, ordinary_reason, battle_active)
	_populate_combat_movement_action(result, battle_active)


static func _populate_exploration_actions(context: SessionWorkflowContext, result: GameView, blocked_by_interaction: bool, battle_active: bool, ordinary_reason: String) -> void:
	var state := context.state
	var field_item_available := false
	for member: CharacterView in result.party_members:
		if member.items.any(func(item: ItemView) -> bool: return item.actions != null and item.actions.use.enabled):
			field_item_available = true
			break
	var combat_item_available := battle_active and not context.rules.combat_flow.magic.character_item_spell_options(state, context.content, result.combat_view.active_actor_id).is_empty()
	result.set_action_availability(&"move", ordinary_reason.is_empty() and not battle_active, ordinary_reason if not ordinary_reason.is_empty() else "Movement is unavailable during battle." if battle_active else "")
	var search_reason := ordinary_reason if not ordinary_reason.is_empty() else "Search is unavailable during battle." if battle_active else "Search is replaced by scroll scribing while camped." if state.party_camping else ""
	result.set_action_availability(&"search", search_reason.is_empty(), search_reason)
	result.set_action_availability(&"toggle_search", search_reason.is_empty(), search_reason)
	var area_search_reason := search_reason if not search_reason.is_empty() else "The party is too fatigued to continue Area Search." if state.party.fatigue > 134 else ""
	result.set_action_availability(&"area_search", area_search_reason.is_empty(), area_search_reason)
	var torch_probe := FieldItemWorkflow.classic_torch_probe(context)
	result.set_action_availability(&"use_torch", ordinary_reason.is_empty() and not battle_active and torch_probe.allowed, ordinary_reason if not ordinary_reason.is_empty() else "Torches are unavailable during battle." if battle_active else torch_probe.reason)
	var encounter_reason := ordinary_reason if not ordinary_reason.is_empty() else "Encounters are unavailable during battle." if battle_active else "Break camp before using Encounter." if state.party_camping else ""
	result.set_action_availability(&"contextual_encounter", encounter_reason.is_empty(), encounter_reason)
	result.set_action_availability(&"camp", ordinary_reason.is_empty() and not battle_active and (state.camping_allowed or state.party_camping), ordinary_reason if not ordinary_reason.is_empty() else "Camping is unavailable during battle." if battle_active else "Camping is unavailable here." if not state.camping_allowed and not state.party_camping else "")
	result.set_action_availability(&"rest", ordinary_reason.is_empty() and not battle_active and state.party_camping, ordinary_reason if not ordinary_reason.is_empty() else "Rest is unavailable during battle." if battle_active else "Make camp before resting.")
	var heal_reason := ordinary_reason if not ordinary_reason.is_empty() else "Heal is unavailable during battle." if battle_active else "The party is too fatigued to continue Heal." if state.party.fatigue > 134 else ""
	result.set_action_availability(&"heal", heal_reason.is_empty(), heal_reason)
	var unavailable_item_reason := ""
	if not blocked_by_interaction and battle_active:
		unavailable_item_reason = context.rules.combat_flow.magic.character_item_spell_unavailable_reason(state, context.content, result.combat_view.active_actor_id)
	result.set_action_availability(&"use_item", not blocked_by_interaction and (combat_item_available or not battle_active and field_item_available), "Resolve the current interaction first." if blocked_by_interaction else unavailable_item_reason if battle_active else "No carried item has a supported Classic field use.")
	result.set_action_availability(&"use_item_on_target", not blocked_by_interaction and combat_item_available, "Resolve the current interaction first." if blocked_by_interaction else unavailable_item_reason if battle_active else "Targeted combat item use is available only during battle.")


static func _populate_magic_actions(context: SessionWorkflowContext, result: GameView, blocked_by_interaction: bool, battle_active: bool, ordinary_reason: String) -> void:
	var field_spell_available := false
	var field_spell_reason := "No known spell has a supported Classic field use."
	for member: CharacterView in result.party_members:
		for spell: SpellView in member.spells:
			if spell.field_cast.enabled:
				field_spell_available = true
				break
			if not spell.field_cast.reason.is_empty():
				field_spell_reason = spell.field_cast.reason
		if field_spell_available:
			break
	var combat_spell_available := battle_active and not context.rules.combat_flow.magic.selection().character_spell_options(context.state, context.content, result.combat_view.active_actor_id).is_empty()
	var cast_enabled := not blocked_by_interaction and (combat_spell_available or not battle_active and field_spell_available)
	var cast_reason := ordinary_reason
	if cast_reason.is_empty() and battle_active:
		cast_reason = context.rules.combat_flow.magic.selection().character_spell_unavailable_reason(context.state, context.content, result.combat_view.active_actor_id)
		if cast_reason.is_empty():
			cast_reason = "No legal Classic combat spell is available."
	elif cast_reason.is_empty():
		cast_reason = field_spell_reason
	result.set_action_availability(&"cast_spell", cast_enabled, "" if cast_enabled else cast_reason)
	result.set_action_availability(&"set_fast_spell", ordinary_reason.is_empty() and not battle_active, ordinary_reason if not ordinary_reason.is_empty() else "Fast Spell bindings cannot be changed during battle." if battle_active else "")
	result.set_action_availability(&"choose_combat_action", battle_active and not blocked_by_interaction, "No battle action is currently available." if not battle_active else "Resolve the current interaction first." if blocked_by_interaction else "")


static func _populate_setup_actions(context: SessionWorkflowContext, result: GameView, blocked_by_interaction: bool, party_setup: bool, setup_member_count: int, setup_member_limit: int, draft_active: bool, battle_active: bool) -> void:
	result.set_action_availability(&"create_party", party_setup and not blocked_by_interaction, "Resolve the current interaction first." if blocked_by_interaction else "Party creation is available only before beginning a campaign." if not party_setup else "")
	result.set_action_availability(&"begin_adventure", party_setup and not blocked_by_interaction and setup_member_count > 0 and not draft_active, "Resolve the current interaction first." if blocked_by_interaction else "The adventure has already begun." if not party_setup else "Finish or cancel the character currently being created." if draft_active else "Add or import at least one character first.")
	result.set_action_availability(&"import_vault_character", party_setup and not blocked_by_interaction and setup_member_count < setup_member_limit and not draft_active, "Resolve the current interaction first." if blocked_by_interaction else "Vault imports are available only during party setup." if not party_setup else "Finish or cancel the character currently being created." if draft_active else "The party is full.")
	result.set_action_availability(&"generate_character_draft", party_setup and not blocked_by_interaction and setup_member_count < setup_member_limit, "Resolve the current interaction first." if blocked_by_interaction else "Character creation is available only during party setup." if not party_setup else "The party is full.")
	result.set_action_availability(&"cancel_character_draft", party_setup and not blocked_by_interaction and draft_active, "There is no generated character to cancel." if not draft_active else "Resolve the current interaction first." if blocked_by_interaction else "Character creation is available only during party setup.")
	result.set_action_availability(&"set_character_draft_spells", party_setup and not blocked_by_interaction and draft_active, "Generate the character before choosing spells." if not draft_active else "Resolve the current interaction first." if blocked_by_interaction else "Character creation is available only during party setup.")
	result.set_action_availability(&"finalize_character", party_setup and not blocked_by_interaction and setup_member_count < setup_member_limit and draft_active, "Resolve the current interaction first." if blocked_by_interaction else "Character creation is available only during party setup." if not party_setup else "Generate and review the character first." if not draft_active else "The party is full.")
	result.set_action_availability(&"remove_party_member", party_setup and not blocked_by_interaction and setup_member_count > 0, "Resolve the current interaction first." if blocked_by_interaction else "Party members can be removed only during party setup." if not party_setup else "The party is empty.")
	result.set_action_availability(&"reorder_party", not party_setup and not blocked_by_interaction and not battle_active and setup_member_count > 1, "Resolve the current interaction first." if blocked_by_interaction else "Begin the adventure before changing party order." if party_setup else "Party order is unavailable during battle." if battle_active else "At least two party members are required.")
	var appearance_available := not party_setup and not blocked_by_interaction and not battle_active and setup_member_count > 0 and context.content.characters.has_complete_appearance_catalog()
	var appearance_reason := "Resolve the current interaction first." if blocked_by_interaction else "Begin the adventure before changing appearance." if party_setup else "Appearance changes are unavailable during battle." if battle_active else "No party member is available." if setup_member_count == 0 else "This package does not contain the complete Classic portrait and combat-icon catalogs." if not context.content.characters.has_complete_appearance_catalog() else ""
	result.set_action_availability(&"change_character_appearance", appearance_available, appearance_reason)


static func _populate_inventory_and_service_actions(result: GameView, ordinary_reason: String, battle_active: bool) -> void:
	for action_id: StringName in [&"equip_item", &"unequip_item", &"drop_item", &"trade_item"]:
		result.set_action_availability(action_id, ordinary_reason.is_empty() and not battle_active, ordinary_reason if not ordinary_reason.is_empty() else "Inventory changes are unavailable during battle." if battle_active else "")
	result.set_action_availability(&"split_item", ordinary_reason.is_empty() and not battle_active, ordinary_reason if not ordinary_reason.is_empty() else "Inventory changes are unavailable during battle." if battle_active else "")
	result.set_action_availability(&"join_item", ordinary_reason.is_empty() and not battle_active, ordinary_reason if not ordinary_reason.is_empty() else "Inventory changes are unavailable during battle." if battle_active else "")
	result.set_action_availability(&"service_action", ordinary_reason.is_empty() and not battle_active and not result.services.is_empty(), ordinary_reason if not ordinary_reason.is_empty() else "Services are unavailable during battle." if battle_active else "No shop, temple, or bank is available at this location.")
	result.set_action_availability(&"money_action", ordinary_reason.is_empty() and not battle_active and result.money_workspace != null, ordinary_reason if not ordinary_reason.is_empty() else "Money management is unavailable during battle." if battle_active else "No party money workspace is available.")
	result.set_action_availability(&"set_location_note", ordinary_reason.is_empty() and not battle_active, ordinary_reason if not ordinary_reason.is_empty() else "Location notes are unavailable during battle." if battle_active else "")


static func _populate_combat_movement_action(result: GameView, battle_active: bool) -> void:
	var combat_move_enabled := false
	var combat_move_reason := "No active battle."
	if battle_active:
		var combat_request_open := result.pending_interaction == null or result.pending_interaction.kind == InteractionRequest.COMBAT
		if not combat_request_open:
			combat_move_reason = "Resolve the current interaction first."
		elif result.combat_view.movement_options.is_empty():
			combat_move_reason = "The active combatant is not available for player-controlled movement."
		else:
			for option: CombatMoveOptionView in result.combat_view.movement_options:
				if option.enabled:
					combat_move_enabled = true
					combat_move_reason = ""
					break
			if not combat_move_enabled:
				combat_move_reason = "The active character has no legal tactical step."
	result.set_action_availability(&"combat_move", combat_move_enabled, combat_move_reason)


static func populate_spell_actions(context: SessionWorkflowContext, result: GameView, character_filter: Dictionary = {}) -> void:
	var blocked_reason := "Resolve the current interaction first." if result.pending_interaction != null else "Complete party setup first." if result.party_setup_available else ""
	var battle_active := result.combat_view != null and result.combat_view.outcome == &"active"
	for member_view: CharacterView in result.party_members:
		if not character_filter.is_empty() and not character_filter.has(member_view.id):
			continue
		var character := context.state.party.character_by_id(member_view.id)
		_populate_learned_spell_actions(context, member_view, character, blocked_reason, battle_active)
		_populate_scroll_actions(context, member_view, character, blocked_reason, battle_active)
		_populate_fast_spell_actions(context, member_view, character, battle_active)


static func _populate_learned_spell_actions(context: SessionWorkflowContext, member_view: CharacterView, character: CharacterState, blocked_reason: String, battle_active: bool) -> void:
	for spell_view: SpellView in member_view.spells:
		var spell := context.content.magic.spell_by_id(spell_view.id)
		spell_view.power_levels.clear()
		spell_view.structural_power_levels.clear()
		spell_view.scroll_power_levels.clear()
		spell_view.structural_scroll_power_levels.clear()
		if not blocked_reason.is_empty():
			spell_view.combat_cast = ActionAvailabilityView.new(&"cast_spell", false, blocked_reason)
			spell_view.field_cast = ActionAvailabilityView.new(&"cast_spell", false, blocked_reason)
			spell_view.make_scroll = ActionAvailabilityView.new(&"cast_spell", false, blocked_reason)
			continue
		if battle_active:
			_populate_combat_learned_spell_action(context, spell_view, character, spell)
			continue
		_populate_field_learned_spell_action(context, spell_view, character, spell)


static func _populate_combat_learned_spell_action(context: SessionWorkflowContext, spell_view: SpellView, character: CharacterState, spell: SpellDefinition) -> void:
	var combat_reason := ""
	var combat_enabled := false
	for power: int in range(1, 8):
		var combat_probe := context.rules.combat_flow.magic.selection().probe_character_spell_choice(context.state, context.content, character.id, spell_view.id, power)
		if combat_probe.allowed:
			combat_enabled = true
		elif combat_reason.is_empty():
			combat_reason = combat_probe.reason_text
		if spell != null and spell.cost < 0:
			break
	spell_view.combat_cast = ActionAvailabilityView.new(&"cast_spell", combat_enabled, combat_reason)
	spell_view.field_cast = ActionAvailabilityView.new(&"cast_spell", false, "Use the tactical spell action during battle.")
	spell_view.make_scroll = ActionAvailabilityView.new(&"cast_spell", false, "Scroll scribing is unavailable during battle.")


static func _populate_field_learned_spell_action(context: SessionWorkflowContext, spell_view: SpellView, character: CharacterState, spell: SpellDefinition) -> void:
	spell_view.combat_cast = ActionAvailabilityView.new(&"cast_spell", false, "Combat casting requires an active battle.")
	var first_reason := ""
	for power: int in range(1, 8):
		var probe := _field_spell_probe(context, character, spell, power, false)
		if probe.allowed:
			spell_view.structural_power_levels.append(power)
			if character.spell_points >= absi(spell.cost * power): spell_view.power_levels.append(power)
			elif first_reason.is_empty(): first_reason = "The character does not have enough spell points."
		elif first_reason.is_empty():
			first_reason = probe.reason
		if spell != null and spell.cost < 0:
			break
	spell_view.field_cast = ActionAvailabilityView.new(&"cast_spell", not spell_view.power_levels.is_empty(), first_reason)
	var make_reason := ""
	for power: int in range(1, 8):
		var make_probe := _make_scroll_probe(context, character, spell, power, false)
		if make_probe.allowed:
			spell_view.structural_scroll_power_levels.append(power)
			if character.spell_points >= absi(spell.cost * power * 2): spell_view.scroll_power_levels.append(power)
			elif make_reason.is_empty(): make_reason = "Scribing requires twice the spell's normal spell-point cost."
		elif make_reason.is_empty():
			make_reason = make_probe.reason
		if spell != null and spell.cost < 0:
			break
	spell_view.make_scroll = ActionAvailabilityView.new(&"cast_spell", not spell_view.scroll_power_levels.is_empty(), make_reason)


static func _populate_scroll_actions(context: SessionWorkflowContext, member_view: CharacterView, character: CharacterState, blocked_reason: String, battle_active: bool) -> void:
	for scroll_view: SpellScrollView in member_view.scrolls:
		if not blocked_reason.is_empty():
			scroll_view.use = ActionAvailabilityView.new(&"cast_spell", false, blocked_reason)
			scroll_view.discard = ActionAvailabilityView.new(&"cast_spell", false, blocked_reason)
			continue
		var scroll := character.scroll_at(scroll_view.slot_index)
		var spell := context.content.magic.spell_by_id(scroll.spell_id) if scroll != null and not scroll.is_empty() else null
		if battle_active:
			var combat_target_id := character.id if spell != null and spell.target_type == 5 else ""
			var combat_probe := context.rules.combat_flow.magic.probe_character_scroll_cast(context.state, context.content, character.id, scroll_view.slot_index, combat_target_id)
			scroll_view.use = ActionAvailabilityView.new(&"cast_spell", combat_probe.allowed, combat_probe.reason_text)
			continue
		var use_probe := _scroll_use_probe(context, character, scroll_view.slot_index, spell)
		scroll_view.use = ActionAvailabilityView.new(&"cast_spell", use_probe.allowed, use_probe.reason)
		var discard_probe := _scroll_discard_probe(context, character, scroll_view.slot_index, spell)
		scroll_view.discard = ActionAvailabilityView.new(&"cast_spell", discard_probe.allowed, discard_probe.reason)


static func _populate_fast_spell_actions(context: SessionWorkflowContext, member_view: CharacterView, character: CharacterState, battle_active: bool) -> void:
	for fast_spell: FastSpellBindingView in member_view.fast_spells:
		if fast_spell.spell_id.is_empty():
			continue
		var bound_spell := context.content.magic.spell_by_id(fast_spell.spell_id)
		if bound_spell == null or not character.known_spells().has(fast_spell.spell_id):
			fast_spell.activation = ActionAvailabilityView.new(&"cast_spell", false, "The stored spell is unavailable to this character.")
			continue
		if battle_active:
			var option_available := false
			for option: CombatSpellOptionView in context.rules.combat_flow.magic.selection().character_spell_options(context.state, context.content, character.id):
				if option.spell_id == bound_spell.id and option.power == fast_spell.power:
					option_available = true
					break
			fast_spell.activation = ActionAvailabilityView.new(&"cast_spell", option_available, "No legal target or casting action is currently available." if not option_available else "")
		else:
			var field_probe := _field_spell_probe(context, character, bound_spell, fast_spell.power)
			fast_spell.activation = ActionAvailabilityView.new(&"cast_spell", field_probe.allowed, field_probe.reason)


static func populate_spell_affordability(context: SessionWorkflowContext, result: GameView, character_filter: Dictionary) -> void:
	for member_view: CharacterView in result.party_members:
		if not character_filter.has(member_view.id):
			continue
		var character := context.state.party.character_by_id(member_view.id)
		for spell_index: int in member_view.spells.size():
			var spell_view: SpellView = member_view.spells[spell_index]
			var spell := context.content.magic.spell_by_id(spell_view.id)
			if spell == null:
				continue
			var affordable: Array[int] = []
			var affordable_scrolls: Array[int] = []
			for power: int in spell_view.structural_power_levels:
				if character.spell_points >= absi(spell.cost * power): affordable.append(power)
			for power: int in spell_view.structural_scroll_power_levels:
				if character.spell_points >= absi(spell.cost * power * 2): affordable_scrolls.append(power)
			if affordable == spell_view.power_levels and affordable_scrolls == spell_view.scroll_power_levels:
				continue
			spell_view = SpellView.new(spell, spell_view)
			spell_view.power_levels = affordable
			spell_view.scroll_power_levels = affordable_scrolls
			spell_view.field_cast = ActionAvailabilityView.new(&"cast_spell", not spell_view.power_levels.is_empty(), "The character does not have enough spell points.")
			spell_view.make_scroll = ActionAvailabilityView.new(&"cast_spell", not spell_view.scroll_power_levels.is_empty(), "Scribing requires twice the spell's normal spell-point cost.")
			member_view.spells[spell_index] = spell_view
		for fast_index: int in member_view.fast_spells.size():
			var fast_spell: FastSpellBindingView = member_view.fast_spells[fast_index]
			if fast_spell.spell_id.is_empty():
				continue
			var bound_spell := context.content.magic.spell_by_id(fast_spell.spell_id)
			var field_probe := _field_spell_probe(context, character, bound_spell, fast_spell.power)
			if fast_spell.activation.enabled != field_probe.allowed or fast_spell.activation.reason != field_probe.reason:
				var replacement := FastSpellBindingView.new(fast_index, character.fast_spell_at(fast_index), bound_spell)
				replacement.activation = ActionAvailabilityView.new(&"cast_spell", field_probe.allowed, field_probe.reason)
				member_view.fast_spells[fast_index] = replacement


static func populate_inventory_item_actions(context: SessionWorkflowContext, result: GameView) -> void:
	var state := context.state
	var content := context.content
	var rules := context.rules
	var context_reason := ""
	if result.pending_interaction != null:
		context_reason = "Resolve the current interaction first."
	elif result.party_setup_available:
		context_reason = "Begin the adventure before changing carried equipment."
	elif result.combat_view != null and result.combat_view.outcome == &"active":
		context_reason = "Use the battle action flow during combat."
	var party := state.party.characters()
	var definitions := content.items.definitions()
	for member_view: CharacterView in result.party_members:
		var character := state.party.character_by_id(member_view.id)
		if character == null:
			continue
		var race := content.characters.race_by_id(character.race_id)
		var caste := content.characters.caste_by_id(character.caste_id)
		var identify_cast := _inventory_identify_cast(context, character)
		for item_view: ItemView in member_view.items:
			var instance := ProjectionPolicy.item_instance(character, item_view.instance_id)
			var definition: ItemDefinition = null if instance == null else content.items.item_by_id(instance.definition_id)
			var actions := InventoryItemActionsView.new()
			if not context_reason.is_empty():
				actions.block_all(context_reason)
				item_view.actions = actions
				continue
			var equip_probe := rules.equipment.classic_equip_probe(character, instance, definition, race, caste, party, definitions)
			var unequip_probe := rules.equipment.classic_unequip_probe(character, instance, definition, definitions)
			var drop_probe := rules.inventory.classic_drop_probe(character, instance)
			var split_probe := rules.inventory.classic_split_probe(character, instance, definition)
			var join_probe := rules.inventory.classic_join_probe(character, instance, definition)
			var use_probe := FieldItemWorkflow.field_item_use_probe(context, character, instance, definition)
			actions.equip = ActionAvailabilityView.new(&"equip_item", equip_probe.allowed, equip_probe.reason)
			actions.unequip = ActionAvailabilityView.new(&"unequip_item", unequip_probe.allowed, unequip_probe.reason)
			actions.drop = ActionAvailabilityView.new(&"drop_item", drop_probe.allowed, drop_probe.reason)
			actions.split = ActionAvailabilityView.new(&"split_item", split_probe.allowed, split_probe.reason)
			actions.join = ActionAvailabilityView.new(&"join_item", join_probe.allowed, join_probe.reason)
			actions.use = ActionAvailabilityView.new(&"use_item", use_probe.allowed, use_probe.reason)
			if identify_cast.is_empty():
				actions.identify = ActionAvailabilityView.new(&"identify_item", false, "No living party member knows Identify Objects with 25 spell points.")
			else:
				actions.identify_caster_id = String(identify_cast[0])
				actions.identify_spell_id = String(identify_cast[1])
				actions.identify = ActionAvailabilityView.new(&"identify_item", true)
			for destination: CharacterState in party:
				if destination == character:
					continue
				var trade_probe := InventoryWorkflow.trade_item_probe(context, character, destination, instance, definition)
				actions.trade_targets.append(ItemTransferTargetView.new(destination.id, destination.name, trade_probe.allowed, trade_probe.reason, destination.carried_load, destination.carried_load + item_view.weight, destination.maximum_load))
			var enabled_targets := actions.trade_targets.filter(func(target: ItemTransferTargetView) -> bool: return target.enabled)
			var trade_reason := "Choose another party member." if actions.trade_targets.is_empty() else actions.trade_targets[0].reason if enabled_targets.is_empty() else ""
			actions.trade = ActionAvailabilityView.new(&"trade_item", not enabled_targets.is_empty(), trade_reason)
			item_view.actions = actions


static func _inventory_identify_cast(context: SessionWorkflowContext, target: CharacterState) -> Array[String]:
	for caster: CharacterState in context.state.party.characters():
		var spells: Array[SpellDefinition] = []
		for spell_id: String in caster.known_spells():
			var spell := context.content.magic.spell_by_id(spell_id)
			if spell != null and absi(spell.special) == 48:
				spells.append(spell)
		spells.sort_custom(func(left: SpellDefinition, right: SpellDefinition) -> bool: return left.classic_id < right.classic_id)
		for spell: SpellDefinition in spells:
			if FieldItemWorkflow.inventory_identify_probe(context, target.id, caster.id, spell.id).allowed:
				return [caster.id, spell.id]
	return []


static func populate_character_draft_spells(context: SessionWorkflowContext, result: GameView) -> void:
	var character := context.state.character_draft.generated_character
	var caste := context.content.characters.caste_by_id(character.caste_id)
	result.character_draft_spell_points_total = context.rules.characters.spell_selection_total(character, caste)
	var spent := 0
	for spell: SpellDefinition in _character_spell_candidates(context, character, caste):
		result.character_draft_spell_options.append(CharacterSpellOptionView.new(spell, context.rules.characters.spell_selection_cost(spell), character.known_spells().has(spell.id)))
	for spell_id: String in character.known_spells():
		spent += context.rules.characters.spell_selection_cost(context.content.magic.spell_by_id(spell_id))
	result.character_draft_spell_points_remaining = maxi(0, result.character_draft_spell_points_total - spent)


static func _character_spell_candidates(context: SessionWorkflowContext, character: CharacterState, caste: CasteDefinition) -> Array[SpellDefinition]:
	var result: Array[SpellDefinition] = []
	if character == null or caste == null or character.spellcaster_type < 1:
		return result
	var maximum_level := context.rules.characters.maximum_spell_selection_level(caste)
	for spell: SpellDefinition in context.content.magic.definitions():
		if int(spell.classic_id / 1000) != character.spellcaster_type:
			continue
		var tier := spell.classic_tier()
		var slot := spell.classic_slot()
		if tier >= 0 and tier < maximum_level and slot >= 1 and slot <= 12:
			result.append(spell)
	result.sort_custom(func(left: SpellDefinition, right: SpellDefinition) -> bool: return left.classic_id < right.classic_id)
	return result


static func _make_scroll_probe(context: SessionWorkflowContext, character: CharacterState, spell: SpellDefinition, power: int, check_affordability: bool = true) -> InventoryActionProbe:
	if character == null or spell == null or not character.known_spells().has(spell.id):
		return InventoryActionProbe.block("The character does not know that spell.")
	if not context.state.party_camping:
		return InventoryActionProbe.block("Enter camp before making a scroll.")
	if character.current_health < 1 or character.spellcaster_type < 1:
		return InventoryActionProbe.block("The selected character cannot scribe scrolls.")
	if not context.rules.equipment.has_equipped_scroll_case(character, context.content):
		return InventoryActionProbe.block("Equip a scroll case before making a scroll.")
	if ProjectionPolicy.first_empty_scroll_slot(character) < 0:
		return InventoryActionProbe.block("The scroll case already contains five spells.")
	if _parchment_instance(context, character) == null:
		return InventoryActionProbe.block("The character has no parchment.")
	if power < 1 or power > 7 or spell.cost < 0 and power != 1:
		return InventoryActionProbe.block("This spell does not support the selected scroll power.")
	if check_affordability and character.spell_points < absi(spell.cost * power * 2):
		return InventoryActionProbe.block("Scribing requires twice the spell's normal spell-point cost.")
	return InventoryActionProbe.permit()


static func _scroll_use_probe(context: SessionWorkflowContext, character: CharacterState, slot_index: int, spell: SpellDefinition) -> InventoryActionProbe:
	if character == null or slot_index < 0 or slot_index >= 5:
		return InventoryActionProbe.block("The scroll slot is unavailable.")
	var scroll := character.scroll_at(slot_index)
	if scroll == null or scroll.is_empty() or spell == null or spell.id != scroll.spell_id or scroll.power < 1 or scroll.power > 7:
		return InventoryActionProbe.block("This scroll slot is empty or invalid.")
	if character.current_health < 1 or character.conditions.is_active(ConditionRules.ANIMATED):
		return InventoryActionProbe.block("The selected character cannot use a scroll.")
	if not context.rules.equipment.has_equipped_scroll_case(character, context.content):
		return InventoryActionProbe.block("Equip the scroll case before using its spells.")
	if not spell.in_camp:
		return InventoryActionProbe.block("This scroll cannot be used outside battle; Classic offers to discard it.")
	if spell.target_type < 0 or spell.target_type > 12:
		return InventoryActionProbe.block("This scroll has an invalid Classic field target type.")
	if not ProjectionPolicy.field_spell_effect_supported(spell):
		return InventoryActionProbe.block("This scroll's Classic field effect is not implemented yet.")
	return InventoryActionProbe.permit()


static func _scroll_discard_probe(context: SessionWorkflowContext, character: CharacterState, slot_index: int, spell: SpellDefinition) -> InventoryActionProbe:
	if spell == null or spell.in_camp:
		return InventoryActionProbe.block("This scroll has a valid field use.")
	var scroll := character.scroll_at(slot_index) if character != null else null
	if scroll == null or scroll.is_empty() or scroll.spell_id != spell.id or scroll.power < 1 or scroll.power > 7:
		return InventoryActionProbe.block("This scroll slot is empty or invalid.")
	if character.current_health < 1 or character.conditions.is_active(ConditionRules.ANIMATED):
		return InventoryActionProbe.block("The selected character cannot use a scroll.")
	if not context.rules.equipment.has_equipped_scroll_case(character, context.content):
		return InventoryActionProbe.block("Equip the scroll case before managing its spells.")
	return InventoryActionProbe.permit()


static func _field_spell_probe(context: SessionWorkflowContext, character: CharacterState, spell: SpellDefinition, power: int, check_affordability: bool = true) -> InventoryActionProbe:
	if character == null or spell == null or not character.known_spells().has(spell.id):
		return InventoryActionProbe.block("The character does not know that spell.")
	if context.state.character_spellcasting_blocked:
		return InventoryActionProbe.block("Classic scenario state currently blocks character spellcasting.")
	if character.current_health < 1 or check_affordability and character.spell_points < 1:
		return InventoryActionProbe.block("The character cannot cast in their current state.")
	for condition: int in [ConditionRules.CONFUSED, ConditionRules.SILENCED, ConditionRules.HELPLESS, ConditionRules.STUPID, ConditionRules.ANIMATED]:
		if character.conditions.is_active(condition):
			return InventoryActionProbe.block("The character's current Classic condition prevents spellcasting.")
	if not spell.in_camp:
		return InventoryActionProbe.block("This spell cannot be cast outside battle.")
	if power < 1 or power > 7 or spell.cost < 0 and power != 1:
		return InventoryActionProbe.block("This spell does not support the selected power level.")
	if check_affordability and character.spell_points < absi(spell.cost * power):
		return InventoryActionProbe.block("The character does not have enough spell points.")
	if spell.target_type < 0 or spell.target_type > 12:
		return InventoryActionProbe.block("This spell has an invalid Classic field target type.")
	if not ProjectionPolicy.field_spell_effect_supported(spell):
		return InventoryActionProbe.block("This spell's Classic field effect is not implemented yet.")
	return InventoryActionProbe.permit()


static func _parchment_instance(context: SessionWorkflowContext, character: CharacterState) -> ItemInstance:
	if character == null:
		return null
	for instance: ItemInstance in character.inventory():
		var definition := context.content.items.item_by_id(instance.definition_id)
		if definition != null and definition.classic_id == 806 and instance.charges != 0:
			return instance
	return null
