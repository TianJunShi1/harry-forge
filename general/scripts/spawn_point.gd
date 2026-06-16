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
## Player 原点到碰撞盒下沿的有符号距离（像素，沿 +y 方向）。
##   • 正值 = 原点在脚的上方（典型"原点在身体中心"约定）
##   • 0    = 原点恰在脚底
##   • 负值 = 原点在脚的下方（本游戏当前 Player 配置：CollisionShape2D
##           position=(0,-15)，CapsuleShape 半径 10 → 碰撞底在本地 y=-5；
##           原点比脚低 5 px，所以应填 -5）
## 与 Player CollisionShape2D 几何保持一致，否则 snap_to_ground 后会
## 出现微小落差，第一物理帧 Idle 误判 is_on_floor=false 切到 Fall，
## 产生可见坠落动画。
@export var player_half_height: float = -5.0
## 向下射线使用的碰撞层掩码（bitmask）。默认 2 = Ground 层；
## 物理层调整后只改这里，不必再回来改硬编码。
@export_flags_2d_physics var ground_mask: int = 2


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
		ground_mask
	)
	var hit := space.intersect_ray(params)
	if hit.is_empty():
		return global_position
	return Vector2(global_position.x, hit.position.y - player_half_height).floor()
