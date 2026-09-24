## Maps Castle's context-specific keys to existing visible application controls.
class_name ClassicKeyboardShortcuts
extends RefCounted

# Castle checkkeypad.c, combat.c, items.c and choice.c own these contexts.
const EXPLORATION := {
	KEY_I: &"inventory", KEY_M: &"money", KEY_S: &"spells", KEY_T: &"trade",
	KEY_A: &"area_search", KEY_C: &"camp", KEY_H: &"heal", KEY_R: &"rest",
	KEY_E: &"encounter", KEY_G: &"service", KEY_L: &"scrolls", KEY_K: &"make_scroll",
}
const COMBAT := {
	KEY_I: &"items", KEY_A: &"auto_turn", KEY_L: &"scrolls", KEY_S: &"spells",
	KEY_U: &"undo", KEY_E: &"escape", KEY_G: &"guard", KEY_B: &"bandage",
	KEY_R: &"reveal_friends", KEY_D: &"delay", KEY_C: &"center_active",
	KEY_N: &"inspect_next", KEY_P: &"inspect_previous", KEY_F: &"finish", KEY_W: &"weapon", KEY_M: &"center_pointer",
}
const INVENTORY := {
	KEY_J: &"join", KEY_D: &"drop", KEY_C: &"identify", KEY_U: &"use",
	KEY_T: &"trade", KEY_ENTER: &"equip", KEY_KP_ENTER: &"equip", KEY_SPACE: &"equip",
}
const SHOP := {KEY_I: &"items", KEY_M: &"money", KEY_P: &"pool", KEY_S: &"share", KEY_ENTER: &"done", KEY_KP_ENTER: &"done"}
const SPELLS := {KEY_SPACE: &"cast", KEY_K: &"make_scroll", KEY_A: &"abort"}
const BUTTONS := {
	&"join": ["JoinAction"], &"drop": ["DropAction"], &"identify": ["IdentifyAction"],
	&"use": ["UseAction"], &"trade": ["TradeAction"], &"equip": ["EquippedAction"],
	&"items": ["ShopItems", "InventoryTradeItems"], &"money": ["InventoryShopMoney", "ShopMoney", "InventoryTradeMoney"],
	&"pool": ["ShopPool", "ShopCompactPool"], &"share": ["ShopShare", "ShopCompactShare"],
	&"done": ["InventoryShopDone", "ShopDone"],
	&"cast": ["SpellCastAction", "CombatSpellAim"], &"make_scroll": ["MakeScrollAction"],
}


static func ensure_defaults() -> void:
	for scope: String in ["exploration", "combat", "inventory", "shop", "spells"]:
		for code: int in bindings(scope):
			var name := _action_name(scope, code)
			if not InputMap.has_action(name): InputMap.add_action(name)
			var event := InputEventKey.new()
			event.physical_keycode = code as Key
			if not InputMap.action_has_event(name, event): InputMap.action_add_event(name, event)


static func action(event: InputEventKey, scope: String) -> StringName:
	if event == null or not event.pressed or event.ctrl_pressed or event.meta_pressed or event.alt_pressed:
		return &""
	for code: int in bindings(scope):
		if event.is_action_pressed(_action_name(scope, code), true):
			return bindings(scope)[code]
	return &""


static func bindings(scope: String) -> Dictionary:
	match scope:
		"exploration": return EXPLORATION
		"combat": return COMBAT
		"inventory": return INVENTORY
		"shop": return SHOP
		"spells": return SPELLS
	return {}


static func _action_name(scope: String, code: int) -> StringName:
	return StringName("realmz_classic_%s_%s" % [scope, String(bindings(scope)[code])])


static func visible_button(root: Node, action_id: StringName) -> BaseButton:
	for name: String in BUTTONS.get(action_id, []):
		for candidate: Node in root.find_children(name, "BaseButton", true, false):
			var button := candidate as BaseButton
			if button.is_visible_in_tree(): return button
	return null


static func activate_visible(root: Node, action_id: StringName) -> bool:
	var button := visible_button(root, action_id)
	if button == null or button.disabled: return false
	button.pressed.emit()
	return true
