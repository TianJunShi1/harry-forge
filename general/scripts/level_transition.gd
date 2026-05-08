class_name LevelTransition extends Area2D

## 关卡切换触发器。玩家（Player）进入碰撞区域时触发 LevelManager.transition_to。
##
## 使用方式：
##   1. 实例化 general/level_transition/Level_transition.tscn
##   2. 调整 CollisionShape2D 覆盖触发区域
##   3. 在 Inspector 设置 target_level 和 target_spawn_id

@export var target_level: PackedScene
@export var target_spawn_id: StringName = &"default"
## 设为 true 可在 grace 期内也触发（默认 false，防止落点反弹）
@export var ignore_grace: bool = false


func _ready() -> void:
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node2D) -> void:
	if not body is Player:
		return
	if LevelManager.is_transitioning():
		return
	if LevelManager.is_in_grace_period() and not ignore_grace:
		return
	if target_level == null:
		push_warning("LevelTransition '%s'：target_level 未指定，忽略触发。" % name)
		return
	LevelManager.transition_to(target_level, target_spawn_id)
