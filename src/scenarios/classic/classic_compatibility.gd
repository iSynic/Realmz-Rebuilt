## Explicit outcomes for source-authored defects, selected by the operation owner.
class_name ClassicCompatibility
extends RefCounted


static func quest_limit(content: RealmzContent) -> int:
	# Castle variables.h owns quest[128]. Legacy packages retain their prior
	# operation limit; complete-record packages may address every native slot.
	return ScenarioProgressState.QUEST_CAPACITY if content.package_schema_version >= 7 else 100


static func source_unavailable(content: RealmzContent, native_path: String, native_id: int) -> bool:
	return content.classic_records != null and content.classic_records.lookup(native_path, native_id).availability != ClassicRecordCatalog.Availability.COMPLETE


static func map_source_unavailable(content: RealmzContent, map_id: String) -> bool:
	var parts := map_id.split(":")
	if parts.size() != 2 or parts[0] not in ["land", "dungeon"] or not parts[1].is_valid_int(): return false
	return source_unavailable(content, "Data LD" if parts[0] == "land" else "Data DL", int(parts[1]))


static func media_reference_source_absent(content: RealmzContent, asset_id: String) -> bool:
	if content.classic_records == null: return false
	var parts := asset_id.split(".")
	if parts.size() != 4 or parts[0] != "classic" or parts[1] != "resource" or not parts[3].is_valid_int(): return false
	var resource_id := int(parts[3])
	return not content.has_media_resource(parts[2], resource_id) and content.classic_records.can_prove_resource_absence(parts[2], resource_id)


static func item_source_unavailable(content: RealmzContent, classic_id: int) -> bool:
	if content.classic_records == null: return false
	# Item 0 is reserved. Stock 1..799 is application-owned; scenario items
	# start at 800 in Data NI. A missing stock definition remains an invariant error.
	return classic_id <= 0 or classic_id >= 1000 or classic_id >= 800 and source_unavailable(content, "Data NI", classic_id - 800)


static func spell_reference_unusable(content: RealmzContent, classic_id: int) -> bool:
	if content.classic_records == null: return false
	# loadspell2 preserves stale spellinfo below 1101 and otherwise indexes
	# spelldata[class-1][level-1][slot-1]. Do not reproduce those unsafe accesses.
	var spell_class := int(classic_id / 1000)
	var level := int(classic_id % 1000 / 100)
	var slot := classic_id % 100
	if spell_class not in range(1, 6) or level not in range(1, 8) or slot not in range(1, 16): return true
	return spell_class == 5 and source_unavailable(content, "Data Spell", (level - 1) * 15 + slot - 1)


static func missing_extra_code(content: RealmzContent, action: ClassicActionDefinition, context: ScenarioExecutionContext) -> ScenarioRuntimeOperationResult:
	if not ClassicOpcodeCatalog.reads_extra_code(action.opcode): return null
	if action.opcode == 69 and action.operand_id == 0: return null
	# Inline typed operands are not a deferred native EDCD lookup.
	if not action.native_extra_code_reference and action.extra_code_fault == null and not action.extra_code.is_empty(): return null
	# Empty-row direct forms are part of the existing runtime instruction contract.
	if action.opcode in [2, 33] and action.extra_code.is_empty() and not action.native_extra_code_reference and action.extra_code_fault == null: return null
	var target := action.operand_id
	if not source_unavailable(content, "Data EDCD", target):
		if action.opcode != 92 or not source_unavailable(content, "Data EDCD", target + 1): return null
	# These operations mutate only the selected target. No supplied operands means
	# no mutation. Branches, payments and interactions instead cancel their timeline.
	if action.opcode in [-23, 7, 12, 13, 15, 16, 22, 23, 30, 41, 43, 45, 50, 51, 52, 54, 57, 60, 61, 63, 68, 69, 70, 90, 92, 103, 106, 120, 121, 123, 124, 125]:
		var result := skip(&"unavailable-mutation-operands", "Data EDCD", target)
		if action.opcode == 45: result.suppress_header_recheck = true
		return result
	if action.opcode in [2, 3, 17, 18, 19, 20, 21, 31, 33, 37, 38, 40, 42, 46, 48, 53, 55, 56, 58, 59, 64, 65, 67, 72, 73, 74, 75, 76, 77, 78, 81, 85, 86, 87, 107, 108, 122, 126]:
		var result := cancel_interaction(&"unavailable-operation-operands", "Data EDCD", target, context)
		result.secondary_door_completed = action.opcode == 20
		result.invocation_returned_early = action.opcode == 37
		return result
	return null


static func skip(operation: StringName, native_path: String, native_id: int) -> ScenarioRuntimeOperationResult:
	return ScenarioRuntimeOperationResult.completed(false, [DomainEvent.new(&"classic_reference_skipped", {"operation": String(operation), "nativePath": native_path, "nativeId": native_id, "source": "native-compatibility"})])


static func cancel_interaction(operation: StringName, native_path: String, native_id: int, context: ScenarioExecutionContext) -> ScenarioRuntimeOperationResult:
	var result := skip(operation, native_path, native_id)
	result.events.append(DomainEvent.new(&"action_point_kept", {"triggerId": context.trigger_id if context != null else "", "source": "native-compatibility"}))
	result.directive = ScenarioVmDirective.native_return(0)
	return result


static func unsafe_battle(content: RealmzContent, state: GameState, battle: BattleDefinition, context: ScenarioExecutionContext) -> ScenarioRuntimeOperationResult:
	var populated := 0
	var held_count := 0
	if not state.allies_suspended:
		for ally: MonsterState in state.party.allies():
			if ally.current_health > 0: held_count += 1
	var slots := battle.monster_slots()
	slots.sort_custom(func(left: BattleMonsterSlotDefinition, right: BattleMonsterSlotDefinition) -> bool:
		return left.coordinate.y < right.coordinate.y or left.coordinate.y == right.coordinate.y and left.coordinate.x < right.coordinate.x)
	for slot: BattleMonsterSlotDefinition in slots:
		# combatsetup.c stops reading native cells once held and new actors fill 100 slots.
		if populated + held_count >= CombatBattleSetup.MAX_MONSTERS: break
		var definition := content.combat.monster_by_id_for_set(slot.monster_id, state.monster_set)
		if definition == null:
			var native_path := "Data MD" + (str(state.monster_set) if state.monster_set != 0 else "")
			var native_id := int(slot.monster_id.get_slice(".", 2))
			if not source_unavailable(content, native_path, native_id):
				return ScenarioRuntimeOperationResult.failed(&"missing_battle_monster", "A source-present battle monster is absent from its compiled catalog.")
			return cancel_interaction(&"unavailable-battle-monster", "Data BD", battle.classic_id, context)
		# combatsetup.c skips each unsigned zero-HD row before actor construction.
		if definition.hit_dice == 0:
			continue
		populated += 1
		var probe := MonsterConsumptionProbe.inspect(content, definition)
		if probe.outcome == MonsterConsumptionProbe.Outcome.PACKAGE_DEFECT:
			return ScenarioRuntimeOperationResult.failed(&"missing_monster_dependency", probe.reason)
		if probe.outcome == MonsterConsumptionProbe.Outcome.AUTHORED_UNSAFE:
			return cancel_interaction(&"unsafe-battle-monster", "Data BD", battle.classic_id, context)
	if populated == 0 and held_count == 0:
		return cancel_interaction(&"empty-battle", "Data BD", battle.classic_id, context)
	return null
