@tool
class_name AmbientLight extends CanvasModulate

@export var runtime_color: Color = Color(0.15, 0.16, 0.22, 1)


func _ready() -> void:
	if Engine.is_editor_hint():
		color = Color.WHITE
	else:
		color = runtime_color
