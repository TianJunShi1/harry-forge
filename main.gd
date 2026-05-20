extends Node2D

@onready var _pixel_renderer: PixelRenderer = $PixelRenderer
@onready var _fade_rect: ColorRect = $TransitionLayer/FadeRect


func _ready() -> void:
	LevelManager.register_renderer(_pixel_renderer, _fade_rect)
	_setup_transition_shader()


func _setup_transition_shader() -> void:
	var mat := ShaderMaterial.new()
	mat.shader = load("res://general/level_transition/transition.gdshader")

	# Simplex 噪声纹理：让擦除边缘凹凸不规则（对应截图中的 Shape Texture）
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.frequency = 0.8  # 较高频率使溅射颗粒更细密
	var noise_tex := NoiseTexture2D.new()
	noise_tex.noise = noise
	noise_tex.width = 256
	noise_tex.height = 256
	noise_tex.seamless = true

	mat.set_shader_parameter(&"base_color",       Color.BLACK)
	mat.set_shader_parameter(&"node_resolution",  _fade_rect.get_viewport_rect().size)
	mat.set_shader_parameter(&"shape_texture",    noise_tex)
	mat.set_shader_parameter(&"factor",           0.0)
	mat.set_shader_parameter(&"width",            0.225)
	mat.set_shader_parameter(&"direction",        4)      # 径向
	mat.set_shader_parameter(&"shape_tiling",     8.0)
	mat.set_shader_parameter(&"shape_rotation",   45.0)
	mat.set_shader_parameter(&"shape_scroll",     Vector2(0.1, 0.1))
	mat.set_shader_parameter(&"shape_feathering", 0.0)
	mat.set_shader_parameter(&"shape_treshold",   1.0)

	_fade_rect.material = mat
