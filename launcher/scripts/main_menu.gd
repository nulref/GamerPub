extends Control

signal game_chosen(game_id: StringName)

const GAME_CARD_SCRIPT := preload("res://launcher/scripts/game_card.gd")
const GAME_LOGO := preload("res://launcher/assets/art/gp_logo.webp")
const JOKER_LOGO := preload("res://shared/assets/Cards/card_joker.png")
const TENK_LOGO := preload("res://shared/assets/Dice/die_red_1.png")

const MAX_VISIBLE_CARDS := 6
const MIN_CARD_WIDTH := 168.0
const CARD_HEIGHT := 210.0
const CARD_GAP := 16
const TRACK_PADDING := 14

# Replace each remaining placeholder as real games are added. The carousel
# automatically supports any number of entries while showing at most six.
const GAMES: Array[Dictionary] = [
	{
		"id": &"joker",
		"name": "Joker",
		"logo": JOKER_LOGO,
		"scene": "res://games/joker/scenes/main_menu.tscn",
	},
	{
		"id": &"tenk",
		"name": "Tenk",
		"logo": TENK_LOGO,
		"scene": "res://games/tenk/scenes/game.tscn",
	},
	{"id": &"game_03", "name": "Game 03", "logo": GAME_LOGO},
	{"id": &"game_04", "name": "Game 04", "logo": GAME_LOGO},
	{"id": &"game_05", "name": "Game 05", "logo": GAME_LOGO},
	{"id": &"game_06", "name": "Game 06", "logo": GAME_LOGO},
	{"id": &"game_07", "name": "Game 07", "logo": GAME_LOGO},
	{"id": &"game_08", "name": "Game 08", "logo": GAME_LOGO},
	{"id": &"game_09", "name": "Game 09", "logo": GAME_LOGO},
	{"id": &"game_10", "name": "Game 10", "logo": GAME_LOGO},
]

@onready var card_scroll: ScrollContainer = %CardScroll
@onready var cards: HBoxContainer = %Cards
@onready var previous_button: Button = %PreviousButton
@onready var next_button: Button = %NextButton
@onready var selection_status: Label = %SelectionStatus
@onready var range_label: Label = %RangeLabel

var _first_visible := 0
var _visible_count := MAX_VISIBLE_CARDS
var _card_step := 0.0
var _scroll_tween: Tween
var _button_group := ButtonGroup.new()


func _ready() -> void:
	_button_group.allow_unpress = false
	_setup_arrow_button(previous_button)
	_setup_arrow_button(next_button)
	_populate_cards()

	previous_button.pressed.connect(_move_carousel.bind(-1))
	next_button.pressed.connect(_move_carousel.bind(1))
	resized.connect(_queue_layout_update)
	card_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	card_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED

	_queue_layout_update()


func _unhandled_key_input(event: InputEvent) -> void:
	if not event.is_pressed() or event.is_echo():
		return

	if event.keycode == KEY_LEFT:
		_move_carousel(-1)
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_RIGHT:
		_move_carousel(1)
		get_viewport().set_input_as_handled()


func _populate_cards() -> void:
	for game in GAMES:
		var card := GAME_CARD_SCRIPT.new() as GameCard
		card.custom_minimum_size = Vector2(MIN_CARD_WIDTH, CARD_HEIGHT)
		card.focus_mode = Control.FOCUS_ALL
		card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		card.toggle_mode = true
		card.button_group = _button_group
		_apply_card_styles(card)
		card.setup(game.id, game.name, game.logo)
		card.game_selected.connect(_on_game_selected)
		cards.add_child(card)


func _queue_layout_update() -> void:
	_update_card_layout.call_deferred()


func _update_card_layout() -> void:
	if not is_instance_valid(card_scroll) or card_scroll.size.x <= 0.0:
		return

	var usable_width := maxf(card_scroll.size.x - (TRACK_PADDING * 2), MIN_CARD_WIDTH)
	_visible_count = clampi(
		int(floor((usable_width + CARD_GAP) / (MIN_CARD_WIDTH + CARD_GAP))),
		1,
		mini(MAX_VISIBLE_CARDS, GAMES.size())
	)

	var total_gaps := CARD_GAP * (_visible_count - 1)
	var card_width: float = floorf((usable_width - float(total_gaps)) / float(_visible_count))
	_card_step = card_width + CARD_GAP

	for child in cards.get_children():
		if child is GameCard:
			child.custom_minimum_size = Vector2(card_width, CARD_HEIGHT)

	_first_visible = mini(_first_visible, _maximum_first_index())
	card_scroll.scroll_horizontal = roundi(_first_visible * _card_step)
	_update_navigation()


func _move_carousel(direction: int) -> void:
	var target_index := clampi(_first_visible + direction, 0, _maximum_first_index())
	if target_index == _first_visible:
		return

	_first_visible = target_index
	if _scroll_tween and _scroll_tween.is_valid():
		_scroll_tween.kill()

	_scroll_tween = create_tween()
	_scroll_tween.set_trans(Tween.TRANS_QUAD)
	_scroll_tween.set_ease(Tween.EASE_OUT)
	_scroll_tween.tween_property(
		card_scroll,
		"scroll_horizontal",
		roundi(_first_visible * _card_step),
		0.22
	)
	_update_navigation()


func _maximum_first_index() -> int:
	return maxi(GAMES.size() - _visible_count, 0)


func _update_navigation() -> void:
	previous_button.disabled = _first_visible == 0
	next_button.disabled = _first_visible >= _maximum_first_index()

	var last_visible := mini(_first_visible + _visible_count, GAMES.size())
	range_label.text = "%d–%d of %d" % [_first_visible + 1, last_visible, GAMES.size()]


func _on_game_selected(game_id: StringName) -> void:
	for game in GAMES:
		if game.id == game_id:
			selection_status.text = "%s selected" % game.name
			game_chosen.emit(game_id)
			var scene_path := String(game.get("scene", ""))
			if scene_path.is_empty():
				return
			var error := get_tree().change_scene_to_file(scene_path)
			if error != OK:
				selection_status.text = "Unable to launch %s" % game.name
				push_error("Unable to launch %s (%s): error %d" % [game.name, scene_path, error])
			return


func _setup_arrow_button(button: Button) -> void:
	button.focus_mode = Control.FOCUS_ALL
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_stylebox_override("normal", _make_style(Color(0.08, 0.04, 0.12, 0.88), Color("9a6535"), 2, 14))
	button.add_theme_stylebox_override("hover", _make_style(Color(0.22, 0.10, 0.18, 0.96), Color("ffd36a"), 3, 14))
	button.add_theme_stylebox_override("pressed", _make_style(Color(0.30, 0.13, 0.15, 1.0), Color("fff0a6"), 3, 14))
	button.add_theme_stylebox_override("focus", _make_style(Color.TRANSPARENT, Color("fff0a6"), 3, 14))
	button.add_theme_stylebox_override("disabled", _make_style(Color(0.04, 0.03, 0.06, 0.55), Color(0.36, 0.28, 0.25, 0.6), 1, 14))
	button.add_theme_color_override("font_color", Color("ffe0a0"))
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.add_theme_color_override("font_pressed_color", Color.WHITE)
	button.add_theme_color_override("font_disabled_color", Color(0.55, 0.50, 0.48, 0.7))


func _apply_card_styles(card: Button) -> void:
	card.add_theme_stylebox_override("normal", _make_style(Color(0.08, 0.035, 0.11, 0.91), Color("7f512c"), 2, 18, 12))
	card.add_theme_stylebox_override("hover", _make_style(Color(0.19, 0.075, 0.15, 0.98), Color("ffd36a"), 3, 18, 18))
	card.add_theme_stylebox_override("pressed", _make_style(Color(0.24, 0.09, 0.13, 1.0), Color("fff0a6"), 4, 18, 20))
	card.add_theme_stylebox_override("focus", _make_style(Color.TRANSPARENT, Color("fff0a6"), 3, 18))


func _make_style(
	background: Color,
	border: Color,
	border_width: int,
	radius: int,
	shadow_size: int = 8
) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(radius)
	style.shadow_color = Color(0.02, 0.01, 0.04, 0.72)
	style.shadow_size = shadow_size
	style.shadow_offset = Vector2(0, 6)
	return style
