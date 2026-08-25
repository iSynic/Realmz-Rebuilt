class_name StartupRouteBridge
extends Node

@onready var _shell: ClassicApplicationShell = get_parent().get_node("ClassicShell") as ClassicApplicationShell


func _enter_tree() -> void:
	var application := get_parent()
	if bool(application.get_meta(&"startup_splash_suppressed", false)):
		var router := application.get_node("ClassicShell/ScreenRouter") as ClassicScreenRouter
		router.set_startup_splash_enabled(false)


func _ready() -> void:
	_shell.show_campaign_selection()


func _process(_delta: float) -> void:
	var application := get_parent()
	var action := StringName(application.get_meta(&"startup_route_request", &""))
	if action.is_empty():
		return
	application.remove_meta(&"startup_route_request")
	match action:
		&"load":
			_shell.show_campaign_selection(true)
		&"vault":
			_shell.show_vault_from_splash()
		&"quit":
			_shell.quit_requested.emit()
		_:
			_shell.show_campaign_selection()
