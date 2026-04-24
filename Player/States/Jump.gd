@icon("res://icon/state.svg")
class_name PlayerstateJump extends Playerstate

@onready var fall_state: Playerstate = %Fall 
# 【修改】删除本地 anim 引用，改用 player.anim 统一访问
# 【修改】删除本地 air_speed，改用 player.air_speed 统一管理
# 【修改】删除本地 jump_velocity，改用 player.jump_velocity 统一管理
# 以后二段跳、蓄力跳等状态也可以共同读取 player 的跳跃参数

# 【新增：是否处于弹跳板弹飞状态的标记】
var is_bouncing: bool = false 

#region /// 核心状态生命周期
func init() -> void:
	pass

func enter() -> void:
	# 只要真正进入跳跃状态，立刻消费土狼时间（双保险）
	# 防止 coyote_timer 还有剩余时被再次利用
	player.coyote_timer = 0.0
	
	# 【核心修改】只有在"不是弹跳"的时候，才赋予普通跳跃的速度！
	# 防止弹跳板给的超大速度在这里被强行重置为 jump_velocity
	if not is_bouncing:
		player.velocity.y = player.jump_velocity
		
	# 【修改】加空判断，重构场景时更不容易报空引用
	if player.anim:
		player.anim.play("jump")

func exit() -> void:
	# 退出跳跃状态时，务必将标记重置，不影响下一次正常起跳
	is_bouncing = false
#endregion

#region /// 帧更新与输入处理
func handle_input(_event : InputEvent) -> Playerstate:
	return null

func process(_delta: float) -> Playerstate:
	# 【修改】朝向翻转改为调用 player.update_facing()，不再重复写 flip_h 逻辑
	player.update_facing()
	return null

func physics_process(_delta: float) -> Playerstate:
	# 【修改】air_speed 改为读取 player.air_speed
	player.velocity.x = player.direction.x * player.air_speed
	
	# 【核心修改】如果是被弹跳板弹飞的，禁止触发小跳减速！
	# 【修改】ui_accept 统一改为 jump
	if not is_bouncing and Input.is_action_just_released("jump") and player.velocity.y < 0:
		player.velocity.y *= 0.5 
		
	if player.velocity.y >= 0:
		return fall_state
		
	return null
#endregion
