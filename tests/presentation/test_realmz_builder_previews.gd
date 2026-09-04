## Verifies editor-only fixtures through the same production binders used at runtime.

extends RealmzTestCase

const PREVIEW_FIXTURES := preload("res://addons/realmz_builder/realmz_builder_preview_fixtures.gd")
const SURFACES := {
	"temple": preload("res://src/ui/interaction_components/temple_interaction.tscn"),
	"bank": preload("res://src/ui/interaction_components/bank_interaction.tscn"),
	"pick-lock": preload("res://src/ui/interaction_components/pick_lock_interaction.tscn"),
	"lifecycle-prompts": preload("res://src/ui/interaction_components/lifecycle_interaction.tscn"),
	"scrolling-text": preload("res://src/ui/interaction_components/scrolling_text_interaction.tscn"),
}
const PROFILES: Array[String] = ["Wide", "Compact", "Empty", "Long Content", "Unavailable", "Error"]


func run() -> void:
	_test_all_profiles_bind_through_production_components()
	_test_representative_collections_and_modes()


func _test_all_profiles_bind_through_production_components() -> void:
	var scene_tree := Engine.get_main_loop() as SceneTree
	for surface_id: String in SURFACES:
		for profile: String in PROFILES:
			var surface := (SURFACES[surface_id] as PackedScene).instantiate() as Control
			scene_tree.root.add_child(surface)
			assert_true(PREVIEW_FIXTURES.bind(surface, surface_id, profile), "%s binds the %s fixture through its production component" % [surface_id, profile])
			assert_equal(String(surface.get_meta("realmz_builder_profile", "")), profile, "%s records the active detached preview profile" % surface_id)
			scene_tree.root.remove_child(surface)
			surface.free()


func _test_representative_collections_and_modes() -> void:
	var temple := _bound_surface("temple", "Wide")
	var bank := _bound_surface("bank", "Unavailable")
	var pick_lock := _bound_surface("pick-lock", "Long Content")
	var lifecycle := _bound_surface("lifecycle-prompts", "Wide")
	var scrolling_text := _bound_surface("scrolling-text", "Long Content")
	assert_equal((temple.find_child("TempleCharacterRows", true, false) as VBoxContainer).find_children("*", "Button", false, false).size(), 2, "Temple preview uses the production adventurer-row collection")
	assert_equal((temple.find_child("TempleServiceRows", true, false) as VBoxContainer).find_children("*", "Button", false, false).size(), 3, "Temple preview uses the production service-row collection")
	assert_true((bank.find_child("BankPool", true, false) as Button).disabled and (bank.find_child("BankShare", true, false) as Button).disabled, "Bank unavailable preview binds request-owned disabled actions")
	assert_equal((pick_lock.find_child("TumblerRows", true, false) as VBoxContainer).get_child_count(), 6, "Pick Lock long-content preview uses the production tumbler rows")
	assert_equal((lifecycle.find_child("LifecycleVerticalActions", true, false) as VBoxContainer).get_child_count(), 3, "Lifecycle preview creates the production response choices")
	assert_not_null(scrolling_text.find_child("ClassicScrollingTextDone", true, false), "scrolling-text preview binds the production scrolling surface and fixed action")
	for surface: Control in [temple, bank, pick_lock, lifecycle, scrolling_text]:
		_free_surface(surface)


func _bound_surface(surface_id: String, profile: String) -> Control:
	var surface := (SURFACES[surface_id] as PackedScene).instantiate() as Control
	(Engine.get_main_loop() as SceneTree).root.add_child(surface)
	PREVIEW_FIXTURES.bind(surface, surface_id, profile)
	return surface


func _free_surface(surface: Control) -> void:
	(Engine.get_main_loop() as SceneTree).root.remove_child(surface)
	surface.free()
