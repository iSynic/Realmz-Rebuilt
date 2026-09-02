class_name ClockRules
extends RefCounted

var _conditions: ConditionRules
var _characters: CharacterRules
var _inventory: InventoryRules


func _init(condition_rules: ConditionRules, character_rules: CharacterRules, inventory_rules: InventoryRules) -> void:
	_conditions = condition_rules
	_characters = character_rules
	_inventory = inventory_rules


func change_fatigue(party: PartyState, amount: int) -> int:
	party.fatigue = clampi(party.fatigue + amount, 4, 135)
	return party.fatigue


func advance_minutes(state: GameState, content: RealmzContent, minutes: int, condition_ticks: int = 0) -> Array[DomainEvent]:
	var elapsed := maxi(0, minutes)
	var previous_day := state.clock.day()
	state.clock.advance_minutes(elapsed)
	var events: Array[DomainEvent] = [DomainEvent.new(&"time_advanced", {"minutes": elapsed, "day": state.clock.day(), "hour": state.clock.hour(), "minute": state.clock.minute()})]
	for day_index: int in state.clock.day() - previous_day:
		for character: CharacterState in state.party.characters():
			var race := content.race_by_id(character.race_id) if content != null else null
			var caste := content.caste_by_id(character.caste_id) if content != null else null
			if race == null or caste == null:
				continue
			var aging := _characters.advance_age_days(character, race, caste, 1)
			if aging != null and aging.changed_group():
				events.append(DomainEvent.new(&"character_age_changed", aging.event_payload(character, race)))
	for tick: int in condition_ticks:
		events.append_array(_conditions.tick_party(state.party))
	return events


func advance_classic_field_time(state: GameState, content: RealmzContent, timeclicks: int, minutes_per_timeclick: int, defer_midnight_recovery: bool = false) -> Array[DomainEvent]:
	var clicks := maxi(0, timeclicks)
	var scale := clampi(minutes_per_timeclick, 1, 5)
	var events: Array[DomainEvent] = []
	for click_index: int in clicks:
		var previous_minutes := state.clock.total_minutes()
		var click_events := advance_minutes(state, content, scale)
		if not click_events.is_empty():
			click_events[0].payload["classicTimeclick"] = click_index + 1
			click_events[0].payload["classicTimeclickCount"] = clicks
		events.append_array(click_events)
		var current_minutes := state.clock.total_minutes()
		var first_hour_boundary := floori(float(previous_minutes) / 60.0) + 1
		var last_hour_boundary := floori(float(current_minutes) / 60.0)
		for hour_boundary: int in range(first_hour_boundary, last_hour_boundary + 1):
			events.append_array(_conditions.tick_party(state.party))
			var previous_fatigue := state.party.fatigue
			change_fatigue(state.party, 1)
			events.append(DomainEvent.new(&"fatigue_changed", {"previous": previous_fatigue, "current": state.party.fatigue, "reason": "hour-boundary", "source": "classic"}))
			events.append_array(_restore_spell_points(state.party))
			if hour_boundary % 12 == 0 and not (defer_midnight_recovery and hour_boundary % 24 == 0):
				events.append_array(_restore_half_day_health(state.party, content))
	return events


func restore_half_day_health(party: PartyState, content: RealmzContent) -> Array[DomainEvent]:
	return _restore_half_day_health(party, content)


func _restore_spell_points(party: PartyState) -> Array[DomainEvent]:
	var events: Array[DomainEvent] = []
	for character: CharacterState in party.characters():
		if character.current_health <= 0 or character.conditions.is_active(ConditionRules.ANIMATED) or character.spell_points >= character.maximum_spell_points:
			continue
		var amount := mini(maxi(1, floori(float(character.level) / 2.0)), character.maximum_spell_points - character.spell_points)
		character.spell_points += amount
		events.append(DomainEvent.new(&"spell_points_recovered", {"characterId": character.id, "amount": amount, "source": "classic-hour"}))
	for ally: MonsterState in party.allies():
		if ally.spell_points >= ally.maximum_spell_points:
			continue
		var amount := mini(maxi(1, floori(float(ally.hit_dice) / 2.0)), ally.maximum_spell_points - ally.spell_points)
		ally.spell_points += amount
		events.append(DomainEvent.new(&"ally_spell_points_recovered", {"allyId": ally.id, "amount": amount, "source": "classic-hour"}))
	return events


func _restore_half_day_health(party: PartyState, content: RealmzContent) -> Array[DomainEvent]:
	var events: Array[DomainEvent] = []
	for character: CharacterState in party.characters():
		if character.current_health >= character.maximum_health or character.current_health <= -10:
			continue
		var ration := _consume_iron_ration(party, content)
		var amount := floori(float(character.level) / 3.0)
		if ration.is_empty():
			amount = floori(float(amount) / 2.0)
		amount = maxi(1, amount)
		amount += character.conditions.value(ConditionRules.POISONED)
		if not ration.is_empty():
			events.append(DomainEvent.new(&"rest_ration_consumed", ration))
		if character.conditions.is_active(ConditionRules.TURNED_TO_STONE):
			continue
		var previous_health := character.current_health
		character.current_health = clampi(character.current_health + amount, -10, character.maximum_health)
		var restored := character.current_health - previous_health
		if restored != 0:
			events.append(DomainEvent.new(&"health_recovered", {"characterId": character.id, "amount": restored, "source": "classic-half-day"}))
	for ally: MonsterState in party.allies():
		if ally.current_health >= ally.maximum_health:
			continue
		var previous_health := ally.current_health
		ally.current_health = mini(ally.maximum_health, ally.current_health + floori(float(ally.hit_dice) / 4.0) + 1)
		var restored := ally.current_health - previous_health
		if restored != 0:
			events.append(DomainEvent.new(&"ally_health_recovered", {"allyId": ally.id, "amount": restored, "source": "classic-half-day"}))
	return events


func _consume_iron_ration(party: PartyState, content: RealmzContent) -> Dictionary:
	var definition := content.item_by_classic_id(877)
	if definition == null:
		return {}
	for character: CharacterState in party.characters():
		for instance: ItemInstance in character.inventory():
			if instance.definition_id != definition.id or instance.charges <= 0:
				continue
			var instance_id := instance.id
			if not _inventory.use_charge(character, instance_id, definition):
				return {}
			return {"characterId": character.id, "instanceId": instance_id, "itemId": definition.id, "chargesRemaining": maxi(0, instance.charges), "source": "classic-half-day"}
	return {}
