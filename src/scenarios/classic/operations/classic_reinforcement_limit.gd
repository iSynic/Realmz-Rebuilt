## Applies the Limit Monster Reinforcements adventure rule. Classic battles can carry a round
## script that rolls each round to bring in more monsters, with no cap but the 100-monster limit.
## The rule counts waves: each round in which that script brings in monsters is one wave.

class_name ClassicReinforcementLimit
extends RefCounted

## Opcodes of a script that only brings in monsters: text, sound, keep codes, spawn, and
## continue if a monster is present. A script with anything else also carries story effects.
const REINFORCEMENT_ONLY_OPCODES: Array[int] = [0, 1, 9, 24, 124, 127]


## Whether a spawn may go ahead. The first spawn of a round script's run uses up one wave; later
## spawns in the same run belong to that wave. Spawns from anything but the round script, such
## as a monster's death script, are never limited.
static func admit_spawn(state: GameState) -> bool:
	var limit := state.adventure_rules.reinforcement_limit
	if limit == AdventureRules.UNLIMITED_REINFORCEMENTS or not _in_round_script(state):
		return true
	var combat := state.combat
	if combat.reinforcement_waves > 0 and combat.reinforcement_wave_round == combat.turns.round_number:
		return true
	if combat.reinforcement_waves >= limit:
		return false
	combat.reinforcement_waves += 1
	combat.reinforcement_wave_round = combat.turns.round_number
	return true


## True when the round script is about to branch to `program` but no wave is left for it, and
## the program does nothing besides bring in monsters. The whole branch is then skipped, so its
## "more join the fight" text doesn't appear when nobody comes.
static func blocks_branch(state: GameState, program: ScenarioProgramDefinition) -> bool:
	var limit := state.adventure_rules.reinforcement_limit
	if limit == AdventureRules.UNLIMITED_REINFORCEMENTS or program == null or not _in_round_script(state):
		return false
	var combat := state.combat
	if combat.reinforcement_waves < limit or combat.reinforcement_wave_round == combat.turns.round_number:
		return false
	var spawns := false
	for index: int in program.instruction_count():
		var instruction: Variant = program.instruction_at(index)
		if not instruction is ClassicActionDefinition:
			return false
		var action: ClassicActionDefinition = instruction
		if not REINFORCEMENT_ONLY_OPCODES.has(action.opcode):
			return false
		spawns = spawns or action.opcode == 124
	return spawns


static func _in_round_script(state: GameState) -> bool:
	var combat := state.combat
	return combat != null and combat.round_cursor != null and combat.round_cursor.phase == &"battle-macro" and combat.death_macros.actor_id().is_empty()
