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
## 转场方向覆盖：勾选后使用下方手动方向，否则从玩家速度自动检测。
@export var override_direction: bool = true
## 仅在 override_direction=true 时生效。
## 右/左/下/上：遮罩从该侧压来；径向：从屏幕中心向外溶解扩散。
@export_enum("右", "左", "下", "上", "径向") var transition_direction: int = 4


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
	var dir := _resolve_direction(body as Player)
	LevelManager.transition_to(packed, target_spawn_id, dir)


## 根据玩家速度自动推断 shader 擦除方向（遮罩从运动来向压来）。
## override_direction=true 时改用手动设置。
func _resolve_direction(player: Player) -> int:
	var move_dir: int
	if override_direction:
		move_dir = transition_direction
	else:
		var vel := player.velocity
		if abs(vel.x) >= abs(vel.y):
			move_dir = 0 if vel.x >= 0.0 else 1  # 右 or 左
		else:
			move_dir = 2 if vel.y >= 0.0 else 3  # 下 or 上
	# 径向模式（4）对称无需翻转；轴向模式需对调（向右运动 → 遮罩从右侧压来）。
	const DIR_FLIP: Array[int] = [1, 0, 3, 2, 4]
	return DIR_FLIP[move_dir]
