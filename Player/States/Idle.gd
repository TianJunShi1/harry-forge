@icon("res://icon/state.svg")
class_name PlayerstateIdle extends Playerstate

# --- 节点与状态引用 ---
@onready var run_state: PlayerstateRun = %Run
@onready var crouch_state: PlayerstateCrouch = %Crouch
@onready var jump_state: PlayerstateJump = %Jump
@onready var fall_state: PlayerstateFall = %Fall
# 【修改】删除本地 anim 引用，改用 player.anim 统一访问


#region /// 核心状态生命周期
func init() -> void:
	pass

func enter() -> void:
	# 【修改】改用 player.anim，加空判断防止场景重构时报空引用
	if player.anim:
		player.anim.play("idle")

func exit() -> void:
	pass
#endregion

#region /// 帧更新与输入处理
func handle_input(_event : InputEvent) -> Playerstate:
	# coyote_timer > 0 覆盖"走出边缘那一帧 input 先于物理帧到来"的漏洞
	if _event.is_action_pressed("jump") and (player.is_on_floor() or player.coyote_timer > 0.0):
		return jump_state
	return null

func process(_delta: float) -> Playerstate:
	return null

func physics_process(_delta: float) -> Playerstate:
	if not player.is_on_floor():
		return fall_state
		
	# 【修改】改用 player.INPUT_DEADZONE 做阈值判断，防止手柄漂移触发下蹲
	if player.direction.y > player.INPUT_DEADZONE:
		return crouch_state
		
	# 【修改】改用 player.has_horizontal_input()，不直接接触 INPUT_DEADZONE 常量
	if player.has_horizontal_input():
		return run_state
		
	player.velocity.x = move_toward(player.velocity.x, 0.0, player.run_deceleration * _delta)
	
	return null
#endregion
