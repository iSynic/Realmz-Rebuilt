## Presents the dynamic player map interaction without owning gameplay state.

class_name PlayerMapInteraction
extends InteractionComponent

var _view: GameView
var _media: ClassicMediaCatalog
var _submitted: bool = false


func configure(game_view: GameView, media: ClassicMediaCatalog) -> void:
	_view = game_view
	_media = media


func build(request: InteractionRequest) -> void:
	var body := request.body as AcknowledgeRequestBody
	var player_map_id := "" if body == null else body.player_map_id
	var selected: PlayerMapView
	if _view != null:
		for player_map: PlayerMapView in _view.acquired_player_maps:
			if player_map.id == player_map_id:
				selected = player_map
				break
	if selected == null:
		(%ImmediatePlayerMap as PlayerMapPresenter).visible = false
		(%UnavailableHint as Label).visible = true
		(%Continue as Button).pressed.connect(_complete)
		return
	var presenter := %ImmediatePlayerMap as PlayerMapPresenter
	presenter.present(selected, _media)
	presenter.scrolling_text_finished.connect(_complete)
	var continue_button := %Continue as Button
	continue_button.pressed.connect(_complete)


func _complete() -> void:
	if _submitted:
		return
	_submitted = true
	response_body_submitted.emit(InteractionResponse.AcknowledgeBody.new())
