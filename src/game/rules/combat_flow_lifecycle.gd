## Implements deterministic combat flow lifecycle rules without presentation dependencies.

class_name CombatFlowLifecycle
extends RefCounted

## Owns battle setup, initiative changes, round effects, and battle completion.


const MONSTER_ATTACK_COMPLETED := 0
const MONSTER_ATTACK_WAITING := 1
const MONSTER_ATTACK_DEATH_MACRO := 2
const MONSTER_ATTACK_FALLBACK := 3
const REACTION_COMPLETED := 0
const REACTION_WAITING := 1
const REACTION_DEATH_MACRO := 2
const REACTION_MOVER_DEFEATED := 3
const MAX_AUTO_OPERATIONS: int = 256
const INVALID_COORDINATE := Vector2i(-100_000, -100_000)
const CHARACTER_FUMBLE_SOUNDS: Array[Dictionary] = [
	{"soundId": 10121, "waitForCompletion": true},
	{"soundId": 10123, "waitForCompletion": true},
	{"soundId": 655, "waitForCompletion": false},
]
const MONSTER_FUMBLE_SOUNDS: Array[Dictionary] = [
	{"soundId": 10121, "waitForCompletion": true},
	{"soundId": 655, "waitForCompletion": true},
]


class ResumedAgeAttack extends RefCounted:
	var combat: CombatState
	var pending: PendingMonsterAttack
	var defeated := false

var _context: CombatContext


func _init(context: CombatContext) -> void:
	_context = context

func advance_turn(state: GameState, content: RealmzContent, rng: RealmzRng, events: Array[DomainEvent]) -> void:
	if state == null or state.combat == null:
		return
	var round_advanced := state.combat.advance_turn()
	for field: RefCounted in state.combat.spell_runtime.decay_persistent_fields_for_phase(state.combat.turns.turn_index):
		events.append(DomainEvent.new(&"combat_persistent_field_expired", {"slot": field.slot, "spellId": field.spell_id, "center": [field.center.x, field.center.y], "shape": field.shape, "queueIcon": field.queue_icon, "source": "classic"}))
	if round_advanced:
		_process_persistent_field_round_collisions(state, content, rng, events)
		process_bleeding_round(state, rng, events)


func _process_persistent_field_round_collisions(state: GameState, content: RealmzContent, rng: RealmzRng, events: Array[DomainEvent]) -> void:
	var combat := state.combat
	if combat == null or combat.battlefield == null or combat.spell_runtime.persistent_fields().is_empty():
		return
	var actor_ids: Array[String] = []
	for character: CharacterState in state.party.characters():
		if character.current_health > 0 and combat.battlefield.actors.has_actor(character.id):
			actor_ids.append(character.id)
	for monster: MonsterState in combat.roster.monsters():
		if monster.current_health > 0 and combat.battlefield.actors.has_actor(monster.id):
			actor_ids.append(monster.id)
	for actor_id: String in actor_ids:
		var result: int = _context.fields().resolve_actor_collisions(state, content, actor_id, rng, events, false, false)
		if result == CombatFlowFields.COLLISION_INVALID:
			events.append(DomainEvent.new(&"combat_persistent_field_collision_failed", {"actorId": actor_id, "reason": "invalid-runtime-state"}))
	if not combat.spell_runtime.pending_death_macro_id().is_empty() and not _context.fields().begin_pending_death_macros(combat, content, events):
		events.append(DomainEvent.new(&"combat_persistent_field_collision_failed", {"actorId": combat.turns.active_actor_id(), "reason": "invalid-death-macro-queue"}))


func process_bleeding_round(state: GameState, rng: RealmzRng, events: Array[DomainEvent]) -> void:
	var combat := state.combat
	for character: CharacterState in state.party.characters():
		if not combat.actor_statuses.is_character_bleeding(character.id):
			continue
		if character.current_health <= -10:
			combat.actor_statuses.set_character_bleeding(character.id, false)
			state.set_combat_auto(character.id, false)
			continue
		character.current_health = _context.arithmetic.signed_16(character.current_health - 1)
		if character.current_health < -9:
			character.lifetime_record.record_death(true)
			combat.actor_statuses.set_character_bleeding(character.id, false)
			state.set_combat_auto(character.id, false)
			_context.automation().remove_defeated_position(combat, character.id, true)
			events.append(DomainEvent.new(&"sound_requested", {"soundId": 132, "waitForCompletion": false, "source": "classic-combat-bleeding"}))
			events.append(DomainEvent.new(&"combatant_bled_to_death", {"characterId": character.id, "health": character.current_health, "source": "classic"}))
			continue
		var roll := rng.draw(100, StringName("combat.bleeding.%s" % character.id))
		var sound_id := 10121 if roll < 50 else 10123
		events.append(DomainEvent.new(&"sound_requested", {"soundId": sound_id, "waitForCompletion": false, "source": "classic-combat-bleeding"}))
		events.append(DomainEvent.new(&"combatant_bleeding_progressed", {"characterId": character.id, "health": character.current_health, "roll": roll, "soundId": sound_id, "source": "classic"}))
	if not _context.actions().bandage_candidate_ids(state).is_empty():
		# getup.c performs a second, party-wide warning draw after every
		# individual bleeding result when the Classic warning preference is on.
		# Realmz Rebuilt currently preserves that default; exposing the preference
		# itself remains owned by the settings workflow.
		var warning_roll := rng.draw(100, &"combat.bleeding.warning-sound")
		var warning_sound_id := 10121 if warning_roll < 50 else 10123
		events.append(DomainEvent.new(&"sound_requested", {"soundId": warning_sound_id, "waitForCompletion": false, "source": "classic-combat-bleeding-warning"}))
		events.append(DomainEvent.new(&"combat_bleeding_warning", {"roll": warning_roll, "soundId": warning_sound_id, "source": "classic-default"}))


func continue_after_monster_death_macro(state: GameState, content: RealmzContent, rng: RealmzRng, completed_combatant_id: String = "") -> CombatFlowResult:
	if state == null or content == null or rng == null or state.combat == null:
		return CombatFlowResult.failed(&"invalid_death_macro_continuation", "Monster death-macro continuation requires an active battle.")
	var events: Array[DomainEvent] = []
	if not state.combat.spell_runtime.pending_death_macro_id().is_empty():
		var expected_id := state.combat.spell_runtime.pending_death_macro_id()
		if completed_combatant_id.is_empty():
			completed_combatant_id = expected_id
		if not state.combat.spell_runtime.complete_death_macro(completed_combatant_id):
			return CombatFlowResult.failed(&"invalid_spell_death_macro_queue", "The completed spell death macro does not match the saved queue cursor.")
		var completed_monster := state.combat.roster.monster_by_id(completed_combatant_id)
		var same_subject_remains := state.combat.spell_runtime.death_macro_queue().has(completed_combatant_id)
		_context.automation().remove_defeated_position(state.combat, completed_combatant_id, completed_monster != null and completed_monster.current_health <= 0 and not same_subject_remains)
		if not state.combat.spell_runtime.pending_death_macro_id().is_empty():
			if not _context.actions().events().request_next_spell_death_macro(state.combat, content, events):
				return CombatFlowResult.failed(&"invalid_spell_death_macro_queue", "The next queued spell death macro references unavailable content.")
			return CombatFlowResult.succeeded(events)
		var spell_actor_id := state.combat.spell_runtime.macro_actor_id()
		var advances_turn := state.combat.spell_runtime.macro_advances_turn()
		if advances_turn:
			if state.combat.turns.active_actor_id() != spell_actor_id:
				return CombatFlowResult.failed(&"invalid_spell_death_macro_queue", "The active caster changed before the queued spell action completed.")
		state.combat.spell_runtime.clear_death_macro_sequence()
		if advances_turn:
			advance_turn(state, content, rng, events)
	_context.automation().remove_all_defeated_positions(state)
	if state.combat.pending_reaction != null:
		var reaction := state.combat.pending_reaction
		var mover_id := reaction.mover_id
		if _context.reactions().combatant_is_alive(state, mover_id):
			reaction.mover_killed = false
			var reaction_result = _context.reactions().continue_pending_reaction(state, content, rng, events)
			if reaction_result == REACTION_WAITING or reaction_result == REACTION_DEATH_MACRO:
				return CombatFlowResult.succeeded(events)
			if reaction_result == REACTION_COMPLETED:
				_context.automation().process_monster_turns(state, content, rng, events)
				return CombatFlowResult.succeeded(events, state.combat.completed)
		else:
			state.combat.pending_reaction = null
		if state.combat.turns.active_actor_id() == mover_id:
			advance_turn(state, content, rng, events)
	if state.combat.completed or finish_if_resolved(state, content, events):
		return CombatFlowResult.succeeded(events, true)
	_context.automation().process_monster_turns(state, content, rng, events)
	return CombatFlowResult.succeeded(events, state.combat.completed)


func finalize_scenario_monster_destruction(state: GameState, content: RealmzContent) -> CombatFlowResult:
	if state == null or content == null or state.combat == null:
		return CombatFlowResult.failed(&"no_active_battle", "Classic monster destruction requires an active battle.")
	var events: Array[DomainEvent] = []
	_context.automation().remove_all_defeated_positions(state)
	if not state.combat.completed:
		finish_if_resolved(state, content, events)
	return CombatFlowResult.succeeded(events, state.combat.completed)


func continue_after_age_update(state: GameState, content: RealmzContent, rng: RealmzRng) -> CombatFlowResult:
	if state == null or content == null or rng == null or state.combat == null or state.combat.pending_monster_attack == null:
		return CombatFlowResult.failed(&"invalid_age_update_continuation", "Monster age-update continuation requires an active battle.")
	var events: Array[DomainEvent] = []
	var resumed_value: Variant = _commit_resumed_age_attack(state, content, rng, events)
	if resumed_value is CombatFlowResult:
		return resumed_value
	var resumed: ResumedAgeAttack = resumed_value
	var combat := resumed.combat
	var pending := resumed.pending
	if combat.pending_reaction != null:
		return _continue_after_age_reaction(state, content, rng, events, resumed)
	if finish_if_resolved(state, content, events):
		return CombatFlowResult.succeeded(events, true)
	var monster := combat.roster.monster_by_id(pending.actor_id)
	var definition := content.combat.monster_by_id(monster.definition_id) if monster != null else null
	if combat.turns.active_turn == null or combat.turns.active_turn.actor_id != pending.actor_id or pending.action != &"advance" or definition == null or combat.turns.active_turn.attack_index >= _context.automation().monster_actions().attack_limit(definition):
		advance_turn(state, content, rng, events)
	elif resumed.defeated:
		combat.turns.active_turn.target_id = ""
	_context.automation().process_monster_turns(state, content, rng, events)
	return CombatFlowResult.succeeded(events, state.combat.completed)


func _commit_resumed_age_attack(state: GameState, content: RealmzContent, rng: RealmzRng, events: Array[DomainEvent]) -> Variant:
	var result := ResumedAgeAttack.new()
	result.combat = state.combat
	result.pending = result.combat.pending_monster_attack
	var target := state.party.character_by_id(result.pending.target_id)
	if target == null:
		return CombatFlowResult.failed(&"invalid_age_update_continuation", "The pending monster attack target is unavailable.")
	if result.pending.weapon_condition_index >= 0:
		if target.conditions.value(result.pending.weapon_condition_index) != result.pending.weapon_condition_before:
			return CombatFlowResult.failed(&"invalid_age_update_continuation", "The pending monster weapon condition no longer matches its saved boundary.")
		target.conditions.set_value(result.pending.weapon_condition_index, result.pending.weapon_condition_after)
	_context.actions().events().append_monster_physical_feedback(events, result.pending.physical_feedback_sound_id)
	target.current_health -= result.pending.damage
	if result.pending.damage > 0:
		result.combat.actor_statuses.mark_attacked(target.id)
	result.defeated = target.current_health <= 0
	_context.actions().mark_character_bleeding(state, target, result.defeated)
	_context.automation().remove_defeated_position(result.combat, target.id, result.defeated)
	var attack_index := maxi(0, result.combat.turns.active_turn.attack_index - 1) if result.combat.turns.active_turn != null and result.combat.pending_reaction == null else 0
	var attacker := result.combat.roster.monster_by_id(result.pending.actor_id)
	var definition := content.combat.monster_by_id(attacker.definition_id) if attacker != null else null
	var weapon := content.items.item_by_id(attacker.weapon_id) if attacker != null and not attacker.weapon_id.is_empty() else null
	var resolution := AttackResolution.new(true, result.defeated, result.pending.chance, result.pending.roll, result.pending.damage)
	_context.actions().events().append_monster_attack_audio(events, attacker, definition, attack_index, weapon, resolution, rng)
	var event := DomainEvent.new(&"combat_attack_resolved", {"actorId": result.pending.actor_id, "targetId": result.pending.target_id, "action": String(result.pending.action), "attackIndex": attack_index, "hit": true, "damage": result.pending.damage, "defeated": result.defeated, "chance": result.pending.chance, "roll": result.pending.roll})
	_context.actions().events().append_physical_result_effect(event, true, weapon != null)
	if result.combat.pending_reaction != null:
		_context.reactions().append_reaction_identity(event, result.pending.action, result.pending.action == &"withdrawal")
	events.append(event)
	result.combat.pending_monster_attack = null
	return result


func _continue_after_age_reaction(state: GameState, content: RealmzContent, rng: RealmzRng, events: Array[DomainEvent], resumed: ResumedAgeAttack) -> CombatFlowResult:
	var combat := resumed.combat
	var reaction_kind := combat.pending_reaction.kind
	var mover_id := combat.pending_reaction.mover_id
	if resumed.defeated:
		combat.pending_reaction.mover_killed = true
	var reaction_result = _context.reactions().continue_pending_reaction(state, content, rng, events)
	if reaction_result == REACTION_WAITING or reaction_result == REACTION_DEATH_MACRO:
		return CombatFlowResult.succeeded(events)
	if reaction_result == REACTION_MOVER_DEFEATED:
		if combat.turns.active_actor_id() == mover_id:
			advance_turn(state, content, rng, events)
		if finish_if_resolved(state, content, events):
			return CombatFlowResult.succeeded(events, true)
		_context.automation().process_monster_turns(state, content, rng, events)
		return CombatFlowResult.succeeded(events, state.combat.completed)
	if reaction_kind == CombatReactionState.CHARACTER_MOVE:
		return CombatFlowResult.succeeded(events)
	_context.automation().process_monster_turns(state, content, rng, events)
	return CombatFlowResult.succeeded(events, state.combat.completed)


func ally_selection_payload(state: GameState, content: RealmzContent) -> Dictionary:
	if state == null or content == null or state.combat == null or not state.combat.completed or state.allies_suspended:
		return {}
	var candidates: Array[Dictionary] = []
	for monster: MonsterState in state.combat.roster.monsters():
		if candidates.size() >= 32 or monster.current_health <= 0 or monster.traitor:
			continue
		var definition := content.combat.monster_by_id(monster.definition_id)
		if definition == null or definition.can_summon == 0:
			continue
		candidates.append({
			"id": monster.id,
			"name": monster.name,
			"currentHealth": monster.current_health,
			"maximumHealth": monster.maximum_health,
			"classicMonsterId": definition.classic_id,
			"required": definition.can_summon < 0,
			"canSummon": definition.can_summon,
		})
	# Castle bodycount.c returns before creating Dialog 173 when count is zero.
	# An empty choice is not an interaction boundary and must not stall battle return.
	if candidates.is_empty():
		return {}
	# bodycount.c promotes mandatory allies and then orders optional survivors by stamina.
	for _pass: int in range(maxi(0, candidates.size() - 1)):
		for index: int in range(maxi(0, candidates.size() - 1)):
			var current: Dictionary = candidates[index]
			var following: Dictionary = candidates[index + 1]
			if int(current["currentHealth"]) < int(following["currentHealth"]) or int(following["canSummon"]) < 0:
				candidates[index] = following
				candidates[index + 1] = current
	var required_ids: Array[String] = []
	for candidate: Dictionary in candidates:
		if candidate["required"]:
			required_ids.append(candidate["id"])
	var maximum := mini(18, 4 + required_ids.size())
	var selected_ids: Array[String] = required_ids.duplicate()
	for index: int in range(mini(10, candidates.size())):
		var candidate_id: String = candidates[index]["id"]
		if selected_ids.size() < maximum and not selected_ids.has(candidate_id):
			selected_ids.append(candidate_id)
	return {
		"prompt": "Choose the allies who will continue with the party.",
		"candidates": candidates,
		"requiredIds": required_ids,
		"maximum": maximum,
		"selectedIds": selected_ids,
	}


func apply_ally_selection(state: GameState, content: RealmzContent, selected_value: Variant) -> CombatFlowResult:
	var payload := ally_selection_payload(state, content)
	if payload.is_empty() or not selected_value is Array:
		return CombatFlowResult.failed(&"invalid_ally_selection", "The post-battle ally selection is unavailable.")
	var selected_ids: Array[String] = []
	for value: Variant in selected_value:
		if not value is String or value.is_empty() or selected_ids.has(value):
			return CombatFlowResult.failed(&"invalid_ally_selection", "Selected allies must be unique stable IDs.")
		selected_ids.append(value)
	if selected_ids.size() > int(payload["maximum"]):
		return CombatFlowResult.failed(&"invalid_ally_selection", "The ally selection exceeds the Classic body-count limit.")
	var candidate_ids: Array[String] = []
	for candidate: Dictionary in payload["candidates"]:
		candidate_ids.append(candidate["id"])
	for required_id: String in payload["requiredIds"]:
		if not selected_ids.has(required_id):
			return CombatFlowResult.failed(&"required_ally_missing", "A scenario-mandatory ally cannot be left behind.")
	for selected_id: String in selected_ids:
		if not candidate_ids.has(selected_id):
			return CombatFlowResult.failed(&"invalid_ally_selection", "The ally selection contains an unavailable combatant.")
	var retained: Array[MonsterState] = []
	for selected_id: String in selected_ids:
		var monster := state.combat.roster.monster_by_id(selected_id)
		if monster == null:
			return CombatFlowResult.failed(&"invalid_ally_selection", "The selected combatant is unavailable.")
		monster.traitor = false
		retained.append(monster)
	state.party.set_allies(retained)
	return CombatFlowResult.succeeded([DomainEvent.new(&"allies_selected", {"battleId": state.combat.battle_id, "allyIds": selected_ids, "maximum": payload["maximum"]})], true)


func fumble_recovery_payload(state: GameState, content: RealmzContent) -> Dictionary:
	if state == null or content == null or state.combat == null or not state.combat.completed:
		return {}
	var queued := state.combat.dropped_items.items()
	if queued.is_empty():
		return {}
	var item: ItemInstance = queued[0]
	var definition := content.items.item_by_id(item.definition_id)
	if definition == null:
		return {}
	var candidates: Array[Dictionary] = []
	for character: CharacterState in state.party.characters():
		var enabled := _context.inventory.can_restore_item(character, item, definition)
		var reason := ""
		if character.inventory().size() >= InventoryRules.MAX_ITEMS:
			reason = "Inventory is full."
		elif character.carried_load + definition.instance_weight(item.charges) > character.maximum_load:
			reason = "The item would exceed maximum load."
		elif not enabled:
			reason = "This character cannot receive the item."
		candidates.append({
			"id": character.id,
			"name": character.name,
			"currentHealth": character.current_health,
			"maximumHealth": character.maximum_health,
			"enabled": enabled,
			"reason": reason,
		})
	return {
		"mode": "fumbled-item-recovery",
		"prompt": "Recover the fumbled weapon or leave it behind.",
		"battleId": state.combat.battle_id,
		"item": {
			"instanceId": item.id,
			"definitionId": item.definition_id,
			"name": definition.name,
			"charges": item.charges,
			"identified": true,
			"description": definition.description,
			"facts": _fumbled_item_facts(item, definition),
		},
		"characters": candidates,
		"remaining": queued.size(),
	}


static func _fumbled_item_facts(item: ItemInstance, definition: ItemDefinition) -> Array[Dictionary]:
	var facts: Array[Dictionary] = [{"label": "Weight", "value": str(definition.instance_weight(item.charges))}]
	if definition.hands != 0:
		facts.append({"label": "Hands", "value": str(definition.hands)})
	if definition.vs_small != 0:
		facts.append({"label": "Damage", "value": "%d–%d" % [1 + definition.damage_bonus, definition.damage_bonus + definition.vs_small]})
	if definition.vs_large != 0:
		facts.append({"label": "Large damage", "value": "%d–%d" % [1 + definition.damage_bonus, definition.damage_bonus + definition.vs_large]})
	if definition.armor_bonus != 0:
		facts.append({"label": "Armor", "value": "%+d" % definition.armor_bonus})
	_append_nonzero_fumble_fact(facts, "Damage bonus", definition.damage_bonus)
	_append_nonzero_fumble_fact(facts, "Strength", definition.strength_bonus)
	_append_nonzero_fumble_fact(facts, "Luck", definition.luck_bonus)
	_append_nonzero_fumble_fact(facts, "Movement", definition.movement_bonus)
	_append_nonzero_fumble_fact(facts, "Magic resistance", definition.magic_resistance_bonus)
	_append_nonzero_fumble_fact(facts, "Spell points", definition.spell_point_bonus)
	_append_nonzero_fumble_fact(facts, "Heat damage", definition.heat)
	_append_nonzero_fumble_fact(facts, "Cold damage", definition.cold)
	_append_nonzero_fumble_fact(facts, "Electrical damage", definition.electric)
	_append_nonzero_fumble_fact(facts, "Versus undead", definition.vs_undead)
	_append_nonzero_fumble_fact(facts, "Versus demons/devils", definition.vs_demon_devil)
	_append_nonzero_fumble_fact(facts, "Versus evil", definition.vs_evil)
	if item.charges > 0:
		facts.append({"label": "Charges", "value": str(item.charges)})
	return facts


static func _append_nonzero_fumble_fact(facts: Array[Dictionary], label: String, value: int) -> void:
	if value != 0:
		facts.append({"label": label, "value": "%+d" % value})


func apply_fumble_recovery(state: GameState, content: RealmzContent, action: StringName, instance_id: String, character_id: String = "") -> CombatFlowResult:
	var request_payload := fumble_recovery_payload(state, content)
	if request_payload.is_empty():
		return CombatFlowResult.failed(&"invalid_fumble_recovery", "Fumbled-weapon recovery is unavailable.")
	if instance_id != request_payload["item"]["instanceId"]:
		return CombatFlowResult.failed(&"invalid_fumble_recovery", "Fumbled-weapon recovery must identify the pending item and action.")
	if action == &"discard":
		var discarded := state.combat.dropped_items.remove(instance_id)
		if discarded == null:
			return CombatFlowResult.failed(&"invalid_fumble_recovery", "The pending fumbled weapon is unavailable.")
		return CombatFlowResult.succeeded([DomainEvent.new(&"fumbled_item_left_behind", {"battleId": state.combat.battle_id, "instanceId": discarded.id, "itemId": discarded.definition_id})])
	if action != &"assign" or character_id.is_empty():
		return CombatFlowResult.failed(&"invalid_fumble_recovery", "Fumbled-weapon recovery requires an available character or discard action.")
	var candidate: Dictionary = {}
	for entry: Dictionary in request_payload["characters"]:
		if entry["id"] == character_id:
			candidate = entry
			break
	if candidate.is_empty() or not candidate["enabled"]:
		return CombatFlowResult.failed(&"invalid_fumble_recovery", "The selected character cannot receive the fumbled weapon.")
	var character := state.party.character_by_id(character_id)
	var queued: ItemInstance = state.combat.dropped_items.items()[0]
	var definition := content.items.item_by_id(queued.definition_id)
	if character == null or definition == null or not _context.inventory.can_restore_item(character, queued, definition):
		return CombatFlowResult.failed(&"invalid_fumble_recovery", "The selected character can no longer receive the fumbled weapon.")
	var recovered := state.combat.dropped_items.remove(instance_id)
	if recovered == null or not _context.inventory.restore_item(character, recovered, definition):
		if recovered != null:
			state.combat.dropped_items.requeue_first(recovered)
		return CombatFlowResult.failed(&"invalid_fumble_recovery", "The fumbled weapon could not be restored atomically.")
	return CombatFlowResult.succeeded([DomainEvent.new(&"fumbled_item_recovered", {"battleId": state.combat.battle_id, "instanceId": recovered.id, "itemId": recovered.definition_id, "characterId": character.id})])


func finish_if_resolved(state: GameState, content: RealmzContent, events: Array[DomainEvent]) -> bool:
	state.prune_combat_auto_characters()
	var combat := state.combat
	if not combat.spell_runtime.pending_death_macro_id().is_empty() or not combat.spell_runtime.macro_actor_id().is_empty():
		return false
	var enemies_alive := false
	for character: CharacterState in state.party.characters():
		if character.current_health > 0 and character.traitor and combat.battlefield != null and combat.battlefield.actors.has_actor(character.id):
			enemies_alive = true
			break
	for monster: MonsterState in combat.roster.monsters():
		if monster.current_health > 0 and monster.traitor and combat.battlefield != null and combat.battlefield.actors.has_actor(monster.id):
			enemies_alive = true
			break
	var party_alive := has_loyal_battlefield_character(state)
	if enemies_alive and party_alive:
		return false
	var outcome: StringName = &"victory" if party_alive else &"retreated" if has_living_retreated_character(state) else &"defeat"
	complete_battle(state, content, outcome, events)
	return true


func finish_classic_macro_victory(state: GameState, content: RealmzContent) -> CombatFlowResult:
	if state == null or content == null or state.combat == null or state.combat.completed:
		return CombatFlowResult.failed(&"no_active_battle", "Classic opcode 100 requires an active battle macro.")
	var defeated: Array[String] = []
	for monster: MonsterState in state.combat.roster.monsters():
		if monster.current_health > 0 and monster.traitor:
			monster.current_health = 0
			state.combat.battlefield.actors.remove_monster(monster.id)
			defeated.append(monster.id)
	state.combat.classic_post_battle_sentinel = 8
	var events: Array[DomainEvent] = [DomainEvent.new(&"classic_battle_forced_victory", {"battleId": state.combat.battle_id, "monsterIds": defeated, "rewardMode": 5, "postBattleSentinel": 8})]
	complete_battle(state, content, &"victory", events)
	return CombatFlowResult.succeeded(events, true)


func complete_battle(state: GameState, _content: RealmzContent, outcome: StringName, events: Array[DomainEvent]) -> void:
	var combat := state.combat
	combat.completed = true
	combat.outcome = outcome
	combat.turns.clear_active_turn()
	state.last_battle_outcome = combat.outcome
	restore_party_allegiance(state, events)
	events.append(DomainEvent.new(&"battle_completed", {"battleId": combat.battle_id, "outcome": String(combat.outcome)}))


static func has_loyal_battlefield_character(state: GameState) -> bool:
	if state.combat == null or state.combat.battlefield == null:
		return false
	for character: CharacterState in state.party.characters():
		if character.current_health > 0 and not character.traitor and state.combat.battlefield.actors.has_actor(character.id):
			return true
	return false


static func has_living_retreated_character(state: GameState) -> bool:
	if state.combat == null or state.combat.battlefield == null:
		return false
	for character: CharacterState in state.party.characters():
		if character.current_health > 0 and not character.traitor and state.combat.actor_statuses.has_character_retreated(character.id):
			return true
	return false


func restore_party_allegiance(state: GameState, events: Array[DomainEvent]) -> void:
	var restored_ids: Array[String] = []
	for character: CharacterState in state.party.characters():
		if character.traitor:
			character.traitor = false
			restored_ids.append(character.id)
	if not restored_ids.is_empty():
		events.append(DomainEvent.new(&"combat_allegiance_restored", {"characterIds": restored_ids}))
