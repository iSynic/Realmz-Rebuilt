## Admits a reviewed selection as one setup transaction.
class_name PartyTransferWorkflow
extends RefCounted


static func import_selected(context: SessionWorkflowContext, pending: bool, payload: PartyIntentPayloads.SavedParty, revision: int) -> SessionWorkflowResult:
	if context.state.party_setup_completed or pending or context.state.character_draft != null:
		return SessionWorkflowResult.failed(&"party_setup_closed", "Finish character creation before importing a party during setup.")
	if payload == null or payload.members.is_empty() or payload.source_file_hash.is_empty() or payload.source_package_hash.is_empty():
		return SessionWorkflowResult.failed(&"invalid_party_import", "Select at least one eligible adventurer from a validated save.")
	if payload.destination_package_hash != context.content.package_hash or payload.setup_revision != revision:
		return SessionWorkflowResult.failed(&"party_import_stale", "Party setup changed. Review the transfer again.")
	var maximum := clampi(context.content.campaign.restrictions.maximum_party_size, 1, 6)
	if payload.members.size() + context.state.party.characters().size() > maximum:
		return SessionWorkflowResult.failed(&"invalid_party_size", "The selected adventurers exceed the remaining party slots.")
	# Validate sequentially against a detached roster so identities shared by two
	# selections are rejected before any existing setup member is touched.
	var staged := GameState.new(PartyState.from_data(context.state.party.to_data()), RealmzClock.new())
	var staging := SessionWorkflowContext.new(context.content, staged, context.rules, null, null, null)
	var imported: Array[CharacterState] = []
	for member: CharacterState in payload.members:
		var candidate := CharacterStateCodec.copy(member)
		if candidate == null:
			return SessionWorkflowResult.failed(&"invalid_party_import", "A selected character is malformed.")
		var failure := PartyAdmissionRules.validate(staging, candidate)
		if failure != null:
			return failure
		if not staged.party.add_character(candidate):
			return SessionWorkflowResult.failed(&"duplicate_party_member", "The selected characters share an identity or possession.")
		imported.append(candidate)
	for member: CharacterState in imported:
		context.state.party.add_character(member)
	return SessionWorkflowResult.completed([DomainEvent.new(&"saved_party_imported", {"characterCount": imported.size(), "sourcePackageHash": payload.source_package_hash})])
