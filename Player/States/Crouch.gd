@icon("res://icon/state.svg")
class_name PlayerstateCrouch extends Playerstate

# --- 节点与状态引用 ---
@onready var idle_state: PlayerstateIdle = %Idle
@onready var jump_state: Playerstate = %Jump 
@onready var anim: AnimatedSprite2D = $"../../AnimatedSprite2D"

# 下蹲时的摩擦力
var friction: float = 1000.0 


#region /// 核心状态生命周期
func init() -> void:
	pass

func enter() -> void:
	# 【这里也补回来了！】
	if anim:
		anim.play("crouch")

func exit() -> void:
	pass
#endregion


#region /// 帧更新与输入处理
func handle_input(_event : InputEvent) -> Playerstate:
	# 下蹲时按下跳跃键，直接起跳
	if _event.is_action_pressed("ui_accept") and player.is_on_floor():
		return jump_state
	return null

func process(_delta: float) -> Playerstate:
	return null

func physics_process(_delta: float) -> Playerstate:
	# 如果松开S键，返回待机状态
	if player.direction.y <= 0:
		return idle_state
		
	# 微微滑行的摩擦力逻辑
	player.velocity.x = move_toward(player.velocity.x, 0, friction * _delta)
	
	return null
#endregion
