class_name CharacterCreationHostController
extends RefCounted

const CharacterCreationSessionScript := preload("res://src/session/character_creation_session.gd")

var _session: CharacterCreationSession


func start(content: RealmzContent, identity: CharacterFileIdentity) -> SessionStep:
	if content == null or identity == null or _session != null:
		return SessionStep.failed(0, &"character_creation_unavailable", "Character creation is already active or its definitions are unavailable.")
	_session = CharacterCreationSessionScript.new()
	var step := _session.start(content, identity.seed, identity.character_id)
	if step.state == SessionStep.State.FAILED:
		_session = null
	return step


func is_active() -> bool:
	return _session != null


func submit(intent: PlayerIntent) -> SessionStep:
	if _session == null:
		return SessionStep.failed(0, &"character_creation_inactive", "Character creation is not active.")
	return _session.submit_intent(intent)


func respond(response: InteractionResponse) -> SessionStep:
	if _session == null:
		return SessionStep.failed(0, &"character_creation_inactive", "Character creation is not active.")
	return _session.respond(response)


func view() -> GameView:
	return _session.view() if _session != null else null


func completed_character() -> CharacterState:
	return _session.completed_character() if _session != null else null


func publication_committed() -> void:
	if _session != null:
		_session.publication_committed()


func finish() -> void:
	_session = null
