## Reverses only the byte-pinned, reviewed native-program restoration receipt.
class_name ProgramPackageDelta
extends RefCounted

const RECEIPT_PATH := "res://src/storage/packages/bundled_campaigns/program-restoration.json.zlib"
const RECEIPT_SHA256 := "c8211ba873d25dbebf9a92f7af760952071aa19e6c6cad2e4580a55fc050ef94"
const COMPRESSED_SHA256 := "3c622bb423d2123f23ea2d3cfde03f6f12caec887f3a43e40f13e870ec070272"
const RECEIPT_BYTES := 18764897
static var _receipt: Dictionary = {}


static func correction(campaign_id: String, package_hash: String) -> Dictionary:
	if _receipt.is_empty():
		if FileAccess.get_sha256(RECEIPT_PATH) != COMPRESSED_SHA256:
			return {}
		var bytes := FileAccess.get_file_as_bytes(RECEIPT_PATH).decompress(RECEIPT_BYTES, FileAccess.COMPRESSION_DEFLATE)
		if bytes.size() != RECEIPT_BYTES or PackageArchiveReader.new().sha256(bytes) != RECEIPT_SHA256:
			return {}
		var parsed: Variant = JSON.parse_string(bytes.get_string_from_utf8())
		if not parsed is Dictionary or parsed.get("kind") != "realmz-rebuilt.program-restoration" or parsed.get("formatVersion") != 1 or parsed.get("applicationPackageHash") != ApplicationLibraryIdentity.PACKAGE_HASH:
			return {}
		_receipt = parsed
	var predecessor := CompressionPackageDelta.previous_hash(campaign_id, package_hash)
	for row: Dictionary in _receipt.get("campaigns", []):
		if row.get("campaignId") == campaign_id and row.get("packageHash") == predecessor:
			return row.duplicate(true)
	return {}


static func reverse_documents(documents: Dictionary, record: Dictionary) -> bool:
	var recipe: Dictionary = record.get("recipe", {})
	if recipe.is_empty():
		return false
	for addition: Dictionary in recipe.monsterSetIntroductions:
		var sets: Array = documents["content.json"].monsterSets
		var matches: Array = sets.filter(func(row: Dictionary) -> bool: return row.setId == addition.setId)
		if matches.size() != 1 or matches[0] != addition:
			return false
		sets.erase(matches[0])
	var maps: Dictionary = {}
	for map: Dictionary in documents["world.json"].maps:
		maps[map.id] = map
	var cells: Array = recipe.cellChanges.duplicate()
	cells.reverse()
	for change: Dictionary in cells:
		var cell: Array = maps[change.mapId].cells[int(change.index)]
		if cell[4] != change.after:
			return false
		cell[4] = change.before.duplicate()
	for change: Dictionary in recipe.randomRectangleAdditions:
		if not _remove_rows(maps[change.mapId].randomRectangles, [change.record]):
			return false
	for group: Dictionary in recipe.monsterSetAdditions:
		var sets: Array = documents["content.json"].monsterSets.filter(func(row: Dictionary) -> bool: return row.setId == group.setId)
		if sets.size() != 1 or not _remove_rows(sets[0].monsters, group.monsters):
			return false
	for change: Dictionary in recipe.randomRectangleLayouts:
		if maps[change.mapId].randomRectangles != change.after:
			return false
		maps[change.mapId].randomRectangles = change.before.duplicate(true)
	for change: Dictionary in recipe.programReplacements:
		var programs: Array = documents["scenario.json"].programs
		var index := programs.find(change.after)
		if index < 0:
			return false
		programs[index] = change.before.duplicate(true)
	for change: Dictionary in recipe.get("textReplacements", []):
		var rows: Array = documents["content.json"][change.family]
		var index := rows.find(change.after)
		if index < 0:
			return false
		rows[index] = change.before.duplicate(true)
	for name: String in recipe.additions:
		for field: String in recipe.additions[name]:
			if not _remove_rows(documents[name][field], recipe.additions[name][field]):
				return false
	return true


static func reverse_payloads(files: Dictionary, record: Dictionary) -> bool:
	var recipe: Dictionary = record.get("recipe", {})
	if not recipe.has("payloadAdditions") or not recipe.has("assetIndexAdditions") or not files.has("assets/index.json"):
		return false
	for addition: Dictionary in recipe.payloadAdditions:
		if not files.has(addition.path):
			return false
		var bytes: PackedByteArray = files[addition.path]
		if bytes.size() != addition.bytes or PackageArchiveReader.new().sha256(bytes) != addition.sha256:
			return false
		files.erase(addition.path)
	var index: Variant = JSON.parse_string((files["assets/index.json"] as PackedByteArray).get_string_from_utf8())
	if not index is Dictionary or not index.get("assets") is Array or not _remove_rows(index.assets, recipe.assetIndexAdditions):
		return false
	for change: Dictionary in recipe.assetMetadataChanges:
		var matches: Array = index.assets.filter(func(row: Dictionary) -> bool: return row.id == change.after.id)
		if matches.size() != 1 or matches[0] != change.after:
			return false
		index.assets[index.assets.find(matches[0])] = change.before.duplicate(true)
	var previous_index := CanonicalJson.encode(index)
	if previous_index.sha256_text() != recipe.previousAssetIndexSha256:
		return false
	files["assets/index.json"] = previous_index.to_utf8_buffer()
	return true


static func _remove_rows(target: Array, additions: Array) -> bool:
	for addition: Dictionary in additions:
		var matches: Array = target.filter(func(row: Dictionary) -> bool: return row.get("id") == addition.id)
		if matches.size() != 1 or matches[0] != addition:
			return false
		target.erase(matches[0])
	return true
