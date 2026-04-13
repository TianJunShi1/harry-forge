@icon("res://icon/state.svg")
class_name PlayerstateFall extends Playerstate

# --- 节点与状态引用 ---
@onready var idle_state: PlayerstateIdle = %Idle
@onready var run_state: PlayerstateRun = %Run
@onready var anim: AnimatedSprite2D = $"../../AnimatedSprite2D" 

var air_speed: float = 160.0 


#region /// 核心状态生命周期
func init() -> void:
	pass

func enter() -> void:
	# 进入状态时，播放不循环的短暂过渡动画
	if anim:
		anim.play("fall")

func exit() -> void:
	pass
#endregion


#region /// 帧更新与输入处理
func handle_input(_event : InputEvent) -> Playerstate:
	return null

func process(_delta: float) -> Playerstate:
	# 【动画衔接】如果过渡动画播完了，立刻切换到循环下落动画
	if anim.animation == "fall" and not anim.is_playing():
		anim.play("fall_loop")
		
	# 处理空中面朝方向
	if player.direction.x < 0:
		anim.flip_h = true
	elif player.direction.x > 0:
		anim.flip_h = false
	return null

func physics_process(_delta: float) -> Playerstate:
	# 1. 允许玩家在空中左右移动
	player.velocity.x = player.direction.x * air_speed
	
	# 2. 核心逻辑：检查是否落地
	if player.is_on_floor():
		# 落地后根据是否有方向输入，决定是站住还是继续跑
		if player.direction.x == 0:
			return idle_state
		else:
			return run_state
			
	return null
#endregion
