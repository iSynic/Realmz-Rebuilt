class_name SessionRestoreCandidate
extends RefCounted

var state: GameState
var rng: RealmzRng
var rules: RealmzRules
var scenario_action_state: ScenarioActionState
var scenario_vm: ScenarioVm
var continuation: SessionContinuation
var battle_return_continuation: SessionContinuation
var session_interaction: InteractionRequest
var view_revision: int


func _init(replacement_state: GameState, replacement_rng: RealmzRng, replacement_rules: RealmzRules, replacement_action_state: ScenarioActionState, replacement_vm: ScenarioVm, replacement_continuation: SessionContinuation, replacement_battle_return: SessionContinuation, replacement_interaction: InteractionRequest, replacement_revision: int) -> void:
	state = replacement_state
	rng = replacement_rng
	rules = replacement_rules
	scenario_action_state = replacement_action_state
	scenario_vm = replacement_vm
	continuation = replacement_continuation
	battle_return_continuation = replacement_battle_return
	session_interaction = replacement_interaction
	view_revision = replacement_revision
