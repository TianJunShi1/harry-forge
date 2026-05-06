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
	_current_scale = maxi(1, mini(scale_x, scale_y))
	_display.scale = Vector2(_current_scale, _current_scale)
	_screen_center = window_size * 0.5
	_display.position = _screen_center
	# 用实际 SubViewport 尺寸（game_size + 1px slack）计算左上角，消除 0.5px 鼠标映射偏差
	var actual_size := Vector2(game_size + Vector2i.ONE)
	_display_origin = _screen_center - actual_size * 0.5 * float(_current_scale)


func _process(_delta: float) -> void:
	if not is_instance_valid(_camera):
		_camera = _find_camera_in_subviewport()
		if _camera == null:
			return
	# 显式取整到物理像素：scale=3 时即 1/3 game-px 步进。
	# 不依赖 project.godot 的 snap_2d_transforms_to_pixel；意图写在代码里。
	var phys_offset := (_camera.subpixel_offset * float(_current_scale)).round()
	_display.position = _screen_center - phys_offset
	_update_filter_for_zoom(_camera.zoom.x)


func _update_filter_for_zoom(cam_zoom: float) -> void:
	# 非整数 zoom 在 NEAREST + 整数倍上采样下产生不均匀 texel 宽度（视觉上"模糊/抖动"）。
	# 过渡期或非整数目标值时切 LINEAR → 统一软化，比 NEAREST 不均匀像素更"有意图"；
	# zoom 收敛到整数后切回 NEAREST，恢复像素清晰感。
	var near_integer := absf(cam_zoom - roundf(cam_zoom)) < 0.005
	var vp_filter := (Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
			if near_integer
			else Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_LINEAR)
	var ci_filter := (CanvasItem.TEXTURE_FILTER_NEAREST
			if near_integer
			else CanvasItem.TEXTURE_FILTER_LINEAR)
	if _sub_viewport.canvas_item_default_texture_filter != vp_filter:
		_sub_viewport.canvas_item_default_texture_filter = vp_filter
	if _display.texture_filter != ci_filter:
		_display.texture_filter = ci_filter


func _input(event: InputEvent) -> void:
	# SubViewport 不在 SubViewportContainer 内，需手动转发输入事件。
	# 鼠标事件还要把屏幕坐标映射回 480×270 游戏坐标系
	# push_input 已走完整 pipeline（含 _unhandled_input），无需再调 push_unhandled_input
	_sub_viewport.push_input(_transform_input(event))


func _transform_input(event: InputEvent) -> InputEvent:
	if event is InputEventMouse:
		var mouse := event as InputEventMouse
		var local: Vector2 = (mouse.position - _display_origin) / float(_current_scale)
		var clone := event.duplicate() as InputEventMouse
		clone.position = local
		if clone is InputEventMouseMotion:
			(clone as InputEventMouseMotion).relative = (mouse as InputEventMouseMotion).relative / float(_current_scale)
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
