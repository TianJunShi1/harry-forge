class_name LevelTransition extends Area2D

## 关卡切换触发器。玩家（Player）进入碰撞区域时触发 LevelManager.transition_to。
##
## 使用方式：
##   1. 实例化 general/level_transition/Level_transition.tscn
##   2. 调整 CollisionShape2D 覆盖触发区域
##   3. 在 Inspector 设置 target_level 和 target_spawn_id

## 目标关卡路径（如 res://Level/01_chapter2/02.tscn）。
## 用路径字符串而非 PackedScene，避免两个关卡场景互相引用造成循环加载死锁。
@export_file("*.tscn") var target_level_path: String = ""
@export var target_spawn_id: StringName = &"default"
## 设为 true 可在 grace 期内也触发（默认 false，防止落点反弹）
@export var ignore_grace: bool = false
## 玩家进入方向：右/左/下/上。遮罩从该方向压来覆盖画面（与移动方向相同侧入场）。
@export_enum("右", "左", "下", "上") var transition_direction: int = 0


func _ready() -> void:
	# 启动期就预检路径配置错误，避免玩家走到才报错；不阻止运行，仅给警告。
	if target_level_path.is_empty():
		push_warning("LevelTransition '%s'：target_level_path 未设置。" % name)
	elif not ResourceLoader.exists(target_level_path):
		push_warning("LevelTransition '%s'：路径不存在 '%s'。" % [name, target_level_path])
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node2D) -> void:
	if not body is Player:
		return
	if LevelManager.is_transitioning():
		return
	if LevelManager.is_in_grace_period() and not ignore_grace:
		return
	if target_level_path.is_empty():
		push_warning("LevelTransition '%s'：target_level_path 未指定，忽略触发。" % name)
		return
	var packed: PackedScene = load(target_level_path)
	if packed == null:
		push_error("LevelTransition '%s'：无法加载场景 '%s'。" % [name, target_level_path])
		return
	# 玩家向右移动时遮罩应从右侧压来（从右到左），其余方向同理；
	# export 存的是玩家运动方向，shader direction 存的是擦除起始侧，两者轴相同但需对调。
	const DIR_FLIP: Array[int] = [1, 0, 3, 2]
	LevelManager.transition_to(packed, target_spawn_id, DIR_FLIP[transition_direction])
