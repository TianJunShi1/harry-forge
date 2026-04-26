class_name CameraBounds
extends Area2D

# 每个房间/区域放一个这个节点
# CollisionShape2D 的矩形大小就是摄像机的边界范围
# 注意：矩形代表"相机不能越过的边"，不是"玩家活动范围"
# 注意：不支持旋转矩形，请保持节点和 CollisionShape2D 不旋转

@export var transition_duration: float = 0.25  # 边界过渡时间（秒，暂时保留供后续使用）
@export var bounds_priority: int = 0           # 优先级，隐藏区域设更高的值来覆盖外层区域

@onready var collision_shape: CollisionShape2D = $CollisionShape2D

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

func _on_body_entered(body: Node) -> void:
	if not body is Player:
		return
	body.push_camera_bounds(get_bounds_rect(), bounds_priority)

func _on_body_exited(body: Node) -> void:
	if not body is Player:
		return
	body.pop_camera_bounds(bounds_priority)

func get_bounds_rect() -> Rect2:
	var shape := collision_shape.shape as RectangleShape2D
	if shape == null:
		push_warning("CameraBounds：CollisionShape2D 必须使用 RectangleShape2D")
		return Rect2()

	# 用 CollisionShape2D 自己的全局位置，正确处理本地偏移
	var center := collision_shape.global_position

	# 把缩放算进去，避免缩放后边界按原始 size 计算
	var size := shape.size * collision_shape.global_scale.abs()

	var top_left := center - size * 0.5
	return Rect2(top_left, size)
