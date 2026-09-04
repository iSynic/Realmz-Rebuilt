## Shares deterministic combat rules and owned collaborators across one combat system.

class_name CombatContext
extends RefCounted

var arithmetic: RealmzArithmetic
var inventory: InventoryRules
var equipment: EquipmentRules
var combat: CombatRules
var magic: MagicRules
var monsters: MonsterRules
var battlefield: BattlefieldRules
var spell_areas: SpellAreaRules
var processing_auto: bool = false
var _rounds: WeakRef
var _actions: WeakRef
var _reactions: WeakRef
var _magic: WeakRef
var _fields: WeakRef
var _summoning: WeakRef
var _phase: WeakRef
var _automation: WeakRef


func _init(rules: RealmzRules) -> void:
	arithmetic = rules.arithmetic
	inventory = rules.inventory
	equipment = rules.equipment
	combat = rules.combat
	magic = rules.magic
	monsters = rules.monsters
	battlefield = rules.battlefield
	spell_areas = rules.spell_areas


func bind_collaborators(
	rounds: RefCounted,
	actions: RefCounted,
	reactions: RefCounted,
	magic_flow: RefCounted,
	fields: RefCounted,
	summoning: RefCounted,
	phase: RefCounted,
	automation: RefCounted
) -> void:
	assert(rounds != null and actions != null and reactions != null and magic_flow != null, "Combat requires its round, action, reaction, and magic collaborators")
	assert(fields != null and summoning != null and phase != null and automation != null, "Combat requires its field, summoning, phase, and automation collaborators")
	_rounds = weakref(rounds)
	_actions = weakref(actions)
	_reactions = weakref(reactions)
	_magic = weakref(magic_flow)
	_fields = weakref(fields)
	_summoning = weakref(summoning)
	_phase = weakref(phase)
	_automation = weakref(automation)


func rounds() -> RefCounted:
	return _rounds.get_ref()


func actions() -> RefCounted:
	return _actions.get_ref()


func reactions() -> RefCounted:
	return _reactions.get_ref()


func magic_flow() -> RefCounted:
	return _magic.get_ref()


func fields() -> RefCounted:
	return _fields.get_ref()


func summoning() -> RefCounted:
	return _summoning.get_ref()


func phase() -> RefCounted:
	return _phase.get_ref()


func automation() -> RefCounted:
	return _automation.get_ref()
