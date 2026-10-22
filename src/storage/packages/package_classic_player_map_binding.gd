## Verifies complete native Player Map facts and their safe display projection.
class_name PackageClassicPlayerMapBinding
extends RefCounted

static func verify_effective_source(records: ClassicRecordCatalog, source: ClassicRecordCatalog.Source, effective: PackedByteArray) -> String:
	if source.native_path != "Data MD2": return ""
	var prefix := PackedByteArray()
	for native_id: int in int(effective.size() / 340):
		var facts := records.player_map_by_id(native_id)
		if facts == null: return "Player Map facts omit complete native row %d." % native_id
		for word: int in facts.words:
			PackageClassicRecordBinding.append_signed_short(prefix, word)
		prefix.append_array(PackedByteArray(facts.note_bytes))
	if prefix != effective.slice(0, prefix.size()):
		return "Player Map facts differ from their retained effective source bytes."
	return ""

static func bind(content: RealmzContent, records: ClassicRecordCatalog) -> String:
	var source := records.source_by_path("Data MD2")
	if source == null: return ""
	for native_id: int in int(source.effective_byte_length / 340):
		var facts := records.player_map_by_id(native_id)
		if facts == null: return "The compiler omitted Player Map facts %d." % native_id
		var definition := content.world.player_map_by_classic_id(native_id)
		if not facts.can_project():
			if definition != null: return "An unsafe Player Map acquired a fabricated display definition."
			continue
		if definition == null: return "The compiler omitted complete usable Player Map %d." % native_id
		var words := facts.words
		var expected_mode := PlayerMapDefinition.SCROLLING_TEXT if words[35] < 0 else (PlayerMapDefinition.PICTURE if words[33] != 0 else (PlayerMapDefinition.DUNGEON_CROP if words[36] != 0 else PlayerMapDefinition.LAND_CROP))
		if definition.mode != expected_mode or definition.start != Vector2i(words[30], words[31]) or definition.icon_size != words[34]:
			return "Player Map %d changed its signed mode, start, or scale." % native_id
		if definition.picture_rect != Rect2i(words[39], words[38], words[41] - words[39], words[40] - words[38]):
			return "Player Map %d changed its native picture rectangle." % native_id
		var error := _bind_references(content, definition, facts)
		if not error.is_empty(): return error
	return ""

static func _bind_references(content: RealmzContent, definition: PlayerMapDefinition, facts: ClassicRecordCatalog.PlayerMapFacts) -> String:
	var words := facts.words
	if definition.mode == PlayerMapDefinition.SCROLLING_TEXT:
		return "" if _resource_matches(content, definition.scrolling_text_asset_id, "TEXT", words[35]) else "Player Map changed its exact TEXT key."
	if definition.map_id != "%s:%d" % ["dungeon" if words[36] != 0 else "land", words[32]]:
		return "Player Map changed its native source-map identity."
	if not _resource_matches(content, definition.party_marker_asset_id, "cicn", 138):
		return "Player Map changed its current-party icon key."
	if definition.mode == PlayerMapDefinition.PICTURE:
		return "" if _resource_matches(content, definition.picture_asset_id, "PICT", words[33]) else "Player Map changed its exact PICT key."
	var markers := definition.markers()
	var index := 0
	for slot: int in range(0, 30, 3):
		if words[slot] == 0: continue
		if index >= markers.size(): return "Player Map omitted a native marker."
		var marker := markers[index]
		if marker.classic_icon_id != words[slot] or marker.coordinate != Vector2i(words[slot + 1], words[slot + 2]) or not _resource_matches(content, marker.icon_asset_id, "cicn", words[slot]):
			return "Player Map changed a signed native marker slot."
		index += 1
	return "" if index == markers.size() else "Player Map added a marker outside its native slots."

static func _resource_matches(content: RealmzContent, identity: String, resource_type: String, resource_id: int) -> bool:
	for asset: MediaAsset in content.media_assets:
		if asset.id == identity:
			return asset.resource_type == resource_type and asset.resource_id == resource_id
	return identity == "classic.resource.%s.%d" % [resource_type, resource_id]
