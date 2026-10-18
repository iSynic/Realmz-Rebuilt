## Validates combat cast sources before target selection is considered.

class_name CombatCastSourceAdmission
extends RefCounted

var _context: CombatContext


func _init(context: CombatContext) -> void:
	_context = context


func probe_item(state: GameState, content: RealmzContent, caster_id: String, instance_id: String) -> CombatSpellCastProbe:
	if state == null or content == null:
		return CombatSpellCastProbe.fault(&"invalid_item_turn", "Item use requires an active game session.")
	var combat := state.combat
	if combat != null and not combat.completed and combat.battlefield == null:
		return CombatSpellCastProbe.fault(&"missing_battlefield", "The active battle has no validated battlefield.")
	if combat == null or combat.completed or combat.battlefield == null or combat.turns.active_actor_id() != caster_id:
		return CombatSpellCastProbe.blocked(&"invalid_item_turn", "Only the active character may use an item in combat.")
	if not combat.spell_runtime.pending_death_macro_id().is_empty():
		return CombatSpellCastProbe.blocked(&"spell_death_macro_pending", "A spell-triggered monster death macro must complete before another combat action.")
	var caster := state.party.character_by_id(caster_id)
	var instance := inventory_instance(caster, instance_id)
	var item: ItemDefinition = null if instance == null else content.items.item_by_id(instance.definition_id)
	var spell: SpellDefinition = null if item == null else content.magic.spell_by_classic_id(item.special_2)
	if instance != null and item == null:
		return CombatSpellCastProbe.fault(&"unknown_item", "Carried item '%s' has no immutable definition." % instance.definition_id)
	if item != null and item.special_2 > 1100 and spell == null:
		return CombatSpellCastProbe.fault(&"unknown_spell", "Item '%s' references unavailable spell %d." % [item.id, item.special_2])
	var race := content.characters.race_by_id(caster.race_id) if caster != null else null
	var caste := content.characters.caste_by_id(caster.caste_id) if caster != null else null
	var use_probe := _context.inventory.classic_spell_item_probe(caster, instance, item, spell, race, caste, true)
	if not use_probe.allowed:
		return CombatSpellCastProbe.blocked(item_use_reason_code(instance, item, spell), use_probe.reason)
	if ClassicSpellDispositionRules.combat_item_disposition(spell) != ClassicSpellDispositionRules.DISPOSITION_EXECUTABLE:
		return CombatSpellCastProbe.blocked(&"unsupported_combat_item_effect", ClassicSpellDispositionRules.unsupported_reason(spell, &"combat-item"))
	if ClassicSpellConditionRules.is_combat_persistent_field_spell(spell) and not combat.spell_runtime.can_queue_persistent_field():
		return CombatSpellCastProbe.blocked(&"persistent_field_queue_limit", "Castle's persistent battlefield-field queue is full.")
	var staged_instance_id := combat.turns.staged_random_item_instance_id()
	if not staged_instance_id.is_empty() and staged_instance_id != instance.id:
		return CombatSpellCastProbe.blocked(&"random_item_target_pending", "Finish targeting the random-power item already staged for this activation.")
	# An unstaged random-power item is a valid source; target validation follows after power preparation.
	return CombatSpellCastProbe.permitted()


func probe_scroll(state: GameState, content: RealmzContent, caster_id: String, scroll_slot: int) -> CombatSpellCastProbe:
	if state == null or content == null:
		return CombatSpellCastProbe.fault(&"invalid_scroll_turn", "Scroll use requires an active game session.")
	var combat := state.combat
	if combat != null and not combat.completed and combat.battlefield == null:
		return CombatSpellCastProbe.fault(&"missing_battlefield", "The active battle has no validated battlefield.")
	if combat == null or combat.completed or combat.battlefield == null or combat.turns.active_actor_id() != caster_id:
		return CombatSpellCastProbe.blocked(&"invalid_scroll_turn", "Only the active character may use a scroll in combat.")
	if not combat.spell_runtime.pending_death_macro_id().is_empty():
		return CombatSpellCastProbe.blocked(&"spell_death_macro_pending", "A spell-triggered monster death macro must complete before another combat action.")
	var caster := state.party.character_by_id(caster_id)
	if caster == null or caster.current_health <= 0 or caster.conditions.is_active(ConditionRules.ANIMATED):
		return CombatSpellCastProbe.blocked(&"scroll_user_unavailable", "The active character cannot use a scroll.")
	if not _context.equipment.has_equipped_scroll_case(caster, content):
		return CombatSpellCastProbe.blocked(&"scroll_case_not_equipped", "Equip a scroll case before using its spells.")
	var scroll := caster.scroll_at(scroll_slot)
	var spell := content.magic.spell_by_id(scroll.spell_id) if scroll != null and not scroll.is_empty() else null
	if scroll != null and not scroll.is_empty() and spell == null:
		return CombatSpellCastProbe.fault(&"unknown_spell", "Scroll spell '%s' has no immutable definition." % scroll.spell_id)
	if scroll_slot < 0 or scroll_slot >= 5 or scroll == null or scroll.is_empty() or spell == null or scroll.power < 1 or scroll.power > 7:
		return CombatSpellCastProbe.blocked(&"invalid_scroll_slot", "This scroll slot is empty or invalid.")
	if not spell.in_combat:
		return CombatSpellCastProbe.blocked(&"scroll_not_available_in_combat", "This scroll cannot be used in combat.")
	if ClassicSpellDispositionRules.combat_scroll_disposition(spell) != ClassicSpellDispositionRules.DISPOSITION_EXECUTABLE:
		return CombatSpellCastProbe.blocked(&"unsupported_combat_scroll", ClassicSpellDispositionRules.unsupported_reason(spell, &"combat-scroll"))
	if ClassicSpellConditionRules.is_combat_persistent_field_spell(spell) and not combat.spell_runtime.can_queue_persistent_field():
		return CombatSpellCastProbe.blocked(&"persistent_field_queue_limit", "Castle's persistent battlefield-field queue is full.")
	var summon_spell: bool = CombatFlowSummoning.is_summon_spell(spell)
	if spell.target_type == 0 and spell.size != 0 and not summon_spell:
		return CombatSpellCastProbe.blocked(&"repeated_open_space_spell_unresolved", "Classic target type 0 with nonzero size selects open-space footprints for summoning or special behavior, not ordinary actors.")
	var cast_level := spell.classic_tier()
	if cast_level < 0 or cast_level > 6:
		return CombatSpellCastProbe.fault(&"invalid_classic_spell_tier", "The scroll spell ID does not encode a valid Classic tier.")
	return CombatSpellCastProbe.permitted()


static func inventory_instance(character: CharacterState, instance_id: String) -> ItemInstance:
	if character == null:
		return null
	for instance: ItemInstance in character.inventory():
		if instance.id == instance_id:
			return instance
	return null


static func item_use_reason_code(instance: ItemInstance, item: ItemDefinition, spell: SpellDefinition) -> StringName:
	if instance == null or item == null:
		return &"unknown_item_instance"
	if instance.charges == 0:
		return &"item_has_no_charges"
	if item.special_2 <= 1100:
		return &"item_has_no_spell_effect"
	if spell == null:
		return &"unknown_item_spell"
	return &"item_cannot_be_used"
