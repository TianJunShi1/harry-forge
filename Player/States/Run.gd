@icon("res://icon/state.svg")
class_name PlayerstateRun extends Playerstate

# --- 节点与状态引用 ---
@onready var idle_state: PlayerstateIdle = %Idle
@onready var anim: AnimatedSprite2D = $"../../AnimatedSprite2D" 

var move_speed: float = 150.0


#region /// 核心状态生命周期
func init() -> void:
	pass

func enter() -> void:
	# 【修复关键 1】：在进入状态的第一时间，立刻同步朝向！
	update_facing_direction()
	if anim:
		anim.play("run")

func exit() -> void:
	pass
#endregion


#region /// 帧更新与输入处理
func handle_input(_event : InputEvent) -> Playerstate:
	return null

func process(_delta: float) -> Playerstate:
	# 【修复关键 2】：将翻转逻辑放在 _process 渲染帧里，保证画面永远不会掉队
	update_facing_direction()
	return null

func physics_process(_delta: float) -> Playerstate:
	# 1. 检查状态切换
	if player.direction.x == 0:
		return idle_state
		
	# 2. 纯粹处理物理移动
	player.velocity.x = player.direction.x * move_speed
		
	return null
#endregion


# 【新增】提取出一个专门的方法来处理朝向，代码更整洁
func update_facing_direction() -> void:
	if player.direction.x < 0:
		anim.flip_h = true   # 向左走，水平翻转
	elif player.direction.x > 0:
		anim.flip_h = false  # 向右走，不翻转
