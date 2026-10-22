## Defines the typed session snapshot contract used by playthrough transactions.

class_name SessionSnapshot
extends RefCounted

var campaign_id: String
var package_hash: String
var rules_version: String
var view_revision: int
var game_state: GameState
var rng_state: RealmzRngState
var scenario_vm: ScenarioVmSnapshot
var scenario_action_state: ScenarioActionState
var continuation: SessionContinuation
var battle_return_continuation: SessionContinuation
var session_interaction: InteractionRequest
var classic_execution: ClassicExecutionState
var deviation_ids: Array[String] = []
## False when a live continuation or state failed to detach; such a snapshot must never be saved.
var is_complete: bool = true


func _init(campaign: String, package_identity: String, rules: String, revision: int, state: GameState, random_state: RealmzRngState, vm_state: ScenarioVmSnapshot = null, action_state: ScenarioActionState = null, pending_continuation: SessionContinuation = null, pending_battle_return: SessionContinuation = null, pending_session_interaction: InteractionRequest = null, native_execution: ClassicExecutionState = null) -> void:
	campaign_id = campaign
	package_hash = package_identity
	rules_version = rules
	view_revision = revision
	game_state = GameState.from_data(state.to_data())
	rng_state = RealmzRngState.from_data(random_state.to_data())
	scenario_vm = ScenarioVmSnapshot.from_data(vm_state.to_data()) if vm_state != null else ScenarioVmSnapshot.new()
	scenario_action_state = ScenarioActionState.from_data(action_state.to_data()) if action_state != null else ScenarioActionState.new()
	continuation = SessionContinuation.from_data(pending_continuation.to_data()) if pending_continuation != null else null
	battle_return_continuation = SessionContinuation.from_data(pending_battle_return.to_data()) if pending_battle_return != null else null
	session_interaction = InteractionRequest.from_data(pending_session_interaction.to_data()) if pending_session_interaction != null else null
	classic_execution = native_execution.copy() if native_execution != null else ClassicExecutionState.new()
	# Release builds strip assert(), so record detachment failures explicitly.
	is_complete = game_state != null and rng_state != null and scenario_vm != null and scenario_action_state != null and (pending_continuation == null or continuation != null) and (pending_battle_return == null or battle_return_continuation != null) and (pending_session_interaction == null or session_interaction != null)
	if not is_complete:
		push_error("A session snapshot could not detach its complete typed state or a live continuation; it cannot be saved.")


func pending_interaction() -> InteractionRequest:
	return session_interaction if session_interaction != null else scenario_vm.pending_request
