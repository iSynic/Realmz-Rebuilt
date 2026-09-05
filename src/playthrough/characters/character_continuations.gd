## Creates character-setup and lifecycle session continuations.

class_name CharacterContinuations
extends RefCounted


static func spell_confirmation(character_id: String, remaining: int) -> SessionContinuation:
	var body := CharacterSpellConfirmationContinuationBody.new()
	body.character_id = character_id
	body.remaining = remaining
	return SessionContinuation.new(&"character-spell-confirmation", body)


static func vault_publication(character_id: String) -> SessionContinuation:
	var body := CharacterVaultPublicationContinuationBody.new()
	body.character_id = character_id
	return SessionContinuation.new(&"character-vault-publication", body)


static func age_updates(body: AgeContinuationBody) -> SessionContinuation:
	return SessionContinuation.new(&"age-updates", body)
