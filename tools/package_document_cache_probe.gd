extends SceneTree

const DOCUMENTS: Array[String] = ["content.json", "world.json", "scenario.json", "assets/index.json"]


func _initialize() -> void:
	var arguments := OS.get_cmdline_user_args()
	if arguments.size() != 1:
		printerr("Usage: godot --headless --path <project> --script res://tools/package_document_cache_probe.gd -- <package.realmz2>")
		quit(2)
		return
	var archive := ZIPReader.new()
	if archive.open(arguments[0]) != OK:
		printerr("Could not open package.")
		quit(1)
		return
	var documents: Dictionary = {}
	var parse_started := Time.get_ticks_msec()
	for path: String in DOCUMENTS:
		documents[path] = JSON.parse_string(archive.read_file(path).get_string_from_utf8())
	var parse_ms := Time.get_ticks_msec() - parse_started
	archive.close()
	var encode_started := Time.get_ticks_msec()
	var encoded := var_to_bytes(documents)
	var encode_ms := Time.get_ticks_msec() - encode_started
	var compress_started := Time.get_ticks_msec()
	var compressed := encoded.compress(FileAccess.COMPRESSION_ZSTD)
	var compress_ms := Time.get_ticks_msec() - compress_started
	var decompress_started := Time.get_ticks_msec()
	var restored := compressed.decompress(encoded.size(), FileAccess.COMPRESSION_ZSTD)
	var decompress_ms := Time.get_ticks_msec() - decompress_started
	var decode_started := Time.get_ticks_msec()
	var decoded: Variant = bytes_to_var(restored)
	var decode_ms := Time.get_ticks_msec() - decode_started
	print(CanonicalJson.encode({
		"cacheBytes": encoded.size(),
		"compressedBytes": compressed.size(),
		"compressMs": compress_ms,
		"decodeMs": decode_ms,
		"decompressMs": decompress_ms,
		"documents": decoded.size() if decoded is Dictionary else 0,
		"encodeMs": encode_ms,
		"parseMs": parse_ms,
	}))
	quit(0)
