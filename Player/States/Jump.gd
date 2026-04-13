@icon("res://icon/state.svg")
class_name PlayerstateJump extends Playerstate

# --- 节点与状态引用 ---
@onready var fall_state: Playerstate = %Fall # 获取下落状态
@onready var anim: AnimatedSprite2D = $"../../AnimatedSprite2D" 

# 跳跃初速度和空中移动速度
var jump_velocity: float = -400.0
var air_speed: float = 160.0


#region /// 核心状态生命周期
func init() -> void:
	pass

func enter() -> void:
	# 1. 给予向上的速度（负数是向上）
	player.velocity.y = jump_velocity
	
	# 2. 播放跳跃动画
	if anim:
		anim.play("jump")

func exit() -> void:
	pass
#endregion


#region /// 帧更新与输入处理
func handle_input(_event : InputEvent) -> Playerstate:
	return null

func process(_delta: float) -> Playerstate:
	# 处理空中面朝方向 (放在 process 保证画面无延迟)
	if player.direction.x < 0:
		anim.flip_h = true
	elif player.direction.x > 0:
		anim.flip_h = false
	return null

func physics_process(_delta: float) -> Playerstate:
	# 1. 允许玩家在空中左右移动
	player.velocity.x = player.direction.x * air_speed
	
	# 2. 核心逻辑：当速度大于等于 0 时（到达最高点），立刻切换到下落状态
	if player.velocity.y >= 0:
		return fall_state
		
	return null
#endregion
