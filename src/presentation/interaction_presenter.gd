class_name InteractionPresenter
extends PanelContainer

signal response_submitted(response: InteractionResponse)

@onready var _prompt: Label = %InteractionPrompt
@onready var _options: VBoxContainer = %InteractionOptions

var _request: InteractionRequest


func present(request: InteractionRequest) -> void:
	_request = request
	for child: Node in _options.get_children():
		child.queue_free()
	visible = request != null
	if request == null:
		_prompt.text = ""
		return
	_prompt.text = String(request.payload.get("prompt", "Choose an option"))
	var options: Variant = request.payload.get("options", [])
	if not options is Array:
		return
	for index: int in range(options.size()):
		var option: Variant = options[index]
		if not option is Dictionary:
			continue
		var button := Button.new()
		button.text = String(option.get("label", "Option %d" % (index + 1)))
		button.custom_minimum_size = Vector2(280.0, 38.0)
		button.pressed.connect(_submit.bind(index))
		_options.add_child(button)
	if _options.get_child_count() > 0:
		(_options.get_child(0) as Button).grab_focus()


func _submit(index: int) -> void:
	if _request == null:
		return
	var response := InteractionResponse.new(_request.request_id, _request.kind, {"index": index})
	_request = null
	visible = false
	response_submitted.emit(response)
