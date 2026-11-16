## Turns detached save sources and transfer reviews into the primitive card data the
## import dialog draws. Never shows raw IDs or hashes as primary text.
class_name PartyImportViewBuilder
extends RefCounted

const MONTHS := ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
const CHANGED_REASON := "This adventure defines a different version."
const SCENARIO_REASON := "This adventure has no matching version of this scenario item."


## Importable saves first, newest first; the dialog reports indices into this order.
static func sort_sources(sources: Array[SavePartySource], records: Array[PackageDiscoveryResult]) -> void:
	var usable: Dictionary = {}
	for source: SavePartySource in sources:
		usable[source] = source.is_valid() and package_for(source, records) != null
	sources.sort_custom(func(a: SavePartySource, b: SavePartySource) -> bool:
		if usable[a] != usable[b]:
			return usable[a]
		return a.modified_unix > b.modified_unix)


static func package_for(source: SavePartySource, records: Array[PackageDiscoveryResult]) -> PackageDiscoveryResult:
	for record: PackageDiscoveryResult in records:
		if record.ready and record.campaign_id == source.campaign_id and record.package_hash == source.package_hash:
			return record
	return null


## The scenario's name from any installed revision, else a readable form of its ID.
static func title_for(campaign_id: String, records: Array[PackageDiscoveryResult]) -> String:
	for record: PackageDiscoveryResult in records:
		if record.campaign_id == campaign_id and not record.display_name.is_empty():
			return record.display_name
	if campaign_id.is_empty():
		return "Unknown scenario"
	return campaign_id.replace("-", " ").replace("_", " ").capitalize()


static func source_row(source: SavePartySource, records: Array[PackageDiscoveryResult]) -> Dictionary:
	var title := title_for(source.campaign_id, records)
	var row := {"title": title, "slot": slot_label(source), "backup": source.source_kind == &"backup", "when": when_label(source.modified_unix), "party": ", ".join(source.party_names), "valid": false, "reason": "", "tooltip": ""}
	if not source.is_valid():
		row["reason"] = error_reason(source.error)
		row["tooltip"] = source.error
	elif package_for(source, records) == null:
		row["reason"] = missing_package_reason(source, records)
		row["tooltip"] = "Needs package fingerprint %s." % source.package_hash.left(8)
	else:
		row["valid"] = true
		row["tooltip"] = "Choose who joins from %s." % title
	return row


static func slot_label(source: SavePartySource) -> String:
	if source.source_kind == &"external":
		return "File %s.r2save" % source.slot_id
	return "Slot %s" % source.slot_id.to_upper() if source.slot_id.length() == 1 else source.slot_id


static func missing_package_reason(source: SavePartySource, records: Array[PackageDiscoveryResult]) -> String:
	return "Needs the %s version it was saved with. Install it from Choose a scenario, then Refresh." % title_for(source.campaign_id, records)


## A short player-facing reason; the full storage message stays in the tooltip.
static func error_reason(error: String) -> String:
	var schema := RegEx.create_from_string("[Ss]ave format v(\\d+)")
	var found := schema.search(error)
	if found != null:
		return "Uses save format v%s, which this version can't read." % found.get_string(1)
	return "This save is damaged or uses a format this version can't read."


## Local time: Today/Yesterday hh:mm, else d Mon yyyy, hh:mm.
static func when_label(unix: int) -> String:
	if unix <= 0:
		return ""
	var bias := int(Time.get_time_zone_from_system().get("bias", 0)) * 60
	var now := int(Time.get_unix_time_from_system()) + bias
	var at := Time.get_datetime_dict_from_unix_time(unix + bias)
	var clock := "%02d:%02d" % [at.hour, at.minute]
	if _same_day(at, Time.get_datetime_dict_from_unix_time(now)):
		return "Today, " + clock
	if _same_day(at, Time.get_datetime_dict_from_unix_time(now - 86400)):
		return "Yesterday, " + clock
	return "%d %s %d, %s" % [at.day, MONTHS[clampi(int(at.month) - 1, 0, 11)], at.year, clock]


static func _same_day(a: Dictionary, b: Dictionary) -> bool:
	return a.year == b.year and a.month == b.month and a.day == b.day


static func source_line(source: SavePartySource, records: Array[PackageDiscoveryResult]) -> String:
	var parts: Array[String] = ["From %s" % title_for(source.campaign_id, records), slot_label(source)]
	if source.source_kind == &"backup":
		parts.append("Backup")
	var when := when_label(source.modified_unix)
	if not when.is_empty():
		parts.append(when)
	return " · ".join(parts)


static func candidate_card(candidate: PartyTransferCandidate, content: RealmzContent, selected: bool, art: CharacterArtBundle) -> Dictionary:
	var character := candidate.character
	var card := {"name": "Unreadable character", "identity": "", "stats": "", "eligible": candidate.eligible(), "selected": selected, "reasons": candidate.reasons.duplicate(), "items": [], "magic": [], "left": [], "left_tooltip": "", "portrait_id": "", "icon_id": "", "portrait": null, "icon": null}
	if character == null:
		return card
	var view := CharacterView.new(character, content)
	card["name"] = view.name
	card["identity"] = "Level %d %s %s" % [view.level, view.race_name, view.caste_name]
	card["stats"] = "Stamina %d/%d  ·  SP %s  ·  %s" % [view.current_health, view.maximum_health, "—" if view.maximum_spell_points <= 0 else "%d/%d" % [view.spell_points, view.maximum_spell_points], money_label(character.money.gold, character.money.gems, character.money.jewelry)]
	card["portrait_id"] = view.portrait_id
	card["icon_id"] = view.combat_icon_id
	card["portrait"] = bundle_texture(art, view.portrait_id)
	card["icon"] = bundle_texture(art, view.combat_icon_id)
	_split_retained(candidate.retained, card)
	_bind_left_behind(candidate.omissions, card)
	return card


static func money_label(gold: int, gems: int, jewelry: int) -> String:
	var parts: Array[String] = []
	if gold > 0: parts.append("%d gold" % gold)
	if gems > 0: parts.append("%d %s" % [gems, "gem" if gems == 1 else "gems"])
	if jewelry > 0: parts.append("%d jewelry" % jewelry)
	return "no money" if parts.is_empty() else ", ".join(parts)


## Kept possessions split into items (identical names grouped) and spells and scrolls.
static func _split_retained(retained: Array[String], card: Dictionary) -> void:
	var counts: Dictionary = {}
	var order: Array[String] = []
	var magic: Array[String] = []
	var scroll := RegEx.create_from_string("^Scroll \\d+: (.*)$")
	for label: String in retained:
		if label.begins_with("Spell: "):
			magic.append(label.trim_prefix("Spell: "))
			continue
		var found := scroll.search(label)
		if found != null:
			magic.append("Scroll of %s" % found.get_string(1))
			continue
		if not counts.has(label):
			order.append(label)
		counts[label] = int(counts.get(label, 0)) + 1
	var items: Array[String] = []
	for label: String in order:
		items.append(label if counts[label] == 1 else "%s ×%d" % [label, counts[label]])
	card["items"] = items
	card["magic"] = magic


static func _bind_left_behind(omissions: Array[PartyTransferOmission], card: Dictionary) -> void:
	var left: Array[String] = []
	var tips: Array[String] = []
	for omission: PartyTransferOmission in omissions:
		left.append("%s (%s)" % [omission.label, _omission_tag(omission)])
		tips.append("%s — %s" % [omission.label, omission.reason])
	card["left"] = left
	card["left_tooltip"] = "\n".join(tips)


static func _omission_tag(omission: PartyTransferOmission) -> String:
	match omission.kind:
		&"item":
			if omission.reason == CHANGED_REASON: return "changed here"
			return "scenario item" if omission.reason == SCENARIO_REASON else "can't transfer"
		&"spell": return "scenario spell"
		&"binding": return "spell removed"
		_: return "can't transfer"


## Imported artwork carried by the save; stock art resolves later from the setup media.
static func bundle_texture(art: CharacterArtBundle, asset_id: String) -> Texture2D:
	if art == null or asset_id.is_empty():
		return null
	var asset := art.asset_by_id(asset_id)
	if asset == null:
		return null
	var image := Image.new()
	if image.load_png_from_buffer(art.read_bytes(asset)) != OK:
		return null
	return ImageTexture.create_from_image(image)
