## Validates portable selected artwork and exposes its immutable image bytes.
class_name CharacterArtBundle
extends MediaSource

const MAX_IMAGE_BYTES := 64 * 1024
const MAX_ASSETS := 16

var _entries: Dictionary = {}


func assets() -> Array[MediaAsset]:
	var result: Array[MediaAsset] = []
	for id: String in _entries:
		result.append(asset_by_id(id))
	return result


func asset_by_id(id: String) -> MediaAsset:
	if not _entries.has(id):
		return null
	var entry: Dictionary = _entries[id]
	var size := 44 if entry.kind == CharacterAppearanceDefinition.PORTRAIT else 32
	return MediaAsset.new(id, entry.label, entry.kind, "image/png", "", 0, (entry.bytes as PackedByteArray).size(), entry.hash, "", size, size, 0, 0, 0, 0, 0, 0, 0, 0, 0)


func owns_asset(asset: MediaAsset) -> bool:
	return asset != null and _entries.has(asset.id)


func read_bytes(asset: MediaAsset) -> PackedByteArray:
	return (_entries[asset.id].bytes as PackedByteArray).duplicate() if owns_asset(asset) else PackedByteArray()


func entries() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for id: String in _entries:
		var entry: Dictionary = _entries[id]
		result.append({"id": id, "group": entry.group, "label": entry.label, "kind": entry.kind})
	return result


func appearance_options() -> Array[CharacterAppearanceOptionView]:
	var result: Array[CharacterAppearanceOptionView] = []
	for id: String in _entries:
		var entry: Dictionary = _entries[id]
		var option := CharacterAppearanceOptionView.new(CharacterAppearanceDefinition.new(id, entry.label, StringName(entry.kind), 0))
		option.art_group = entry.group
		result.append(option)
	result.sort_custom(func(left: CharacterAppearanceOptionView, right: CharacterAppearanceOptionView) -> bool: return (left.art_group + left.label + left.id).naturalnocasecmp_to(right.art_group + right.label + right.id) < 0)
	return result


func to_data() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var ids := _entries.keys()
	ids.sort()
	for id: String in ids:
		var entry: Dictionary = _entries[id]
		result.append({"id": id, "group": entry.group, "label": entry.label, "kind": entry.kind, "png": Marshalls.raw_to_base64(entry.bytes)})
	return result


func add(id: String, group: String, label: String, kind: String, bytes: PackedByteArray) -> bool:
	if not CharacterArtIdentity.is_valid(id, kind) or group.strip_edges().is_empty() or group.length() > 128 or label.strip_edges().is_empty() or label.length() > 128 or bytes.size() < 33 or bytes.size() > MAX_IMAGE_BYTES:
		return false
	var target_size := 44 if kind == CharacterAppearanceDefinition.PORTRAIT else 32
	if bytes.slice(0, 8) != PackedByteArray([137, 80, 78, 71, 13, 10, 26, 10]) or bytes.slice(12, 16).get_string_from_ascii() != "IHDR" or bytes.decode_u32(16) != _big_endian(target_size) or bytes.decode_u32(20) != _big_endian(target_size):
		return false
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(bytes)
	var digest := hash.finish().hex_encode()
	if id != CharacterArtIdentity.make(kind, digest):
		return false
	var image := Image.new()
	if image.load_png_from_buffer(bytes) != OK or image.get_size() != Vector2i(target_size, target_size):
		return false
	_entries[id] = {"group": group, "label": label, "kind": kind, "bytes": bytes.duplicate(), "hash": digest}
	return true


func matches_characters(characters: Array[CharacterState]) -> bool:
	var required: Dictionary = {}
	for character: CharacterState in characters:
		for kind: String in [CharacterAppearanceDefinition.PORTRAIT, CharacterAppearanceDefinition.COMBAT_ICON]:
			var id := character.portrait_id if kind == CharacterAppearanceDefinition.PORTRAIT else character.combat_icon_id
			if not CharacterArtIdentity.is_imported(id):
				continue
			if not CharacterArtIdentity.is_valid(id, kind) or not _entries.has(id):
				return false
			required[id] = true
	return required.size() == _entries.size()


static func from_data(data: Variant) -> CharacterArtBundle:
	if not data is Array or data.size() > MAX_ASSETS:
		return null
	var result := CharacterArtBundle.new()
	for value: Variant in data:
		if not value is Dictionary or value.size() != 5:
			return null
		for field: String in ["id", "group", "label", "kind", "png"]:
			if not value.get(field) is String:
				return null
		if value.png.length() > MAX_IMAGE_BYTES * 2 or result._entries.has(value.id) or not result.add(value.id, value.group, value.label, value.kind, Marshalls.base64_to_raw(value.png)):
			return null
	return result


static func snapshot_characters(snapshot: SessionSnapshot) -> Array[CharacterState]:
	var result := snapshot.game_state.party.characters()
	var draft := snapshot.game_state.character_draft
	if draft != null:
		var selection := CharacterState.new("draft-art", "", 1, 1)
		selection.portrait_id = draft.portrait_id
		selection.combat_icon_id = draft.combat_icon_id
		result.append(selection)
		if draft.generated_character != null:
			result.append(draft.generated_character)
	return result


static func _big_endian(value: int) -> int:
	return (value & 255) << 24
