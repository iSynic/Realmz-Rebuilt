extends RealmzTestCase


func run() -> void:
	var rng := RealmzRng.new(1)
	assert_equal(rng.draw(100, "vector.first"), 52, "QuickDraw seed 1 first Castle-scaled roll matches")
	assert_equal(rng.draw(100, "vector.second"), 47, "QuickDraw seed 1 second Castle-scaled roll matches")
	assert_equal(rng.draw(100, "vector.third"), 65, "QuickDraw seed 1 third Castle-scaled roll matches")
	assert_equal(rng.snapshot().generator_state, 1_622_650_073, "QuickDraw state follows the documented Park-Miller sequence")
	assert_equal(rng.snapshot().draw_count, 3, "draw count is persisted independently of state")
	assert_equal(rng.trace()[2]["raw"], -21_287, "the returned QuickDraw value is the signed low word")

	var saved := rng.snapshot()
	var restored := RealmzRng.new(99)
	assert_true(restored.restore(saved), "valid RNG state restores")
	assert_equal(restored.draw(6, "vector.after_restore"), rng.draw(6, "vector.control"), "restored state continues the exact sequence")

	var scripted := ScriptedRng.new([-32_767, 0, 32_767])
	assert_equal(scripted.draw(100, "scripted.high-negative"), 100, "Castle scaling uses absolute raw output")
	assert_equal(scripted.draw(100, "scripted.zero"), 1, "Castle Rand returns at least one")
	assert_equal(scripted.draw(100, "scripted.high-positive"), 100, "Castle scaling reaches the requested range")
