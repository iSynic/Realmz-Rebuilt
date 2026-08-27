class_name LifecyclePartyWorkflow
extends RefCounted


static func create_party(context: SessionWorkflowContext, pending: bool, specs: Array[CharacterCreationSpec]) -> SessionWorkflowResult:
	if context.state.party_setup_completed or pending:
		return SessionWorkflowResult.failed(&"party_setup_closed", "Party creation is available only during party setup.")
	if context.state.character_draft != null:
		return SessionWorkflowResult.failed(&"character_draft_active", "Finish or cancel the character currently being created.")
	var maximum_party_size := clampi(context.content.campaign_definition().restrictions.maximum_party_size, 1, 6)
	if specs.is_empty() or specs.size() > maximum_party_size:
		return SessionWorkflowResult.failed(&"invalid_party_size", "This campaign allows one through %d characters." % maximum_party_size)
	var campaign := context.content.campaign_definition()
	var created: Array[CharacterState] = []
	var names: Dictionary = {}
	for index: int in specs.size():
		var spec: CharacterCreationSpec = specs[index]
		var validation := _character_creation_error(context, spec, names)
		if not validation.is_empty():
			return SessionWorkflowResult.failed(StringName(validation["code"]), String(validation["message"]))
		var character := _create_character_from_spec(context, spec, "party.character.%d" % (index + 1), true, created)
		if character == null:
			return SessionWorkflowResult.failed(&"character_creation_failed", "Realmz rules rejected a party member.")
		names[spec.name.to_lower()] = true
		created.append(character)
	context.state.party = PartyState.new(context.state.party.map_id, context.state.party.coordinate, created)
	context.state.experience_multiplier = party_experience_multiplier(created, context.state.difficulty, campaign)
	context.state.party_setup_completed = true
	var character_ids: Array[String] = []
	for character: CharacterState in created:
		character_ids.append(character.id)
	return SessionWorkflowResult.completed([DomainEvent.new(&"party_created", {"characterIds": character_ids})])


static func begin_adventure(context: SessionWorkflowContext, pending: bool) -> SessionWorkflowResult:
	if context.state.party_setup_completed or pending:
		return SessionWorkflowResult.failed(&"party_setup_closed", "Party setup is no longer active.")
	if context.state.character_draft != null:
		return SessionWorkflowResult.failed(&"character_draft_active", "Finish or cancel the character currently being created before beginning.")
	var characters := context.state.party.characters()
	if characters.is_empty():
		return SessionWorkflowResult.failed(&"empty_party", "Add or import at least one character before beginning.")
	context.state.experience_multiplier = party_experience_multiplier(characters, context.state.difficulty, context.content.campaign_definition())
	context.state.party_setup_completed = true
	var character_ids: Array[String] = []
	for character: CharacterState in characters:
		character_ids.append(character.id)
	return SessionWorkflowResult.completed([DomainEvent.new(&"party_created", {"characterIds": character_ids})])


static func import_vault_character(context: SessionWorkflowContext, pending: bool, payload: PlayerIntent.VaultImportPayload) -> SessionWorkflowResult:
	if context.state.party_setup_completed or pending:
		return SessionWorkflowResult.failed(&"party_setup_closed", "Vault import is available only during party setup.")
	if context.state.character_draft != null:
		return SessionWorkflowResult.failed(&"character_draft_active", "Finish or cancel the character currently being created before importing from the vault.")
	if payload == null or payload.character_id.is_empty() or payload.revision_hash.is_empty() or payload.character_state == null:
		return SessionWorkflowResult.failed(&"invalid_vault_import", "A validated vault character revision is required.")
	var imported := CharacterState.from_data(payload.character_state.to_data())
	if imported == null or imported.id != payload.character_id:
		return SessionWorkflowResult.failed(&"invalid_vault_import", "The vault character state is malformed.")
	var restrictions := context.content.campaign_definition().restrictions
	var maximum_party_size := clampi(restrictions.maximum_party_size, 1, 6)
	var current_characters := context.state.party.characters()
	if current_characters.size() >= maximum_party_size:
		return SessionWorkflowResult.failed(&"invalid_party_size", "This campaign allows no more than %d characters." % maximum_party_size)
	if context.content.race_by_id(imported.race_id) == null or context.content.caste_by_id(imported.caste_id) == null:
		return SessionWorkflowResult.failed(&"vault_character_ineligible", "The vault character's race or class is not defined by this campaign.")
	if restrictions.banned_races.has(imported.race_id) or restrictions.banned_castes.has(imported.caste_id):
		return SessionWorkflowResult.failed(&"vault_character_ineligible", "The campaign restrictions reject this vault character.")
	if restrictions.maximum_level > 0 and imported.level > restrictions.maximum_level:
		return SessionWorkflowResult.failed(&"vault_character_ineligible", "The vault character exceeds this campaign's maximum level.")
	var race := context.content.race_by_id(imported.race_id)
	var caste := context.content.caste_by_id(imported.caste_id)
	context.rules.characters.ensure_age_group(imported, race, caste)
	if not race.eligible_caste_ids.is_empty() and not race.eligible_caste_ids.has(caste.id):
		return SessionWorkflowResult.failed(&"vault_character_ineligible", "The vault character's race cannot use that class.")
	if not caste.eligible_race_ids.is_empty() and not caste.eligible_race_ids.has(race.id):
		return SessionWorkflowResult.failed(&"vault_character_ineligible", "The vault character's class is not available to that race.")
	var imported_item_ids: Dictionary = {}
	for item: ItemInstance in imported.inventory():
		if context.content.item_by_id(item.definition_id) == null:
			return SessionWorkflowResult.failed(&"vault_character_ineligible", "The vault character carries an item unavailable in this campaign.")
		if imported_item_ids.has(item.id) or context.state.party.owns_item_instance(item.id):
			return SessionWorkflowResult.failed(&"duplicate_item_ownership", "That character revision does not uniquely own every exact item instance.")
		imported_item_ids[item.id] = true
	var imported_load := context.rules.inventory.calculated_load(imported, context.content.item_definitions())
	if imported_load < 0 or imported_load > imported.maximum_load:
		return SessionWorkflowResult.failed(&"vault_character_ineligible", "The vault character's carried wealth and items exceed this character's load limit.")
	# Vault revisions preserve item identity and equipment state, but load is derived
	# again from the target package so stale local revisions cannot bypass capacity.
	imported.carried_load = imported_load
	for spell_id: String in imported.known_spells():
		if context.content.spell_by_id(spell_id) == null:
			return SessionWorkflowResult.failed(&"vault_character_ineligible", "The vault character knows a spell unavailable in this campaign.")
	for scroll: SpellScrollState in imported.scroll_case():
		if not scroll.is_empty() and context.content.spell_by_id(scroll.spell_id) == null:
			return SessionWorkflowResult.failed(&"vault_character_ineligible", "The vault character's scroll case contains a spell unavailable in this campaign.")
	for binding: FastSpellBindingState in imported.fast_spells():
		if binding.is_empty():
			continue
		var bound_spell := context.content.spell_by_id(binding.spell_id)
		if bound_spell == null or not imported.known_spells().has(binding.spell_id):
			return SessionWorkflowResult.failed(&"vault_character_ineligible", "The vault character's Fast Spell bindings reference an unavailable or unknown spell.")
		if binding.power < 1 or binding.power > 7 or bound_spell.cost < 0 and binding.power != 1:
			return SessionWorkflowResult.failed(&"vault_character_ineligible", "The vault character's Fast Spell bindings contain an invalid power.")
	if context.content.has_character_appearance_catalog():
		var portrait := context.content.appearance_by_id(imported.portrait_id) if not imported.portrait_id.is_empty() else null
		if (portrait != null and portrait.kind != CharacterAppearanceDefinition.PORTRAIT) or (not imported.portrait_id.is_empty() and portrait == null):
			return SessionWorkflowResult.failed(&"vault_character_ineligible", "The vault character uses a portrait unavailable in this campaign package.")
		var combat_icon := context.content.appearance_by_id(imported.combat_icon_id) if not imported.combat_icon_id.is_empty() else null
		if (combat_icon != null and combat_icon.kind != CharacterAppearanceDefinition.COMBAT_ICON) or (not imported.combat_icon_id.is_empty() and combat_icon == null):
			return SessionWorkflowResult.failed(&"vault_character_ineligible", "The vault character uses a combat icon unavailable in this campaign package.")
	for current: CharacterState in current_characters:
		if current.id == imported.id or current.name.to_lower() == imported.name.to_lower():
			return SessionWorkflowResult.failed(&"duplicate_party_member", "That vault character is already represented in the party.")
	if not context.state.party.add_character(imported):
		return SessionWorkflowResult.failed(&"vault_character_ineligible", "The validated vault character could not be added to the party.")
	return SessionWorkflowResult.completed([DomainEvent.new(&"vault_character_imported", {"characterId": imported.id, "revisionHash": payload.revision_hash, "sourceCampaignId": payload.source_campaign_id})])


static func generate_character_draft(context: SessionWorkflowContext, pending: bool, payload: PlayerIntent.CharacterDraftPayload) -> SessionWorkflowResult:
	if context.state.party_setup_completed or pending:
		return SessionWorkflowResult.failed(&"party_setup_closed", "Character creation is available only during party setup.")
	if payload == null or payload.spec == null:
		return SessionWorkflowResult.failed(&"invalid_character_spec", "Generate Character requires exactly one typed specification.")
	var maximum_party_size := clampi(context.content.campaign_definition().restrictions.maximum_party_size, 1, 6)
	var current_characters := context.state.party.characters()
	if current_characters.size() >= maximum_party_size:
		return SessionWorkflowResult.failed(&"invalid_party_size", "This campaign allows no more than %d characters." % maximum_party_size)
	var names: Dictionary = {}
	for current: CharacterState in current_characters:
		names[current.name.to_lower()] = true
	var validation := _character_creation_error(context, payload.spec, names)
	if not validation.is_empty():
		return SessionWorkflowResult.failed(StringName(validation["code"]), String(validation["message"]))
	var character_id := context.state.character_draft.generated_character.id if context.state.character_draft != null and context.state.character_draft.generated_character != null else _next_party_character_id(context.state)
	var character := _create_character_from_spec(context, payload.spec, character_id)
	if character == null:
		return SessionWorkflowResult.failed(&"character_creation_failed", "Realmz rules rejected the character draft.")
	var draft := CharacterDraft.new()
	draft.name = payload.spec.name
	draft.gender = payload.spec.gender
	draft.starting_level = payload.spec.starting_level
	draft.race_id = payload.spec.race_id
	draft.caste_id = payload.spec.caste_id
	draft.portrait_id = character.portrait_id
	draft.combat_icon_id = character.combat_icon_id
	draft.generated_character = character
	context.state.character_draft = draft
	return SessionWorkflowResult.completed([DomainEvent.new(&"character_draft_generated", {"characterId": character.id, "name": character.name})])


static func cancel_character_draft(context: SessionWorkflowContext, pending: bool) -> SessionWorkflowResult:
	if context.state.party_setup_completed or pending:
		return SessionWorkflowResult.failed(&"party_setup_closed", "Character creation is available only during party setup.")
	if context.state.character_draft == null:
		return SessionWorkflowResult.failed(&"no_character_draft", "There is no generated character to cancel.")
	var character_id := context.state.character_draft.generated_character.id if context.state.character_draft.generated_character != null else ""
	context.state.character_draft = null
	return SessionWorkflowResult.completed([DomainEvent.new(&"character_draft_cancelled", {"characterId": character_id})])


static func set_character_draft_spells(context: SessionWorkflowContext, pending: bool, spell_ids: Array[String]) -> SessionWorkflowResult:
	if context.state.party_setup_completed or pending:
		return SessionWorkflowResult.failed(&"party_setup_closed", "Spell selection is available only during character creation.")
	if context.state.character_draft == null or context.state.character_draft.generated_character == null:
		return SessionWorkflowResult.failed(&"no_character_draft", "Generate the character before choosing spells.")
	var character := context.state.character_draft.generated_character
	var caste := context.content.caste_by_id(character.caste_id)
	var candidate_ids: Dictionary = {}
	for spell: SpellDefinition in _character_spell_candidates(context, character, caste):
		candidate_ids[spell.id] = spell
	var selected: Array[String] = []
	var spent := 0
	for spell_id: String in spell_ids:
		if selected.has(spell_id) or not candidate_ids.has(spell_id):
			return SessionWorkflowResult.failed(&"invalid_character_spell", "The selected spell is not available to this character.")
		selected.append(spell_id)
		spent += context.rules.characters.spell_selection_cost(candidate_ids[spell_id] as SpellDefinition)
	var total := context.rules.characters.spell_selection_total(character, caste)
	if spent > total:
		return SessionWorkflowResult.failed(&"character_spell_budget_exceeded", "The selected spells exceed this character's Classic selection points.")
	character.set_known_spells(selected)
	return SessionWorkflowResult.completed([DomainEvent.new(&"character_draft_spells_changed", {"characterId": character.id, "spellIds": selected, "remaining": total - spent})])


static func prepare_character_finalize(context: SessionWorkflowContext, pending: bool) -> CharacterFinalizeWorkflowResult:
	if context.state.party_setup_completed or pending:
		return CharacterFinalizeWorkflowResult.failed(&"party_setup_closed", "Character creation is available only during party setup.")
	if context.state.character_draft == null or context.state.character_draft.generated_character == null:
		return CharacterFinalizeWorkflowResult.failed(&"no_character_draft", "Generate and review the character before finalizing it.")
	var maximum_party_size := clampi(context.content.campaign_definition().restrictions.maximum_party_size, 1, 6)
	var current_characters := context.state.party.characters()
	if current_characters.size() >= maximum_party_size:
		return CharacterFinalizeWorkflowResult.failed(&"invalid_party_size", "This campaign allows no more than %d characters." % maximum_party_size)
	var draft := context.state.character_draft
	var names: Dictionary = {}
	for current: CharacterState in current_characters:
		names[current.name.to_lower()] = true
	var validation := _character_creation_error(context, draft.to_creation_spec(), names)
	if not validation.is_empty():
		return CharacterFinalizeWorkflowResult.failed(StringName(validation["code"]), String(validation["message"]))
	var caste := context.content.caste_by_id(draft.generated_character.caste_id)
	var total := context.rules.characters.spell_selection_total(draft.generated_character, caste)
	var spent := 0
	for spell_id: String in draft.generated_character.known_spells():
		spent += context.rules.characters.spell_selection_cost(context.content.spell_by_id(spell_id))
	return CharacterFinalizeWorkflowResult.ready(draft.generated_character.id, draft.generated_character.name, maxi(0, total - spent))


static func commit_character_draft(context: SessionWorkflowContext) -> CharacterFinalizeWorkflowResult:
	if context.state.character_draft == null or context.state.character_draft.generated_character == null:
		return CharacterFinalizeWorkflowResult.failed(&"no_character_draft", "The generated character is no longer available.")
	var maximum_party_size := clampi(context.content.campaign_definition().restrictions.maximum_party_size, 1, 6)
	if context.state.party.characters().size() >= maximum_party_size:
		return CharacterFinalizeWorkflowResult.failed(&"invalid_party_size", "This campaign allows no more than %d characters." % maximum_party_size)
	var character := CharacterState.from_data(context.state.character_draft.generated_character.to_data())
	if character == null:
		return CharacterFinalizeWorkflowResult.failed(&"character_creation_failed", "Realmz rules rejected the generated character.")
	var party_context := context.state.party.characters()
	party_context.append(character)
	if not _materialize_initial_inventory(context, character, context.content.caste_by_id(character.caste_id), party_context) or not context.state.party.add_character(character):
		return CharacterFinalizeWorkflowResult.failed(&"character_creation_failed", "Realmz rules rejected the generated character.")
	context.state.character_draft = null
	return CharacterFinalizeWorkflowResult.committed(character.id, character.name, [DomainEvent.new(&"character_finalized", {"characterId": character.id})])


static func character_draft_is_valid(content: RealmzContent, state: GameState, rules: RealmzRules) -> bool:
	if state.character_draft == null:
		return true
	if state.party_setup_completed or state.character_draft.finalized or state.character_draft.generated_character == null:
		return false
	var draft := state.character_draft
	var character := draft.generated_character
	if character.name != draft.name or character.gender != draft.gender or character.race_id != draft.race_id or character.caste_id != draft.caste_id or character.portrait_id != draft.portrait_id or character.combat_icon_id != draft.combat_icon_id:
		return false
	var race := content.race_by_id(character.race_id)
	var caste := content.caste_by_id(character.caste_id)
	if race == null or caste == null:
		return false
	var restrictions := content.campaign_definition().restrictions
	if restrictions.banned_races.has(race.id) or restrictions.banned_castes.has(caste.id):
		return false
	if not race.eligible_caste_ids.is_empty() and not race.eligible_caste_ids.has(caste.id):
		return false
	if not caste.eligible_race_ids.is_empty() and not caste.eligible_race_ids.has(race.id):
		return false
	for current: CharacterState in state.party.characters():
		if current.id == character.id or current.name.to_lower() == character.name.to_lower():
			return false
	var candidate_ids: Dictionary = {}
	for spell: SpellDefinition in content.spell_definitions():
		if int(spell.classic_id / 1000) == character.spellcaster_type:
			var tier := spell.classic_tier()
			if tier >= 0 and tier < rules.characters.maximum_spell_selection_level(caste):
				candidate_ids[spell.id] = spell
	var spent := 0
	for spell_id: String in character.known_spells():
		if not candidate_ids.has(spell_id):
			return false
		spent += rules.characters.spell_selection_cost(candidate_ids[spell_id] as SpellDefinition)
	if spent > rules.characters.spell_selection_total(character, caste):
		return false
	for item: ItemInstance in character.inventory():
		if content.item_by_id(item.definition_id) == null:
			return false
	return true


static func party_experience_multiplier(characters: Array[CharacterState], difficulty: int, campaign: CampaignDefinition) -> float:
	if campaign == null or not campaign.guidance_authored or campaign.recommended_party_levels <= 0:
		return 1.0
	var current_levels := 0
	for character: CharacterState in characters:
		current_levels += character.level
	var multiplier := PartySetupRules.experience_multiplier(campaign.recommended_party_levels, current_levels, difficulty)
	return 1.0 if multiplier <= 0.0 else multiplier


static func set_party_setup_options(context: SessionWorkflowContext, pending: bool, difficulty: int, monster_set: int) -> SessionWorkflowResult:
	if context.state.party_setup_completed or pending:
		return SessionWorkflowResult.failed(&"party_setup_closed", "Party setup options are no longer available.")
	if difficulty < -2 or difficulty > 2:
		return SessionWorkflowResult.failed(&"invalid_difficulty", "Classic difficulty must be between Novice and Veteran.")
	if not context.content.available_monster_sets().has(monster_set):
		return SessionWorkflowResult.failed(&"unavailable_monster_set", "That Classic monster set is not present in this campaign package.")
	context.state.difficulty = difficulty
	context.state.monster_set = monster_set
	return SessionWorkflowResult.completed([DomainEvent.new(&"party_setup_options_changed", {"difficulty": difficulty, "monsterSet": monster_set})])


static func remove_party_member(context: SessionWorkflowContext, pending: bool, character_id: String) -> SessionWorkflowResult:
	if context.state.party_setup_completed or pending:
		return SessionWorkflowResult.failed(&"party_setup_closed", "Party members can be removed only during party setup.")
	context.state.set_combat_auto(character_id, false)
	if character_id.is_empty() or not context.state.party.remove_character(character_id):
		return SessionWorkflowResult.failed(&"unknown_party_member", "The selected character is not in the setup party.")
	context.state.set_selected_character_ids([])
	return SessionWorkflowResult.completed([DomainEvent.new(&"party_member_removed", {"characterId": character_id})])


static func reorder_party(context: SessionWorkflowContext, character_ids: Array[String]) -> SessionWorkflowResult:
	var current := context.state.party.characters()
	if current.size() < 2:
		return SessionWorkflowResult.failed(&"party_order_unavailable", "At least two party members are required to change party order.")
	var previous_ids: Array[String] = []
	for character: CharacterState in current:
		previous_ids.append(character.id)
	if not context.state.party.reorder_characters(character_ids):
		return SessionWorkflowResult.failed(&"invalid_party_order", "Party Order requires every current character exactly once.")
	return SessionWorkflowResult.completed([DomainEvent.new(&"party_reordered", {"previousCharacterIds": previous_ids, "characterIds": character_ids.duplicate(), "source": "classic"})])


static func change_character_appearance(context: SessionWorkflowContext, payload: PlayerIntent.AppearancePayload) -> SessionWorkflowResult:
	if not context.state.party_setup_completed:
		return SessionWorkflowResult.failed(&"appearance_change_unavailable", "Begin the adventure before changing appearance.")
	if context.state.combat != null and not context.state.combat.completed:
		return SessionWorkflowResult.failed(&"appearance_change_unavailable", "Appearance changes are unavailable during battle.")
	if not context.content.has_character_appearance_catalog():
		return SessionWorkflowResult.failed(&"appearance_change_unavailable", "This package does not contain the complete Classic portrait and combat-icon catalogs.")
	var character := context.state.party.character_by_id(payload.character_id)
	if character == null:
		return SessionWorkflowResult.failed(&"unknown_party_member", "The selected character is not in the active party.")
	if payload.appearance_kind not in [CharacterAppearanceDefinition.PORTRAIT, CharacterAppearanceDefinition.COMBAT_ICON]:
		return SessionWorkflowResult.failed(&"invalid_appearance_kind", "Choose either a portrait or a combat icon.")
	var appearance := context.content.appearance_by_id(payload.appearance_id)
	if appearance == null or appearance.kind != payload.appearance_kind:
		return SessionWorkflowResult.failed(&"invalid_character_appearance", "The selected appearance is unavailable for that role.")
	var previous_id := character.portrait_id if payload.appearance_kind == CharacterAppearanceDefinition.PORTRAIT else character.combat_icon_id
	if previous_id == appearance.id:
		return SessionWorkflowResult.failed(&"appearance_unchanged", "Choose a different appearance before applying the change.")
	if payload.appearance_kind == CharacterAppearanceDefinition.PORTRAIT:
		character.portrait_id = appearance.id
	else:
		character.combat_icon_id = appearance.id
	return SessionWorkflowResult.completed([DomainEvent.new(&"character_appearance_changed", {
		"characterId": character.id,
		"appearanceKind": String(payload.appearance_kind),
		"previousAppearanceId": previous_id,
		"appearanceId": appearance.id,
		"source": "classic-character-menu",
	})])


static func _character_creation_error(context: SessionWorkflowContext, spec: CharacterCreationSpec, existing_names: Dictionary) -> Dictionary:
	if spec == null:
		return {"code": &"invalid_character_spec", "message": "A character specification is required."}
	if spec.name.is_empty() or spec.name.length() > 24 or spec.gender not in [1, 2]:
		return {"code": &"invalid_character_spec", "message": "Every party member requires a valid name and gender."}
	if not CharacterRules.STARTING_LEVELS.has(spec.starting_level):
		return {"code": &"invalid_starting_level", "message": "Starting level must be one of Castle's fixed character-creation choices."}
	if existing_names.has(spec.name.to_lower()):
		return {"code": &"duplicate_character_name", "message": "Party member names must be unique."}
	var race := context.content.race_by_id(spec.race_id)
	var caste := context.content.caste_by_id(spec.caste_id)
	if race == null or caste == null:
		return {"code": &"unknown_character_definition", "message": "Party creation references an unavailable race or caste."}
	var restrictions := context.content.campaign_definition().restrictions
	if restrictions.banned_races.has(race.id):
		return {"code": &"restricted_race", "message": "This campaign does not allow the selected race."}
	if restrictions.banned_castes.has(caste.id):
		return {"code": &"restricted_caste", "message": "This campaign does not allow the selected class."}
	if restrictions.maximum_level > 0 and spec.starting_level > restrictions.maximum_level:
		return {"code": &"restricted_starting_level", "message": "This campaign allows characters only through level %d." % restrictions.maximum_level}
	if not race.eligible_caste_ids.is_empty() and not race.eligible_caste_ids.has(caste.id):
		return {"code": &"incompatible_race_class", "message": "The selected race cannot use that class."}
	if not caste.eligible_race_ids.is_empty() and not caste.eligible_race_ids.has(race.id):
		return {"code": &"incompatible_class_race", "message": "The selected class is not available to that race."}
	if context.content.has_character_appearance_catalog() and _resolved_character_appearance(context, spec, race).is_empty():
		return {"code": &"invalid_character_appearance", "message": "The selected portrait or combat icon is unavailable in this campaign package."}
	return {}


static func _create_character_from_spec(context: SessionWorkflowContext, spec: CharacterCreationSpec, character_id: String, add_starting_items: bool = false, party_context: Array[CharacterState] = []) -> CharacterState:
	var race := context.content.race_by_id(spec.race_id)
	var character := context.rules.characters.create_character(character_id, spec.name, race, context.content.caste_by_id(spec.caste_id), spec.gender, context.rng, false, spec.starting_level)
	if character == null:
		return null
	var appearance := _resolved_character_appearance(context, spec, race)
	character.portrait_id = String(appearance.get("portraitId", spec.portrait_id))
	character.combat_icon_id = String(appearance.get("combatIconId", spec.combat_icon_id))
	if add_starting_items:
		var equipment_context := party_context.duplicate()
		equipment_context.append(character)
		if not _materialize_initial_inventory(context, character, context.content.caste_by_id(spec.caste_id), equipment_context):
			return null
	return character


static func _materialize_initial_inventory(context: SessionWorkflowContext, character: CharacterState, caste: CasteDefinition, party_context: Array[CharacterState]) -> bool:
	if character == null or caste == null or not character.inventory().is_empty():
		return false
	var definitions := context.content.item_definitions()
	character.carried_load = context.rules.inventory.calculated_load(character, definitions)
	if character.carried_load < 0 or character.carried_load > character.maximum_load:
		return false
	var added: Array[ItemInstance] = []
	for index: int in caste.start_items().size():
		var definition := context.content.item_by_id(caste.start_items()[index])
		if definition == null:
			return false
		var instance := context.rules.inventory.add_item(character, definition, "%s.item.%d" % [character.id, index], true)
		# Castle tests capacity before writing the item record. Its separate numitems
		# counter advances too early; the direct model keeps only records that fit.
		if instance != null:
			added.append(instance)
	var race := context.content.race_by_id(character.race_id)
	for instance: ItemInstance in added:
		var definition := context.content.item_by_id(instance.definition_id)
		context.rules.inventory.equip_classic(character, instance, definition, race, caste, party_context, definitions)
	return context.rules.inventory.calculated_load(character, definitions) == character.carried_load


static func _resolved_character_appearance(context: SessionWorkflowContext, spec: CharacterCreationSpec, race: RaceDefinition) -> Dictionary:
	if not context.content.has_character_appearance_catalog():
		return {"portraitId": spec.portrait_id, "combatIconId": spec.combat_icon_id}
	var default_portrait_resource := 257 if race.default_icon_set == 0 else 251 + race.default_icon_set * 6
	var portrait := context.content.appearance_by_id(spec.portrait_id) if not spec.portrait_id.is_empty() else context.content.appearance_by_resource(CharacterAppearanceDefinition.PORTRAIT, default_portrait_resource)
	if portrait == null or portrait.kind != CharacterAppearanceDefinition.PORTRAIT:
		return {}
	var icon := context.content.appearance_by_id(spec.combat_icon_id) if not spec.combat_icon_id.is_empty() else context.content.appearance_by_resource(CharacterAppearanceDefinition.COMBAT_ICON, 9000 - 257 + portrait.classic_resource_id)
	if icon == null or icon.kind != CharacterAppearanceDefinition.COMBAT_ICON:
		return {}
	return {"portraitId": portrait.id, "combatIconId": icon.id}


static func _next_party_character_id(state: GameState) -> String:
	var character_id := state.next_instance_id("party.character")
	while state.party.character_by_id(character_id) != null:
		character_id = state.next_instance_id("party.character")
	return character_id


static func _character_spell_candidates(context: SessionWorkflowContext, character: CharacterState, caste: CasteDefinition) -> Array[SpellDefinition]:
	var result: Array[SpellDefinition] = []
	if character == null or caste == null or character.spellcaster_type < 1:
		return result
	var maximum_level := context.rules.characters.maximum_spell_selection_level(caste)
	for spell: SpellDefinition in context.content.spell_definitions():
		if int(spell.classic_id / 1000) != character.spellcaster_type:
			continue
		var tier := spell.classic_tier()
		var slot := spell.classic_slot()
		if tier >= 0 and tier < maximum_level and slot >= 1 and slot <= 12:
			result.append(spell)
	result.sort_custom(func(left: SpellDefinition, right: SpellDefinition) -> bool: return left.classic_id < right.classic_id)
	return result
