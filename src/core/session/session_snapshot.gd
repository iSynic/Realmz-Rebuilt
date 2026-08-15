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
var session_interaction: InteractionRequest
var deviation_ids: Array[String] = []
var combat_state: Dictionary = {}
var metadata: Dictionary = {}


func _init(campaign: String, package_identity: String, rules: String, revision: int, state: GameState, random_state: RealmzRngState, vm_state: ScenarioVmSnapshot = null, action_state: ScenarioActionState = null, pending_continuation: SessionContinuation = null, pending_session_interaction: InteractionRequest = null) -> void:
	campaign_id = campaign
	package_hash = package_identity
	rules_version = rules
	view_revision = revision
	game_state = state
	rng_state = random_state
	scenario_vm = vm_state if vm_state != null else ScenarioVmSnapshot.new()
	scenario_action_state = action_state if action_state != null else ScenarioActionState.new()
	continuation = SessionContinuation.from_data(pending_continuation.to_data()) if pending_continuation != null else null
	session_interaction = pending_session_interaction


func pending_interaction() -> InteractionRequest:
	return session_interaction if session_interaction != null else scenario_vm.pending_request
