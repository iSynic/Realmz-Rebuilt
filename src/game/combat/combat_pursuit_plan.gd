## Retains one initial pursuit step until a mutation or reaction invalidates it.
class_name CombatPursuitPlan
extends RefCounted

var _field: BattlefieldState
var _actor_id: String
var _target_id: String
var _movement: int
var _contact: bool
var _actors_revision: int
var _terrain_revision: int
var _step: BattlefieldStepResult


func _init(field: BattlefieldState, actor_id: String, target_id: String, movement: int, contact: bool, step: BattlefieldStepResult) -> void:
	_field = field
	_actor_id = actor_id
	_target_id = target_id
	_movement = movement
	_contact = contact
	_actors_revision = field.actors.revision()
	_terrain_revision = field.terrain.revision()
	_step = step


func initial_step(field: BattlefieldState, actor_id: String, target_id: String, movement: int, contact: bool, visited: Array[Vector2i]) -> BattlefieldStepResult:
	if field != _field or actor_id != _actor_id or target_id != _target_id or movement != _movement or contact != _contact:
		return null
	if field.actors.revision() != _actors_revision or field.terrain.revision() != _terrain_revision:
		return null
	# The planner excludes the current anchor already; any older anchor changes
	# the route query and must use an ordinary fresh search.
	if visited.size() != 1 or visited[0] != field.actors.actor_position(actor_id):
		return null
	return _step
