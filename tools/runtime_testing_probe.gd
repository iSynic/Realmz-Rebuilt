## Runs the read-only testing adapter without UI or player persistence for transport diagnostics.
extends SceneTree


func _initialize() -> void:
	var session := GameSessionController.new()
	root.add_child(session)
	var testing := RuntimeTestingHost.new()
	root.add_child(testing)
	var status := testing.bind(session, func() -> RealmzContent: return null, func() -> Dictionary: return {"explorationInput": false, "routeInput": false, "combatPlayback": false, "hostInteraction": false, "headless": true})
	if status != OK:
		printerr("Runtime testing probe rejected: %s" % error_string(status))
		quit(2)
