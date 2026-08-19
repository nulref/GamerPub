class_name JokerMobileUI
extends RefCounted
## Shared sizing helpers for the browser build on phones and tablets.

const TOUCH_TARGET_HEIGHT := 82.0
const CONTROL_FONT_SIZE := 24


static func is_active() -> bool:
	return OS.has_feature("web_android") or OS.has_feature("web_ios")


static func enlarge_control(
	control: Control,
	minimum_height: float = TOUCH_TARGET_HEIGHT,
	font_size: int = CONTROL_FONT_SIZE
) -> void:
	var minimum := control.custom_minimum_size
	minimum.y = maxf(minimum.y, minimum_height)
	control.custom_minimum_size = minimum
	if font_size > 0:
		control.add_theme_font_size_override("font_size", font_size)
