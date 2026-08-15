class_name CharacterCreationSession
extends RefCounted

var _session: GameSession
var _published_character_id: String = ""


func start(content: RealmzContent, rng_seed: int, published_character_id: String) -> SessionStep:
	if _session != null:
		return SessionStep.failed(0, &"character_creator_started", "Character creation is already active.")
	if content == null or published_character_id.is_empty():
		return SessionStep.failed(0, &"invalid_character_catalog", "The Classic character library is unavailable.")
	_published_character_id = published_character_id
	_session = GameSession.new()
	return _session.start(content, rng_seed)


func submit_intent(intent: PlayerIntent) -> SessionStep:
	if _session == null or intent == null:
		return SessionStep.failed(_revision(), &"character_creator_unavailable", "Character creation is unavailable.")
	if intent.kind not in [
		PlayerIntent.Kind.GENERATE_CHARACTER_DRAFT,
		PlayerIntent.Kind.CANCEL_CHARACTER_DRAFT,
		PlayerIntent.Kind.SET_CHARACTER_DRAFT_SPELLS,
		PlayerIntent.Kind.FINALIZE_CHARACTER,
	]:
		return SessionStep.failed(_revision(), &"unsupported_character_intent", "That action is unavailable in the standalone Character Files creator.")
	return _accept_implicit_publication(_session.submit_intent(intent))


func respond(response: InteractionResponse) -> SessionStep:
	if _session == null:
		return SessionStep.failed(_revision(), &"character_creator_unavailable", "Character creation is unavailable.")
	return _accept_implicit_publication(_session.respond(response))


func view() -> GameView:
	return _session.view() if _session != null else GameView.new(0, false, null)


func completed_character() -> CharacterState:
	if _session == null:
		return null
	var boundary := _session.snapshot()
	if boundary == null or boundary.game_state.party.characters().size() != 1:
		return null
	var character := CharacterState.from_data(boundary.game_state.party.characters()[0].to_data())
	if character != null:
		character.id = _published_character_id
	return character


func publication_committed() -> SessionStep:
	var character := completed_character()
	if character == null:
		return SessionStep.failed(_revision(), &"no_character_draft", "The completed character is unavailable.")
	return SessionStep.completed(_revision(), [DomainEvent.new(&"character_file_published", {"characterId": character.id})])


func _accept_implicit_publication(step: SessionStep) -> SessionStep:
	if step == null or step.state != SessionStep.State.WAITING_FOR_INTERACTION or step.interaction == null:
		return step
	var asks_to_publish := step.events.any(func(event: DomainEvent) -> bool: return event.kind == &"character_vault_confirmation_requested")
	if not asks_to_publish:
		return step
	var accepted := _session.respond(InteractionResponse.yes_no(step.interaction, true))
	if accepted.state == SessionStep.State.FAILED:
		return accepted
	var events: Array[DomainEvent] = []
	events.append_array(step.events)
	events.append_array(accepted.events)
	if accepted.state == SessionStep.State.WAITING_FOR_INTERACTION:
		return SessionStep.waiting(accepted.view_revision, accepted.interaction, events)
	return SessionStep.completed(accepted.view_revision, events)


func _revision() -> int:
	return _session.view().revision if _session != null else 0
