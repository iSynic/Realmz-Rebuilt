## Owns the Classic bank request and every committed wealth transfer.

class_name ClassicBankingOperations
extends RefCounted

var _game_state: GameState
var _rules: RealmzRules
var _money: ClassicMoneyTransferSupport


func _init(game_state: GameState, rules: RealmzRules, money: ClassicMoneyTransferSupport) -> void:
	_game_state = game_state
	_rules = rules
	_money = money


func request(request_id: String) -> ScenarioRuntimeOperationResult:
	_rules.economy.bank_to_pool(_game_state.party)
	return ScenarioRuntimeOperationResult.waiting(_interaction_request(request_id), ScenarioServiceContinuations.banking(), [
		DomainEvent.new(&"bank_opened", {"pooledWealth": _game_state.party.pooled_wealth.to_data()}),
		DomainEvent.new(&"sound_requested", {"soundId": 141, "waitForCompletion": false, "source": "classic-bank-swap-button"}),
		DomainEvent.new(&"sound_requested", {"soundId": 3003, "waitForCompletion": false, "stopExisting": true, "source": "classic-bank-swap-open"}),
	])


func resume(continuation: ScenarioRuntimeContinuation, response: InteractionResponse, request_id: String) -> ScenarioRuntimeOperationResult:
	var body := response.body as InteractionResponse.BankBody
	if response.kind != InteractionRequest.BANK or body == null:
		return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_response", "Bank response requires an action.")
	var action := String(body.action)
	if action == "leave":
		return ScenarioRuntimeOperationResult.completed(true, [
			DomainEvent.new(&"bank_closed", {"pooledWealthReturnedToBank": false}),
			DomainEvent.new(&"sound_requested", {"soundId": 141, "waitForCompletion": false, "source": "classic-bank-swap-done"}),
		])
	var selected_character_id := body.character_id
	var events: Array[DomainEvent] = []
	var error := _apply_action(body, events)
	if error != null:
		return error
	return ScenarioRuntimeOperationResult.waiting(_interaction_request(request_id, selected_character_id), continuation, events)


func _interaction_request(request_id: String, selected_character_id: String = "") -> InteractionRequest:
	var characters: Array[Dictionary] = []
	for character: CharacterState in _game_state.party.characters():
		var transfers: Array[Dictionary] = []
		for denomination: String in ["gold", "gems", "jewelry"]:
			var kind := ClassicMoneyTransferSupport.wealth_kind(denomination)
			var amount := EconomyRules.classic_transfer_increment(kind as WealthState.Kind)
			var to_pool := _rules.economy.transfer_probe(_game_state.party, character, kind as WealthState.Kind, amount, false)
			var to_character := _rules.economy.transfer_probe(_game_state.party, character, kind as WealthState.Kind, amount, true)
			transfers.append({
				"denomination": denomination,
				"amount": amount,
				"toPool": ClassicMoneyTransferSupport.probe_data(to_pool),
				"toCharacter": ClassicMoneyTransferSupport.probe_data(to_character),
			})
		characters.append({
			"id": character.id,
			"name": character.name,
			"wealth": character.money.to_data(),
			"load": character.carried_load,
			"maximumLoad": character.maximum_load,
			"transfers": transfers,
		})
	if selected_character_id.is_empty() and not characters.is_empty():
		selected_character_id = String(characters[0]["id"])
	return InteractionRequest.from_payload(request_id, InteractionRequest.BANK, {
		"selectedCharacterId": selected_character_id,
		"pooledWealth": _game_state.party.pooled_wealth.to_data(),
		"bankedWealth": _game_state.party.banked_wealth.to_data(),
		"pool": ClassicMoneyTransferSupport.probe_data(_rules.economy.pool_probe(_game_state.party)),
		"share": ClassicMoneyTransferSupport.probe_data(_rules.economy.share_probe(_game_state.party)),
		"characters": characters,
		"actions": ["pool", "share", "to-pool", "to-character", "leave"],
	})


func _apply_action(body: InteractionResponse.BankBody, events: Array[DomainEvent]) -> ScenarioRuntimeOperationResult:
	var action := String(body.action)
	match action:
		"pool": return _pool(events)
		"share": return _share(events)
		"to-pool", "to-character": return _transfer(body, events)
		_: return ScenarioRuntimeOperationResult.failed(&"unknown_bank_action", "Bank action '%s' is unavailable." % action)


func _pool(events: Array[DomainEvent]) -> ScenarioRuntimeOperationResult:
	var context_error := _money.movement_context_error()
	if not context_error.is_empty():
		return ScenarioRuntimeOperationResult.failed(&"invalid_money_context", context_error)
	var probe := _rules.economy.pool_probe(_game_state.party)
	if not probe.allowed:
		return ScenarioRuntimeOperationResult.failed(&"money_action_unavailable", probe.reason)
	_rules.economy.pool_party_wealth(_game_state.party)
	_money.recalculate_party_movement()
	events.append(DomainEvent.new(&"wealth_pooled", {"source": "classic-bank", "wealth": _game_state.party.pooled_wealth.to_data()}))
	events.append(DomainEvent.new(&"sound_requested", {"soundId": 128, "waitForCompletion": false, "source": "classic-bank-pool"}))
	return null


func _share(events: Array[DomainEvent]) -> ScenarioRuntimeOperationResult:
	var context_error := _money.movement_context_error()
	if not context_error.is_empty():
		return ScenarioRuntimeOperationResult.failed(&"invalid_money_context", context_error)
	var probe := _rules.economy.share_probe(_game_state.party)
	if not probe.allowed:
		return ScenarioRuntimeOperationResult.failed(&"money_action_unavailable", probe.reason)
	_rules.economy.share_pooled_wealth(_game_state.party)
	_money.recalculate_party_movement()
	events.append(DomainEvent.new(&"wealth_shared", {"source": "classic-bank", "remaining": _game_state.party.pooled_wealth.to_data()}))
	events.append(DomainEvent.new(&"sound_requested", {"soundId": 128, "waitForCompletion": false, "source": "classic-bank-share"}))
	return null


func _transfer(body: InteractionResponse.BankBody, events: Array[DomainEvent]) -> ScenarioRuntimeOperationResult:
	if body.character_id.is_empty() or body.denomination.is_empty() or body.amount < 1:
		return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_response", "Bank-backed Swap requires character, denomination, and amount.")
	var context_error := _money.movement_context_error()
	if not context_error.is_empty():
		return ScenarioRuntimeOperationResult.failed(&"invalid_money_context", context_error)
	var character := _game_state.party.character_by_id(body.character_id)
	var kind := ClassicMoneyTransferSupport.wealth_kind(body.denomination)
	if character == null:
		return ScenarioRuntimeOperationResult.failed(&"unknown_character", "The selected bank character is unavailable.")
	if kind < 0:
		return ScenarioRuntimeOperationResult.failed(&"unknown_wealth_kind", "The selected bank denomination is unavailable.")
	if body.amount != EconomyRules.classic_transfer_increment(kind as WealthState.Kind):
		return ScenarioRuntimeOperationResult.failed(&"invalid_money_increment", "Classic Swap moves five gold or one gem or jewelry per action.")
	var to_character := body.action == &"to-character"
	var probe := _rules.economy.transfer_probe(_game_state.party, character, kind as WealthState.Kind, body.amount, to_character)
	if not probe.allowed:
		return ScenarioRuntimeOperationResult.failed(&"money_action_unavailable", probe.reason)
	var transferred := _rules.economy.transfer_pool_to_character(_game_state.party, character, kind as WealthState.Kind, body.amount) if to_character else _rules.economy.transfer_character_to_pool(_game_state.party, character, kind as WealthState.Kind, body.amount)
	if not transferred:
		return ScenarioRuntimeOperationResult.failed(&"money_action_unavailable", "The selected bank transfer is no longer available.")
	_money.recalculate_party_movement()
	events.append(DomainEvent.new(&"wealth_transferred", {"source": "classic-bank", "characterId": character.id, "direction": String(body.action), "kind": body.denomination, "amount": body.amount}))
	events.append(DomainEvent.new(&"sound_requested", {"soundId": 10051 if to_character else 663, "waitForCompletion": false, "source": "classic-bank-swap"}))
	return null
