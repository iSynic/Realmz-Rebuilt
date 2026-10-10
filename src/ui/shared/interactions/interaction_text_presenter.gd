## Binds request headings, narrative prompts and unsupported-request hints.
class_name InteractionTextPresenter
extends RefCounted

var _heading: Label
var _prompt: Label
var _options: VBoxContainer
var _hint_scene: PackedScene


func _init(heading: Label, prompt: Label, options: VBoxContainer, hint_scene: PackedScene) -> void:
	_heading = heading
	_prompt = prompt
	_options = options
	_hint_scene = hint_scene


func present(request: InteractionRequest, classic_text_context: String) -> void:
	set_heading(InteractionComponentFactory.heading_for_kind(request.kind))
	if request.kind == InteractionRequest.SESSION_LIFECYCLE:
		set_heading("")
	if request.kind == InteractionRequest.CHARACTER_SELECTION and (request.body as CharacterSelectionRequestBody).spell_context != null:
		set_heading("Spell Target")
	_prompt.text = InteractionComponentFactory.prompt_for(request, classic_text_context)
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER if InteractionLayoutPolicy.uses_classic_click_modal(request) or InteractionLayoutPolicy.uses_floating_choice_modal(request) else HORIZONTAL_ALIGNMENT_LEFT
	_prompt.visible = not _prompt.text.is_empty()
	if InteractionLayoutPolicy.uses_application_workspace(request):
		set_heading("")
		_prompt.text = ""
		_prompt.visible = false
	if request.kind in [InteractionRequest.AGE_UPDATE, InteractionRequest.ALLY_SELECTION, InteractionRequest.LEVEL_UP, InteractionRequest.PICK_LOCK]:
		set_heading("")
		_prompt.text = ""
		_prompt.visible = false
	if InteractionLayoutPolicy.is_player_map_request(request) or InteractionLayoutPolicy.is_scrolling_text_request(request):
		_prompt.text = ""
		_prompt.visible = false
	if request.kind == &"combat_action":
		set_heading("")
		_prompt.text = ""
		_prompt.visible = false


func add_hint(text: String) -> Label:
	_options.visible = true
	var label := _hint_scene.instantiate() as Label
	label.text = text
	_options.add_child(label)
	return label


func set_heading(value: String) -> void:
	_heading.text = value
	_heading.visible = not value.is_empty()
