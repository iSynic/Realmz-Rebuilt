## Prepares explicit cross-adventure copies without time, RNG, or source mutation.
class_name PartyTransferRules
extends RefCounted


static func prepare(source: GameState, source_content: RealmzContent, destination: SessionWorkflowContext, revision: int, file_hash: String) -> PartyTransferReview:
	var result := PartyTransferReview.new()
	result.source_package_hash = source_content.package_hash
	result.destination_package_hash = destination.content.package_hash
	result.destination_revision = revision
	result.source_file_hash = file_hash
	result.available_slots = maxi(0, clampi(destination.content.campaign.restrictions.maximum_party_size, 1, 6) - destination.state.party.characters().size())
	for character: CharacterState in source.party.characters():
		result.candidates.append(_prepare_character(character, source_content, destination))
	result.left_behind.append("Pooled money, bank balances, shared storage, and confiscated equipment stay in the source adventure.")
	if not source.party.allies().is_empty():
		result.left_behind.append("%d recruited allies or summons stay in the source adventure." % source.party.allies().size())
	if source.combat != null:
		var friendly_monsters := source.combat.roster.monsters().filter(func(monster: MonsterState) -> bool: return not monster.traitor)
		if not friendly_monsters.is_empty():
			result.left_behind.append("%d friendly battlefield creatures, including summons, stay behind." % friendly_monsters.size())
	if source.combat != null and not source.combat.dropped_items.items().is_empty():
		result.left_behind.append("%d battlefield-dropped items stay in the source adventure." % source.combat.dropped_items.items().size())
	return result


static func _prepare_character(original: CharacterState, source: RealmzContent, destination: SessionWorkflowContext) -> PartyTransferCandidate:
	var result := PartyTransferCandidate.new()
	result.character = CharacterStateCodec.copy(original)
	var character := result.character
	if character == null:
		result.reasons.append("The saved character could not be decoded.")
		return result
	if source.rules_version != destination.content.rules_version:
		result.reasons.append("The source and destination use different rules versions.")
	for family: StringName in [&"races", &"castes"]:
		var id := character.race_id if family == &"races" else character.caste_id
		if not source.transfer_catalog.matches(destination.content.transfer_catalog, family, id):
			result.reasons.append("The destination's %s definition differs from the source." % ("race" if family == &"races" else "caste"))
	if not result.reasons.is_empty():
		return result
	var rules := destination.rules
	var source_race := source.characters.race_by_id(character.race_id)
	var retained: Array[ItemInstance] = []
	for instance: ItemInstance in character.inventory():
		var item := source.items.item_by_id(instance.definition_id)
		var portable := _item_portable(source, destination.content, item)
		if portable:
			retained.append(instance)
			result.retained.append(item.name if instance.identified else item.unidentified_name)
		else:
			var reason := "Scenario-owned equipment stays behind." if source.transfer_catalog.is_scenario_owned(&"items", instance.definition_id) else "Its definition, resources, or scenario-only behavior cannot transfer compatibly."
			result.omit(&"item", instance.id, (item.name if instance.identified else item.unidentified_name) if item != null else "Unavailable item", reason)
			if instance.equipped and (item == null or not rules.equipment.force_unequip(character, instance, item, source.items.definitions(), source_race)):
				result.reasons.append("The equipped item's effects could not be removed safely.")
	character.set_inventory(retained)
	_clean_magic(character, source, destination.content, result)
	for id: String in [character.portrait_id, character.combat_icon_id]:
		if id.is_empty():
			continue
		var appearance := source.characters.appearance_by_id(id)
		var target := destination.content.characters.appearance_by_id(id)
		if appearance == null or target == null or appearance.kind != target.kind or appearance.classic_resource_id != target.classic_resource_id or not _media_matches(source, destination.content, "cicn", appearance.classic_resource_id):
			result.reasons.append("The destination cannot preserve this character's portrait or combat icon.")
	# Timed effects expire at the new-adventure boundary; permanent signed markers
	# and permanent equipment contributions remain exactly as saved.
	cleanup_for_new_adventure(character)
	character.carried_load = rules.inventory.calculated_load(character, destination.content.items.definitions())
	var movement_bonus := 0
	for instance: ItemInstance in retained:
		if instance.equipped:
			movement_bonus += destination.content.items.item_by_id(instance.definition_id).movement_bonus
	rules.characters.recalculate_movement(character, destination.content.characters.race_by_id(character.race_id), movement_bonus)
	character.movement = character.maximum_movement
	character.attacks_remaining = character.normal_attacks
	var failure := PartyAdmissionRules.validate(destination, character)
	if failure != null:
		result.reasons.append(failure.error_message)
	return result


static func cleanup_for_new_adventure(character: CharacterState) -> void:
	character.conditions.clear_positive()
	character.traitor = false


static func _item_portable(source: RealmzContent, target: RealmzContent, item: ItemDefinition, visited: Dictionary = {}) -> bool:
	if item == null or absi(item.item_type) in [23, 25] or item.special_1 == -23 or not _portable(source, target, &"items", item.id):
		return false
	if visited.has(item.id):
		return true
	visited[item.id] = true
	if not _media_matches(source, target, "cicn", item.icon_id) or not _media_matches(source, target, "cicn", item.visible_icon_id(false)) or item.sound_id != 0 and not _media_matches(source, target, "snd ", absi(item.sound_id + 600)):
		return false
	if not item.cursed_item_id.is_empty() and not _item_portable(source, target, source.items.item_by_id(item.cursed_item_id), visited):
		return false
	if item.special_2 > 1100 and absi(item.special_1) in range(1, 9):
		var spell := source.magic.spell_by_classic_id(item.special_2)
		return spell != null and _spell_portable(source, target, spell.id)
	return true


static func _portable(source: RealmzContent, target: RealmzContent, family: StringName, id: String) -> bool:
	return not source.transfer_catalog.is_scenario_owned(family, id) and source.transfer_catalog.matches(target.transfer_catalog, family, id)


static func _clean_magic(character: CharacterState, source: RealmzContent, target: RealmzContent, result: PartyTransferCandidate) -> void:
	var known: Array[String] = []
	for id: String in character.known_spells():
		if _spell_portable(source, target, id):
			known.append(id)
			result.retained.append("Spell: " + source.magic.spell_by_id(id).name)
		else:
			var spell := source.magic.spell_by_id(id)
			result.omit(&"spell", id, spell.name if spell != null else id, "Scenario magic or incompatible resources stay behind.")
	character.set_known_spells(known)
	for index: int in character.scroll_case().size():
		var scroll := character.scroll_at(index)
		if not scroll.is_empty() and not _spell_portable(source, target, scroll.spell_id):
			result.omit(&"scroll", scroll.spell_id, "Scroll case slot %d" % (index + 1), "This spell cannot transfer compatibly.")
			character.clear_scroll(index)
		elif not scroll.is_empty():
			result.retained.append("Scroll %d: %s" % [index + 1, source.magic.spell_by_id(scroll.spell_id).name])
	for index: int in character.fast_spells().size():
		var binding := character.fast_spell_at(index)
		if not binding.is_empty() and not known.has(binding.spell_id):
			result.omit(&"binding", binding.spell_id, "Fast Spell slot %d" % (index + 1), "The bound spell was removed.")
			character.clear_fast_spell(index)


static func _spell_portable(source: RealmzContent, target: RealmzContent, id: String) -> bool:
	var spell := source.magic.spell_by_id(id)
	if spell == null or not _portable(source, target, &"spells", id):
		return false
	var view := SpellView.new(spell)
	for resource: int in view.animation_resource_ids:
		if not _media_matches(source, target, "cicn", resource):
			return false
	if not _media_matches(source, target, view.icon_resource_type, view.icon_id):
		return false
	if spell.queue_icon > 0 and not _media_matches(source, target, "PICT", 302):
		return false
	return _media_matches(source, target, "snd ", absi(spell.sound_start + 600)) and _media_matches(source, target, "snd ", absi(spell.sound_end + 600))


static func _media_matches(source: RealmzContent, target: RealmzContent, type: String, id: int) -> bool:
	if id == 0:
		return true
	var source_asset: MediaAsset
	var target_asset: MediaAsset
	for asset: MediaAsset in source.media_assets:
		if asset.resource_type == type and asset.resource_id == id:
			source_asset = asset
	for asset: MediaAsset in target.media_assets:
		if asset.resource_type == type and asset.resource_id == id:
			target_asset = asset
	return source_asset != null and target_asset != null and source_asset.sha256 == target_asset.sha256 and source_asset.mime_type == target_asset.mime_type
