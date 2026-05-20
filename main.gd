extends Node2D

@onready var _pixel_renderer: PixelRenderer = $PixelRenderer
@onready var _fade_rect: ColorRect = $TransitionLayer/FadeRect


func _ready() -> void:
	LevelManager.register_renderer(_pixel_renderer, _fade_rect)
	_setup_transition_shader()


func _setup_transition_shader() -> void:
	var mat := ShaderMaterial.new()
	mat.shader = load("res://general/level_transition/transition.gdshader")

	mat.set_shader_parameter(&"base_color",       Color.BLACK)
	mat.set_shader_parameter(&"node_resolution",  _fade_rect.get_viewport_rect().size)
	mat.set_shader_parameter(&"shape_texture",    _bake_noise_texture())
	mat.set_shader_parameter(&"factor",           0.0)
	mat.set_shader_parameter(&"width",            0.4)
	mat.set_shader_parameter(&"direction",        0)
	mat.set_shader_parameter(&"shape_tiling",     0.4)
	mat.set_shader_parameter(&"shape_rotation",   0.0)   # 旋转+mod 会在贴图边界产生撕裂线
	mat.set_shader_parameter(&"shape_scroll",     Vector2(0.0, 0.0))  # 滚动造成转场期间拉伸感
	mat.set_shader_parameter(&"shape_feathering", 0.4)
	mat.set_shader_parameter(&"shape_treshold",   1.0)

	_fade_rect.material = mat


# NoiseTexture2D 在 Godot 4 里异步生成，首帧 shader 会拿到空纹理导致效果异常。
# 改用 Image 逐像素同步写入，保证 material 挂载时纹理已完全就绪。
func _bake_noise_texture() -> ImageTexture:
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.frequency = 0.8
	noise.fractal_octaves = 4
	const SIZE := 128
	var img := Image.create(SIZE, SIZE, false, Image.FORMAT_L8)
	for y in SIZE:
		for x in SIZE:
			var v: float = noise.get_noise_2d(float(x), float(y)) * 0.5 + 0.5
			img.set_pixel(x, y, Color(v, v, v))
	return ImageTexture.create_from_image(img)
