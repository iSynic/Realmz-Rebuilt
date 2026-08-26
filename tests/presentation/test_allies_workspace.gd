extends RealmzTestCase

const Controller := preload("res://src/presentation/controllers/creature_library_workspace_controller.gd")


func run() -> void:
	_test_allies_workspace()


func _test_allies_workspace() -> void:
	var body := VBoxContainer.new(); var view := GameView.new(7, true, null); var monster := MonsterState.new("ally.fixture", "classic.monster.4", "Allied Knight", 8, 10, 4, 9, 3, 15, 6, false)
	monster.icon_id = 384
	var definition := MonsterDefinition.new("classic.monster.4", 4, "Allied Knight", 4, 0, 9, 3, 15, [0, 0, 0, 0, 0, 0, 0, 0], [0, -2, 0, 0, 0, 0], [1, 0, 0, 0, 0, 0], [0, 0, 0], [], [], [MonsterAttackDefinition.new(1, 6, 40, 0)], [], 42, "A disciplined guardian recorded in the active monster set.", false); definition.movement_max = 8; definition.icon_id = 384; view.party_allies = [MonsterView.new(monster, definition)]; view.bestiary_entries = [MonsterCatalogEntryView.new(definition)]
	var controller := Controller.new()
	controller.present_allies(body, view, null, 1.0)
	var labels := _labels_in(body)
	assert_true(labels.has("Allied Knight") and labels.has("Classic monster 4") and labels.has("4 Hit Dice"), "Allies renders current held-over source identity")
	assert_true(labels.has("8 / 10") and labels.has("No"), "Allies exposes detached current state without mutation")
	assert_not_null(body.find_child("AlliesListPane", true, false), "Allies owns a backed selection pane")
	assert_not_null(body.find_child("AllyDetailPane", true, false), "Allies owns a backed detail pane")
	assert_not_null(body.find_child("AllyRow_ally.fixture".validate_node_name(), true, false), "Allies gives each current ally one stable inspect row")
	assert_not_null(body.find_child("AllyStateCards", true, false), "Allies groups current conditions and defenses in a stable detail region")
	assert_not_null(body.find_child("AllyIcon", true, false), "Allies reserves exact nearest-neighbor CICN presentation in its detail header")
	for child: Node in body.get_children():
		body.remove_child(child)
		child.queue_free()
	controller.set_layout_profile(UiLayoutProfile.COMPACT)
	controller.present_allies(body, view, null, 1.0)
	assert_true((body.find_child("AlliesColumns", true, false) as BoxContainer).vertical, "the optional 800x600 profile stacks list and detail instead of squeezing their fact columns")
	for child: Node in body.get_children(): body.remove_child(child); child.queue_free()
	controller.set_layout_profile(UiLayoutProfile.WIDE); controller.present_bestiary(body, view, null, 1.0); labels = _labels_in(body)
	assert_true(labels.has("Allied Knight") and labels.has("Classic monster 4  •  name 42") and labels.has("A disciplined guardian recorded in the active monster set."), "Bestiary consumes the preserved description and independent Classic name identity from its detached catalog")
	assert_true(body.find_child("BestiaryListPane", true, false) != null and body.find_child("BestiaryDetailPane", true, false) != null and body.find_child("BestiaryIcon", true, false) != null and labels.has("1–6 damage") and labels.has("Charm"), "Bestiary exposes the source combat facts and exact CICN stage behind stable list/detail panes")
	for child: Node in body.get_children():
		body.remove_child(child)
		child.queue_free()
	view.party_allies.clear()
	controller.present_allies(body, view, null, 1.0)
	assert_true(_labels_in(body).has("No current allies") and _labels_in(body).has("No allies are currently with the party."), "Allies has an explicit concise empty state")
	body.free()


func _labels_in(root: Node) -> Array[String]:
	var labels: Array[String] = []
	for child: Node in root.find_children("*", "Label", true, false):
		labels.append((child as Label).text)
	return labels
