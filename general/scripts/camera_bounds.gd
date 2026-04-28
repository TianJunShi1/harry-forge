class_name CameraBounds
extends Area2D

# 每个房间/区域放一个这个节点
# 默认情况下：CollisionShape2D 既是触发区，也是摄像机边界
# 只有在"隐藏区域 / 特殊区域"时，才启用自定义边界
# 注意：不支持旋转矩形，请保持节点和 CollisionShape2D 不旋转

@export var transition_duration: float = 0.40  # 边界过渡时间（秒）
@export var bounds_priority: int = 0           # 优先级，隐藏区域设更高的值覆盖外层区域

# 普通房间：use_custom_bounds = false，直接拉 CollisionShape2D 大小即可
# 隐藏区域：use_custom_bounds = true，CollisionShape2D 做大一点提前触发，
#           实际摄像机边界由 BoundsCenter（Marker2D 子节点）+ bounds_size 决定
@export var use_custom_bounds: bool = false
@export var bounds_size: Vector2 = Vector2(320, 180)  # 只在 use_custom_bounds=true 时生效

# 隐藏区域默认固定镜头到房间中心，普通区域不受影响
@export var lock_camera_to_room_center: bool = true

@onready var collision_shape: CollisionShape2D = $CollisionShape2D
@onready var bounds_center: Marker2D = get_node_or_null("BoundsCenter")

func _ready() -> void:
	add_to_group("camera_bounds")
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	call_deferred("_apply_if_player_already_inside")

func _apply_if_player_already_inside() -> void:
	for body in get_overlapping_bodies():
		if body is Player:
			body.push_camera_bounds(
				get_instance_id(),
				get_bounds_rect(),
				bounds_priority,
				transition_duration,
				_should_lock_camera_to_center()
			)

func _on_body_entered(body: Node) -> void:
	if not body is Player:
		return
	body.push_camera_bounds(
		get_instance_id(),
		get_bounds_rect(),
		bounds_priority,
		transition_duration,
		_should_lock_camera_to_center()
	)

func _on_body_exited(body: Node) -> void:
	if not body is Player:
		return
	body.pop_camera_bounds(get_instance_id())

func _should_lock_camera_to_center() -> bool:
	# 只有自定义边界模式且勾选了锁定，才固定镜头
	return use_custom_bounds and lock_camera_to_room_center

func get_bounds_rect() -> Rect2:
	# 隐藏区域模式：用 BoundsCenter + bounds_size 决定真实摄像机边界
	if use_custom_bounds:
		var center := bounds_center.global_position if bounds_center else global_position
		# 边界至少扩到当前视口大小，避免隐藏区域比屏幕小时被强制居中
		var viewport_size := get_viewport_rect().size
		var final_size := Vector2(
			max(bounds_size.x, viewport_size.x),
			max(bounds_size.y, viewport_size.y)
		)
		var top_left := center - final_size * 0.5
		return Rect2(top_left, final_size)

	# 普通房间模式：直接用 CollisionShape2D 的矩形作为边界
	var shape := collision_shape.shape as RectangleShape2D
	if shape == null:
		push_warning("CameraBounds：CollisionShape2D 必须使用 RectangleShape2D")
		return Rect2()

	var center := collision_shape.global_position
	var size := shape.size * collision_shape.global_scale.abs()
	var top_left := center - size * 0.5
	return Rect2(top_left, size)
