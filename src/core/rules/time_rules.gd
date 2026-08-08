class_name ClockRules
extends RefCounted

var _conditions: ConditionRules
var _characters: CharacterRules


func _init(condition_rules: ConditionRules, character_rules: CharacterRules) -> void:
	_conditions = condition_rules
	_characters = character_rules


func change_fatigue(party: PartyState, amount: int) -> int:
	party.fatigue = clampi(party.fatigue + amount, 4, 135)
	return party.fatigue


func advance_minutes(state: GameState, content: RealmzContent, minutes: int, condition_ticks: int = 0) -> Array[DomainEvent]:
	var elapsed := maxi(0, minutes)
	var previous_day := state.clock.day()
	state.clock.advance_minutes(elapsed)
	var events: Array[DomainEvent] = [DomainEvent.new(&"time_advanced", {"minutes": elapsed, "day": state.clock.day(), "hour": state.clock.hour()})]
	for day_index: int in state.clock.day() - previous_day:
		for character: CharacterState in state.party.characters():
			var race := content.race_by_id(character.race_id) if content != null else null
			var caste := content.caste_by_id(character.caste_id) if content != null else null
			if race == null or caste == null:
				continue
			var aging := _characters.advance_age_days(character, race, caste, 1)
			if aging != null and aging.changed_group():
				events.append(DomainEvent.new(&"character_age_changed", aging.event_payload(character)))
	for tick: int in condition_ticks:
		events.append_array(_conditions.tick_party(state.party))
	return events


func camp(state: GameState, content: RealmzContent, hours: int = 8) -> Array[DomainEvent]:
	var events := advance_minutes(state, content, maxi(1, hours) * 60, maxi(1, hours))
	state.party.fatigue = 4
	for character: CharacterState in state.party.characters():
		if character.current_health > 0:
			character.current_health = mini(character.maximum_health, character.current_health + maxi(1, hours))
			character.spell_points = character.maximum_spell_points
	events.append(DomainEvent.new(&"party_camped", {"hours": maxi(1, hours)}))
	return events
