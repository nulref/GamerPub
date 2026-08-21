class_name GameCard
extends Button

signal game_selected(game_id: StringName)

const NORMAL_SCALE := Vector2.ONE
const HOVER_SCALE := Vector2(1.1, 1.1)
const TWEEN_DURATION := 0.14

var game_id: StringName
var _scale_tween: Tween
var _content: VBoxContainer
var _logo_rect: TextureRect
var _name_label: Label


func setup(id: StringName, display_name: String, logo: Texture2D) -> void:
	game_id = id
	tooltip_text = "Select %s" % display_name
	accessibility_name = display_name

	_content = VBoxContainer.new()
	_content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 18)
	_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.alignment = BoxContainer.ALIGNMENT_CENTER
	_content.add_theme_constant_override("separation", 14)
	add_child(_content)

	_logo_rect = TextureRect.new()
	_logo_rect.custom_minimum_size = Vector2(104, 104)
	_logo_rect.texture = logo
	_logo_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_logo_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_logo_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_logo_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.add_child(_logo_rect)

	_name_label = Label.new()
	_name_label.text = display_name
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_name_label.add_theme_font_size_override("font_size", 19)
	_name_label.add_theme_color_override("font_color", Color("fff0c7"))
	_name_label.add_theme_color_override("font_shadow_color", Color(0.08, 0.03, 0.1, 0.9))
	_name_label.add_theme_constant_override("shadow_offset_x", 2)
	_name_label.add_theme_constant_override("shadow_offset_y", 2)
	_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.add_child(_name_label)

	resized.connect(_update_pivot)
	mouse_entered.connect(_set_hovered.bind(true))
	mouse_exited.connect(_set_hovered.bind(false))
	focus_entered.connect(_set_hovered.bind(true))
	focus_exited.connect(_set_hovered.bind(false))
	pressed.connect(_on_pressed)
	_update_pivot()


func apply_responsive_layout(portrait: bool) -> void:
	var inset := 28.0 if portrait else 18.0
	_content.offset_left = inset
	_content.offset_top = inset
	_content.offset_right = -inset
	_content.offset_bottom = -inset
	_content.add_theme_constant_override("separation", 24 if portrait else 14)
	_logo_rect.custom_minimum_size = Vector2(220, 220) if portrait else Vector2(104, 104)
	_name_label.add_theme_font_size_override("font_size", 32 if portrait else 19)


func _set_hovered(is_hovered: bool) -> void:
	if _scale_tween and _scale_tween.is_valid():
		_scale_tween.kill()

	_scale_tween = create_tween()
	_scale_tween.set_trans(Tween.TRANS_BACK if is_hovered else Tween.TRANS_QUAD)
	_scale_tween.set_ease(Tween.EASE_OUT)
	_scale_tween.tween_property(self, "scale", HOVER_SCALE if is_hovered else NORMAL_SCALE, TWEEN_DURATION)
	z_index = 10 if is_hovered else 0


func _update_pivot() -> void:
	pivot_offset = size * 0.5


func _on_pressed() -> void:
	game_selected.emit(game_id)
