class_name PixelRenderer extends Node2D

## 像素完美渲染容器。
##
## 工作原理：
##   1. 关卡内容渲染到 SubViewport（内部尺寸 = game_size + 1px slack）
##   2. SubViewport 内的 GameCamera2D 把 global_position floor 到整数像素，
##      所以 SubViewport 输出永远像素对齐——无 shimmer
##   3. DisplaySprite 把 SubViewport 按 screen_scale 放大显示到屏幕中心
##   4. 每帧从 GameCamera2D 读 subpixel_offset，对 DisplaySprite 反向平移
##      `-subpixel_offset * screen_scale` 屏幕像素，恢复亚像素平滑感

@export var level: PackedScene
@export var game_size: Vector2i = Vector2i(480, 270)
@export var screen_scale: int = 3

@onready var _sub_viewport: SubViewport = $SubViewport
@onready var _display: Sprite2D = $DisplaySprite

var _camera: GameCamera2D
var _screen_center: Vector2


func _ready() -> void:
	# 必须在 GameCamera（priority 0）之后处理，否则读到上一帧的 subpixel_offset 导致抖动
	process_priority = 1
	_sub_viewport.size = game_size + Vector2i.ONE
	_display.texture = _sub_viewport.get_texture()
	_display.scale = Vector2(screen_scale, screen_scale)
	_screen_center = Vector2(game_size) * 0.5 * screen_scale
	_display.position = _screen_center
	if level:
		_sub_viewport.add_child(level.instantiate())


func _process(_delta: float) -> void:
	if not is_instance_valid(_camera):
		_camera = _find_camera_in_subviewport()
		if _camera == null:
			return
	_display.position = _screen_center - _camera.subpixel_offset * float(screen_scale)


func _input(event: InputEvent) -> void:
	# SubViewport 不在 SubViewportContainer 内，需手动转发输入事件
	_sub_viewport.push_input(event)
	_sub_viewport.push_unhandled_input(event)


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
