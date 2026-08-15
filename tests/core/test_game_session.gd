extends RealmzTestCase


func run() -> void:
	var session := GameSession.new()
	var before_start := session.submit_intent(PlayerIntent.new(PlayerIntent.Kind.SEARCH))
	assert_equal(before_start.state, SessionStep.State.FAILED, "an unstarted session rejects intents")
	assert_equal(before_start.error_code, &"session_not_started", "the rejection is explicit")

	var invalid_start := session.start(null, 42)
	assert_equal(invalid_start.state, SessionStep.State.FAILED, "start requires validated typed content")
	assert_equal(invalid_start.error_code, &"invalid_content", "invalid content never partially starts a session")

	var snapshot := session.snapshot()
	assert_equal(snapshot, null, "an unstarted session has no save boundary")

	var character := CharacterState.new("fast.spell.character", "Quickcaster", 12, 12)
	assert_equal(character.fast_spells().size(), 10, "every character owns Castle's ten Fast Spell slots")
	assert_true(character.fast_spells().all(func(binding: FastSpellBindingState) -> bool: return binding.is_empty()), "new characters default every Fast Spell slot to undefined")
	assert_true(character.bind_fast_spell(9, "classic.spell.quick", 4), "slot ten accepts a typed stable spell identity and power")
	var round_trip := CharacterState.from_data(JSON.parse_string(JSON.stringify(character.to_data())))
	assert_equal(round_trip.fast_spell_at(9).to_data(), {"spellId": "classic.spell.quick", "power": 4}, "Fast Spell bindings round-trip inside character-owned state")
	var corrupt := character.to_data()
	corrupt["fastSpells"][0] = {"spellId": "", "power": 2}
	assert_equal(CharacterState.from_data(corrupt), null, "malformed empty Fast Spell bindings fail strict character restoration")

	var malformed_requests: Array = [
		[InteractionRequest.ACKNOWLEDGE, {"prompt": "Read this.", "journalEligible": true}],
		[InteractionRequest.YES_NO, {"yesLabel": "Yes", "noLabel": "No", "yesId": 1}],
		[InteractionRequest.INDEXED_CHOICE, {"prompt": "Choose.", "options": [{"label": 7}]}],
		[InteractionRequest.CHARACTER_SELECTION, {"count": 1, "eligible": [{"id": "hero"}]}],
		[InteractionRequest.ALLY_SELECTION, {"prompt": "Choose.", "maximum": 1, "selectedIds": [], "requiredIds": [], "candidates": [{"id": "ally", "name": "Ally", "classicMonsterId": 1}]}],
		[InteractionRequest.SESSION_LIFECYCLE, {"operation": "quit-application", "prompt": "Quit?", "inCombat": false, "options": [{"action": "cancel", "label": 3}]}],
	]
	for malformed: Array in malformed_requests:
		assert_equal(InteractionRequest.from_payload("malformed.contract", malformed[0], malformed[1]), null, "typed interaction request variants reject partial or malformed nested records")
