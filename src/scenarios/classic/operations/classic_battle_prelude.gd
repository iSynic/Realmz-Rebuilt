## Castle's click-to-continue text before a scripted fight. `newland.c` cases 2, 48, 56 and
## 107 call `textbox(-1, message)` before choosing the battle, and `combat.c` does the same
## for the battle's own before-message; `textbox-time.c` waits for a click or key when the
## message number is positive.
class_name ClassicBattlePrelude
extends RefCounted


## The acknowledgement that shows `message`, with the same journal offer as any text box.
static func request(request_id: String, message: MessageDefinition, state: GameState) -> InteractionRequest:
	var eligible := ScenarioProgressState.journal_message_id_is_valid(message.id)
	return InteractionRequest.from_payload(request_id, InteractionRequest.ACKNOWLEDGE, {
		"prompt": message.text, "messageId": message.id, "presentation": "classic-textbox",
		"journalEligible": eligible, "journalRecorded": eligible and state.scenario_progress.journal_message_is_recorded(message.id),
	})


## Suspends `action` on `message` at `stage`; `events` are what has already happened.
static func wait(stage: StringName, message: MessageDefinition, action: ClassicActionDefinition, battle_number: int, context: ScenarioExecutionContext, request_id: String, state: GameState, events: Array[DomainEvent]) -> ScenarioRuntimeOperationResult:
	var source := "classic-battle" if stage == ScenarioBattlePreludeBody.INSTRUCTION else "classic-battle-definition"
	events.append(DomainEvent.new(&"message_shown", {"messageId": message.id, "text": message.text, "source": source, "classicClick": true}))
	var continuation := ScenarioCombatContinuations.battle_prelude(stage, message.id, action.opcode, action.gosub, action.extra_code, battle_number, context)
	return ScenarioRuntimeOperationResult.waiting(request(request_id, message, state), continuation, events)


## The battle's before-message when Castle would wait on it, or null.
static func before_message(content: RealmzContent, battle: BattleDefinition) -> MessageDefinition:
	return content.scenario_records.message_by_id(battle.message_before_id) if battle.message_before_id > 0 else null


## Records the acknowledged message in the journal when the player asked for a note.
## Returns false when the message cannot be recorded.
static func take_note(state: GameState, acknowledgement: InteractionResponse.AcknowledgeBody, message_id: int, events: Array[DomainEvent]) -> bool:
	if not acknowledgement.take_note or state.scenario_progress.journal_message_is_recorded(message_id):
		return true
	if not state.scenario_progress.record_journal_message(message_id):
		return false
	events.append(DomainEvent.new(&"journal_entry_recorded", {"messageId": message_id}))
	return true
