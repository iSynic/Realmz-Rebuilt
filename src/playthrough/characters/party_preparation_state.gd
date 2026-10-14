## Retains ordinary party transactions and RNG before the immutable world is activated.
class_name PartyPreparationState
extends SessionContext

var catalog: ScenarioSetupCatalog
var awaiting_world := true


func prepare(setup_catalog: ScenarioSetupCatalog, initial_seed: int) -> void:
	catalog = setup_catalog
	begin(catalog.content, initial_seed)


func activate(full_content: RealmzContent) -> bool:
	if not awaiting_world or not catalog.matches(full_content) or state.party_setup_completed or session_interaction != null:
		return false
	content = full_content
	reset_scenario_execution()
	awaiting_world = false
	return true
