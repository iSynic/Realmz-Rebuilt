class_name TextChoiceInteraction
extends InteractionComponent


func build(request: InteractionRequest) -> void:
	match request.kind:
		&"encounter_choice", &"scenario_choice":
			var body := request.body as InteractionRequest.ChoiceRequestBody
			if body == null: return
			for index: int in body.options.size():
				var option := body.options[index]
				add_response(option.label if not option.label.is_empty() else "Option %d" % (index + 1), {"index": index})
			if request.kind == &"encounter_choice" and body.can_back_out:
				add_response("Back out", {"cancelled": true})
		&"yes_no":
			var body := request.body as InteractionRequest.YesNoRequestBody
			if body == null: return
			add_response(body.yes_label, {"accepted": true})
			add_response(body.no_label, {"accepted": false})
		&"acknowledge":
			var body := request.body as InteractionRequest.AcknowledgeBody
			if body == null: return
			if body.journal_eligible and not body.journal_recorded:
				add_response("Take note", {"takeNote": true})
			elif body.journal_recorded:
				add_hint("Already recorded in the journal.")
			add_response("Continue", {})
