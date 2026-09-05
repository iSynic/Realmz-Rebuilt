## Shares Classic wealth-transfer validation and movement recalculation.

class_name ClassicMoneyTransferSupport
extends RefCounted

var _content: RealmzContent
var _game_state: GameState
var _rules: RealmzRules


func _init(content: RealmzContent, game_state: GameState, rules: RealmzRules) -> void:
	_content = content
	_game_state = game_state
	_rules = rules


func movement_context_error() -> String:
	for character: CharacterState in _game_state.party.characters():
		if _content.characters.race_by_id(character.race_id) == null or _content.characters.caste_by_id(character.caste_id) == null:
			return "Character '%s' has no package-backed race or class for Classic movement recalculation." % character.id
	return ""


func recalculate_party_movement() -> void:
	for character: CharacterState in _game_state.party.characters():
		var race := _content.characters.race_by_id(character.race_id)
		var caste := _content.characters.caste_by_id(character.caste_id)
		_rules.characters.recalculate_movement(character, race, caste.movement_bonus)


static func probe_data(probe: EconomyActionProbe) -> Dictionary:
	return {"enabled": probe != null and probe.allowed, "reason": "" if probe != null and probe.allowed else "Action availability is unavailable." if probe == null else probe.reason}


static func wealth_kind(value: String) -> int:
	match value:
		"gold": return WealthState.Kind.GOLD
		"gems": return WealthState.Kind.GEMS
		"jewelry": return WealthState.Kind.JEWELRY
	return -1
