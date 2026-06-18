@icon("res://icon/state.svg")
class_name PlayerstateRun extends Playerstate

# --- 节点与状态引用 ---
@onready var idle_state: PlayerstateIdle = %Idle
@onready var jump_state: PlayerstateJump = %Jump
@onready var fall_state: PlayerstateFall = %Fall
# 【修改】删除本地 anim 引用，改用 player.anim 统一访问
# 【修改】删除本地 update_facing_direction()，改用 player.update_facing() 统一管理


#region /// 核心状态生命周期
func init() -> void:
	pass

func enter() -> void:
	# 【修复关键 1】：在进入状态的第一时间，立刻同步朝向！
	# 【修改】改用 player.update_facing()
	player.update_facing()
	# 【修改】改用 player.anim，加空判断防止场景重构时报空引用
	if player.anim:
		player.anim.play("run")

func exit() -> void:
	pass
#endregion

#region /// 帧更新与输入处理
func handle_input(_event : InputEvent) -> Playerstate:
	# coyote_timer > 0 覆盖"走出边缘那一帧 input 先于物理帧到来"的漏洞：
	# 上一帧落地刷新了计时器，这一帧 handle_input 时它尚未被物理帧扣减，完全有效
	if _event.is_action_pressed("jump") and (player.is_on_floor() or player.coyote_timer > 0.0):
		return jump_state
	return null

func process(_delta: float) -> Playerstate:
	# 【修复关键 2】：将翻转逻辑放在 _process 渲染帧里，保证画面永远不会掉队
	# 【修改】改用 player.update_facing()
	player.update_facing()
	return null

func physics_process(_delta: float) -> Playerstate:
	# 如果突然不在地面上了（比如走出了平台边缘），立刻切换到下落状态
	if not player.is_on_floor():
		return fall_state
		
	# 1. 检查状态切换
	# 【修改】改用 player.has_horizontal_input()，防止手柄漂移导致无法回到 Idle
	if not player.has_horizontal_input():
		return idle_state
		
	# 2. 纯粹处理物理移动（加速曲线，约 5 帧到达最高速）
	var target := player.direction.x * player.run_speed
	player.velocity.x = move_toward(player.velocity.x, target, player.run_acceleration * _delta)
		
	return null
#endregion
