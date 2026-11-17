## Filters a readable action log and lays it out for reading: round headings, one block per
## acting combatant, repeated lines folded into a count. It reads only the lines' own wording.
class_name ActionLogFormat
extends RefCounted

const ROUND_PREFIX := "Round "
const TURN_SUFFIX := " acts"
const MOVE_SUFFIX := " moved"
const ATTACK_INFIX := " attacks "
const FACT_INFIX := " · "
const INDENT := "    "


## The lines to show: movement dropped when `hide_movement`, and, when `actor` is named, only
## lines that actor makes or receives. Round headings always stay.
static func filtered(lines: Array[String], hide_movement: bool, actor: String) -> Array[String]:
	var result: Array[String] = []
	for line: String in lines:
		if hide_movement and line.ends_with(MOVE_SUFFIX): continue
		if not actor.is_empty() and not line.begins_with(ROUND_PREFIX) and actor not in names_in(line): continue
		result.append(line)
	return result


## Every name that makes or receives a line, in first-seen order.
static func actors(lines: Array[String]) -> Array[String]:
	var result: Array[String] = []
	for line: String in lines:
		if line.begins_with(ROUND_PREFIX): continue
		for name: String in names_in(line):
			if not result.has(name): result.append(name)
	return result


## The names a line concerns: its subject and, for an attack, its target.
static func names_in(line: String) -> Array[String]:
	var result: Array[String] = []
	if line.contains(ATTACK_INFIX):
		result.assign(line.split(ATTACK_INFIX, true, 1))
	elif line.ends_with(TURN_SUFFIX): result.append(line.trim_suffix(TURN_SUFFIX))
	elif line.ends_with(MOVE_SUFFIX): result.append(line.trim_suffix(MOVE_SUFFIX))
	elif line.contains(FACT_INFIX): result.append(line.split(FACT_INFIX, true, 1)[0])
	return result


## Consecutive identical lines become one line with a count.
static func folded(lines: Array[String]) -> Array[String]:
	var result: Array[String] = []
	var index := 0
	while index < lines.size():
		var count := 1
		while index + count < lines.size() and lines[index + count] == lines[index]: count += 1
		result.append(lines[index] if count == 1 else "%s ×%d" % [lines[index], count])
		index += count
	return result


## The lines as RichTextLabel markup: round headings in `accent` at `heading_size`, each
## acting combatant's name leading an indented block, movement in `muted`.
static func markup(lines: Array[String], accent: Color, muted: Color, heading_size: int) -> String:
	var parts: Array[String] = []
	var in_turn := false
	for line: String in folded(lines):
		var text := line.replace("[", "[lb]")
		if line.begins_with(ROUND_PREFIX):
			parts.append("%s[font_size=%d][color=#%s]%s[/color][/font_size]" % ["" if parts.is_empty() else "\n", heading_size, accent.to_html(false), text])
			in_turn = false
		elif line.ends_with(TURN_SUFFIX):
			parts.append("%s[color=#%s]%s[/color]" % ["" if parts.is_empty() else "\n", accent.to_html(false), text.trim_suffix(TURN_SUFFIX)])
			in_turn = true
		elif (line.substr(0, line.rfind(" ×")) if line.contains(" ×") else line).ends_with(MOVE_SUFFIX):
			parts.append("%s[color=#%s]%s[/color]" % [INDENT if in_turn else "", muted.to_html(false), text])
		else:
			parts.append("%s%s%s" % [INDENT if in_turn else "", INDENT if in_turn and not line.contains(ATTACK_INFIX) and _follows_action(parts) else "", text])
	return "\n".join(parts)


## True when the previous line in a turn was an attack or one of its results, so a result
## sits one step further in than the action it belongs to.
static func _follows_action(parts: Array[String]) -> bool:
	return not parts.is_empty() and (parts[-1].contains(ATTACK_INFIX) or parts[-1].begins_with(INDENT + INDENT))
