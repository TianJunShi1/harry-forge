@icon("res://icon/state.svg")
class_name PlayerstateIdle extends Playerstate

# --- 节点与状态引用 ---
@onready var run_state: PlayerstateRun = %Run
@onready var crouch_state: Playerstate = %Crouch
@onready var jump_state: Playerstate = %Jump
@onready var fall_state: Playerstate = %Fall
@onready var anim: AnimatedSprite2D = $"../../AnimatedSprite2D"

# 地面摩擦力
var friction: float = 800.0 


#region /// 核心状态生命周期
func init() -> void:
	pass

func enter() -> void:
	if anim:
		anim.play("idle")

func exit() -> void:
	pass
#endregion


#region /// 帧更新与输入处理
func handle_input(_event : InputEvent) -> Playerstate:
	if _event.is_action_pressed("ui_accept") and player.is_on_floor():
		return jump_state
	return null

func process(_delta: float) -> Playerstate:
	return null

func physics_process(_delta: float) -> Playerstate:
	if not player.is_on_floor():
		return fall_state

	if player.direction.y > 0:
		return crouch_state

	if player.direction.x != 0:
		return run_state
		
	# 微微滑行的摩擦力逻辑
	player.velocity.x = move_toward(player.velocity.x, 0, friction * _delta)
	
	return null
#endregion
