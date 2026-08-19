class_name JokerCardDefinition
extends Resource
## Immutable, editor-friendly data shared by every card of a rank.

@export var id: StringName
@export var label: String
@export var accent: Color = Color.WHITE
@export var is_joker: bool = false
@export var artwork: Texture2D
