class_name PixelRenderer extends Node2D

## 像素完美渲染容器（自动整数倍缩放）。
##
## 工作原理：
##   1. 关卡内容渲染到 SubViewport（内部尺寸 = game_size + 1px slack）
##   2. SubViewport 内的 GameCamera2D 把 global_position floor 到整数像素，
##      所以 SubViewport 输出永远像素对齐——无 shimmer
##   3. DisplaySprite 把 SubViewport 按当前整数倍缩放显示到屏幕中心
##   4. 每帧从 GameCamera2D 读 subpixel_offset，对 DisplaySprite 反向平移
##      `-subpixel_offset * current_scale` 屏幕像素，恢复亚像素平滑感
##   5. 窗口尺寸变化时自动重算最大整数缩放倍数（floor(window/game)），
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
	_current_scale = max(1, min(scale_x, scale_y))
	_display.scale = Vector2(_current_scale, _current_scale)
	_screen_center = window_size * 0.5
	_display.position = _screen_center
	_display_origin = _screen_center - Vector2(game_size) * 0.5 * float(_current_scale)


func _process(_delta: float) -> void:
	if not is_instance_valid(_camera):
		_camera = _find_camera_in_subviewport()
		if _camera == null:
			return
	_display.position = _screen_center - _camera.subpixel_offset * float(_current_scale)


func _input(event: InputEvent) -> void:
	# SubViewport 不在 SubViewportContainer 内，需手动转发输入事件。
	# 鼠标事件还要把屏幕坐标映射回 480×270 游戏坐标系
	var fwd := _transform_input(event)
	_sub_viewport.push_input(fwd)
	_sub_viewport.push_unhandled_input(fwd)


func _transform_input(event: InputEvent) -> InputEvent:
	if event is InputEventMouse:
		var local := (event.position - _display_origin) / float(_current_scale)
		var clone: InputEvent = event.duplicate()
		(clone as InputEventMouse).position = local
		if clone is InputEventMouseMotion:
			(clone as InputEventMouseMotion).relative = (event as InputEventMouseMotion).relative / float(_current_scale)
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
