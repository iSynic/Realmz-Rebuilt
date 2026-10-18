## Builds typed begin responses and targeting requests from detached combat choices.
class_name BattleCastTargetingPolicy
extends RefCounted

static func requires_commitment(body: InteractionResponse.CombatBody, weapon_mode: StringName) -> bool:
	return body.action in [&"cast_spell", &"use_scroll", &"use_item"] or body.action == &"attack" and weapon_mode == &"missile"


static func begin_response(body: InteractionResponse.CombatBody) -> InteractionResponse.CombatBody:
	var selection := CombatCastSelection.from_body(body)
	var result := selection.to_body()
	result.action = begin_action_for(selection, body)
	return result


static func begin_action_for(selection: CombatCastSelection, body: InteractionResponse.CombatBody) -> StringName:
	if body.action == &"attack":
		return &"begin_projectile"
	match selection.action:
		&"cast_spell": return &"begin_spell"
		&"use_scroll": return &"begin_scroll"
		&"use_item": return &"begin_item"
	return &""


static func can_start_source(pending: CombatCastSelection, body: InteractionResponse.CombatBody) -> bool:
	return pending == null or pending.same_source(CombatCastSelection.from_body(body)) and pending.power == body.power


static func selection_for_targeting(pending: CombatCastSelection, body: InteractionResponse.CombatBody) -> CombatCastSelection:
	if pending != null and can_start_source(pending, body):
		return pending
	return null


static func option_matches_selection(selection: CombatCastSelection, option: InteractionRequestValue.CastOption) -> bool:
	match selection.action:
		&"cast_spell": return option.spell_id == selection.spell_id and option.power == selection.power
		&"use_scroll": return option.scroll_slot == selection.scroll_slot and option.power == selection.power
		&"use_item": return option.item_instance_id == selection.item_instance_id and option.power == selection.power
	return false


static func contains_spell_option(spell_options: Array[InteractionRequestValue.CastOption], selected: InteractionRequestValue.CastOption) -> bool:
	for option: InteractionRequestValue.CastOption in spell_options:
		if option.spell_id == selected.spell_id and option.power == selected.power and option.target_mode == selected.target_mode:
			return true
	return false


static func find_matching_option(selection: CombatCastSelection, options: Array[InteractionRequestValue.CastOption]) -> InteractionRequestValue.CastOption:
	for option: InteractionRequestValue.CastOption in options:
		if option_matches_selection(selection, option):
			return option
	return null


static func targeting_request(options: Array[InteractionRequestValue.CastOption], selected: InteractionRequestValue.CastOption, response_body: InteractionResponse.CombatBody) -> CombatTargetingRequest:
	var mode := selected.target_mode
	var candidate_ids: Array[String] = []
	if mode in [&"combatant", &"sequence"]:
		for candidate: InteractionRequestValue.CombatTarget in selected.target_candidates:
			if not candidate.id.is_empty(): candidate_ids.append(candidate.id)
	if mode == &"combatant":
		for candidate: InteractionRequestValue.CastOption in options:
			if candidate.spell_id == selected.spell_id and candidate.power == selected.power and candidate.scroll_slot == selected.scroll_slot and candidate.target_mode == &"combatant" and not candidate.target_id.is_empty(): candidate_ids.append(candidate.target_id)
	var result := CombatTargetingRequest.new(mode, response_body)
	result.classic_backdrops = true
	result.candidate_ids = candidate_ids
	result.maximum_targets = selected.maximum_targets
	result.area_offsets = selected.area_offsets.duplicate()
	result.area_rotation_offsets = selected.area_rotation_offsets.duplicate(true)
	result.default_target_coordinate = selected.default_target_coordinate
	result.legal_coordinates = selected.legal_target_coordinates.duplicate()
	result.validation_deferred = response_body.action == &"cast_spell" and mode in [&"combatant", &"sequence"] or mode == &"area" and (result.legal_coordinates.is_empty() or result.supports_rotation())
	return result


static func pending_request(selection: CombatCastSelection, body: InteractionResponse.CombatBody, spell_options: Array[InteractionRequestValue.CastOption], scroll_options: Array[InteractionRequestValue.CastOption], item_options: Array[InteractionRequestValue.CastOption], attack_enabled: bool, attack_targets: Array[InteractionRequestValue.CombatTarget]) -> CombatTargetingRequest:
	if selection.action == &"attack":
		var attack_request := CombatTargetingRequest.new(&"combatant", body)
		attack_request.classic_backdrops = true
		if attack_enabled:
			for target: InteractionRequestValue.CombatTarget in attack_targets:
				if not target.id.is_empty(): attack_request.candidate_ids.append(target.id)
		return attack_request
	var options: Array[InteractionRequestValue.CastOption] = []
	match selection.action:
		&"cast_spell": options = spell_options
		&"use_scroll": options = scroll_options
		&"use_item": options = item_options
	var option := find_matching_option(selection, options)
	if option == null:
		return null
	return targeting_request(options, option, body)
