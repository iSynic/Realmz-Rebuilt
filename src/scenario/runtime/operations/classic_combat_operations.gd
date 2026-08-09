class_name ClassicCombatOperations
extends RefCounted

var _content: RealmzContent
var _game_state: GameState
var _rules: RealmzRules


func _init(content: RealmzContent, game_state: GameState, rules: RealmzRules) -> void:
	_content = content
	_game_state = game_state
	_rules = rules


func cause_fumble(action: ClassicActionDefinition, context: Dictionary) -> ScenarioRuntimeOperationResult:
	if action.extra_code.size() < 2:
		return ScenarioRuntimeOperationResult.failed(&"missing_extra_code", "Classic opcode 122 requires message and sound fields.")
	if _game_state.combat == null or _game_state.combat.completed:
		return ScenarioRuntimeOperationResult.completed(false, [DomainEvent.new(&"combat_fumble_skipped", {"reason": "no-active-battle", "source": "classic"})])
	var actor_id := str(context.get("combatantId", _game_state.combat.active_actor_id()))
	var result := _rules.combat_flow.cause_active_fumble(_game_state, _content, actor_id)
	if not result.ok:
		return ScenarioRuntimeOperationResult.failed(result.error_code, result.error_message)
	if result.events.any(func(event: DomainEvent) -> bool: return event.kind == &"combat_fumble_skipped" and event.payload.get("reason") in ["no-physical-action", "not-party-actor"]):
		return ScenarioRuntimeOperationResult.completed(false, result.events)
	var events: Array[DomainEvent] = []
	if int(action.extra_code[1]) != 0:
		events.append(DomainEvent.new(&"sound_requested", {"soundId": absi(int(action.extra_code[1])), "waitForCompletion": int(action.extra_code[1]) < 0, "source": "classic"}))
	if int(action.extra_code[0]) != 0:
		var message := _content.message_by_id(absi(int(action.extra_code[0])))
		if message != null:
			events.append(DomainEvent.new(&"message_shown", {"messageId": message.id, "text": message.text, "source": "classic"}))
	events.append_array(result.events)
	var changed := false
	for event: DomainEvent in result.events:
		if event.kind == &"combatant_fumbled":
			changed = true
			break
	return ScenarioRuntimeOperationResult.completed(changed, events)
