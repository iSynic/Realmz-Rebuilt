## Castle's click-to-continue before-message for a random-rectangle battle. `combat.c`
## shows `battle.messagebefore` after the battle is drawn and before the battlefield is
## built, for random encounters as for scripted ones. The chosen battle and its surprise
## ride in the exploration continuation's `random_battle_stage`, whose saved fields are fixed.
class_name RandomBattlePrelude
extends RefCounted

const STAGE := "before-message"


## The stage that remembers the signed Classic `battle_number` and the caller's `surprise`.
static func stage_for(battle_number: int, surprise: int) -> StringName:
	return StringName("%s:%d:%d" % [STAGE, battle_number, surprise])


## True when `stage` names this wait, whether or not its figures are well formed.
static func is_stage(stage: StringName) -> bool:
	return String(stage).begins_with(STAGE)


## `[battle_number, surprise]` from a stage built by `stage_for`, or empty.
static func staged(stage: StringName) -> Array[int]:
	var parts := String(stage).split(":")
	if parts.size() != 3 or parts[0] != STAGE or not parts[1].is_valid_int() or not parts[2].is_valid_int() or int(parts[2]) < -1 or int(parts[2]) > 1:
		return []
	return [int(parts[1]), int(parts[2])]


## Suspends the drawn battle on its before-message. `events` are what has already happened.
static func wait(context: SessionContext, exploration: ExplorationContinuationBody, region: RandomEncounterRegion, battle_number: int, surprise: int, message: MessageDefinition, events: Array[DomainEvent]) -> SessionCoordinatorResult:
	exploration.active_random_region_id = region.id
	exploration.random_battle_stage = stage_for(battle_number, surprise)
	var request_id := "random-before:%s:%d" % [region.id, context.rng.snapshot().draw_count]
	context.session_interaction = ClassicBattlePrelude.request(request_id, message, context.state)
	events.append(DomainEvent.new(&"message_shown", {"messageId": message.id, "text": message.text, "source": "classic-battle-definition", "classicClick": true}))
	return SessionCoordinatorResult.waiting(context.session_interaction, events)


## Starts the remembered battle once the player has acknowledged its message.
static func respond(context: SessionContext, response: InteractionResponse) -> SessionCoordinatorResult:
	var acknowledgement := response.body as InteractionResponse.AcknowledgeBody
	if response.kind != InteractionRequest.ACKNOWLEDGE or acknowledgement == null:
		return SessionCoordinatorResult.rejected(&"invalid_interaction_response", "The message before a random battle requires an acknowledgement.")
	var exploration := context.session_continuation.exploration()
	var figures := staged(exploration.random_battle_stage) if exploration != null else ([] as Array[int])
	var map := context.content.world.map_by_id(exploration.map_id) if exploration != null else null
	var region: RandomEncounterRegion = map.random_region_by_id(exploration.active_random_region_id) if map != null else null
	var battle := context.content.combat.battle_by_classic_id(absi(figures[0])) if not figures.is_empty() else null
	if region == null or battle == null:
		return SessionCoordinatorResult.failed(&"invalid_session_continuation", "The message before a random battle has no matching continuation.")
	var events: Array[DomainEvent] = []
	if not ClassicBattlePrelude.take_note(context.state, acknowledgement, battle.message_before_id, events):
		return SessionCoordinatorResult.rejected(&"journal_message_unrepresentable", "This message cannot be recorded in the journal.")
	context.session_interaction = null
	exploration.active_random_region_id = ""
	exploration.random_battle_stage = &""
	return context.exploration().start_random_battle(region, figures[1], events, figures[0])


## True when a saved wait still matches its content and the pending text box.
static func restores(content: RealmzContent, state: GameState, exploration: ExplorationContinuationBody, pending: InteractionRequest) -> bool:
	var figures := staged(exploration.random_battle_stage)
	var battle := content.combat.battle_by_classic_id(absi(figures[0])) if not figures.is_empty() else null
	var message := ClassicBattlePrelude.before_message(content, battle) if battle != null else null
	return message != null and pending != null and state.combat == null and ClassicBattlePrelude.request(pending.request_id, message, state).to_data() == pending.to_data()
