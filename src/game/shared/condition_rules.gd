## Implements deterministic condition rules without presentation dependencies.

class_name ConditionRules
extends RefCounted

const RUNS_AWAY := 0
const HELPLESS := 1
const TANGLED := 2
const CURSED := 3
const MAGIC_AURA := 4
const STUPID := 5
const SLOW := 6
const SHIELD_FROM_HITS := 7
const SHIELD_FROM_PROJECTILES := 8
const POISONED := 9
const REGENERATING := 10
const FIRE_PROTECTION := 11
const COLD_PROTECTION := 12
const ELECTRICAL_PROTECTION := 13
const CHEMICAL_PROTECTION := 14
const MENTAL_PROTECTION := 15
const STRONG := 21
const PROTECTION_FROM_EVIL := 22
const SPEEDY := 23
const INVISIBLE := 24
const ANIMATED := 25
const TURNED_TO_STONE := 26
const BLIND := 27
const DISEASED := 28
const CONFUSED := 29
const REFLECTING_SPELLS := 30
const REFLECTING_ATTACKS := 31
const ATTACK_BONUS := 32
const ABSORBING_ENERGY := 33
const ENERGY_DRAIN := 34
const ABSORBING_ENERGY_FROM_ATTACKS := 35
const HINDERED_ATTACKS := 36
const HINDERED_DEFENSE := 37
const DEFENSE_BONUS := 38
const SILENCED := 39

const PARTY_DRAGON_HIDE := 2
const PARTY_DISCOVER_SECRET := 3
const PARTY_CHARM_RESISTANCE := 8
const PARTY_TORCH_LIT := 0
const PARTY_WIZARDS_EYE := 4
const PARTY_SEARCHING := 5


func tick_character(character: CharacterState, in_combat: bool = false, arithmetic: RealmzArithmetic = null) -> Array[DomainEvent]:
	var events: Array[DomainEvent] = []
	if character.conditions.is_active(REGENERATING) and (character.current_health > 0 if in_combat else character.current_health > -10) and character.current_health < character.maximum_health and not character.conditions.is_active(ANIMATED):
		var healed := mini(absi(character.conditions.value(REGENERATING)), character.maximum_health - character.current_health)
		if not in_combat or not character.conditions.is_active(TURNED_TO_STONE):
			var regenerated := character.current_health + absi(character.conditions.value(REGENERATING))
			character.current_health = mini(character.maximum_health, maxi(-10, arithmetic.signed_16(regenerated))) if arithmetic != null else character.current_health + healed
		var payload := {"characterId": character.id, "condition": REGENERATING, "amount": absi(character.conditions.value(REGENERATING)) if in_combat else healed}
		if in_combat: payload.merge({"health": character.current_health, "combat": true})
		events.append(DomainEvent.new(&"condition_healed", payload))
	for index: int in [DISEASED, POISONED]:
		if character.conditions.is_active(index) and character.current_health > 0 and character.conditions.value(ANIMATED) > -1:
			var damage := absi(character.conditions.value(index))
			character.current_health = arithmetic.signed_16(character.current_health - damage) if arithmetic != null else character.current_health - damage
			var payload := {"characterId": character.id, "condition": index, "amount": damage}
			if in_combat: payload.merge({"health": character.current_health, "combat": true})
			events.append(DomainEvent.new(&"condition_damaged", payload))
	if character.conditions.is_active(ENERGY_DRAIN) and character.current_health > 0:
		var drained := character.spell_points - absi(character.conditions.value(ENERGY_DRAIN))
		character.spell_points = maxi(0, arithmetic.signed_16(drained) if arithmetic != null else drained)
	if character.conditions.is_active(ABSORBING_ENERGY) and (character.maximum_spell_points != 0 if in_combat else character.maximum_spell_points > 0) and character.current_health > 0:
		var absorbed := character.spell_points + absi(character.conditions.value(ABSORBING_ENERGY))
		character.spell_points = mini(character.maximum_spell_points, arithmetic.signed_16(absorbed) if arithmetic != null else absorbed)
	if in_combat and character.conditions.is_active(CONFUSED) and character.traitor:
		character.traitor = false
		events.append(DomainEvent.new(&"combat_allegiance_restored", {"characterIds": [character.id]}))
	for index: int in character.conditions.decay_positive():
		var payload := {"characterId": character.id, "condition": index}
		if index == HELPLESS:
			payload["helplessBefore"] = true
			payload["helplessAfter"] = false
		events.append(DomainEvent.new(&"condition_expired", payload))
	return events


func tick_party_conditions(party: PartyState) -> Array[DomainEvent]:
	var events: Array[DomainEvent] = []
	for index: int in party.conditions.decay_positive():
		events.append(DomainEvent.new(&"party_condition_expired", {"condition": index}))
	# Castle reduces every positive party condition once, then reduces Torch Lit
	# once more. Values already expired by the shared pass are not decremented again.
	if party.conditions.value(PARTY_TORCH_LIT) > 0:
		party.conditions.add(PARTY_TORCH_LIT, -1)
		if party.conditions.value(PARTY_TORCH_LIT) == 0:
			events.append(DomainEvent.new(&"party_condition_expired", {"condition": PARTY_TORCH_LIT}))
	return events


func tick_party(party: PartyState) -> Array[DomainEvent]:
	var events := tick_party_conditions(party)
	for character: CharacterState in party.characters():
		events.append_array(tick_character(character))
	for ally: MonsterState in party.allies():
		for index: int in ally.conditions.decay_positive():
			var payload := {"allyId": ally.id, "condition": index}
			if index == HELPLESS:
				payload["helplessBefore"] = true
				payload["helplessAfter"] = false
			events.append(DomainEvent.new(&"ally_condition_expired", payload))
	return events
