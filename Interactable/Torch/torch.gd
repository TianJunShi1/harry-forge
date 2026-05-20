extends Node2D

@onready var _light: PointLight2D = $PointLight2D

@export var base_energy: float = 1.4
@export var flicker_amount: float = 0.12

var _time: float = 0.0


func _process(delta: float) -> void:
	_time += delta
	var flicker := sin(_time * 7.3) * flicker_amount + sin(_time * 13.1) * (flicker_amount * 0.5)
	_light.energy = base_energy + flicker
