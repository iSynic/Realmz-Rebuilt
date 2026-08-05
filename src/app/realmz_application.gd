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
	_status_label.text = "MCP input verified"
