class_name CameraBounds
extends Area2D

# 每个房间/区域放一个这个节点
# 默认情况下：CollisionShape2D 既是触发区，也是摄像机边界
# 只有在“隐藏区域 / 特殊区域”时，才启用自定义边界
# 注意：不支持旋转矩形，请保持节点和 CollisionShape2D 不旋转

@export var transition_duration: float = 0.40  # 边界过渡时间（秒，当前版本已实际用于边界 Tween）
@export var bounds_priority: int = 0           # 优先级，隐藏区域设更高的值来覆盖外层区域

@export var use_custom_bounds: bool = false    # 关闭时直接用 CollisionShape2D 当边界；开启时用下面这套
@export var bounds_size: Vector2 = Vector2(320, 180)  # 自定义边界大小（只在 use_custom_bounds=true 时生效）

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
			body.push_camera_bounds(get_instance_id(), get_bounds_rect(), bounds_priority, transition_duration)

func _on_body_entered(body: Node) -> void:
	if not body is Player:
		return
	body.push_camera_bounds(get_instance_id(), get_bounds_rect(), bounds_priority, transition_duration)

func _on_body_exited(body: Node) -> void:
	if not body is Player:
		return
	body.pop_camera_bounds(get_instance_id())

func get_bounds_rect() -> Rect2:
	# 自定义边界：用于隐藏区域、小夹层、特殊房间
	if use_custom_bounds:
		var center := bounds_center.global_position if bounds_center else global_position

		# 自定义边界如果比视口还小，Player 侧会进入“小区域居中”逻辑，
		# 体感上会更像被吸到中心，而不是顺滑滑进去。
		# 这里把边界至少扩到当前视口大小，避免隐藏区域一进入就被强制居中。
		var viewport_size := get_viewport_rect().size
		var final_size := Vector2(
			max(bounds_size.x, viewport_size.x),
			max(bounds_size.y, viewport_size.y)
		)

		var top_left := center - final_size * 0.5
		return Rect2(top_left, final_size)

	# 默认边界：直接使用 CollisionShape2D 的矩形
	var shape := collision_shape.shape as RectangleShape2D
	if shape == null:
		push_warning("CameraBounds：CollisionShape2D 必须使用 RectangleShape2D")
		return Rect2()

	var center := collision_shape.global_position
	var size := shape.size * collision_shape.global_scale.abs()
	var top_left := center - size * 0.5
	return Rect2(top_left, size)
