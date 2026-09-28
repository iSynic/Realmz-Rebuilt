## Castle drawbody policy and disposable event-local backdrop state.
class_name ClassicCombatBackdrop
extends RefCounted

const TRAITOR := 1
const HELPLESS := 2
var actors: Dictionary = {}
var active_actor_id := ""


static func flags(traitor: bool, helpless: bool) -> int:
	return (TRAITOR if traitor else 0) | (HELPLESS if helpless else 0)


static func source_rect(footprint: Vector2i, state: int) -> Rect2:
	var extent := Vector2(footprint) * 32.0
	var corner := Vector2(512 + (64 if state & TRAITOR else 0), 416 + (128 if state & HELPLESS else 0))
	return Rect2(corner - extent, extent)


static func shown(id: String, active: String, state: int, forced: bool, frame: CombatPlaybackFrame) -> bool:
	if frame != null:
		if frame.hides(id): return false
		if not frame.active_combatant_id.is_empty(): active = frame.active_combatant_id
		if frame.kind == &"actor_cue": active = frame.actor_id
		if frame.kind in [&"melee_attack", &"projectile", &"spell_cast", &"spell_projectile", &"result"] and frame.actor_id == id: return true
		if frame.kind == &"backdrop_effect" and frame.target_id == id: return true
	return id == active or bool(state & HELPLESS) or forced


func seed(view: GameView) -> void:
	actors.clear()
	active_actor_id = ""
	if view == null or view.combat_view == null: return
	active_actor_id = view.combat_view.active_actor_id
	for character: CharacterView in view.party_members:
		actors[character.id] = flags(character.traitor, character.condition_values[ConditionRules.HELPLESS] != 0)
	for monster: MonsterView in view.combat_view.monsters:
		actors[monster.id] = flags(monster.traitor, monster.helpless)


func apply_result(payload: Dictionary, suffix: String = "After") -> void:
	if not payload.has("traitor" + suffix) and not payload.has("helpless" + suffix): return
	var id := String(payload.get("targetId", payload.get("characterId", payload.get("allyId", ""))))
	if id.is_empty(): return
	var state := int(actors.get(id, 0))
	if payload.has("traitor" + suffix):
		state = (state & ~TRAITOR) | (TRAITOR if bool(payload["traitor" + suffix]) else 0)
	if payload.has("helpless" + suffix):
		state = (state & ~HELPLESS) | (HELPLESS if bool(payload["helpless" + suffix]) else 0)
	actors[id] = state


static func clipped_source(destination: Rect2, source: Rect2, clip: Rect2) -> Rect2:
	var visible := destination.intersection(clip)
	var scale := source.size / destination.size
	return Rect2(source.position + (visible.position - destination.position) * scale, visible.size * scale)


static func interaction_forces(id: String, interaction: BattlefieldInteractionController) -> bool:
	return interaction.reveal_friends or id == interaction.inspected_combatant_id or id == interaction.backdrop_focus_id or interaction.targeting != null and interaction.targeting.classic_backdrops


func rewind(events: Array[DomainEvent]) -> void:
	for index: int in range(events.size() - 1, -1, -1):
		apply_result(events[index].payload, "Before")


func observe_action(event: DomainEvent) -> void:
	if bool(event.payload.get("reaction", false)): return
	if event.kind in [&"combatant_moved", &"combatants_swapped", &"combat_attack_resolved", &"combat_projectile_resolved", &"combat_turn_passed", &"combat_monster_action", &"combat_auto_started"]:
		active_actor_id = String(event.payload.get("actorId", active_actor_id))
	elif event.kind == &"combat_spell_cast" and event.payload.get("source", "") != "classic-monster-macro":
		active_actor_id = String(event.payload.get("actorId", active_actor_id))
