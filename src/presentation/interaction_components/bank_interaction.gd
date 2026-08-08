class_name BankInteraction
extends InteractionComponent


func build(request: InteractionRequest) -> void:
	add_hint("Carried %d • deposited %d" % [int(request.payload.get("carriedGold", 0)), int(request.payload.get("bankedGold", 0))])
	var amount := SpinBox.new()
	amount.min_value = 0
	amount.max_value = maxi(int(request.payload.get("carriedGold", 0)), int(request.payload.get("bankedGold", 0)))
	amount.prefix = "Gold "
	add_child(amount)
	var deposit := Button.new()
	deposit.text = "Deposit"
	deposit.pressed.connect(func() -> void: payload_submitted.emit({"action": "deposit", "amount": int(amount.value)}))
	add_child(deposit)
	var withdraw := Button.new()
	withdraw.text = "Withdraw"
	withdraw.pressed.connect(func() -> void: payload_submitted.emit({"action": "withdraw", "amount": int(amount.value)}))
	add_child(withdraw)
	add_response("Leave bank", {"action": "leave"})
