class_name PixelRenderer extends Node2D

## 像素风格渲染容器（canvas-items 架构）。
##
## 工作原理：
##   1. 关卡内容直接在原生窗口分辨率渲染（canvas-items），Camera2D.zoom 控制视角。
##   2. _current_scale = min(window_w/game_w, window_h/game_h)，确保至少 game_size 的世界内容可见，
##      写入 GameCamera2D.default_zoom，由相机平滑过渡到 Camera2D.zoom。
##   3. 相机位置直接使用浮点值（不 floor），粒子 / 慢速对象在屏幕像素级完全平滑。
##   4. 窗口尺寸变化时重算 zoom，通知 GameCamera2D 更新。

@export var level: PackedScene
@export var game_size: Vector2i = Vector2i(480, 270)

@export_group("Atmosphere")
@export var atmosphere_color: Color = Color(1, 1, 1, 1)
@export_range(0.5, 2.0, 0.05) var brightness: float = 1.2
@export_range(0.5, 2.0, 0.05) var contrast: float = 1.05
@export_range(0.0, 1.0, 0.05) var vignette: float = 0.6
@export var vignette_color: Color = Color(0, 0, 0, 1)

@onready var _world_root: Node2D = $WorldRoot
@onready var _canvas_modulate: CanvasModulate = $WorldRoot/CanvasModulate

var _camera: GameCamera2D
var _camera_search_pending: bool = false
var _current_level: Node
var _current_scale: float = 1.0
var _screen_center: Vector2
var _display_origin: Vector2


func _ready() -> void:
	process_priority = 1
	add_to_group(&"pixel_renderer")
	_world_root.add_to_group(&"world_root")
	_apply_atmosphere_exports()
	if level:
		load_level(level)
	else:
		_begin_camera_search()
	get_tree().root.size_changed.connect(_recalculate_layout)
	_recalculate_layout()


func _apply_atmosphere_exports() -> void:
	_canvas_modulate.color = atmosphere_color


# ============================================================================
# 关卡切换 API
# ============================================================================

## 卸载当前关卡（若有），实例化并挂载 packed 到 WorldRoot。
## 这是 PixelRenderer 的关卡切换唯一入口；外部不应直接 add_child 到 WorldRoot。
func load_level(packed: PackedScene) -> Node:
	if packed == null:
		push_warning("PixelRenderer.load_level：packed 为空，已忽略。")
		return null
	unload_level()
	_current_level = packed.instantiate()
	_world_root.add_child(_current_level)
	_camera = _find_camera_in_world()
	if _camera == null:
		_begin_camera_search()
	else:
		_end_camera_search()
		_update_camera_zoom()
	return _current_level


## 卸载当前关卡（如果存在）。queue_free 在帧末执行，本帧仍可安全访问。
func unload_level() -> void:
	if is_instance_valid(_current_level):
		_current_level.queue_free()
	_current_level = null
	_camera = null
	_begin_camera_search()


func get_current_level() -> Node:
	return _current_level


## 当前有效显示倍数（Camera2D.zoom，含区域 zoom_override 覆盖）。
func get_effective_scale() -> float:
	if not is_instance_valid(_camera):
		return float(_current_scale)
	return maxf(1.0, _camera.zoom.x)


## 将游戏世界坐标转换为屏幕坐标，供 CanvasLayer 内的 UI 元素跟随世界对象。
func world_to_screen(world_pos: Vector2) -> Vector2:
	if not is_instance_valid(_camera):
		return _screen_center
	return get_viewport().get_canvas_transform() * world_pos


## 返回游戏内容区域左上角的屏幕坐标。
func get_display_origin() -> Vector2:
	return _display_origin


## 返回游戏内容在屏幕坐标系中的显示矩形（canvas-items 模式下通常等于完整视口）。
func get_display_rect() -> Rect2:
	return get_viewport().get_visible_rect()


# ============================================================================
# 内部：相机自动发现（signal 驱动，零轮询）
# ============================================================================

func _begin_camera_search() -> void:
	if _camera_search_pending or is_instance_valid(_camera):
		return
	_camera_search_pending = true
	_world_root.child_entered_tree.connect(_on_world_root_child_entered)


func _end_camera_search() -> void:
	if not _camera_search_pending:
		return
	_camera_search_pending = false
	_world_root.child_entered_tree.disconnect(_on_world_root_child_entered)


func _on_world_root_child_entered(_child: Node) -> void:
	call_deferred("_scan_for_camera")


func _scan_for_camera() -> void:
	if is_instance_valid(_camera):
		return
	var found := _find_camera_in_world()
	if found != null:
		_camera = found
		_end_camera_search()
		_update_camera_zoom()


func _recalculate_layout() -> void:
	var window_size := Vector2(get_viewport().get_visible_rect().size)
	var scale_y := window_size.y / float(game_size.y)
	var scale_x := window_size.x / float(game_size.x)
	_current_scale = maxf(1.0, minf(scale_x, scale_y))
	_screen_center = window_size * 0.5
	_display_origin = _screen_center - Vector2(game_size) * 0.5 * _current_scale
	_update_camera_zoom()


func _update_camera_zoom() -> void:
	if not is_instance_valid(_camera):
		return
	_camera.set_base_zoom(Vector2(_current_scale, _current_scale))


func _process(_delta: float) -> void:
	if not is_instance_valid(_camera):
		return
	var zoom := maxf(_camera.zoom.x, 1.0)
	var visible_size := Vector2(game_size) * zoom
	_display_origin = _screen_center - visible_size * 0.5


func _find_camera_in_world() -> GameCamera2D:
	var stack: Array = [_world_root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is GameCamera2D and node.is_in_group("game_camera"):
			return node
		for child in node.get_children():
			stack.append(child)
	return null


# ============================================================================
# 大气效果 API（场景切换 / 白天黑夜过渡用）
# ============================================================================

## 设置全局大气颜色。duration > 0 时平滑过渡，= 0 时立即生效。
func set_atmosphere_color(color: Color, duration: float = 0.0) -> void:
	if duration <= 0.0:
		_canvas_modulate.color = color
		return
	var tw := create_tween()
	tw.tween_property(_canvas_modulate, "color", color, duration)


## canvas-items 模式下暂无 post-process 层，以下接口保存值但暂不应用视觉效果。
func set_vignette_color(color: Color, _duration: float = 0.0) -> void:
	vignette_color = color


func set_vignette_strength(strength: float, _duration: float = 0.0) -> void:
	vignette = strength


func set_brightness(value: float, _duration: float = 0.0) -> void:
	brightness = value


func set_contrast(value: float, _duration: float = 0.0) -> void:
	contrast = value
