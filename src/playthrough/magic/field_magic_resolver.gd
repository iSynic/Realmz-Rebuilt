## Resolves ordered field-magic targets and publishes their committed effects.

class_name FieldMagicResolver
extends RefCounted


static func group_target_ids(party: PartyState, spell: SpellDefinition) -> Array[String]:
	var ids := _party_character_ids(party)
	if spell.target_type in [3, 9]:
		for ally: MonsterState in party.allies():
			ids.append(ally.id)
	return ids


static func selected_targets(party: PartyState, target_ids: Array[String], include_allies: bool) -> Variant:
	var selected: Dictionary = {}
	var ally_ids: Dictionary = {}
	if include_allies:
		for ally: MonsterState in party.allies():
			ally_ids[ally.id] = true
	for target_id: String in target_ids:
		if target_id.is_empty() or selected.has(target_id) or party.character_by_id(target_id) == null and not ally_ids.has(target_id):
			return null
		selected[target_id] = true
	return selected


static func resolve(context: SessionWorkflowContext, caster: CharacterState, selected: Dictionary, spell: SpellDefinition, power: int, spend_spell_points: bool, allow_empty: bool) -> GroupSpellResolution:
	var targets := _ordered_party_targets(context.state.party, selected)
	var allies := _ordered_party_allies(context.state.party, selected)
	var castes: Array[CasteDefinition] = []
	var races: Array[RaceDefinition] = []
	for target: CharacterState in targets:
		castes.append(context.content.characters.caste_by_id(target.caste_id))
		races.append(context.content.characters.race_by_id(target.race_id))
	var definitions: Array[MonsterDefinition] = []
	for ally: MonsterState in allies:
		var definition := context.content.combat.monster_by_id(ally.definition_id)
		if definition == null:
			return null
		definitions.append(definition)
	return context.rules.magic.resolve_field_spell(caster, targets, spell, power, context.rng, castes, races, spend_spell_points, allow_empty, context.content.items.definitions(), allies, definitions)


static func append_events(context: SessionWorkflowContext, events: Array[DomainEvent], character: CharacterState, spell: SpellDefinition, power: int, resolution: GroupSpellResolution, sound_source: StringName, state_source: StringName, event_kind: StringName, event_context: Dictionary = {}) -> void:
	var start_sound := spell.sound_start + 600
	if start_sound != 0:
		events.append(DomainEvent.new(&"sound_requested", {"soundId": absi(start_sound), "waitForCompletion": true, "source": String(sound_source)}))
	var special := absi(spell.special)
	if special == 68:
		context.state.party.fatigue = 4
		events.append(DomainEvent.new(&"party_fatigue_changed", {"fatigue": 4, "spellId": spell.id, "source": String(state_source)}))
	elif spell.target_type == 7:
		var condition_index := 0 if special == 50 else special
		var next_value := power * 30 - 1 if special == 50 else maxi(context.state.party.conditions.value(condition_index), resolution.duration)
		if special != 50 or power * 30 > context.state.party.conditions.value(condition_index):
			context.state.party.conditions.set_value(condition_index, next_value)
		events.append(DomainEvent.new(&"party_condition_changed", {"condition": condition_index, "value": context.state.party.conditions.value(condition_index), "spellId": spell.id, "source": String(state_source)}))
	for index: int in resolution.resolutions.size():
		var target_resolution := resolution.resolutions[index]
		var payload := {"characterId": character.id, "targetId": resolution.target_ids[index], "targetKind": String(resolution.target_kinds[index]), "spellId": spell.id, "power": power, "saved": target_resolution.saved, "damage": target_resolution.damage, "healing": maxi(0, -target_resolution.damage), "duration": target_resolution.duration, "source": "classic"}
		if target_resolution.cleared_condition >= 0:
			payload["clearedCondition"] = target_resolution.cleared_condition
		if not target_resolution.unequipped_item_ids.is_empty():
			payload["unequippedItemIds"] = target_resolution.unequipped_item_ids.duplicate()
		payload.merge(event_context, true)
		events.append(DomainEvent.new(event_kind, payload))
		if target_resolution.aging != null and target_resolution.aging.changed_group():
			var target := context.state.party.character_by_id(resolution.target_ids[index])
			events.append(DomainEvent.new(&"character_age_changed", target_resolution.aging.event_payload(target, context.content.characters.race_by_id(target.race_id))))
	if spell.target_type == 11 and spell.sound_end + 600 != 0:
		events.append(DomainEvent.new(&"sound_requested", {"soundId": absi(spell.sound_end + 600), "waitForCompletion": false, "source": String(sound_source)}))


static func _ordered_party_targets(party: PartyState, selected: Dictionary) -> Array[CharacterState]:
	var targets: Array[CharacterState] = []
	for member: CharacterState in party.characters():
		if selected.has(member.id):
			targets.append(member)
	return targets


static func _ordered_party_allies(party: PartyState, selected: Dictionary) -> Array[MonsterState]:
	var targets: Array[MonsterState] = []
	for ally: MonsterState in party.allies():
		if selected.has(ally.id):
			targets.append(ally)
	return targets


static func _party_character_ids(party: PartyState) -> Array[String]:
	var ids: Array[String] = []
	for member: CharacterState in party.characters():
		ids.append(member.id)
	return ids
