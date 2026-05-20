class_name PromptHint extends Node2D

@export var dissolve_duration: float = 1.5

@onready var _icon: Sprite2D = $Sprite2D

var _mat: ShaderMaterial
var _tween: Tween


func _ready() -> void:
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://general/ui/dissolve.gdshader")
	_mat.set_shader_parameter(&"factor", 0.0)
	_mat.set_shader_parameter(&"direction", 0)
	_mat.set_shader_parameter(&"width", 0.4)
	_mat.set_shader_parameter(&"shape_tiling", 3.0)
	_mat.set_shader_parameter(&"shape_feathering", 0.0)
	_mat.set_shader_parameter(&"shape_treshold", 1.0)
	_mat.set_shader_parameter(&"shape_texture", _bake_noise())
	_icon.material = _mat
	hide()


func show_hint() -> void:
	show()
	_tween_factor(0.0, 1.0)


func hide_hint() -> void:
	_tween_factor(1.0, 0.0, true)


func _tween_factor(from: float, to: float, hide_after: bool = false) -> void:
	if _tween and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.tween_method(
		func(v: float) -> void: _mat.set_shader_parameter(&"factor", v),
		from, to, dissolve_duration
	)
	if hide_after:
		_tween.tween_callback(hide)


func _bake_noise() -> ImageTexture:
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.frequency = 0.8
	noise.fractal_octaves = 4
	const SIZE := 64
	var img := Image.create(SIZE, SIZE, false, Image.FORMAT_L8)
	for y in SIZE:
		for x in SIZE:
			var v := noise.get_noise_2d(float(x), float(y)) * 0.5 + 0.5
			img.set_pixel(x, y, Color(v, v, v))
	return ImageTexture.create_from_image(img)
