## Shares macro entry and completion between direct, scenario and destruction callers.
class_name ScenarioMacroLifecycle
extends RefCounted

var _content: RealmzContent
var _state: GameState
var _rng: RealmzRng
var _rules: RealmzRules


func _init(content: RealmzContent, state: GameState, rng: RealmzRng, rules: RealmzRules) -> void:
	_content = content
	_state = state
	_rng = rng
	_rules = rules


func begin(call: ScenarioMacroCall, preceding_events: Array[DomainEvent]) -> ScenarioRuntimeOperationResult:
	if not matches_battle(call): return ScenarioRuntimeOperationResult.failed(&"invalid_macro_call", "The macro entry has no matching battle or caller.", preceding_events)
	if _content.scenario.program_by_id(call.program_id) == null and not _content.scenario.native_program_is_unavailable(call.program_id):
		return ScenarioRuntimeOperationResult.failed(&"unknown_scenario_program", "The macro program is unavailable.", preceding_events)
	if call.kind == ScenarioMacroCall.Kind.DEATH and call.return_kind != ScenarioMacroCall.ReturnKind.DESTRUCTION:
		var pending := _state.combat.pending_operations.death_macro
		if pending == null or pending.combatant_id != call.combatant_id or pending.program_id() != call.program_id:
			return ScenarioRuntimeOperationResult.failed(&"invalid_macro_call", "The macro entry has no matching pending operation.", preceding_events)
		_state.combat.pending_operations.death_macro = null
	var events: Array[DomainEvent] = []
	events.assign(preceding_events)
	if call.kind == ScenarioMacroCall.Kind.ROUND:
		events.append(DomainEvent.new(&"battle_macro_started", {"battleId": call.battle_id, "programId": call.program_id, "round": _state.combat.turns.round_number}))
	else:
		events.append(DomainEvent.new(&"monster_death_macro_started", {"battleId": call.battle_id, "combatantId": call.combatant_id, "programId": call.program_id}))
	return ScenarioRuntimeOperationResult.calling(ScenarioProgramCall.macro_call(call), events)


func complete(call: ScenarioMacroCall) -> CombatFlowResult:
	if not matches_battle(call): return CombatFlowResult.failed(&"invalid_macro_return", "The completed macro lost its battle or return owner.")
	var combat := _state.combat
	var events: Array[DomainEvent] = []
	var result: CombatFlowResult
	if call.kind == ScenarioMacroCall.Kind.ROUND:
		events.append(DomainEvent.new(&"battle_macro_completed", {"battleId": call.battle_id, "programId": call.program_id, "round": combat.turns.round_number}))
		result = CombatFlowResult.succeeded([], true) if combat.completed else _rules.combat_flow.rounds.continue_after_battle_macro(_state, _content, _rng)
	else:
		var monster := combat.roster.monster_by_id(call.combatant_id)
		# killbody counts the hostile kill before its post-macro traitor clear;
		# direct and scenario callers retain that same numenemy/killmon order.
		if call.reset_traitor_on_complete: combat.clear_classic_death_macro_traitor(monster, _state.party)
		events.append(DomainEvent.new(&"monster_death_macro_completed", {"battleId": call.battle_id, "combatantId": call.combatant_id, "programId": call.program_id, "revived": monster.current_health > 0}))
		if call.return_kind == ScenarioMacroCall.ReturnKind.DESTRUCTION:
			if combat.turns.active_turn != null: combat.turns.active_turn.classic_physical_active = false
			if monster.current_health <= 0 and combat.battlefield != null: combat.battlefield.actors.remove_monster(monster.id)
			result = CombatFlowResult.succeeded([])
		else:
			result = _rules.combat_flow.continue_after_monster_death_macro(_state, _content, _rng, call.combatant_id)
	result.events = events + result.events
	return result


func matches_battle(call: ScenarioMacroCall) -> bool:
	return call != null and call.is_valid() and _state.combat != null and _state.combat.battle_id == call.battle_id and (call.kind == ScenarioMacroCall.Kind.ROUND or _state.combat.roster.monster_by_id(call.combatant_id) != null)


func enter_source(call: ScenarioMacroCall, shared: ScenarioClassicExecutionState) -> void:
	if call.kind == ScenarioMacroCall.Kind.ROUND:
		shared.battle_macro_active = true
		return
	var monsters := _state.combat.roster.monsters()
	var index := call.queued_source.monster_index if call.queued_source != null else monsters.find(_state.combat.roster.monster_by_id(call.combatant_id))
	# killbody's queued index zero deliberately leaves macromonster unchanged.
	if call.reset_traitor_on_complete or index != 0: shared.macro_monster_index = index


func return_source(call: ScenarioMacroCall, shared: ScenarioClassicExecutionState) -> void:
	if call.kind == ScenarioMacroCall.Kind.ROUND: shared.battle_macro_active = false
	elif call.reset_traitor_on_complete: shared.macro_monster_index = 0
