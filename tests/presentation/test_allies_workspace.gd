extends RealmzTestCase

const Controller := preload("res://src/presentation/controllers/creature_library_workspace_controller.gd")


func run() -> void:
	_test_allies_workspace()


func _test_allies_workspace() -> void:
	var body := VBoxContainer.new()
	var view := GameView.new(7, true, null)
	var monster := MonsterState.new("ally.fixture", "classic.monster.4", "Allied Knight", 8, 10, 4, 9, 3, 15, 6, false)
	monster.icon_id = 384
	var definition := MonsterDefinition.new("classic.monster.4", 4, "Allied Knight", 4, 0, 9, 3, 15, [0, 0, 0, 0, 0, 0, 0, 0], [0, 0, 0, 0, 0, 0], [0, 0, 0, 0, 0, 0], [0, 0, 0], [], [], [], [])
	definition.movement_max = 8
	view.party_allies = [MonsterView.new(monster, definition)]
	Controller.new().present_allies(body, view, null, 1.0)
	var labels := _labels_in(body)
	assert_true(labels.has("Allied Knight") and labels.has("Classic monster 4  •  4 Hit Dice"), "Allies renders current held-over source identity")
	assert_true(labels.has("8 / 10") and labels.has("Friendly"), "Allies exposes detached current state without mutation")
	assert_not_null(body.find_child("AlliesListPane", true, false), "Allies owns a backed selection pane")
	assert_not_null(body.find_child("AllyDetailPane", true, false), "Allies owns a backed detail pane")
	for child: Node in body.get_children():
		body.remove_child(child)
		child.queue_free()
	view.party_allies.clear()
	Controller.new().present_allies(body, view, null, 1.0)
	assert_true(_labels_in(body).has("No current allies"), "Allies has an explicit empty state")
	body.free()


func _labels_in(root: Node) -> Array[String]:
	var labels: Array[String] = []
	for child: Node in root.find_children("*", "Label", true, false):
		labels.append((child as Label).text)
	return labels
