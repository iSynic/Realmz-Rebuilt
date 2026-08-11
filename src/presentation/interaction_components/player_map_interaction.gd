class_name PlayerMapInteraction
extends InteractionComponent

var _view: GameView
var _media: PackageMediaCatalog


func configure(game_view: GameView, media: PackageMediaCatalog) -> void:
	_view = game_view
	_media = media


func build(request: InteractionRequest) -> void:
	var player_map_id := String(request.payload.get("playerMapId", ""))
	var selected: PlayerMapView
	if _view != null:
		for player_map: PlayerMapView in _view.acquired_player_maps:
			if player_map.id == player_map_id:
				selected = player_map
				break
	if selected == null:
		add_hint("The acquired map is unavailable in the current detached view.")
		add_response("Continue", {})
		return
	var presenter := PlayerMapPresenter.new()
	presenter.name = "ImmediatePlayerMap"
	presenter.present(selected, _media)
	add_child(presenter)
	add_response("Continue", {})
