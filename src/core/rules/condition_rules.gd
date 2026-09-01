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


func tick_character(character: CharacterState) -> Array[DomainEvent]:
	var events: Array[DomainEvent] = []
	if character.conditions.is_active(REGENERATING) and character.current_health > -10 and character.current_health < character.maximum_health and not character.conditions.is_active(ANIMATED):
		var healed := mini(absi(character.conditions.value(REGENERATING)), character.maximum_health - character.current_health)
		character.current_health += healed
		events.append(DomainEvent.new(&"condition_healed", {"characterId": character.id, "condition": REGENERATING, "amount": healed}))
	for index: int in [DISEASED, POISONED]:
		if character.conditions.is_active(index) and character.current_health > 0 and character.conditions.value(ANIMATED) > -1:
			var damage := absi(character.conditions.value(index))
			character.current_health -= damage
			events.append(DomainEvent.new(&"condition_damaged", {"characterId": character.id, "condition": index, "amount": damage}))
	if character.conditions.is_active(ENERGY_DRAIN) and character.current_health > 0:
		character.spell_points = maxi(0, character.spell_points - absi(character.conditions.value(ENERGY_DRAIN)))
	if character.conditions.is_active(ABSORBING_ENERGY) and character.maximum_spell_points > 0 and character.current_health > 0:
		character.spell_points = mini(character.maximum_spell_points, character.spell_points + absi(character.conditions.value(ABSORBING_ENERGY)))
	for index: int in character.conditions.decay_positive():
		events.append(DomainEvent.new(&"condition_expired", {"characterId": character.id, "condition": index}))
	return events


func tick_party(party: PartyState) -> Array[DomainEvent]:
	var events: Array[DomainEvent] = []
	for index: int in party.conditions.decay_positive():
		events.append(DomainEvent.new(&"party_condition_expired", {"condition": index}))
	# Castle reduces every positive party condition once, then reduces Torch Lit
	# once more. Values already expired by the shared pass are not decremented again.
	if party.conditions.value(PARTY_TORCH_LIT) > 0:
		party.conditions.add(PARTY_TORCH_LIT, -1)
		if party.conditions.value(PARTY_TORCH_LIT) == 0:
			events.append(DomainEvent.new(&"party_condition_expired", {"condition": PARTY_TORCH_LIT}))
	for character: CharacterState in party.characters():
		events.append_array(tick_character(character))
	for ally: MonsterState in party.allies():
		for index: int in ally.conditions.decay_positive():
			events.append(DomainEvent.new(&"ally_condition_expired", {"allyId": ally.id, "condition": index}))
	return events
