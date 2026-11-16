## One party member on the collapsed party dock: portrait, a stamina bar, a spell-point bar
## (both shaded by how much is left, as the roster's numbers are)
## and a column of buff pips. The portrait gains an accent outline when the member is the
## selected character, a corner badge while a harmful condition is active, and a brief
## outline in the warning colour on bad news.

class_name PartyDockEntry
extends Control

const PORTRAIT := 44.0
const BAR := 5.0
const GAP := 3.0
const PIP := 9.0
const MAX_PIPS := 4
const FLASH_SECONDS := 1.4
const TRACK_COLOR := Color(0.14, 0.17, 0.2)
const BUFF_COLOR := Color(0.47, 0.81, 0.6)

var character_id := ""
var _portrait: Texture2D
var _stamina := 1.0
var _spell := -1.0
var _buffs := 0
var _selected := false
var _afflicted := false
var _scale := 1.0
var _flash := 0.0:
	set(value):
		_flash = value
		queue_redraw()
var _flash_tween: Tween


## `facts`: id, name, portrait, stamina and spell fractions (spell below zero for none),
## buffs, selected, afflicted and a tooltip.
func bind(facts: Dictionary, ui_scale: float) -> void:
	character_id = String(facts.id)
	_portrait = facts.portrait as Texture2D
	_stamina = clampf(float(facts.stamina), 0.0, 1.0)
	_spell = float(facts.spell)
	_buffs = mini(int(facts.buffs), MAX_PIPS)
	_selected = bool(facts.selected)
	_afflicted = bool(facts.afflicted)
	_scale = ui_scale
	tooltip_text = String(facts.tooltip)
	custom_minimum_size = Vector2(PORTRAIT + GAP + BAR + GAP + BAR + GAP + PIP, PORTRAIT) * ui_scale
	queue_redraw()


## Moves the stamina bar to `fraction` without rebinding the entry.
func show_stamina(fraction: float) -> void:
	_stamina = clampf(fraction, 0.0, 1.0)
	queue_redraw()


## Draws attention to this member for a moment; instant under reduced motion.
func flash(reduced_motion: bool) -> void:
	if _flash_tween != null and _flash_tween.is_running():
		_flash_tween.kill()
	_flash = 1.0
	_flash_tween = create_tween()
	if reduced_motion:
		_flash_tween.tween_interval(FLASH_SECONDS)
		_flash_tween.tween_property(self, "_flash", 0.0, 0.0)
	else:
		_flash_tween.tween_property(self, "_flash", 0.0, FLASH_SECONDS)


func _draw() -> void:
	var palette := UiThemeService.current()
	var side := PORTRAIT * _scale
	var portrait := Rect2(Vector2.ZERO, Vector2(side, side))
	draw_rect(portrait, TRACK_COLOR)
	if _portrait != null:
		draw_texture_rect(_portrait, portrait, false)
	if _selected:
		draw_rect(portrait.grow(-1.0), palette.colors[&"accent"], false, 2.0)
	if _flash > 0.0:
		draw_rect(portrait.grow(-1.0), Color(palette.colors[&"bad"], _flash), false, 3.0)
	if _afflicted:
		var centre := portrait.end - Vector2(7.0, 7.0) * _scale
		draw_circle(centre, 6.0 * _scale, palette.colors[&"backdrop"])
		draw_circle(centre, 4.0 * _scale, palette.colors[&"bad"])
	var x := side + GAP * _scale
	_draw_bar(x, _stamina, RosterVitalColors.stamina_bar(_stamina))
	x += (BAR + GAP) * _scale
	if _spell >= 0.0:
		_draw_bar(x, clampf(_spell, 0.0, 1.0), RosterVitalColors.spell_bar(_spell))
	x += (BAR + GAP) * _scale
	for index: int in _buffs:
		var top := side - (index + 1) * PIP * _scale - index * 2.0 * _scale
		draw_rect(Rect2(x, top, PIP * _scale, PIP * _scale), BUFF_COLOR)


func _draw_bar(x: float, fraction: float, color: Color) -> void:
	var side := PORTRAIT * _scale
	draw_rect(Rect2(x, 0.0, BAR * _scale, side), TRACK_COLOR)
	draw_rect(Rect2(x, side * (1.0 - fraction), BAR * _scale, side * fraction), color)
