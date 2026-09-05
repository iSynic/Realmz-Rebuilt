extends RealmzTestCase

const Controller := preload("res://src/ui/characters/creature_library_screen_controller.gd")
const AlliesScreenScene := preload("res://src/ui/characters/allies_screen.tscn")
const BestiaryScreenScene := preload("res://src/ui/characters/bestiary_screen.tscn")


func run() -> void:
	_test_allies_workspace()


func _test_allies_workspace() -> void:
	var allies := AlliesScreenScene.instantiate() as CreatureLibraryScreen
	var bestiary := BestiaryScreenScene.instantiate() as CreatureLibraryScreen
	var view := GameView.new(7, true, null); var monster := MonsterState.new("ally.fixture", "classic.monster.4", "Allied Knight", 8, 10, 4, 9, 3, 15, 6, false)
	monster.icon_id = 384
	var definition := MonsterDefinition.new("classic.monster.4", 4, "Allied Knight", 4, 0, 9, 3, 15, [0, 0, 0, 0, 0, 0, 0, 0], [0, -2, 0, 0, 0, 0], [1, 0, 0, 0, 0, 0], [0, 0, 0], [], [], [MonsterAttackDefinition.new(1, 6, 40, 0)], [], 42, "A disciplined guardian recorded in the active monster set.", false); definition.movement_max = 8; definition.icon_id = 384; view.party_allies = [MonsterView.new(monster, definition)]; view.bestiary_entries = [MonsterCatalogEntryView.new(definition)]
	var controller := Controller.new()
	controller.present_allies(allies, view, null, 1.0)
	var labels := _labels_in(allies)
	assert_true(labels.has("Allied Knight") and labels.has("Classic monster 4") and labels.has("4 Hit Dice"), "Allies renders current held-over source identity")
	assert_true(labels.has("8 / 10") and labels.has("No"), "Allies exposes detached current state without mutation")
	assert_not_null(allies.find_child("CreatureListPanel", true, false), "Allies owns an authored selection pane")
	assert_not_null(allies.find_child("CreatureDetailPanel", true, false), "Allies owns an authored detail pane")
	assert_not_null(allies.find_child("AllyRow_ally.fixture".validate_node_name(), true, false), "Allies gives each current ally one stable inspect row")
	assert_not_null(allies.find_child("CreatureStateCards", true, false), "Allies groups current conditions and defenses in an authored detail region")
	assert_not_null(allies.find_child("CreatureIcon", true, false), "Allies reserves exact nearest-neighbor CICN presentation in its authored header")
	controller.set_layout_profile(UiLayoutProfile.COMPACT)
	controller.present_allies(allies, view, null, 1.0)
	assert_true((allies.find_child("CreatureColumns", true, false) as BoxContainer).vertical, "the optional 800x600 profile stacks list and detail instead of squeezing their fact columns")
	controller.set_layout_profile(UiLayoutProfile.WIDE); controller.present_bestiary(bestiary, view, null, 1.0); labels = _labels_in(bestiary)
	assert_true(labels.has("Allied Knight") and labels.has("Classic monster 4  •  name 42") and labels.has("A disciplined guardian recorded in the active monster set."), "Bestiary consumes the preserved description and independent Classic name identity from its detached catalog")
	assert_true(bestiary.find_child("CreatureListPanel", true, false) != null and bestiary.find_child("CreatureDetailPanel", true, false) != null and bestiary.find_child("CreatureIcon", true, false) != null and labels.has("1–6 damage") and labels.has("Charm"), "Bestiary exposes source combat facts and exact CICN stage through its authored workspace")
	view.party_allies.clear()
	controller.present_allies(allies, view, null, 1.0)
	assert_true(_labels_in(allies).has("No current allies") and _labels_in(allies).has("No allies are currently with the party."), "Allies has an explicit concise empty state")
	allies.free()
	bestiary.free()


func _labels_in(root: Node) -> Array[String]:
	var labels: Array[String] = []
	for child: Node in root.find_children("*", "Label", true, false):
		labels.append((child as Label).text)
	return labels
