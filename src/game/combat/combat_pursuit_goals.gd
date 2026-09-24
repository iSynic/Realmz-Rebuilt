## Builds transient firing-position goals without moving actors or drawing RNG.
class_name CombatPursuitGoals
extends CombatAiScoringSupport


func character_profiles(state: GameState, content: RealmzContent, actor: CharacterState) -> Array[Dictionary]:
	var profiles: Array[Dictionary] = []
	for spell_id: String in actor.known_spells():
		for power: int in range(1, 8):
			var candidates: Array[Dictionary] = []
			_append_profile(candidates, content.magic.spell_by_id(spell_id), power)
			if not candidates.is_empty() and _context.magic_flow().selection().probe_character_spell_choice(state, content, actor.id, spell_id, power).allowed:
				profiles.append_array(candidates)
	var equipped := _context.equipment.combat_equipment(actor, content.items.definitions())
	if equipped.valid and equipped.melee_weapon != null:
		var probe: CombatSpellCastProbe = _context.magic_flow().probe_character_item_spell(state, content, actor.id, "", equipped.melee_weapon_instance_id)
		# Target rejection follows ordinary source admission; it must not suppress pursuit.
		if probe.allowed or probe.reason in [&"invalid_item_target", &"item_target_unavailable"]:
			var power := absi(equipped.melee_weapon.special_1)
			if power == 8: power = maxi(1, state.combat.turns.staged_random_item_power(actor.id, equipped.melee_weapon_instance_id))
			_append_profile(profiles, content.magic.spell_by_classic_id(equipped.melee_weapon.special_2), power)
	if actor.attacks_remaining >= 2:
		var projectile = _context.reactions().character_projectile_profile(actor, content, equipped, state.combat)
		if projectile != null and (projectile.available or projectile.error_code == &"projectile_power_roll_required"):
			profiles.append({"spell": projectile.spell, "range": projectile.maximum_range, "physical": true, "targetKind": &"monster"})
	return profiles


func monster_profiles(state: GameState, content: RealmzContent, actor: MonsterState, definition: MonsterDefinition) -> Array[Dictionary]:
	var profiles: Array[Dictionary] = []
	var missile_item := content.items.item_by_id(definition.item_id_at(1))
	var missile_spell := content.magic.spell_by_classic_id(absi(missile_item.special_2)) if missile_item != null else null
	if definition.missile_percent > 0 and missile_spell != null and _context.actions().projectile_spell_unavailable_reason(missile_spell).is_empty() and actor.spell_points >= absi(missile_spell.cost):
		profiles.append({"spell": missile_spell, "range": absi(missile_spell.range_min + missile_spell.range_max), "physical": true, "targetKind": &"character"})
	if definition.magic_attack_count <= 0 or state.monster_spellcasting_blocked or state.combat.actor_statuses.was_attacked(actor.id): return profiles
	if state.combat.turns.active_turn != null and state.combat.turns.active_turn.spell_cast_count >= definition.magic_attack_count: return profiles
	for condition: int in [ConditionRules.STUPID, ConditionRules.CONFUSED, ConditionRules.SILENCED, ConditionRules.HELPLESS]:
		if actor.conditions.is_active(condition): return profiles
	var seen_spells: Dictionary = {}
	for slot: int in 10:
		var spell := content.magic.spell_by_id(definition.spell_id_at(slot))
		if spell == null or not _context.automation().monster_spell_unavailable_reason(spell).is_empty(): continue
		if seen_spells.has(spell.id): continue
		seen_spells[spell.id] = true
		var fixed := ClassicSpellSourceRules.is_combat_application_elemental_attack(spell) or ClassicSpellSourceRules.is_zero_cost_monster_projectile_spell(spell)
		var maximum := 1 if fixed else 7 if spell.cost == 0 else mini(7, actor.spell_points / spell.cost)
		for power: int in range(1, maximum + 1): _append_profile(profiles, spell, power)
	return profiles


func firing_anchors(state: GameState, content: RealmzContent, actor_id: String, target_id: String, profiles: Array[Dictionary]) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var field := state.combat.battlefield
	var terrain := CombatMonsterActions.battle_terrain_set(content, field)
	if terrain == null or not field.actors.has_actor(target_id): return result
	var occupied := _actors_by_cell(field)
	var origin := field.actors.actor_position(actor_id)
	var unique: Dictionary = {}
	var footprints: Dictionary = {}
	var geometries := _firing_geometries(state, content, actor_id, target_id, profiles)
	# Check every usable geometry at the current position before enumerating
	# distant anchors. Equivalent geometry needs only its largest admitted range.
	for geometry: Dictionary in geometries:
		var profile: Dictionary = geometry["profile"]
		geometry["centers"] = _centers(state, actor_id, target_id, profile, occupied)
		for center: Vector2i in geometry["centers"]:
			if floori(Vector2(center - origin).length()) <= int(geometry["radius"]) and _position_is_safe(state, terrain, actor_id, origin, center, profile, occupied, footprints) and (not geometry["los"] or _context.battlefield.has_line_of_sight_to_coordinate(field, terrain, actor_id, center, origin, occupied)):
				return [origin]
	for geometry: Dictionary in geometries:
		var profile: Dictionary = geometry["profile"]
		var radius: int = geometry["radius"]
		for center: Vector2i in geometry["centers"]:
			for y: int in range(maxi(0, center.y - radius - 1), mini(BattlefieldGrid.SIZE, center.y + radius + 2)):
				for x: int in range(maxi(0, center.x - radius - 1), mini(BattlefieldGrid.SIZE, center.x + radius + 2)):
					var anchor := Vector2i(x, y)
					if unique.has(anchor) or floori(Vector2(center - anchor).length()) > radius: continue
					if not _position_is_safe(state, terrain, actor_id, anchor, center, profile, occupied, footprints): continue
					if geometry["los"] and not _context.battlefield.has_line_of_sight_to_coordinate(field, terrain, actor_id, center, anchor, occupied): continue
					unique[anchor] = true
	for value: Variant in unique: result.append(value)
	result.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.y < b.y or a.y == b.y and a.x < b.x)
	return result


func _firing_geometries(state: GameState, content: RealmzContent, actor_id: String, target_id: String, profiles: Array[Dictionary]) -> Array[Dictionary]:
	var geometries: Dictionary = {}
	for profile: Dictionary in profiles:
		var spell: SpellDefinition = profile["spell"]
		if _target_hard_immune(state, content, target_id, spell): continue
		if not profile.get("physical", false) and spell.target_type != 6 and _target_reflects(state, target_id): continue
		if profile.get("targetKind") == &"monster" and state.combat.roster.monster_by_id(target_id) == null: continue
		if profile.get("targetKind") == &"character" and state.party.character_by_id(target_id) == null: continue
		var condition := ClassicSpellConditionRules.combat_condition_effect_index(spell)
		if condition >= 0 and _target_condition_value(state, target_id, condition) != 0: continue
		var radius := int(profile["range"])
		if state.combat.roster.monster_by_id(actor_id) != null:
			var size := state.combat.battlefield.actors.actor_size(actor_id)
			radius += (1 if size != 0 else 0) + (1 if size == 3 else 0)
		var require_los := spell.range_min + spell.range_max > 0
		var key := "%s:%d:%d" % [require_los, spell.target_type, _context.spell_areas.shape_for(spell, int(profile.get("power", 1)), int(profile.get("rotation", 0))) if spell.target_type in [3, 4] else 0]
		if not geometries.has(key) or radius > int(geometries[key]["radius"]):
			geometries[key] = {"profile": profile, "radius": radius, "los": require_los}
	var result: Array[Dictionary] = []
	result.assign(geometries.values())
	return result


func _append_profile(profiles: Array[Dictionary], spell: SpellDefinition, power: int) -> void:
	if spell == null or power < 1 or spell.cannot == 4 or not spell.target_type in [0, 1, 3, 4, 6]: return
	if CombatFlowSummoning.is_summon_spell(spell) or ClassicSpellSpecialEffectRules.is_combat_magic_detection_spell(spell): return
	if ClassicSpellConditionRules.is_combat_healing_spell(spell) or MagicRules.is_condition_cure_spell(spell) or ClassicSpellSpecialEffectRules.is_combat_spell_point_restore_spell(spell): return
	if expected_spell_effect(spell, power) <= 0 and ClassicSpellConditionRules.combat_condition_effect_index(spell) < 0 and not ClassicSpellSpecialEffectRules.is_combat_charm_spell(spell): return
	for rotation: int in (4 if spell.can_rotate and spell.target_type in [3, 4] else 1):
		profiles.append({"spell": spell, "power": power, "range": absi(spell.range_min + spell.range_max * power), "rotation": rotation})


func _centers(state: GameState, actor_id: String, target_id: String, profile: Dictionary, occupied: Dictionary) -> Array[Vector2i]:
	var field := state.combat.battlefield
	var spell: SpellDefinition = profile["spell"]
	if not spell.target_type in [3, 4]: return [field.actors.actor_position(target_id)]
	var shape := _context.spell_areas.shape_for(spell, int(profile["power"]), int(profile.get("rotation", 0)))
	var offsets := _context.spell_areas.pattern(shape)
	var result: Array[Vector2i] = []
	for target_cell: Vector2i in field.actors.actor_footprint(target_id):
		for offset: Vector2i in offsets:
			var center := target_cell - offset
			if result.has(center) or not _context.spell_areas.pattern_fits(center, shape): continue
			var safe := true
			for area_offset: Vector2i in offsets:
				var occupant := String(occupied.get(center + area_offset, ""))
				if not occupant.is_empty() and occupant != actor_id and _same_side(state, actor_id, occupant): safe = false
				if not occupant.is_empty() and _target_reflects(state, occupant): safe = false
			if safe: result.append(center)
	return result


func _position_is_safe(state: GameState, terrain: BattleTerrainSetDefinition, actor_id: String, anchor: Vector2i, center: Vector2i, profile: Dictionary, occupied: Dictionary, footprints: Dictionary) -> bool:
	var spell: SpellDefinition = profile["spell"]
	if not footprints.has(anchor):
		var cells := state.combat.battlefield.actors.actor_footprint_at(actor_id, anchor)
		var valid := true
		for cell: Vector2i in cells:
			if not BattlefieldGrid.contains(cell) or occupied.has(cell) and occupied[cell] != actor_id:
				valid = false
				break
			var tile := terrain.tile_by_id(state.combat.battlefield.terrain.tile_at(cell))
			if tile == null or tile.solid > (1 if cells.size() > 1 else 0):
				valid = false
				break
		footprints[anchor] = cells if valid else []
	var footprint: Array = footprints[anchor]
	if footprint.is_empty(): return false
	if spell.target_type in [3, 4]:
		for offset: Vector2i in _context.spell_areas.pattern(_context.spell_areas.shape_for(spell, int(profile["power"]), int(profile.get("rotation", 0)))):
			if footprint.has(center + offset): return false
	if spell.target_type == 6:
		for occupant: String in _context.battlefield.ray_actor_ids(state.combat.battlefield, terrain, actor_id, center, spell.range_min + spell.range_max > 0, anchor, occupied):
			if _same_side(state, actor_id, occupant): return false
	return true


static func _same_side(state: GameState, actor_id: String, target_id: String) -> bool:
	var character := state.party.character_by_id(actor_id)
	return CombatAiTargetFacts.character_is_friendly(state, character, target_id) if character != null else CombatAiTargetFacts.monster_is_friendly(state, state.combat.roster.monster_by_id(actor_id), target_id)
