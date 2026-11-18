extends RealmzTestCase

## Opcode 12 in a dungeon: the wall an Action Point opens, and saves written while the write was misplaced.


func run() -> void:
	_test_replaced_cells()
	_test_saved_axes()
	var loaded := load_test_package("res://src/storage/packages/bundled_campaigns/scenario-war-in-the-sword-lands.realmz2")
	if not loaded.is_ok():
		return
	var content: RealmzContent = loaded.content
	var program := content.scenario.program_by_id("trigger:Data DDD:1:43")
	var action: ClassicActionDefinition = program.instruction_at(6) if program != null else null
	assert_true(action != null and action.opcode == 12 and action.extra_code == [1, 11, 5, 0, 1], "the temple Action Point retains its authored wall replacement")
	if action == null:
		return
	var state := GameState.new(PartyState.new("dungeon:1", Vector2i(12, 5), [CharacterState.new("temple.hero", "Hero", 30, 30)]), RealmzClock.new())
	var api := RealmzRuntimeApi.new(content, state, RealmzRng.new(7), ScenarioActionState.new(), RealmzRules.new())
	var topology := content.world.map_by_id("dungeon:1").topology
	assert_equal(topology.probe_entry(Vector2i(11, 5), Vector2i.LEFT, state.world).reason, &"terrain_blocked", "the wall west of the Action Point starts closed")
	var result := api.execute_classic(action, "temple.wall")
	assert_equal(result.state, ScenarioRuntimeOperationResult.State.COMPLETED, "the replacement completes")
	assert_true(state.world.topology.has_terrain_override("dungeon:1", Vector2i(11, 5)) and not state.world.topology.has_terrain_override("dungeon:1", Vector2i(5, 11)), "the replacement lands on column 11, row 5")
	var opened := topology.effective_cell_at(Vector2i(11, 5), state.world)
	assert_true(topology.probe_entry(Vector2i(11, 5), Vector2i.LEFT, state.world).allowed and opened.terrain_id == "classic.dungeon.floor" and not opened.blocks_los and opened.edge(&"west").kind == &"open", "the wall becomes open floor the party can enter and see through")
	assert_true(opened.feature_by_kind(&"unmapped") == null and topology.cell_at(Vector2i(11, 5)).terrain_id == "classic.dungeon.wall", "the written value replaces every authored bit while the package cell stays as authored")


func _test_replaced_cells() -> void:
	var wall_edge := MapEdge.new(&"wall", false, true)
	var authored := MapCell.new("dungeon:9:cell:3,4", Vector2i(3, 4), "classic.dungeon.wall", false, 1, true, false, false, false, false, false, false, 0, 0, "dungeon-top-down-302", ["ap"], [], {&"north": wall_edge, &"east": wall_edge, &"south": wall_edge, &"west": wall_edge}, [])
	var door := ClassicDungeonTileRules.replaced_cell(authored, 0x0003)
	assert_true(door.passable and not door.blocks_los and door.edge(&"east").kind == &"door" and door.edge(&"east").door_id == "dungeon:9:cell:3,4:door" and door.feature_by_kind(&"door").orientation == &"horizontal", "a door value makes a passable door cell")
	var secret := ClassicDungeonTileRules.replaced_cell(authored, 0x0101)
	assert_true(secret.passable and secret.blocks_los and secret.edge(&"north").kind == &"secret" and secret.edge(&"north").passable and not secret.edge(&"north").initially_discovered and not secret.edge(&"south").passable, "a secret passage opens only its own side and starts hidden")
	var marked_wall := ClassicDungeonTileRules.replaced_cell(authored, 0x1001)
	assert_true(marked_wall.terrain_id == "classic.dungeon.wall" and marked_wall.passable and marked_wall.edge(&"west").kind == &"open" and marked_wall.feature_by_kind(&"action-point") != null and marked_wall.trigger_ids() == ["ap"], "an Action Point wall stays enterable and keeps its records")
	var solid := ClassicDungeonTileRules.replaced_cell(authored, 0x4091)
	assert_true(not solid.passable and solid.blocks_los and solid.edge(&"south").kind == &"wall" and solid.feature_by_kind(&"column") != null and solid.feature_by_kind(&"no-wall-in-battle") != null and solid.feature_by_kind(&"unmapped") != null, "a plain wall value stays closed and keeps its markers")


func _test_saved_axes() -> void:
	var world := WorldState.new()
	world.topology.replace_terrain("dungeon:1", Vector2i(11, 5), "classic.terrain.0")
	var current := world.to_data()
	assert_true(WorldState.from_data(current).topology.has_terrain_override("dungeon:1", Vector2i(11, 5)), "a current save keeps its dungeon replacement where it was written")
	var earlier := current.duplicate(true)
	earlier.erase("dungeonTerrainAxes")
	earlier["terrainOverrides"] = {"dungeon:1:22,10": "classic.terrain.0", "land:0:20,47": "classic.terrain.-1227"}
	var repaired := WorldState.from_data(earlier).topology
	assert_true(repaired.has_terrain_override("dungeon:1", Vector2i(10, 22)) and not repaired.has_terrain_override("dungeon:1", Vector2i(22, 10)) and repaired.has_terrain_override("land:0", Vector2i(20, 47)), "an earlier save's dungeon replacement moves to the cell the scenario named, and land replacements stay put")
