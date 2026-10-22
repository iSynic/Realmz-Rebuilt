## Defines the typed session restore candidate contract used by playthrough transactions.

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
var classic_execution: ClassicExecutionState


func _init(replacement_state: GameState, replacement_rng: RealmzRng, replacement_rules: RealmzRules, replacement_action_state: ScenarioActionState, replacement_vm: ScenarioVm, replacement_continuation: SessionContinuation, replacement_battle_return: SessionContinuation, replacement_interaction: InteractionRequest, replacement_revision: int, native_execution: ClassicExecutionState = null) -> void:
	state = replacement_state
	rng = replacement_rng
	rules = replacement_rules
	scenario_action_state = replacement_action_state
	scenario_vm = replacement_vm
	continuation = replacement_continuation
	battle_return_continuation = replacement_battle_return
	session_interaction = replacement_interaction
	view_revision = replacement_revision
	classic_execution = native_execution.copy() if native_execution != null else ClassicExecutionState.new()


static func capture_setup(context: SessionContext) -> SessionRestoreCandidate:
	# This is an owned preimage, not save admission: early setup has no world yet.
	var saved := context.create_snapshot()
	var saved_rng := context.rng.fork()
	if saved == null or saved_rng == null:
		return null
	var saved_vm := ScenarioVm.new()
	saved_vm.configure(context.content.scenario if context.content.scenario != null else ScenarioDefinition.new([], []))
	if not saved_vm.restore(saved.scenario_vm):
		return null
	var continuation := saved.continuation if saved.continuation != null else SessionContinuation.new()
	var battle_return := saved.battle_return_continuation if saved.battle_return_continuation != null else SessionContinuation.new()
	return SessionRestoreCandidate.new(saved.game_state, saved_rng, context.rules, saved.scenario_action_state, saved_vm, continuation, battle_return, saved.session_interaction, saved.view_revision, saved.classic_execution)
