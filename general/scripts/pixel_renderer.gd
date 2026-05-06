class_name PixelRenderer extends Node2D

## 像素完美渲染容器（蔚蓝式 SubViewport 架构）。
##
## 工作原理：
##   1. SubViewport 内部永远 1:1 渲染（GameCamera2D.zoom 恒为 ONE），
##      内层 Camera2D 把 global_position floor 到整数像素，确保 SubViewport
##      输出绝对 pixel-perfect——无亚像素采样错位、无 shimmer
##   2. DisplaySprite 在外层做缩放：scale = _current_scale × camera.displayed_zoom
##      整数 zoom（2.0/3.0）→ 物理像素完美整数倍；非整数 zoom（1.3 等）→
##      NEAREST 采样下物理像素宽度不均（有 3px 有 4px）但每个像素绝对锐利
##      这就是 Celeste 等顶级像素游戏的"sharp non-integer zoom"做法
##   3. 每帧读 GameCamera2D.subpixel_offset（游戏像素残差），按
##      `-subpixel_offset × _current_scale × zoom_factor` 平移 DisplaySprite，
##      恢复亚像素级平滑移动
##   4. 窗口尺寸变化时自动重算最大整数基础缩放倍数（floor(window/game)），
##      画面始终居中，未覆盖的区域为黑边

@export var level: PackedScene
@export var game_size: Vector2i = Vector2i(480, 270)

@onready var _sub_viewport: SubViewport = $SubViewport
@onready var _display: Sprite2D = $DisplaySprite

var _camera: GameCamera2D
var _current_scale: int = 1
var _screen_center: Vector2
# DisplaySprite 在屏幕坐标系下占据矩形的左上角，用于鼠标坐标反向映射
var _display_origin: Vector2


func _ready() -> void:
	# 必须在 GameCamera（priority 0）之后处理，否则读到上一帧的 subpixel_offset 导致抖动
	process_priority = 1
	_sub_viewport.size = game_size + Vector2i.ONE
	_display.texture = _sub_viewport.get_texture()
	if level:
		_sub_viewport.add_child(level.instantiate())
	get_tree().root.size_changed.connect(_recalculate_layout)
	_recalculate_layout()


func _recalculate_layout() -> void:
	var window_size := Vector2(get_viewport().get_visible_rect().size)
	# 同时考虑横竖向，取小的；最小 1 防止超小窗口出现 0 倍
	var scale_y := int(floor(window_size.y / float(game_size.y)))
	var scale_x := int(floor(window_size.x / float(game_size.x)))
	_current_scale = maxi(1, mini(scale_x, scale_y))
	_screen_center = window_size * 0.5
	_display.position = _screen_center
	# DisplaySprite.scale 在 _process 里每帧根据 zoom 动态设置；这里仅给个初始值
	_display.scale = Vector2(_current_scale, _current_scale)


func _process(_delta: float) -> void:
	if not is_instance_valid(_camera):
		_camera = _find_camera_in_subviewport()
		if _camera == null:
			return
	# 蔚蓝架构：缩放在外层做。effective_scale = 基础整数 × 显示 zoom。
	# 整数 zoom 时 effective_scale 仍为整数 → 物理像素完美对齐；
	# 非整数 zoom 时 effective_scale 非整数 → NEAREST 采样下物理像素宽度不均（3/4 px 交错）
	# 但每个像素仍绝对锐利（无 LINEAR 羽化）。
	var zoom_factor := _camera.displayed_zoom.x
	var effective_scale := float(_current_scale) * zoom_factor
	_display.scale = Vector2(effective_scale, effective_scale)
	# subpixel 补偿：1 game pixel = effective_scale physical pixels，残差按此换算
	var phys_offset := (_camera.subpixel_offset * effective_scale).round()
	_display.position = _screen_center - phys_offset
	# 鼠标坐标映射所需的左上角，按 effective_scale 计算
	var actual_size := Vector2(game_size + Vector2i.ONE)
	_display_origin = _screen_center - actual_size * 0.5 * effective_scale


func _input(event: InputEvent) -> void:
	# SubViewport 不在 SubViewportContainer 内，需手动转发输入事件。
	# 鼠标事件还要把屏幕坐标映射回 480×270 游戏坐标系
	# push_input 已走完整 pipeline（含 _unhandled_input），无需再调 push_unhandled_input
	_sub_viewport.push_input(_transform_input(event))


func _transform_input(event: InputEvent) -> InputEvent:
	if event is InputEventMouse:
		var mouse := event as InputEventMouse
		# 用 DisplaySprite 当前实际缩放（含 zoom）反算游戏坐标
		var eff_scale := _display.scale.x
		var local: Vector2 = (mouse.position - _display_origin) / eff_scale
		var clone := event.duplicate() as InputEventMouse
		clone.position = local
		if clone is InputEventMouseMotion:
			(clone as InputEventMouseMotion).relative = (mouse as InputEventMouseMotion).relative / eff_scale
		return clone
	return event


func _find_camera_in_subviewport() -> GameCamera2D:
	# 遍历 SubViewport 子树查找 game_camera 组成员
	var stack: Array = [_sub_viewport]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is GameCamera2D and node.is_in_group("game_camera"):
			return node
		for child in node.get_children():
			stack.append(child)
	return null
