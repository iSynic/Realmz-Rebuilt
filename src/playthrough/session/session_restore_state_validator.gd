## Validates detached game state before a restored playthrough can be committed.

class_name SessionRestoreStateValidator
extends RefCounted

static func normalize_age_groups(state: GameState, content: RealmzContent, rules: RealmzRules) -> void:
	for character: CharacterState in state.party.characters():
		var race := content.characters.race_by_id(character.race_id)
		var caste := content.characters.caste_by_id(character.caste_id)
		if race != null and caste != null:
			rules.characters.ensure_age_group(character, race, caste)


static func party_inventory_is_valid(content: RealmzContent, state: GameState, rules: RealmzRules) -> bool:
	if content == null or state == null or rules == null:
		return false
	var definitions := content.items.definitions()
	for character: CharacterState in state.party.characters():
		if rules.inventory.calculated_load(character, definitions) != character.carried_load:
			return false
		for scroll: SpellScrollState in character.scroll_case():
			if not scroll.is_empty() and content.magic.spell_by_id(scroll.spell_id) == null:
				return false
	return true


static func combat_staged_item_is_valid(content: RealmzContent, state: GameState, rules: RealmzRules) -> bool:
	if state.combat == null or state.combat.turns.staged_random_item_instance_id().is_empty():
		return true
	var actor_id := state.combat.turns.active_actor_id()
	var character := state.party.character_by_id(actor_id)
	var instance_id := state.combat.turns.staged_random_item_instance_id()
	if character == null or state.combat.completed or state.combat.turns.staged_random_item_power(actor_id, instance_id) not in range(1, 8):
		return false
	var instance: ItemInstance = null
	for candidate: ItemInstance in character.inventory():
		if candidate.id == instance_id:
			instance = candidate
			break
	var item := content.items.item_by_id(instance.definition_id) if instance != null else null
	var spell := content.magic.spell_by_classic_id(item.special_2) if item != null else null
	if item == null or spell == null or absi(item.special_1) != 8:
		return false
	var use_probe := rules.inventory.classic_spell_item_probe(character, instance, item, spell, content.characters.race_by_id(character.race_id), content.characters.caste_by_id(character.caste_id), true)
	if not use_probe.allowed or ClassicSpellDispositionRules.combat_item_disposition(spell) != ClassicSpellDispositionRules.DISPOSITION_EXECUTABLE:
		return false
	return true


static func combat_vm_request_is_valid(content: RealmzContent, state: GameState, rng: RealmzRng, rules: RealmzRules, action_state: ScenarioActionState, request: InteractionRequest) -> bool:
	if request == null or request.kind != InteractionRequest.COMBAT:
		return true
	if state.combat == null or state.combat.completed:
		return false
	var expected := RealmzRuntimeApi.new(content, state, rng, action_state, rules).active_combat_request(request.request_id)
	return expected != null and expected.to_data() == request.to_data()


static func party_fast_spells_are_valid(content: RealmzContent, state: GameState) -> bool:
	if content == null or state == null:
		return false
	for character: CharacterState in state.party.characters():
		for binding: FastSpellBindingState in character.fast_spells():
			if binding.is_empty():
				continue
			var spell := content.magic.spell_by_id(binding.spell_id)
			if spell == null or not character.known_spells().has(binding.spell_id) or binding.power < 1 or binding.power > 7 or spell.cost < 0 and binding.power != 1:
				return false
	return true


static func party_appearance_is_valid(content: RealmzContent, state: GameState) -> bool:
	if content == null or state == null:
		return false
	if not content.characters.has_complete_appearance_catalog():
		return true
	for character: CharacterState in state.party.characters():
		if not character.portrait_id.is_empty():
			var portrait := content.characters.appearance_by_id(character.portrait_id)
			if portrait == null or portrait.kind != CharacterAppearanceDefinition.PORTRAIT:
				return false
		if not character.combat_icon_id.is_empty():
			var icon := content.characters.appearance_by_id(character.combat_icon_id)
			if icon == null or icon.kind != CharacterAppearanceDefinition.COMBAT_ICON:
				return false
	return true


static func shop_state_is_valid(content: RealmzContent, state: GameState) -> bool:
	if content == null or state == null:
		return false
	if not state.location_services.active_shop_id.is_empty() and content.economy.shop_by_id(state.location_services.active_shop_id) == null:
		return false
	for shop_id: Variant in state.location_services.shop_buyback_overrides():
		var shop := content.economy.shop_by_id(String(shop_id))
		if shop == null:
			return false
		var occupied_slots: Dictionary = {}
		for index: int in shop.item_ids().size():
			if state.location_services.shop_quantity(shop, index) > 0: occupied_slots[shop.stock_slot(index)] = true
		for item_id: Variant in state.location_services.shop_buyback_overrides()[shop_id]:
			var item := content.items.item_by_id(String(item_id))
			var slot := state.location_services.shop_buyback_slot(String(shop_id), String(item_id))
			if item == null or slot < 0 or slot > 999 or slot / 200 != item.classic_id / 200 or occupied_slots.has(slot):
				return false
			occupied_slots[slot] = true
	return true


static func location_notes_are_valid(content: RealmzContent, state: GameState) -> bool:
	if content == null or state == null:
		return false
	var counts: Dictionary = {}
	var ordinals: Dictionary = {}
	for note: LocationNoteState in state.world.exploration.location_notes():
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


static func boat_overlays_are_valid(content: RealmzContent, state: GameState) -> bool:
	if content == null or state == null:
		return false
	for key_value: Variant in state.world.topology.boat_presence_overrides().keys():
		var key := String(key_value)
		var separator := key.rfind(":")
		if separator <= 0:
			return false
		var map := content.world.map_by_id(key.left(separator))
		var components := key.substr(separator + 1).split(",", false, 1)
		if map == null or map.level_type != &"land" or components.size() != 2 or not components[0].is_valid_int() or not components[1].is_valid_int() or map.topology.cell_at(Vector2i(int(components[0]), int(components[1]))) == null:
			return false
	return true


static func journal_messages_are_valid(content: RealmzContent, state: GameState) -> bool:
	for message_id: int in state.scenario_progress.journal_message_ids():
		if not ScenarioProgressState.journal_message_id_is_valid(message_id) or content.scenario_records.message_by_id(message_id) == null:
			return false
	return true


static func acquired_player_maps_are_valid(content: RealmzContent, state: GameState) -> bool:
	if content == null or state == null:
		return false
	for player_map_id: String in state.world.exploration.acquired_map_ids():
		if content.world.player_map_by_id(player_map_id) == null:
			return false
	return true
