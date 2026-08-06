class_name RealmzApplication
extends Control

const GameSessionControllerScript := preload("res://src/app/game_session_controller.gd")
const PresentationCoordinatorScript := preload("res://src/presentation/presentation_coordinator.gd")
const PackageRepositoryScript := preload("res://src/infrastructure/packages/package_repository.gd")
const SaveRepositoryScript := preload("res://src/infrastructure/saves/save_repository.gd")

@onready var _status_label: Label = %Status

var session_controller: GameSessionController
var presentation_coordinator: PresentationCoordinator
var package_repository: PackageRepository
var save_repository: SaveRepository
var _active_content: RealmzContent


func _ready() -> void:
	package_repository = PackageRepositoryScript.new()
	save_repository = SaveRepositoryScript.new()
	session_controller = GameSessionControllerScript.new()
	presentation_coordinator = PresentationCoordinatorScript.new()
	add_child(session_controller)
	add_child(presentation_coordinator)
	presentation_coordinator.bind(session_controller)
	_status_label.text = "Pure session boundary online"


func _on_smoke_action_pressed() -> void:
	if not session_controller.session().view().session_started:
		_status_label.text = "MCP input verified • no package loaded"
		return
	var step := session_controller.submit_intent(PlayerIntent.new(PlayerIntent.Kind.SEARCH))
	if step.state == SessionStep.State.FAILED:
		_status_label.text = "Search failed • %s" % step.error_message
		return
	var roll: int = step.events[0].payload.get("roll", 0)
	var current_view := session_controller.session().view()
	_status_label.text = "Search committed • roll %d • day %d %02d:00" % [roll, current_view.realmz_day, current_view.realmz_hour]


func start_package(package_path: String, initial_seed: int) -> SessionStep:
	var package_result := package_repository.load_package(package_path)
	if not package_result.is_ok():
		_status_label.text = "Package rejected • %s" % package_result.error_message
		return SessionStep.failed(0, package_result.error_code, package_result.error_message)
	var step := session_controller.start(package_result.content, initial_seed)
	if step.state == SessionStep.State.FAILED:
		_status_label.text = "Session start failed • %s" % step.error_message
		return step
	_active_content = package_result.content
	var current_view := session_controller.session().view()
	_status_label.text = "Loaded %s • %s %d,%d • seed %d" % [_active_content.campaign_id, current_view.party_map_id, current_view.party_coordinate.x, current_view.party_coordinate.y, initial_seed]
	return step


func save_active_session(slot_id: String) -> bool:
	if _active_content == null:
		_status_label.text = "Save failed • no package loaded"
		return false
	var saved := save_repository.save(_active_content.campaign_id, slot_id, session_controller.session().snapshot())
	_status_label.text = "Saved %s" % slot_id if saved else "Save failed • %s" % save_repository.last_error
	return saved
