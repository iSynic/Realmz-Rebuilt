class_name TextChoiceInteraction
extends InteractionComponent


func build(request: InteractionRequest) -> void:
	match request.kind:
		&"encounter_choice", &"scenario_choice":
			var options: Variant = request.payload.get("options", [])
			if options is Array:
				for index: int in options.size():
					var option: Variant = options[index]
					if option is Dictionary:
						add_response(String(option.get("label", "Option %d" % (index + 1))), {"index": index})
			if request.kind == &"encounter_choice" and bool(request.payload.get("canBackOut", false)):
				add_response("Back out", {"cancelled": true})
		&"yes_no":
			add_response(String(request.payload.get("yesLabel", "Yes")), {"accepted": true})
			add_response(String(request.payload.get("noLabel", "No")), {"accepted": false})
		&"acknowledge":
			add_response("Continue", {})
