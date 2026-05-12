class_name SpawnPoint extends Marker2D

## 关卡落点标记。关卡切换时 LevelManager 按 spawn_id 找到此节点，
## 将新 Player 传送到这里并应用 spawn_facing。

@export var spawn_id: StringName = &"default"
## 落地朝向：0=保留来源关卡的朝向快照；1=向左；2=向右
@export_enum("保留", "向左", "向右") var spawn_facing: int = 0

## 出生时是否向下射线找最近地面，让设计者无需精确对齐地板像素。
@export var snap_to_ground: bool = true
## 向下搜索的最大距离（像素）。超出此距离不调整位置。
@export var snap_search_distance: float = 256.0
## Player 碰撞盒下沿到原点的距离（像素）。与 Player CollisionShape2D 的半高保持一致。
@export var player_half_height: float = 16.0


func _ready() -> void:
	add_to_group("spawn_points")


## 计算最终出生全局坐标。
## snap_to_ground=true 时向下射线找最近 Ground 层地面，
## 将 y 调整到 ground_y - player_half_height（玩家脚踩地面）。
## 射线范围内无地面时返回原始坐标，不强制调整。
func get_resolved_spawn_position() -> Vector2:
	if not snap_to_ground:
		return global_position
	var space := get_world_2d().direct_space_state
	var params := PhysicsRayQueryParameters2D.create(
		global_position,
		global_position + Vector2(0, snap_search_distance),
		2  # Ground 物理层（layer 2）
	)
	var hit := space.intersect_ray(params)
	if hit.is_empty():
		return global_position
	return Vector2(global_position.x, hit.position.y - player_half_height).floor()
