## Session-local queue; randomness and playback position never enter GameState.
class_name MusicPlaybackQueue
extends RefCounted

var position: float = 0.0
var exhausted: bool = false
var signature: String = ""
var _tracks: Array[String] = []
var _order: Array[String] = []
var _cursor: int = 0
var _shuffle: bool = false
var _repeat: String = "all"
var _random: RandomNumberGenerator


func _init(random: RandomNumberGenerator = null) -> void:
	_random = random if random != null else RandomNumberGenerator.new()
	if random == null:
		_random.randomize()


func configure(playlist: MusicLibraryView.Playlist) -> bool:
	var next := JSON.stringify([playlist.id, playlist.tracks, playlist.shuffle, playlist.repeat]) if playlist != null else "original"
	if next == signature:
		return false
	signature = next
	_tracks.assign(playlist.tracks if playlist != null else ["@original"])
	_shuffle = playlist.shuffle if playlist != null else false
	_repeat = playlist.repeat if playlist != null else "one"
	position = 0.0
	exhausted = false
	_new_cycle()
	return true


func current() -> String:
	return "" if exhausted or _order.is_empty() else _order[_cursor]


func count() -> int:
	return _tracks.size()


func retry_unavailable(changed_tracks: Array[String]) -> bool:
	if not changed_tracks.any(func(id: String) -> bool: return id in _tracks):
		return false
	exhausted = false
	position = 0.0
	_cursor = 0
	return true


func advance(unavailable: bool = false) -> void:
	position = 0.0
	if _repeat == "one" and not unavailable:
		return
	_cursor += 1
	if _cursor < _order.size():
		return
	if _repeat == "none":
		exhausted = true
	else:
		_new_cycle()


func _new_cycle() -> void:
	_order = _tracks.duplicate()
	_cursor = 0
	if _shuffle:
		for index: int in range(_order.size() - 1, 0, -1):
			var selected := _random.randi_range(0, index)
			var held := _order[index]
			_order[index] = _order[selected]
			_order[selected] = held
