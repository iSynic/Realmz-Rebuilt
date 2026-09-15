## Sweeps package-backed Party Auto from a caller-supplied checkpoint party.
##
## An older checkpoint may supply diagnostic combatants only. In that case the
## output names every character whose missing equipment order was reconstructed
## from its equipped inventory rows; this never rewrites or restores that save.
extends SceneTree

const PERFORMANCE_PACKAGE_LOADER := preload("res://tools/performance_package_loader.gd")
const MAX_ACTIVATIONS := 256


func _initialize() -> void:
	var arguments := OS.get_cmdline_user_args()
	if arguments.size() < 3 or arguments.size() > 4:
		printerr("Usage: godot --headless --path <project> --script res://tools/combat_auto_reproduction_probe.gd -- <package.realmz2> <checkpoint.r2save> <classic-battle-id> [seed-count]")
		call_deferred("_quit_cleanly", 2)
		return
	var loaded := PERFORMANCE_PACKAGE_LOADER.load_scenario(arguments[0])
	if not loaded.is_ok():
		printerr("PACKAGE_REJECTED %s: %s" % [loaded.error_code, loaded.error_message])
		call_deferred("_quit_cleanly", 1)
		return
	var checkpoint_text := FileAccess.get_file_as_string(arguments[1])
	var checkpoint: Variant = JSON.parse_string(checkpoint_text)
	if not checkpoint is Dictionary or not checkpoint.get("gameState") is Dictionary:
		printerr("CHECKPOINT_REJECTED: input has no gameState object")
		call_deferred("_quit_cleanly", 1)
		return
	var source_format := int(checkpoint.get("formatVersion", -1))
	var state_data: Dictionary = checkpoint["gameState"].duplicate(true)
	var assumed_orders := _supply_diagnostic_equipment_order(state_data)
	var baseline := GameState.from_data(state_data)
	if baseline == null:
		printerr("CHECKPOINT_REJECTED: gameState cannot form a current diagnostic state")
		call_deferred("_quit_cleanly", 1)
		return
	baseline.combat = null
	var content: RealmzContent = loaded.content
	var battle_id := int(arguments[2])
	var battle := content.combat.battle_by_classic_id(battle_id)
	if battle == null:
		printerr("BATTLE_REJECTED: Classic battle %d is unavailable" % battle_id)
		call_deferred("_quit_cleanly", 1)
		return
	var seed_count := clampi(int(arguments[3]) if arguments.size() == 4 else 100, 1, 10_000)
	var failures: Array[Dictionary] = []
	var outcomes: Dictionary = {}
	var checkpoint_run: Dictionary = {}
	var saved_rng := RealmzRngState.from_data(checkpoint.get("rng"))
	if saved_rng != null:
		var checkpoint_rng := RealmzRng.new()
		checkpoint_rng.restore(saved_rng)
		checkpoint_run = _run_with_rng(baseline, content, battle, 0, checkpoint_rng)
		if not bool(checkpoint_run.get("ok", false)):
			failures.append(checkpoint_run)
	for seed: int in range(1, seed_count + 1):
		var result := _run_seed(baseline, content, battle, seed)
		var outcome := String(result.get("outcome", "unknown"))
		outcomes[outcome] = int(outcomes.get(outcome, 0)) + 1
		if not bool(result.get("ok", false)):
			failures.append(result)
			if failures.size() >= 32:
				break
	print(CanonicalJson.encode({
		"battleClassicId": battle_id,
		"checkpointFormatVersion": source_format,
		"checkpointRngRun": checkpoint_run,
		"checkpointSha256": checkpoint_text.sha256_text(),
		"diagnosticEquipmentOrderAssumptions": assumed_orders,
		"failures": failures,
		"outcomes": outcomes,
		"packageSha256": FileAccess.get_sha256(arguments[0]),
		"seedsRequested": seed_count,
		"seedsRun": outcomes.values().reduce(func(total: int, count: Variant) -> int: return total + int(count), 0),
	}))
	call_deferred("_quit_cleanly", 1 if not failures.is_empty() else 0)


func _run_seed(baseline: GameState, content: RealmzContent, battle: BattleDefinition, seed: int) -> Dictionary:
	return _run_with_rng(baseline, content, battle, seed, RealmzRng.new(seed))


func _run_with_rng(baseline: GameState, content: RealmzContent, battle: BattleDefinition, seed: int, rng: RealmzRng) -> Dictionary:
	var state := GameState.from_data(baseline.to_data())
	var rules := RealmzRules.new()
	var setup := rules.combat_flow.start_battle(state, content, battle, rng)
	if not setup.ok or state.combat == null:
		return _failure(seed, 0, state, setup.error_code, setup.error_message, rng)
	for character: CharacterState in state.party.characters():
		if character.current_health > 0 and state.combat.battlefield.actors.has_actor(character.id):
			state.set_combat_auto(character.id, true)
	var activations := 0
	while state.combat != null and not state.combat.completed and activations < MAX_ACTIVATIONS:
		var actor_id := state.combat.turns.active_actor_id()
		var actor := state.party.character_by_id(actor_id)
		if actor == null:
			return _failure(seed, activations, state, &"non_character_boundary", "Persistent Auto stopped on a non-character activation.", rng)
		var result := rules.combat_flow.run_persistent_auto_characters(state, content, rng)
		activations += 1
		if not result.ok:
			return _failure(seed, activations, state, result.error_code, result.error_message, rng)
		if result.events.any(func(event: DomainEvent) -> bool: return event.kind in [&"monster_death_macro_requested", &"battle_before_macro_requested", &"battle_after_macro_requested"]):
			return _failure(seed, activations, state, &"scenario_continuation_required", "Direct rules probing reached a scenario-owned combat continuation.", rng)
	if state.combat != null and not state.combat.completed:
		return _failure(seed, activations, state, &"activation_limit", "Combat remained active after the bounded activation limit.", rng)
	return {"ok": true, "seed": seed, "activations": activations, "outcome": String(state.last_battle_outcome), "rngDrawCount": rng.snapshot().draw_count}


func _failure(seed: int, activations: int, state: GameState, code: StringName, message: String, rng: RealmzRng) -> Dictionary:
	var combat := state.combat
	return {
		"ok": false,
		"seed": seed,
		"activations": activations,
		"outcome": String(combat.outcome) if combat != null else String(state.last_battle_outcome),
		"round": combat.turns.round_number if combat != null else -1,
		"actorId": combat.turns.active_actor_id() if combat != null else "",
		"errorCode": String(code),
		"errorMessage": message,
		"rngDrawCount": rng.snapshot().draw_count,
	}


func _supply_diagnostic_equipment_order(state_data: Dictionary) -> Array[String]:
	var assumed: Array[String] = []
	var party: Variant = state_data.get("party")
	if not party is Dictionary or not party.get("characters") is Array:
		return assumed
	for character: Variant in party["characters"]:
		if not character is Dictionary or character.has("equipmentOrder") or not character.get("inventory") is Array:
			continue
		var order: Array[String] = []
		for item: Variant in character["inventory"]:
			if item is Dictionary and bool(item.get("equipped", false)):
				order.append(String(item.get("id", "")))
		character["equipmentOrder"] = order
		assumed.append(String(character.get("id", "")))
	return assumed


func _quit_cleanly(code: int) -> void:
	quit(code)
