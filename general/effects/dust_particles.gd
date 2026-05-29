class_name DustParticles extends GPUParticles2D

## 全屏环境灰尘飘散效果。
## 挂在 GameCamera2D 下，发射区域 = 游戏画面（480×270），
## local_coords=false 让粒子在世界空间漂移，镜头移动不影响飘散感。

## 粒子发射区域大小（游戏像素），建议覆盖整个关卡或区域范围
@export var emit_size: Vector2 = Vector2(2000, 600)
@export var particle_count: int = 80
@export var particle_lifetime: float = 10.0
## 粒子最小/最大漂移速度（游戏像素/秒）
@export var speed_min: float = 4.0
@export var speed_max: float = 14.0
## 主漂移方向（归一化），默认斜向右上
@export var drift_direction: Vector3 = Vector3(0.8, -0.3, 0.0)
## 散布角度（度），越大越随机
@export var spread_angle: float = 25.0
## 粒子透明度峰值
@export var max_alpha: float = 0.45


func _ready() -> void:
	_setup_texture()
	_setup_material()

	amount = particle_count
	lifetime = particle_lifetime
	# 预填充：进场时屏幕内已有粒子，不会从空白开始
	preprocess = particle_lifetime
	local_coords = false
	# 粒子均匀持续发射，不爆发
	explosiveness = 0.0
	randomness = 0.5


func _setup_texture() -> void:
	# 2×2 白色硬像素，保持像素风格
	var img := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	texture = ImageTexture.create_from_image(img)


func _setup_material() -> void:
	var mat := ParticleProcessMaterial.new()

	# 发射区域：以节点为中心的 480×270 盒子，覆盖整个画面
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	mat.emission_box_extents = Vector3(emit_size.x * 0.5, emit_size.y * 0.5, 1.0)

	# 漂移方向与散布
	mat.direction = drift_direction.normalized()
	mat.spread = spread_angle
	mat.initial_velocity_min = speed_min
	mat.initial_velocity_max = speed_max

	# 无重力，自由漂浮
	mat.gravity = Vector3.ZERO

	# 粒子大小：0.5~1.5 游戏像素
	mat.scale_min = 0.5
	mat.scale_max = 1.5

	# 生命周期内淡入淡出，避免粒子突然出现/消失
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1, 1, 1, 0.0))
	gradient.add_point(0.12, Color(1, 1, 1, max_alpha))
	gradient.add_point(0.88, Color(1, 1, 1, max_alpha))
	gradient.add_point(1.0, Color(1, 1, 1, 0.0))
	var grad_tex := GradientTexture1D.new()
	grad_tex.gradient = gradient
	mat.color_ramp = grad_tex

	process_material = mat
