extends Node2D

@onready var _pixel_renderer: PixelRenderer = $PixelRenderer
@onready var _fade_rect: ColorRect = $TransitionLayer/FadeRect


func _ready() -> void:
	LevelManager.register_renderer(_pixel_renderer, _fade_rect)
	_setup_transition_shader()


func _setup_transition_shader() -> void:
	var mat := ShaderMaterial.new()
	mat.shader = load("res://general/level_transition/transition.gdshader")

	# 横向线性渐变：控制擦除方向（黑→白 = 从左到右）
	var grad := Gradient.new()
	grad.set_color(0, Color.BLACK)
	grad.set_color(1, Color.WHITE)
	var grad_tex := GradientTexture1D.new()
	grad_tex.gradient = grad
	grad_tex.width = 256

	# Simplex 噪声纹理：让边缘凹凸不规则
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	var noise_tex := NoiseTexture2D.new()
	noise_tex.noise = noise
	noise_tex.width = 128
	noise_tex.height = 128
	noise_tex.seamless = true

	mat.set_shader_parameter(&"base_color",       Color.BLACK)
	mat.set_shader_parameter(&"node_resolution",  _fade_rect.get_viewport_rect().size)
	mat.set_shader_parameter(&"gradient_texture", grad_tex)
	mat.set_shader_parameter(&"shape_texture",    noise_tex)
	mat.set_shader_parameter(&"factor",           0.0)
	mat.set_shader_parameter(&"width",            0.3)
	mat.set_shader_parameter(&"shape_tiling",     8.0)
	mat.set_shader_parameter(&"shape_feathering", 0.3)
	mat.set_shader_parameter(&"shape_treshold",   1.0)
	mat.set_shader_parameter(&"gradient_fixed",   false)

	_fade_rect.material = mat
