extends RealmzTestCase

## Walking beside a hidden dungeon passage reveals it, as Castle's per-step dungeon check does.

const FIXTURE_PATH: String = "res://tests/fixtures/packages/realmz2-synthetic-fixture.realmz2"
const SECRET_ID := "dungeon:0:cell:0,1:secret:east"


func run() -> void:
	var loaded := load_test_package(FIXTURE_PATH)
	if not loaded.is_ok():
		return
	var content: RealmzContent = loaded.content
	var session := GameSession.new()
	session.start(content, 1)
	_begin_standard_fixture_adventure(session, content)
	assert_equal(session.submit_intent(ExplorationIntents.toggle_search()).state, SessionStep.State.COMPLETED, "the fixture party turns Search on")
	_restore_fixture_position(session, content, "dungeon:0", Vector2i(3, 0), "the fixture party stands in the dungeon corridor")
	var far := session.submit_intent(ExplorationIntents.move(Vector2i.LEFT))
	assert_true(far.state == SessionStep.State.COMPLETED and session.view().party_coordinate == Vector2i(2, 0) and not _discovered(far).has(SECRET_ID), "a step that ends two cells from the passage finds nothing")
	var minutes_before := session.snapshot().game_state.clock.total_minutes()
	var beside := session.submit_intent(ExplorationIntents.move(Vector2i.LEFT))
	assert_true(beside.state == SessionStep.State.COMPLETED and session.view().party_coordinate == Vector2i(1, 0), "the party steps beside the hidden passage")
	assert_true(_discovered(beside).has(SECRET_ID) and session.snapshot().game_state.world.topology.secret_is_discovered(SECRET_ID), "the step reveals the passage without walking into it")
	assert_true(session.snapshot().game_state.clock.total_minutes() > minutes_before + 1, "Search mode spends its extra time on the dungeon check")
	var again := session.submit_intent(ExplorationIntents.move(Vector2i.RIGHT))
	assert_true(again.state == SessionStep.State.COMPLETED and _discovered(again).is_empty(), "a revealed passage is not found twice")


func _discovered(step: SessionStep) -> Array[String]:
	var found: Array[String] = []
	for event: DomainEvent in step.events:
		if event.kind == &"secret_discovered":
			found.append(RowFields.text(event.payload, "secretId"))
	return found
