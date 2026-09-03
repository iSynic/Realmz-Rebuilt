class_name SessionCoordinatorContext
extends RefCounted

var content: RealmzContent
var state: GameState
var rng: RealmzRng
var rules: RealmzRules
var scenario_vm: ScenarioVm
var scenario_action_state: ScenarioActionState
var runtime_api: RealmzRuntimeApi
var session_continuation: SessionContinuation
var battle_return_continuation: SessionContinuation
var session_interaction: InteractionRequest
var _view_revision: int
var _exploration_coordinator: RefCounted
var _scenario_coordinator: RefCounted
var _responses_coordinator: RefCounted


func _init(
	value_content: RealmzContent,
	value_state: GameState,
	value_rng: RealmzRng,
	value_rules: RealmzRules,
	value_scenario_vm: ScenarioVm,
	value_action_state: ScenarioActionState,
	value_runtime_api: RealmzRuntimeApi,
	value_continuation: SessionContinuation,
	value_battle_return: SessionContinuation,
	value_interaction: InteractionRequest,
	value_revision: int
) -> void:
	content = value_content
	state = value_state
	rng = value_rng
	rules = value_rules
	scenario_vm = value_scenario_vm
	scenario_action_state = value_action_state
	runtime_api = value_runtime_api
	session_continuation = value_continuation
	battle_return_continuation = value_battle_return
	session_interaction = value_interaction
	_view_revision = value_revision


func current_revision() -> int:
	return _view_revision


func next_revision() -> int:
	return _view_revision + 1


func bind_coordinators(exploration: RefCounted, scenario: RefCounted, responses: RefCounted) -> void:
	assert(exploration != null and scenario != null and responses != null, "A session operation requires its complete coordinator set")
	_exploration_coordinator = exploration
	_scenario_coordinator = scenario
	_responses_coordinator = responses


func exploration() -> RefCounted:
	return _exploration_coordinator


func scenario() -> RefCounted:
	return _scenario_coordinator


func responses() -> RefCounted:
	return _responses_coordinator


func release_coordinators() -> void:
	_exploration_coordinator = null
	_scenario_coordinator = null
	_responses_coordinator = null


func workflow_context(events: Array[DomainEvent] = []) -> SessionWorkflowContext:
	return SessionWorkflowContext.new(content, state, rules, rng, scenario_vm, scenario_action_state, events)


func set_continuation(continuation: SessionContinuation) -> void:
	assert(continuation != null and not continuation.is_empty(), "A live continuation must have a typed body")
	session_continuation = continuation


func completed(events: Array[DomainEvent]) -> SessionCoordinatorResult:
	return SessionCoordinatorResult.completed(events)


func waiting(request: InteractionRequest, events: Array[DomainEvent]) -> SessionCoordinatorResult:
	return SessionCoordinatorResult.waiting(request, events)


func failed(code: StringName, message: String, events: Array[DomainEvent] = []) -> SessionCoordinatorResult:
	return SessionCoordinatorResult.failed(code, message, events)


func closed(events: Array[DomainEvent], reason: String) -> SessionCoordinatorResult:
	return SessionCoordinatorResult.closed(events, reason)


func events_have(events: Array[DomainEvent], kind: StringName) -> bool:
	for event in events:
		if event.kind == kind:
			return true
	return false


func event_payload(events: Array[DomainEvent], kind: StringName) -> Dictionary:
	for event in events:
		if event.kind == kind:
			return event.payload
	return {}


func item_instance(character: CharacterState, instance_id: String) -> ItemInstance:
	if character == null or instance_id.is_empty():
		return null
	for instance: ItemInstance in character.inventory():
		if instance.id == instance_id:
			return instance
	return null


func recalculate_party_movement() -> void:
	for character: CharacterState in state.party.characters():
		var race := content.race_by_id(character.race_id)
		var caste := content.caste_by_id(character.caste_id)
		rules.characters.recalculate_movement(character, race, caste.movement_bonus)


func money_kind(value: String) -> int:
	match value:
		"gold": return WealthState.Kind.GOLD
		"gems": return WealthState.Kind.GEMS
		"jewelry": return WealthState.Kind.JEWELRY
	return -1
