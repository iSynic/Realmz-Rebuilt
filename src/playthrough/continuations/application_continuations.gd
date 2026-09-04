## Creates application and character-lifecycle session continuations.

class_name ApplicationContinuations
extends RefCounted


static func hook(body: ApplicationContinuationBody) -> SessionContinuation:
	return SessionContinuation.new(&"application-hook", body)


static func character_spell_confirmation(character_id: String, remaining: int) -> SessionContinuation:
	var body := ApplicationContinuationBody.new()
	body.character_id = character_id
	body.remaining = remaining
	return SessionContinuation.new(&"character-spell-confirmation", body)


static func character_vault_publication(character_id: String) -> SessionContinuation:
	var body := ApplicationContinuationBody.new()
	body.character_id = character_id
	return SessionContinuation.new(&"character-vault-publication", body)


static func age_updates(body: AgeContinuationBody) -> SessionContinuation:
	return SessionContinuation.new(&"age-updates", body)
