## Shares existing Character Files admission checks with explicit party transfer.
class_name PartyAdmissionRules
extends RefCounted


static func source_definition_error(source: ContentTransferCatalog, target: RealmzContent, character: CharacterState, source_campaign_id: String) -> String:
	if source == null:
		return "The Character File's source rule definitions are unavailable."
	for family: StringName in [&"races", &"castes"]:
		var id := character.race_id if family == &"races" else character.caste_id
		if source.is_scenario_specific(family, id) and source_campaign_id != target.campaign_id:
			return "This character uses scenario custom race or class rules and is available only in its source scenario (%s)." % source_campaign_id
		if source != target.transfer_catalog and not source.matches(target.transfer_catalog, family, id):
			return "The destination's %s definition differs from this character's source." % ("race" if family == &"races" else "class")
	return ""


static func validate(context: SessionWorkflowContext, imported: CharacterState) -> SessionWorkflowResult:
	for failure: SessionWorkflowResult in [definition_error(context, imported), magic_error(context, imported), appearance_error(context, imported)]:
		if failure != null:
			return failure
	for current: CharacterState in context.state.party.characters():
		if current.id == imported.id or current.name.to_lower() == imported.name.to_lower():
			return SessionWorkflowResult.failed(&"duplicate_party_member", "That character is already represented in the party.")
	return null


static func definition_error(context: SessionWorkflowContext, imported: CharacterState) -> SessionWorkflowResult:
	var restrictions := context.content.campaign.restrictions
	if context.content.characters.race_by_id(imported.race_id) == null or context.content.characters.caste_by_id(imported.caste_id) == null:
		return SessionWorkflowResult.failed(&"vault_character_ineligible", "The vault character's race or class is not defined by this campaign.")
	if restrictions.banned_races.has(imported.race_id) or restrictions.banned_castes.has(imported.caste_id):
		return SessionWorkflowResult.failed(&"vault_character_ineligible", "The campaign restrictions reject this vault character.")
	if restrictions.maximum_level > 0 and imported.level > restrictions.maximum_level:
		return SessionWorkflowResult.failed(&"vault_character_ineligible", "The vault character exceeds this campaign's maximum level.")
	var race := context.content.characters.race_by_id(imported.race_id)
	var caste := context.content.characters.caste_by_id(imported.caste_id)
	context.rules.characters.ensure_age_group(imported, race, caste)
	if not race.eligible_caste_ids.is_empty() and not race.eligible_caste_ids.has(caste.id):
		return SessionWorkflowResult.failed(&"vault_character_ineligible", "The vault character's race cannot use that class.")
	if not caste.eligible_race_ids.is_empty() and not caste.eligible_race_ids.has(race.id):
		return SessionWorkflowResult.failed(&"vault_character_ineligible", "The vault character's class is not available to that race.")
	var imported_item_ids: Dictionary = {}
	for item: ItemInstance in imported.inventory():
		if context.content.items.item_by_id(item.definition_id) == null:
			return SessionWorkflowResult.failed(&"vault_character_ineligible", "The vault character carries an item unavailable in this campaign.")
		if imported_item_ids.has(item.id) or context.state.party.owns_item_instance(item.id):
			return SessionWorkflowResult.failed(&"duplicate_item_ownership", "That character revision does not uniquely own every exact item instance.")
		imported_item_ids[item.id] = true
	var imported_load := context.rules.inventory.calculated_load(imported, context.content.items.definitions())
	if imported_load < 0 or imported_load > imported.maximum_load:
		return SessionWorkflowResult.failed(&"vault_character_ineligible", "The vault character's carried wealth and items exceed this character's load limit.")
	# Vault revisions preserve item identity and equipment state, but load is derived
	# again from the target package so stale local revisions cannot bypass capacity.
	imported.carried_load = imported_load
	return null


static func magic_error(context: SessionWorkflowContext, imported: CharacterState) -> SessionWorkflowResult:
	for spell_id: String in imported.known_spells():
		if context.content.magic.spell_by_id(spell_id) == null:
			return SessionWorkflowResult.failed(&"vault_character_ineligible", "The vault character knows a spell unavailable in this campaign.")
	for scroll: SpellScrollState in imported.scroll_case():
		if not scroll.is_empty() and context.content.magic.spell_by_id(scroll.spell_id) == null:
			return SessionWorkflowResult.failed(&"vault_character_ineligible", "The vault character's scroll case contains a spell unavailable in this campaign.")
	for binding: FastSpellBindingState in imported.fast_spells():
		if binding.is_empty():
			continue
		var bound_spell := context.content.magic.spell_by_id(binding.spell_id)
		if bound_spell == null or not imported.known_spells().has(binding.spell_id):
			return SessionWorkflowResult.failed(&"vault_character_ineligible", "The vault character's Fast Spell bindings reference an unavailable or unknown spell.")
		if binding.power < 1 or binding.power > 7 or bound_spell.cost < 0 and binding.power != 1:
			return SessionWorkflowResult.failed(&"vault_character_ineligible", "The vault character's Fast Spell bindings contain an invalid power.")
	return null


static func appearance_error(context: SessionWorkflowContext, imported: CharacterState) -> SessionWorkflowResult:
	if context.content.characters.has_complete_appearance_catalog():
		var portrait := context.content.characters.appearance_by_id(imported.portrait_id) if not imported.portrait_id.is_empty() else null
		if (portrait != null and portrait.kind != CharacterAppearanceDefinition.PORTRAIT) or (not imported.portrait_id.is_empty() and portrait == null):
			return SessionWorkflowResult.failed(&"vault_character_ineligible", "The vault character uses a portrait unavailable in this campaign package.")
		var combat_icon := context.content.characters.appearance_by_id(imported.combat_icon_id) if not imported.combat_icon_id.is_empty() else null
		if (combat_icon != null and combat_icon.kind != CharacterAppearanceDefinition.COMBAT_ICON) or (not imported.combat_icon_id.is_empty() and combat_icon == null):
			return SessionWorkflowResult.failed(&"vault_character_ineligible", "The vault character uses a combat icon unavailable in this campaign package.")
	return null
