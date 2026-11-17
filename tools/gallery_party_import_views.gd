## Representative Import party from save views for the UI gallery: a populated save list, the
## unreadable-save banner, and review cards with stock art, a blocked character and long lists.
extends RefCounted


static func sources() -> Array:
	return [
		{"title": "City of Bywater", "slot": "Slot B", "backup": false, "when": "Today, 21:40", "party": "Keylar, Lothlorian, Silver Leaf, Traskelion, Trevor, Vormale", "valid": true, "reason": "", "tooltip": ""},
		{"title": "City of Bywater", "slot": "Slot B", "backup": true, "when": "Today, 20:05", "party": "Keylar, Lothlorian, Silver Leaf, Traskelion, Trevor, Vormale", "valid": true, "reason": "", "tooltip": ""},
		{"title": "Trouble in the Sword Lands", "slot": "Slot C", "backup": false, "when": "12 Nov 2026, 18:22", "party": "Anwen, Brask, Corin, Dara", "valid": true, "reason": "", "tooltip": ""},
		{"title": "Mithril Vault", "slot": "Slot C", "backup": false, "when": "9 Nov 2026, 10:02", "party": "Ari", "valid": false, "reason": "Needs the Mithril Vault version it was saved with. Install it from Choose a scenario, then Refresh.", "tooltip": "Needs package fingerprint 1a2b3c4d."},
		{"title": "Realmz Synthetic Fixture", "slot": "Slot A", "backup": false, "when": "2 Oct 2026, 08:15", "party": "Bryn", "valid": false, "reason": "Uses save format v1, which this version can't read.", "tooltip": "Save format v1 is incompatible with Realmz Rebuilt save v9."},
	]


static func selection() -> Dictionary:
	return {"phase": "selection", "sources": sources()}


static func error() -> Dictionary:
	return {"phase": "error", "sources": sources(), "error_title": "Couldn't read City of Bywater · Slot B", "message": "The save changed or is damaged since the list was made. Choose it again, or choose another save."}


static func review(portraits: Array[String], icons: Array[String]) -> Dictionary:
	var spells := ["Light", "Charm Person", "Fire Bolt", "Detect Magic", "Shield", "Sleep", "Magic Missile", "Web", "Haste", "Scroll of Light"]
	var cards: Array = [
		_card("Keylar", "Level 4 Half-Ogre Barbarian", "Stamina 31/34  ·  SP —  ·  212 gold, 3 gems, 1 jewelry", ["Broadsword", "Chain Mail", "Shield", "Healing Potion ×2 (this adventure's version)"], [], ["Bywater Guild Key (scenario item)"]),
		_card("Lothlorian", "Level 4 Elf Sorcerer", "Stamina 16/18  ·  SP 41/62  ·  88 gold", ["Quarterstaff", "Robe"], spells, []),
		_card("Silver Leaf", "Level 4 Halfling Thief", "Stamina 20/20  ·  SP —  ·  140 gold, 1 gem", ["Short Sword", "Leather Armor", "Lock Picks"], [], []),
		_card("Traskelion", "Level 12 Dwarf Fighter", "Stamina 88/88  ·  SP —  ·  1,204 gold", ["Battle Axe", "Plate Mail"], [], []),
	]
	for index: int in cards.size():
		cards[index]["portrait_id"] = portraits[index % portraits.size()] if not portraits.is_empty() else ""
		cards[index]["icon_id"] = icons[index % icons.size()] if not icons.is_empty() else ""
	cards[2]["portrait_id"] = ""
	cards[2]["icon_id"] = ""
	cards[3]["eligible"] = false
	cards[3]["selected"] = false
	cards[3]["reasons"] = ["Traskelion is level 12; this adventure allows characters up to level 8."]
	return {"phase": "review", "candidates": cards, "available_slots": 4, "left_behind": ["Pooled money, bank balances, shared storage, and confiscated equipment stay in the source adventure.", "2 recruited allies or summons stay in the source adventure."], "changed_items": ["Healing Potion", "Lock Picks"], "adopt_changed": true, "source_line": "From City of Bywater · Slot B · Today, 21:40", "destination": "Joining Trouble in the Sword Lands", "error": ""}


static func _card(name: String, identity: String, stats: String, items: Array, magic: Array, left: Array) -> Dictionary:
	return {"name": name, "identity": identity, "stats": stats, "eligible": true, "selected": true, "reasons": [], "items": items, "magic": magic, "left": left, "left_tooltip": "", "portrait": null, "icon": null}
