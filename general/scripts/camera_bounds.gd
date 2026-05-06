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
##   • Boss 战 / 大场景：zoom_override = Vector2(0.7, 0.7)（看到更多）

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

## 仅 CUSTOM_FROM_MARKER 模式生效。需要在本节点下放一个 Marker2D 命名为 "BoundsCenter"
@export var custom_bounds_size: Vector2 = Vector2(320, 180)

@export_group("Zoom")
## 进入此区域时切换到的 zoom。Vector2.ZERO 表示沿用 GameCamera2D 的 default_zoom
## 注意：Godot 4 Camera2D 的 zoom > 1 是放大（看更少），< 1 是缩小（看更多）
@export var zoom_override: Vector2 = Vector2.ZERO

## 隐藏房间专用 zoom 标量（仅 mode = LOCK_TO_CENTER 时生效）。
## 1.0 = 无效果；>1 = 放大（看更少，更聚焦/压迫感）；<1 = 缩小（看更多）。
## 非 1.0 时会覆盖 zoom_override；过渡时长由 GameCamera2D 的 zoom_smoothing 控制。
##
## 像素清晰度：整数值（2.0）pixel-perfect（过渡完成后 PixelRenderer 自动恢复 NEAREST）。
## 非整数值（1.3 等）在过渡中及静止时均保持 LINEAR 过滤（统一软化，无法消除）。
## 想要无模糊的效果，必须使用整数。推荐 2.0。
@export_range(0.5, 4.0, 1.0) var hidden_room_zoom: float = 1.0

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
	# 处理玩家在本区域内时被实例化的情况（关卡加载场景）
	call_deferred("_apply_if_player_already_inside")


func _resolve_camera() -> void:
	if camera_path != NodePath(""):
		_camera = get_node_or_null(camera_path) as GameCamera2D
	if _camera == null:
		# 在场景树里找 game_camera 组
		for n in get_tree().get_nodes_in_group("game_camera"):
			if n is GameCamera2D:
				_camera = n
				break
	if _camera == null:
		push_warning("CameraZone：找不到 GameCamera2D。请把 GameCamera 加入 'game_camera' 组，或显式指定 camera_path。")


func _apply_if_player_already_inside() -> void:
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
	if _camera == null:
		_resolve_camera()
	if _camera:
		_camera.pop_zone(get_instance_id())


func _push_to_camera() -> void:
	# PixelRenderer 延迟加载关卡时 GameCamera 可能比 CameraZone 晚 ready，重试一次
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
			# 边界至少不能比视口还小（防止 lock 模式下出现奇怪的居中）
			var viewport_size := get_viewport_rect().size
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
