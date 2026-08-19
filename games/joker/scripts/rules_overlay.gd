class_name JokerRulesOverlay
extends Control
## Shared modal used by the main menu and game screen.

@onready var close_button: Button = %CloseRulesButton

var _previous_focus: Control


func _ready() -> void:
	close_button.pressed.connect(close)
	set_process_unhandled_input(false)
	if JokerMobileUI.is_active():
		JokerMobileUI.enlarge_control(close_button, 72.0)
		$ScreenMargin/Center/Panel/Margin/Column/Title.add_theme_font_size_override(
			"font_size", 32
		)
		$ScreenMargin/Center/Panel/Margin/Column/Tagline.add_theme_font_size_override(
			"font_size", 22
		)
		var body: RichTextLabel = $ScreenMargin/Center/Panel/Margin/Column/Body
		body.add_theme_font_size_override("normal_font_size", 20)
		body.add_theme_font_size_override("bold_font_size", 20)
		$ScreenMargin/Center/Panel/Margin/Column/Reminder.add_theme_font_size_override(
			"font_size", 20
		)


func open() -> void:
	_previous_focus = get_viewport().gui_get_focus_owner()
	show()
	set_process_unhandled_input(true)
	close_button.grab_focus()


func close() -> void:
	hide()
	set_process_unhandled_input(false)
	if is_instance_valid(_previous_focus):
		_previous_focus.grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		close()
	get_viewport().set_input_as_handled()
