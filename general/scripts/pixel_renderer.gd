class_name PixelRenderer extends Node2D

## 像素完美渲染容器（蔚蓝式 SubViewport 架构）。
##
## 工作原理：
##   1. SubViewport 内部永远 1:1 渲染（GameCamera2D.zoom 恒为 ONE），
##      内层 Camera2D 把 global_position floor 到整数像素，确保 SubViewport
##      输出绝对 pixel-perfect——无亚像素采样错位、无 shimmer
##   2. DisplaySprite 在外层做缩放：effective_scale = _current_scale × zoom（保留浮点，不取整）
##      整数 zoom（2.0/3.0）每个物理像素宽度相等，完全 pixel-perfect；
##      非整数 zoom（1.3）有的物理像素宽 3px、有的宽 4px，但每个像素边缘绝对锐利
##      （蔚蓝式 sharp non-integer zoom）。取整会在 zoom 插值过程中产生突变跳帧，故不做。
##   3. 每帧读 GameCamera2D.subpixel_offset（游戏像素残差），按
##      `-subpixel_offset × effective_scale` 平移 DisplaySprite，
##      恢复亚像素级平滑移动
##   4. 窗口尺寸变化时自动重算最大整数基础缩放倍数（floor(window/game)），
##      画面始终居中，未覆盖的区域为黑边

@export var level: PackedScene
@export var game_size: Vector2i = Vector2i(480, 270)

@export_group("Atmosphere")
@export var atmosphere_color: Color = Color(1, 1, 1, 1)
@export_range(0.5, 2.0, 0.05) var brightness: float = 1.2
@export_range(0.5, 2.0, 0.05) var contrast: float = 1.05
@export_range(0.0, 1.0, 0.05) var vignette: float = 0.6
@export var vignette_color: Color = Color(0, 0, 0, 1)

@onready var _sub_viewport: SubViewport = $SubViewport
@onready var _display: Sprite2D = $DisplaySprite
@onready var _canvas_modulate: CanvasModulate = $SubViewport/GlobalEffects/CanvasModulate

var _camera: GameCamera2D
# child_entered_tree 监听是否已挂上；signal 驱动取代每帧轮询
var _camera_search_pending: bool = false
var _current_level: Node
var _current_scale: int = 1
var _screen_center: Vector2
# DisplaySprite 在屏幕坐标系下占据矩形的左上角，用于鼠标坐标反向映射
var _display_origin: Vector2
var _prev_zoom: float = 1.0


func _ready() -> void:
	# 必须在 GameCamera（priority 0）之后处理，否则读到上一帧的 subpixel_offset 导致抖动
	process_priority = 1
	add_to_group(&"pixel_renderer")
	_sub_viewport.size = game_size + Vector2i.ONE
	_display.texture = _sub_viewport.get_texture()
	_apply_atmosphere_exports()
	if level:
		load_level(level)
	else:
		# 没有预设 level，挂监听等外部代码 load_level 或直接 add_child
		_begin_camera_search()
	get_tree().root.size_changed.connect(_recalculate_layout)
	_recalculate_layout()


func _apply_atmosphere_exports() -> void:
	_canvas_modulate.color = atmosphere_color
	var mat := _display.material as ShaderMaterial
	mat.set_shader_parameter("brightness", brightness)
	mat.set_shader_parameter("contrast", contrast)
	mat.set_shader_parameter("vignette_strength", vignette)
	mat.set_shader_parameter("vignette_color", vignette_color)


# ============================================================================
# 关卡切换 API
# ============================================================================

## 卸载当前关卡（若有），实例化并挂载 packed 到 SubViewport。
## 这是 PixelRenderer 的关卡切换唯一入口；外部不应直接 add_child 到 SubViewport。
func load_level(packed: PackedScene) -> Node:
	if packed == null:
		push_warning("PixelRenderer.load_level：packed 为空，已忽略。")
		return null
	unload_level()
	_current_level = packed.instantiate()
	_sub_viewport.add_child(_current_level)
	# add_child 同步把整棵子树入树，立刻扫一次；扫不到（异步加 camera）就交给 signal 兜底。
	# 同步找到后必须调 _end_camera_search()：unload_level() 已连接 child_entered_tree，
	# 若不断开，信号永久挂着，后续每次 SubViewport 增删节点都会触发无效 deferred scan。
	_camera = _find_camera_in_subviewport()
	if _camera == null:
		_begin_camera_search()
	else:
		_end_camera_search()
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


## 当前有效显示倍数（基础整数缩放 × zoom）。
func get_effective_scale() -> float:
	if not is_instance_valid(_camera):
		return float(_current_scale)
	return maxf(1.0, float(_current_scale) * _camera.displayed_zoom.x)


## 将游戏世界坐标转换为屏幕坐标，供 CanvasLayer 内的 UI 元素跟随世界对象。
## 包含 subpixel_offset 补偿，与 DisplaySprite 的亚像素平移保持完全同步。
func world_to_screen(world_pos: Vector2) -> Vector2:
	if not is_instance_valid(_camera):
		return _screen_center
	var cam_center := _camera.get_screen_center_position()
	var eff := get_effective_scale()
	var vp_pos := world_pos - cam_center + Vector2(game_size) * 0.5
	var phys_offset := (_camera.subpixel_offset * eff).round()
	return _display_origin + vp_pos * eff - phys_offset


## 返回 DisplaySprite 当前在屏幕坐标系中的显示矩形（含 zoom 缩放）。
## 供 LevelManager / main.gd 将 FadeRect 对齐到游戏内容区域。
func get_display_rect() -> Rect2:
	# _display.position 含亚像素补偿（每帧最多飘移 1px），用 _screen_center 作为稳定中心。
	# floor+ceil 消除浮点残差，再各扩 1px 确保覆盖边缘像素、不留微小切边。
	# SubViewport 贴图实际尺寸是 game_size + 1px slack；用实际尺寸才能在高倍缩放下完整覆盖
	var size := (Vector2(game_size + Vector2i.ONE) * _display.scale.x).ceil()
	var origin := (_screen_center - size * 0.5).floor()
	return Rect2(origin - Vector2.ONE, size + Vector2(2.0, 2.0))


# ============================================================================
# 内部：相机自动发现（signal 驱动，零轮询）
# ============================================================================

func _begin_camera_search() -> void:
	if _camera_search_pending or is_instance_valid(_camera):
		return
	_camera_search_pending = true
	# 只听直接子节点入树事件（关卡根节点）；深层 GameCamera 由 _scan_for_camera 递归找
	_sub_viewport.child_entered_tree.connect(_on_subviewport_child_entered)


func _end_camera_search() -> void:
	if not _camera_search_pending:
		return
	_camera_search_pending = false
	_sub_viewport.child_entered_tree.disconnect(_on_subviewport_child_entered)


func _on_subviewport_child_entered(_child: Node) -> void:
	# child_entered_tree 在子节点 _enter_tree 之后触发，但深层子节点的 _enter_tree
	# 还在传播；defer 一帧到 idle，等整棵子树都入树并注册到 group 后再扫
	call_deferred("_scan_for_camera")


func _scan_for_camera() -> void:
	if is_instance_valid(_camera):
		return
	var found := _find_camera_in_subviewport()
	if found != null:
		_camera = found
		_end_camera_search()


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
	# camera 由 signal 驱动赋值（_begin_camera_search → _on_subviewport_child_entered）；
	# 这里只读，找不到就跳过本帧渲染调整
	if not is_instance_valid(_camera):
		return
	# 蔚蓝架构：缩放在外层做，NEAREST filter 保证每个游戏像素绝对锐利。
	# effective_scale 保持 float：非整数 zoom（1.2/1.4）时部分物理像素宽 4px、
	# 部分宽 5px，但像素边缘仍完全清晰（蔚蓝式 sharp non-integer zoom）。
	# 不做 roundf：整数取整会在 zoom 插值途中触发突变（如 4×→5×），
	# 在 CameraZone 过渡动画中产生可见的一帧跳变。
	# maxf(1.0, ...) 防止极小 zoom 导致 DisplaySprite 缩到 0。
	var zoom_factor := _camera.displayed_zoom.x
	var effective_scale := maxf(1.0, float(_current_scale) * zoom_factor)
	_display.scale = Vector2(effective_scale, effective_scale)
	# subpixel 补偿：zoom 过渡期间 round() 会因两个浮点同时变化产生 1px 随机跳变；
	# 过渡中放弃取整（接受极微的亚像素渗漏），zoom 稳定后恢复 pixel-perfect 对齐。
	var raw_offset := _camera.subpixel_offset * effective_scale
	var zoom_transitioning := absf(zoom_factor - _prev_zoom) > 0.0005
	_prev_zoom = zoom_factor
	var phys_offset := raw_offset if zoom_transitioning else raw_offset.round()
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
		# 用 DisplaySprite 当前实际缩放（含 zoom）反算游戏坐标。
		# maxf 防御：极小窗口下若 _current_scale 跌到非正常值导致 scale 为 0 会除零崩溃
		var eff_scale := maxf(_display.scale.x, 0.0001)
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


## 设置暗角强度（0=无暗角，6=极强）。duration > 0 时平滑过渡。
func set_vignette_color(color: Color, duration: float = 0.0) -> void:
	var mat := _display.material as ShaderMaterial
	if duration <= 0.0:
		mat.set_shader_parameter("vignette_color", color)
		return
	var from: Color = mat.get_shader_parameter("vignette_color")
	create_tween().tween_method(
		func(v: Color) -> void: mat.set_shader_parameter("vignette_color", v),
		from, color, duration
	)


func set_vignette_strength(strength: float, duration: float = 0.0) -> void:
	var mat := _display.material as ShaderMaterial
	if mat == null:
		return
	if duration <= 0.0:
		mat.set_shader_parameter("vignette_strength", strength)
		return
	var from: float = mat.get_shader_parameter("vignette_strength")
	var tw := create_tween()
	tw.tween_method(
		func(v: float) -> void: mat.set_shader_parameter("vignette_strength", v),
		from, strength, duration
	)


## 设置全局亮度（1.0=默认，>1 更亮，<1 更暗）。duration > 0 时平滑过渡。
func set_brightness(value: float, duration: float = 0.0) -> void:
	var mat := _display.material as ShaderMaterial
	if duration <= 0.0:
		mat.set_shader_parameter("brightness", value)
		return
	var from: float = mat.get_shader_parameter("brightness")
	var tw := create_tween()
	tw.tween_method(
		func(v: float) -> void: mat.set_shader_parameter("brightness", v),
		from, value, duration
	)


## 设置全局对比度（1.0=默认，>1 更强烈）。duration > 0 时平滑过渡。
func set_contrast(value: float, duration: float = 0.0) -> void:
	var mat := _display.material as ShaderMaterial
	if duration <= 0.0:
		mat.set_shader_parameter("contrast", value)
		return
	var from: float = mat.get_shader_parameter("contrast")
	var tw := create_tween()
	tw.tween_method(
		func(v: float) -> void: mat.set_shader_parameter("contrast", v),
		from, value, duration
	)
