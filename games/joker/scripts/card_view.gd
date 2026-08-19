class_name JokerCardView
extends Button
## A reusable scene representing one card in the human player's hand.

signal card_chosen(card_index: int)

const DEFAULT_MINIMUM_SIZE := Vector2(112, 151)
const MOBILE_PORTRAIT_MINIMUM_SIZE := Vector2(124, 180)

var _card_index: int = -1


func _ready() -> void:
	pressed.connect(_on_pressed)
	apply_mobile_layout()


func apply_mobile_layout() -> void:
	if not JokerMobileUI.is_active():
		return
	custom_minimum_size = (
		MOBILE_PORTRAIT_MINIMUM_SIZE
		if get_viewport_rect().size.y > get_viewport_rect().size.x
		else DEFAULT_MINIMUM_SIZE
	)


func setup(definition: JokerCardDefinition, card_index: int, can_pass: bool) -> void:
	_card_index = card_index
	disabled = not can_pass
	icon = definition.artwork

	if definition.artwork:
		text = ""
	else:
		text = definition.label

	tooltip_text = (
		"Pass the Joker" if definition.is_joker
		else "Pass a %s" % definition.label
	)
	add_theme_color_override("font_color", definition.accent)
	add_theme_color_override("font_hover_color", definition.accent.lightened(0.12))
	add_theme_color_override("font_pressed_color", definition.accent.darkened(0.08))
	add_theme_color_override("font_disabled_color", definition.accent.darkened(0.35))


func _on_pressed() -> void:
	card_chosen.emit(_card_index)
