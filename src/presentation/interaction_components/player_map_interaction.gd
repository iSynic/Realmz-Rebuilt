class_name PlayerMapInteraction
extends InteractionComponent

var _view: GameView
var _media: ClassicMediaCatalog
var _submitted: bool = false


func configure(game_view: GameView, media: ClassicMediaCatalog) -> void:
	_view = game_view
	_media = media


func build(request: InteractionRequest) -> void:
	var body := request.body as InteractionRequest.AcknowledgeBody
	var player_map_id := "" if body == null else body.player_map_id
	var selected: PlayerMapView
	if _view != null:
		for player_map: PlayerMapView in _view.acquired_player_maps:
			if player_map.id == player_map_id:
				selected = player_map
				break
	if selected == null:
		add_hint("The acquired map is unavailable in the current detached view.")
		add_response("Continue", InteractionResponse.AcknowledgeBody.new())
		return
	var presenter := PlayerMapPresenter.new()
	presenter.name = "ImmediatePlayerMap"
	presenter.present(selected, _media)
	presenter.scrolling_text_finished.connect(_complete)
	add_child(presenter)
	var continue_button := Button.new()
	continue_button.text = "Continue"
	continue_button.custom_minimum_size.y = 36.0
	continue_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	continue_button.pressed.connect(_complete)
	add_child(continue_button)


func _complete() -> void:
	if _submitted:
		return
	_submitted = true
	response_body_submitted.emit(InteractionResponse.AcknowledgeBody.new())
