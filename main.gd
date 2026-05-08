extends Node2D

@onready var _pixel_renderer: PixelRenderer = $PixelRenderer
@onready var _fade_rect: ColorRect = $TransitionLayer/FadeRect


func _ready() -> void:
	LevelManager.register_renderer(_pixel_renderer, _fade_rect)
