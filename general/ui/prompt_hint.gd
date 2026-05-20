class_name PromptHint extends Node2D

## 跟随的世界空间目标（由持有者在 _ready 中赋值）
var follow_target: Node2D
## 相对目标的偏移，单位：游戏像素（会随 effective_scale 换算到屏幕像素）
@export var follow_offset: Vector2 = Vector2(0, -20)
@export var dissolve_duration: float = 1.5

@onready var _icon: Sprite2D = $Sprite2D

var _mat: ShaderMaterial
var _tween: Tween
var _renderer: PixelRenderer


func _ready() -> void:
	_setup_material()
	hide()
	# 延迟一帧：main.gd 在自己的 _ready 里创建 UILayer，
	# deferred 确保所有 _ready 都跑完后再执行重挂
	call_deferred(&"_reparent_to_ui_layer")


func _reparent_to_ui_layer() -> void:
	var layers := get_tree().get_nodes_in_group(&"prompt_ui_layer")
	if layers.is_empty():
		return
	var renderers := get_tree().get_nodes_in_group(&"pixel_renderer")
	if renderers.is_empty():
		return
	_renderer = renderers[0] as PixelRenderer
	reparent(layers[0], false)


func _process(_delta: float) -> void:
	if not is_instance_valid(_renderer):
		return
	if not is_instance_valid(follow_target):
		queue_free()
		return
	var eff := _renderer.get_effective_scale()
	_icon.scale = Vector2(eff, eff)
	global_position = _renderer.world_to_screen(follow_target.global_position) + follow_offset * eff


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


func _setup_material() -> void:
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
