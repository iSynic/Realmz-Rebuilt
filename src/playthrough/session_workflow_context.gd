class_name SessionWorkflowContext
extends RefCounted

var content: RealmzContent
var state: GameState
var rules: RealmzRules
var rng: RealmzRng
var scenario_vm: ScenarioVm
var scenario_action_state: ScenarioActionState
var events: Array[DomainEvent]


func _init(
	validated_content: RealmzContent,
	mutable_state: GameState,
	realmz_rules: RealmzRules,
	random_source: RealmzRng,
	vm: ScenarioVm,
	action_state: ScenarioActionState,
	event_sink: Array[DomainEvent] = [],
) -> void:
	content = validated_content
	state = mutable_state
	rules = realmz_rules
	rng = random_source
	scenario_vm = vm
	scenario_action_state = action_state
	events = event_sink


func publish(event: DomainEvent) -> void:
	if event != null:
		events.append(event)


func publish_all(values: Array[DomainEvent]) -> void:
	events.append_array(values)
