## Applies Castle getup.c start-of-activation conditions and runs forced party activations.

class_name CombatActivationConditions
extends RefCounted

const CONTINUE := &"continue"
const BREAK := &"break"
const RETURN := &"return"
const ANIMATED_ACTION := &"advance"
const FLEEING_ACTION := &"retreat"
const REACTION_WAITING := 1
const REACTION_DEATH_MACRO := 2
const REACTION_MOVER_DEFEATED := 3
const CONFUSION_UNCHANGED := &"unchanged"
const CONFUSION_TURNED := &"turned"
const CONFUSION_RECOVERED := &"recovered"
const CONFUSION_FLEEING := &"fleeing"
const CONFUSION_HELPLESS := &"helpless"

var failure_result: CombatFlowResult
var _context: CombatContext
var _animated: CombatCharmedCharacterAutomation
var _frightened: CombatFrightenedCharacterAutomation


func _init(context: CombatContext, monster_actions: CombatMonsterActions) -> void:
	_context = context
	_animated = CombatCharmedCharacterAutomation.new(context, monster_actions)
	_frightened = CombatFrightenedCharacterAutomation.new(context, monster_actions)


## True while charm, confusion or fear owns the active party actor's activation.
static func automates(combat: CombatState, character: CharacterState) -> bool:
	if combat == null or character == null or combat.turns.active_actor_id() != character.id:
		return false
	var turn := combat.turns.active_turn
	return character.traitor or turn != null and turn.action in [ANIMATED_ACTION, FLEEING_ACTION]


## Runs the active character's forced activation, or prepares it for manual control.
func process_character(state: GameState, content: RealmzContent, character: CharacterState, rng: RealmzRng, events: Array[DomainEvent]) -> StringName:
	failure_result = null
	var combat := state.combat
	if combat.turns.active_turn == null:
		if not _begin_character(state, character, rng, events):
			return _finish_activation(state, content, rng, events)
		# A confused last loyal character defects before acting, as Castle's partyloss check runs first.
		if character.traitor and _context.rounds().finish_if_resolved(state, content, events):
			return BREAK
	var action := combat.turns.active_turn.action
	if action == FLEEING_ACTION:
		var flight := _frightened.run(state, content, character, rng, events)
		if flight in [REACTION_WAITING, REACTION_DEATH_MACRO]:
			return RETURN
		return BREAK if flight == CombatFrightenedCharacterAutomation.RELEASED else _finish_activation(state, content, rng, events)
	if character.traitor or action == ANIMATED_ACTION:
		return _run_animated(state, content, character, rng, events)
	return BREAK


## Castle getup.c:284-299 confusion; true when the monster loses this activation.
func confused_monster_loses_turn(state: GameState, monster: MonsterState, rng: RealmzRng, events: Array[DomainEvent]) -> bool:
	if not monster.conditions.is_active(ConditionRules.CONFUSED):
		return false
	var outcome := _roll_confusion(monster.id, monster.traitor, monster.conditions, true, rng, events)
	if outcome == CONFUSION_TURNED:
		monster.classic_traitor = 1
	elif outcome == CONFUSION_RECOVERED:
		monster.classic_traitor = 0
	state.combat.reconcile_classic_counters(state.party)
	return outcome == CONFUSION_HELPLESS


func _begin_character(state: GameState, character: CharacterState, rng: RealmzRng, events: Array[DomainEvent]) -> bool:
	# Castle getup.c:209-210 skips a helpless character before charm, fear, confusion or setup.
	if character.conditions.is_active(ConditionRules.HELPLESS):
		events.append(DomainEvent.new(&"combat_turn_passed", {"actorId": character.id, "action": "incapacitated"}))
		return false
	# getup.c:211-231 animates charmed and already-frightened characters before confusion.
	var animated := character.traitor or character.conditions.is_active(ConditionRules.RUNS_AWAY)
	if (character.traitor or character.conditions.value(ConditionRules.ANIMATED) > -1) and character.conditions.is_active(ConditionRules.CONFUSED):
		var outcome := _roll_confusion(character.id, character.traitor, character.conditions, false, rng, events)
		if outcome == CONFUSION_HELPLESS:
			events.append(DomainEvent.new(&"combat_turn_passed", {"actorId": character.id, "action": "incapacitated"}))
			return false
		if outcome == CONFUSION_TURNED:
			character.classic_traitor = 1
			animated = true
		elif outcome == CONFUSION_RECOVERED:
			# Castle leaves this activation animated, so the restored character acts automatically.
			character.classic_traitor = 0
		state.combat.reconcile_classic_counters(state.party)
	_context.actions().prepare_character_turn(state.combat, character)
	if animated:
		# Fear newly rolled here waits for the next activation unless charm already animated it.
		state.combat.turns.active_turn.action = FLEEING_ACTION if character.conditions.is_active(ConditionRules.RUNS_AWAY) else ANIMATED_ACTION
	return true


func _roll_confusion(actor_id: String, hostile: bool, conditions: ConditionSet, monster: bool, rng: RealmzRng, events: Array[DomainEvent]) -> StringName:
	var roll := rng.draw(100, &"combat.confusion.roll")
	var outcome := CONFUSION_UNCHANGED
	if roll > 60:
		outcome = CONFUSION_FLEEING
		conditions.add(ConditionRules.RUNS_AWAY, 1)
	elif roll >= 40:
		outcome = CONFUSION_HELPLESS
		conditions.add(ConditionRules.HELPLESS, 1)
	elif rng.draw(2, &"combat.confusion.turn") == 1 and not hostile:
		outcome = CONFUSION_TURNED
	# The second draw happens whenever the first test fails; Castle compares 2 for characters, 1 for monsters.
	elif rng.draw(2, &"combat.confusion.recover") == (1 if monster else 2) and hostile:
		outcome = CONFUSION_RECOVERED
	events.append(DomainEvent.new(&"combat_confusion_resolved", {"actorId": actor_id, "outcome": String(outcome), "roll": roll}))
	return outcome


func _run_animated(state: GameState, content: RealmzContent, character: CharacterState, rng: RealmzRng, events: Array[DomainEvent]) -> StringName:
	var attacked := false
	# Castle combat.c:958-962 repeats combatchoice until fewer than two half-attacks remain.
	while character.current_health > 0:
		# Each combatchoice tries the missile weapon before moving to strike.
		var shot := _animated.process_charmed_missile(state, content, character, rng, events)
		if _animated.failure_result != null:
			failure_result = _animated.failure_result
			return RETURN
		if shot == CombatCharmedCharacterAutomation.MACRO_SEQUENCE:
			return RETURN
		if shot == CombatCharmedCharacterAutomation.DEATH_MACRO:
			_context.rounds().advance_turn(state, content, rng, events)
			return RETURN
		if shot == CombatCharmedCharacterAutomation.ATTACKED:
			attacked = true
			if not CombatFlowActions.character_can_continue(character):
				break
			continue
		var movement_result := _animated.advance_charmed_character(state, content, character, rng, events)
		if movement_result in [REACTION_WAITING, REACTION_DEATH_MACRO]:
			return RETURN
		if movement_result == REACTION_MOVER_DEFEATED:
			break
		var attack := _animated.process_charmed_character_turn(state, content, character, rng, events)
		if _animated.failure_result != null:
			failure_result = _animated.failure_result
			return RETURN
		if attack == CombatCharmedCharacterAutomation.DEATH_MACRO:
			_context.rounds().advance_turn(state, content, rng, events)
			return RETURN
		if attack == CombatCharmedCharacterAutomation.NO_TARGET:
			if not attacked:
				events.append(DomainEvent.new(&"combat_monster_action_unavailable", {"actorId": character.id, "action": "advance", "reason": "no-legal-contact"}))
			break
		attacked = true
		if not CombatFlowActions.character_can_continue(character):
			break
	return _finish_activation(state, content, rng, events)


func _finish_activation(state: GameState, content: RealmzContent, rng: RealmzRng, events: Array[DomainEvent]) -> StringName:
	return BREAK if _context.rounds().advance_turn_and_check_resolved(state, content, rng, events) else CONTINUE
