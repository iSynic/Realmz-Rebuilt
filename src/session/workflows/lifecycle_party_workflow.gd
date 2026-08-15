class_name LifecyclePartyWorkflow
extends RefCounted


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
