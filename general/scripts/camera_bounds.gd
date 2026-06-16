class_name CameraZone extends Area2D

## 摄像机区域。覆盖在地图上某一段区域，玩家走进来时通知 GameCamera2D
## 切换到这套配置（边界、模式、zoom）。
##
## 使用方式：
##   1. 在地图里实例化 general/camera_bounds.tscn
##   2. 调整 CollisionShape2D（必须是 RectangleShape2D）覆盖你想限制的区域
##   3. 在 Inspector 配置 mode / zoom_override / priority 等
##
## 三种典型用法：
##   • 普通房间：mode = FOLLOW，bounds_source = AUTO_FROM_COLLISION
##   • 隐藏房间：mode = LOCK_TO_CENTER，bounds_source = CUSTOM_FROM_MARKER（提前触发）
##   • Boss 战 / 聚焦房间：hidden_room_zoom > 1（外层显示放大，不改变 Camera 世界视野）

enum FollowMode {
	FOLLOW,           # 摄像机跟随玩家（典型房间）
	LOCK_TO_CENTER,   # 摄像机固定在区域中心（隐藏房间 / 静态镜头）
}

enum BoundsSource {
	AUTO_FROM_COLLISION,    # 边界 = CollisionShape2D 的矩形
	CUSTOM_FROM_MARKER,     # 边界 = BoundsCenter Marker2D + custom_bounds_size
							# （触发区可以做大一点，提前进入）
}

# ============================================================================
# 编辑器参数
# ============================================================================

@export_group("Mode")
## 摄像机在本区域的行为：跟随玩家 vs 锁定中心
@export var mode: FollowMode = FollowMode.FOLLOW

## 边界来自哪里
@export var bounds_source: BoundsSource = BoundsSource.AUTO_FROM_COLLISION

## 仅 CUSTOM_FROM_MARKER 模式生效。需要在本节点下放一个 Marker2D 命名为 "BoundsCenter"。
## 实际边界尺寸不会小于游戏视口（默认 480×270）；传入更小的值会被自动钳到视口尺寸，
## 防止 lock 模式下出现"相机半视野 > bounds"的居中歧义。
@export var custom_bounds_size: Vector2 = Vector2(320, 180)

@export_group("Zoom")
## 进入此区域时切换到的 zoom。Vector2.ZERO 表示沿用 GameCamera2D 的 default_zoom
## 注意：Godot 4 Camera2D 的 zoom > 1 是放大（看更少），< 1 是缩小（看更多）
@export var zoom_override: Vector2 = Vector2.ZERO

## 隐藏房间专用 zoom 标量（仅 mode = LOCK_TO_CENTER 时生效）。
## 1.0 = 无效果；>1 = 放大（看更少，画面聚焦感）。
## 非 1.0 时会覆盖 zoom_override；过渡时长由 GameCamera2D 的 zoom_smoothing 控制。
##
## 蔚蓝式架构下任何 zoom 值都不会有 LINEAR 模糊：
## - 整数（2.0/3.0）：物理像素完美整数倍，pixel-perfect
## - 非整数（1.3/1.5）：物理像素宽度不均（有的 3px 有的 4px），但每个像素绝对锐利
##
## 注意：本架构下 zoom < 1 是"画面缩小+黑边"而非"看更多世界"，请避开 < 1 的值。
@export_range(1.0, 4.0, 0.05) var hidden_room_zoom: float = 1.0

@export_group("Priority & Transition")
## 优先级。隐藏房间嵌在大房间里时，给隐藏房间设更大的值，让它覆盖外层
@export_range(-10, 100, 1) var zone_priority: int = 0

## 进入/退出此区域时的过渡时长（秒）
@export_range(0.0, 3.0, 0.05) var transition_duration: float = 0.4

@export_group("Camera Reference")
## GameCamera2D 节点路径。留空则自动按组 "game_camera" 查找
@export var camera_path: NodePath

# ============================================================================
# 内部
# ============================================================================

@onready var collision_shape: CollisionShape2D = $CollisionShape2D
@onready var bounds_center_marker: Marker2D = get_node_or_null("BoundsCenter")

var _camera: GameCamera2D


func _ready() -> void:
	add_to_group("camera_zones")
	_resolve_camera()
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	if bounds_source == BoundsSource.CUSTOM_FROM_MARKER and bounds_center_marker == null:
		push_warning("CameraZone '%s'：bounds_source = CUSTOM_FROM_MARKER 但找不到子节点 'BoundsCenter'（Marker2D）。将退化为使用本节点位置。" % name)
	# 处理玩家在本区域内时被实例化的情况（关卡加载场景）
	call_deferred("_apply_if_player_already_inside")


func _resolve_camera() -> void:
	if camera_path != NodePath(""):
		_camera = get_node_or_null(camera_path) as GameCamera2D
		if is_instance_valid(_camera):
			return
	# 优先在当前关卡子树内找，避免切关期间拿到旧关卡的 Camera（即使它尚未被释放）
	var level_root := _get_level_root()
	if level_root != null:
		_camera = _find_camera_in_subtree(level_root)
		if is_instance_valid(_camera):
			return
	# 子树找不到时全局兜底（直接运行单关卡、不经 SubViewport 的场景）
	for n in get_tree().get_nodes_in_group("game_camera"):
		if n is GameCamera2D and is_instance_valid(n):
			_camera = n
			return
	push_warning("CameraZone：找不到 GameCamera2D。请把 GameCamera 加入 'game_camera' 组，或显式指定 camera_path。")


# 沿 parent 链向上，找到直接挂在 SubViewport 下的节点（即关卡根节点）
func _get_level_root() -> Node:
	var node := get_parent()
	while node != null:
		if node.get_parent() is SubViewport:
			return node
		node = node.get_parent()
	return null


func _find_camera_in_subtree(root: Node) -> GameCamera2D:
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is GameCamera2D and n.is_in_group("game_camera"):
			return n
		for child in n.get_children():
			stack.append(child)
	return null


func _apply_if_player_already_inside() -> void:
	# 清除可能因切关而失效的悬挂引用；重试一次兜底加载时序问题
	if not is_instance_valid(_camera):
		_camera = null
	if _camera == null:
		_resolve_camera()
	if _camera == null:
		return
	for body in get_overlapping_bodies():
		if body is Player:
			_push_to_camera()
			return


func _on_body_entered(body: Node) -> void:
	if not (body is Player):
		return
	_push_to_camera()


func _on_body_exited(body: Node) -> void:
	if not (body is Player):
		return
	# 先清悬挂引用，再 resolve，确保 pop 发给当前关卡的 Camera
	if not is_instance_valid(_camera):
		_camera = null
	if _camera == null:
		_resolve_camera()
	if _camera:
		_camera.pop_zone(get_instance_id())


func _push_to_camera() -> void:
	# 先清悬挂引用（旧 Camera 已释放），再 resolve；两层防御同时覆盖"已释放"和"仍存活但是旧的"
	if not is_instance_valid(_camera):
		_camera = null
	if _camera == null:
		_resolve_camera()
	if _camera == null:
		return
	# 隐藏房间专用 zoom 在 LOCK_TO_CENTER 模式下覆盖 zoom_override；其它情况沿用 zoom_override
	var effective_zoom: Vector2 = zoom_override
	if mode == FollowMode.LOCK_TO_CENTER and not is_equal_approx(hidden_room_zoom, 1.0):
		effective_zoom = Vector2(hidden_room_zoom, hidden_room_zoom)
	_camera.push_zone(get_instance_id(), {
		"priority": zone_priority,
		"bounds": _compute_bounds(),
		"lock_to_center": mode == FollowMode.LOCK_TO_CENTER,
		"zoom_override": effective_zoom,
		"transition_duration": transition_duration,
	})


func _compute_bounds() -> Rect2:
	match bounds_source:
		BoundsSource.CUSTOM_FROM_MARKER:
			var center: Vector2 = bounds_center_marker.global_position if bounds_center_marker else global_position
			# 边界至少不能比游戏视口还小（防止 lock 模式下出现奇怪的居中）。
			# 减 Vector2.ONE 抵消 PixelRenderer 给 SubViewport 加的 1px slack，与
			# game_camera.gd:_get_camera_half_view 的算法保持一致
			var viewport_size := get_viewport_rect().size - Vector2.ONE
			var final_size := Vector2(
				maxf(custom_bounds_size.x, viewport_size.x),
				maxf(custom_bounds_size.y, viewport_size.y)
			)
			return Rect2(center - final_size * 0.5, final_size)
		_:
			# AUTO_FROM_COLLISION
			var shape := collision_shape.shape as RectangleShape2D
			if shape == null:
				push_warning("CameraZone：CollisionShape2D 必须是 RectangleShape2D")
				return Rect2()
			var center := collision_shape.global_position
			var size := shape.size * collision_shape.global_scale.abs()
			return Rect2(center - size * 0.5, size)
