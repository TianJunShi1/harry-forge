class_name PromptHint extends Node2D

@export var fade_duration: float = 0.3

@onready var _icon: Sprite2D = $Sprite2D

var _tween: Tween


func _ready() -> void:
	modulate.a = 0.0
	hide()


func show_hint() -> void:
	show()
	_tween_alpha(0.0, 1.0)


func hide_hint() -> void:
	_tween_alpha(1.0, 0.0, true)


func _tween_alpha(from: float, to: float, hide_after: bool = false) -> void:
	if _tween and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(self, "modulate:a", to, fade_duration).from(from)
	if hide_after:
		_tween.tween_callback(hide)
