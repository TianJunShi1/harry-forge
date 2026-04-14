@icon("res://icon/state.svg")
class_name PlayerstateJump extends Playerstate

@onready var fall_state: Playerstate = %Fall 
@onready var anim: AnimatedSprite2D = $"../../AnimatedSprite2D" 

var jump_velocity: float = -380.0
var air_speed: float = 160.0


#region /// 核心状态生命周期
func init() -> void:
	pass

func enter() -> void:
	player.velocity.y = jump_velocity
	if anim:
		anim.play("jump")

func exit() -> void:
	pass
#endregion


#region /// 帧更新与输入处理
func handle_input(_event : InputEvent) -> Playerstate:
	return null

func process(_delta: float) -> Playerstate:
	if player.direction.x < 0:
		anim.flip_h = true
	elif player.direction.x > 0:
		anim.flip_h = false
	return null

func physics_process(_delta: float) -> Playerstate:
	player.velocity.x = player.direction.x * air_speed
	
	# 【新增：短按小跳逻辑】
	# 如果玩家松开了跳跃键，并且当前还在往上飞（velocity.y < 0）
	if Input.is_action_just_released("ui_accept") and player.velocity.y < 0:
		# 把向上的速度削减一半，制造出提前掉落的手感
		player.velocity.y *= 0.5 
		
	# 当速度大于等于 0 时（到达最高点），立刻切换到下落状态
	if player.velocity.y >= 0:
		return fall_state
		
	return null
#endregion
