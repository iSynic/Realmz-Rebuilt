## Castle's ordered Data TD3 scan, independent of presentation and package storage.
class_name ClassicTimedEncounterRules
extends RefCounted

class Check extends RefCounted:
	var eligible: bool = false
	var stop_scan: bool = false
	var events: Array[DomainEvent] = []


static func check(encounter: TimedEncounterDefinition, content: RealmzContent, state: GameState, rng: RealmzRng, map: MapDefinition, coordinate: Vector2i, day: int) -> Check:
	var result := Check.new()
	if encounter.id > 150:
		result.stop_scan = true
		return result
	var effective := state.scenario_progress.encounters.timed_override(encounter.id)
	var effective_day := int(effective.get("day", encounter.day))
	if effective_day != day:
		result.stop_scan = effective_day == 0
		return result
	var increment := int(effective.get("increment", encounter.increment))
	var next_day := ((effective_day + increment + 32768) & 65535) - 32768
	var chance := int(effective.get("percent", encounter.chance_percent))
	var roll := rng.draw(100, StringName("timed-encounter.%d" % encounter.id))
	var prerequisites := roll <= chance
	if prerequisites and encounter.required_item_id > 0:
		prerequisites = _has_item(content, state, encounter.required_item_id)
	if prerequisites and encounter.required_quest_id > -1:
		prerequisites = state.scenario_progress.quest_is_set(encounter.required_quest_id)
	result.eligible = prerequisites and _location_matches(encounter, state, map, coordinate)
	# Castle's midnight scan writes the row at breakofday. A failed location
	# continues reading, so that earlier row's local increment is not written.
	var write_row := not prerequisites or result.eligible or next_day == 0
	result.stop_scan = not prerequisites or (not result.eligible and next_day == 0)
	if write_row:
		effective["day"] = next_day
		state.scenario_progress.encounters.set_timed_override(encounter.id, effective)
		result.events.append(DomainEvent.new(&"timed_encounter_advanced", {"encounterId": encounter.id, "day": effective_day, "nextDay": next_day, "source": "classic-midnight"}))
	result.events.append(DomainEvent.new(&"timed_encounter_checked", {"encounterId": encounter.id, "roll": roll, "chancePercent": chance, "eligible": result.eligible}))
	return result


static func _location_matches(encounter: TimedEncounterDefinition, state: GameState, map: MapDefinition, coordinate: Vector2i) -> bool:
	var mode := encounter.native_facts.words[10] if encounter.native_facts != null else int(encounter.location_kind)
	if mode <= 0: return true
	if mode not in [1, 2] or map == null: return false
	if mode == 1 and map.level_type != &"land" or mode == 2 and map.level_type != &"dungeon": return false
	if map.level_index != encounter.required_level: return false
	if encounter.required_random_rectangle > -1:
		var region := map.random_region_by_index(encounter.required_random_rectangle)
		if region == null or not state.world.triggers.random_region(region).contains(region.bounds, coordinate): return false
	if encounter.required_x > -1:
		# Preserve Castle's recx-gated Y test, including its authored negative Y.
		return coordinate.x == encounter.required_x and coordinate.y == encounter.required_y
	return true


static func _has_item(content: RealmzContent, state: GameState, classic_id: int) -> bool:
	var definition := content.items.item_by_classic_id(classic_id)
	if definition == null: return false
	for character: CharacterState in state.party.characters():
		for instance: ItemInstance in character.inventory():
			if instance.definition_id == definition.id: return true
	return false
