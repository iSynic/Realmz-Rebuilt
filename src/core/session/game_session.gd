class_name GameSession
extends RefCounted

var _content: RealmzContent
var _state: GameState
var _rng: RealmzRng
var _started: bool = false
var _view_revision: int = 0
var _pending_interaction: InteractionRequest


func start(content: RealmzContent, initial_seed: int) -> SessionStep:
	if _started:
		return SessionStep.failed(_view_revision, "session_already_started", "The session has already started.")
	if content == null:
		return SessionStep.failed(_view_revision, "invalid_content", "Validated Realmz content is required.")
	var start_map := content.world.map_by_id(content.start_map_id)
	if start_map == null or start_map.topology.cell_at(content.start_coordinate) == null:
		return SessionStep.failed(_view_revision, "invalid_start_location", "The package start location is unavailable.")
	_content = content
	var starting_characters: Array[CharacterState] = [CharacterState.new("party.starting.adventurer", "Adventurer", 10, 10)]
	_state = GameState.new(PartyState.new(content.start_map_id, content.start_coordinate, starting_characters), RealmzClock.new())
	_rng = RealmzRng.new(initial_seed)
	_started = true
	_view_revision = 1
	return SessionStep.completed(_view_revision, [DomainEvent.new("session_started", {"campaignId": content.campaign_id})])


func restore(content: RealmzContent, save_envelope: SaveEnvelope) -> SessionStep:
	if content == null or save_envelope == null:
		return SessionStep.failed(_view_revision, "invalid_restore", "Validated content and save data are required.")
	if save_envelope.campaign_id != content.campaign_id or save_envelope.package_hash != content.package_hash:
		return SessionStep.failed(_view_revision, "package_mismatch", "The save belongs to a different package build.")
	if save_envelope.rules_version != content.rules_version:
		return SessionStep.failed(_view_revision, "rules_mismatch", "The save uses a different Realmz rules version.")
	var saved_map := content.world.map_by_id(save_envelope.game_state.party.map_id)
	if saved_map == null or saved_map.topology.cell_at(save_envelope.game_state.party.coordinate) == null:
		return SessionStep.failed(_view_revision, "invalid_saved_location", "The saved party location is unavailable.")
	var replacement_rng := RealmzRng.new()
	if not replacement_rng.restore(save_envelope.rng_state):
		return SessionStep.failed(_view_revision, "invalid_rng_state", "The saved random state is invalid.")
	var replacement_state := GameState.from_data(save_envelope.game_state.to_data())
	if replacement_state == null:
		return SessionStep.failed(_view_revision, "invalid_game_state", "The saved game state is invalid.")
	var replacement_interaction: InteractionRequest = null
	if save_envelope.pending_interaction != null:
		replacement_interaction = InteractionRequest.from_data(save_envelope.pending_interaction.to_data())
		if replacement_interaction == null:
			return SessionStep.failed(_view_revision, "invalid_interaction_state", "The pending interaction is invalid.")
	_content = content
	_state = replacement_state
	_rng = replacement_rng
	_pending_interaction = replacement_interaction
	_view_revision = save_envelope.view_revision
	_started = true
	return SessionStep.completed(_view_revision, [DomainEvent.new("session_restored")])


func submit_intent(intent: PlayerIntent) -> SessionStep:
	if not _started:
		return SessionStep.failed(_view_revision, "session_not_started", "Start or restore the session first.")
	if _pending_interaction != null:
		return SessionStep.failed(_view_revision, "interaction_pending", "Respond to the pending interaction first.")
	if intent == null:
		return SessionStep.failed(_view_revision, "invalid_intent", "A typed player intent is required.")
	match intent.kind:
		PlayerIntent.Kind.SEARCH:
			return _search()
		_:
			return SessionStep.failed(_view_revision, "intent_not_implemented", "This Realmz intent is not implemented in the current slice.")


func respond(response: InteractionResponse) -> SessionStep:
	if _pending_interaction == null:
		return SessionStep.failed(_view_revision, "no_interaction_pending", "There is no interaction to resume.")
	if response == null or response.request_id != _pending_interaction.request_id:
		return SessionStep.failed(_view_revision, "interaction_mismatch", "The response does not match the pending request.")
	_pending_interaction = null
	_view_revision += 1
	return SessionStep.completed(_view_revision)


func view() -> GameView:
	if not _started:
		return GameView.new(_view_revision, false, _pending_interaction)
	return GameView.new(_view_revision, true, _pending_interaction, _state.party.map_id, _state.party.coordinate, _state.clock.day(), _state.clock.hour())


func snapshot() -> SaveEnvelope:
	if not _started:
		return null
	var envelope := SaveEnvelope.new(_content.campaign_id, _content.package_hash, _content.rules_version, _view_revision, _state, _rng.snapshot(), _pending_interaction)
	return SaveEnvelope.from_data(envelope.to_data())


func rng_trace() -> Array[Dictionary]:
	return [] if _rng == null else _rng.trace()


func _search() -> SessionStep:
	_state.mark_searched(_state.party.map_id, _state.party.coordinate)
	var roll: int = _rng.draw(100, "exploration.search")
	_state.clock.advance_minutes(1)
	_view_revision += 1
	return SessionStep.completed(_view_revision, [DomainEvent.new("search_completed", {"mapId": _state.party.map_id, "x": _state.party.coordinate.x, "y": _state.party.coordinate.y, "roll": roll})])
