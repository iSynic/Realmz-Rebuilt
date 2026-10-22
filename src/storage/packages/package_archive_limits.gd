## Bounds untrusted package archives from their ZIP central directory before any entry is inflated.

class_name PackageArchiveLimits
extends RefCounted

## Bundled worlds peak near 37 MiB per entry and 67 MiB per archive.
const MAX_ENTRY_BYTES: int = 512 * 1024 * 1024
const MAX_TOTAL_BYTES: int = 2 * 1024 * 1024 * 1024
const _END_RECORD_SIZE: int = 22
const _MAX_COMMENT_BYTES: int = 65_535
const _END_SIGNATURE: int = 0x06054b50
const _ENTRY_SIGNATURE: int = 0x02014b50
const _ENTRY_HEADER_SIZE: int = 46


## Returns an empty string when every declared entry size is within bounds.
## Godot sizes each inflate buffer from these declared sizes, so checking them
## first prevents a small hostile archive from exhausting memory.
static func error_for(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return "Could not open package for size validation."
	var length := file.get_length()
	var tail_size := mini(length, _END_RECORD_SIZE + _MAX_COMMENT_BYTES)
	file.seek(length - tail_size)
	var tail := file.get_buffer(tail_size)
	var end := -1
	for offset: int in range(tail.size() - _END_RECORD_SIZE, -1, -1):
		if tail.decode_u32(offset) == _END_SIGNATURE:
			end = offset
			break
	if end < 0:
		return "Package is not a readable ZIP archive."
	var entry_count := tail.decode_u16(end + 10)
	var directory_size := tail.decode_u32(end + 12)
	var directory_offset := tail.decode_u32(end + 16)
	if entry_count == 0xFFFF or directory_size == 0xFFFFFFFF or directory_offset == 0xFFFFFFFF:
		return "ZIP64 package archives are not supported."
	if directory_offset + directory_size > length:
		return "Package ZIP directory lies outside the archive."
	file.seek(directory_offset)
	var directory := file.get_buffer(directory_size)
	var cursor := 0
	var total := 0
	for index: int in entry_count:
		if cursor + _ENTRY_HEADER_SIZE > directory.size() or directory.decode_u32(cursor) != _ENTRY_SIGNATURE:
			return "Package ZIP directory is malformed."
		var entry_bytes := directory.decode_u32(cursor + 24)
		if entry_bytes > MAX_ENTRY_BYTES:
			return "A package entry declares %d bytes, above the %d-byte limit." % [entry_bytes, MAX_ENTRY_BYTES]
		total += entry_bytes
		if total > MAX_TOTAL_BYTES:
			return "Package entries declare more than %d bytes in total." % MAX_TOTAL_BYTES
		cursor += _ENTRY_HEADER_SIZE + directory.decode_u16(cursor + 28) + directory.decode_u16(cursor + 30) + directory.decode_u16(cursor + 32)
	return ""
