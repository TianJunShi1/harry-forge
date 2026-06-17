@icon("res://icon/state.svg")
class_name PlayerstateJump extends Playerstate

@onready var fall_state: PlayerstateFall = %Fall
@onready var wall_slide_state: PlayerstateWallSlide = %WallSlide
# 【修改】删除本地 anim 引用，改用 player.anim 统一访问
# 【修改】删除本地 air_speed，改用 player.air_speed 统一管理
# 【修改】删除本地 jump_velocity，改用 player.jump_velocity 统一管理
# 以后二段跳、蓄力跳等状态也可以共同读取 player 的跳跃参数

# 松开跳跃键时的小跳速度衰减系数
const EARLY_RELEASE_MULTIPLIER : float = 0.5

# 【新增：是否处于弹跳板弹飞状态的标记】
var is_bouncing: bool = false

#region /// 核心状态生命周期
func init() -> void:
	# 弹跳板触发时由 Player 发 signal，本状态接管切换。
	# 与 Player 的耦合从"持有具体状态类引用"降为"广播 signal"。
	# 守卫：场景重载 / 编辑器热更新若让 init 跑两遍，避免双连接 → 单次弹跳触发两次切换
	if not player.bounce_requested.is_connected(_on_bounce_requested):
		player.bounce_requested.connect(_on_bounce_requested)


func _on_bounce_requested() -> void:
	is_bouncing = true
	player.call_deferred("change_state", self)

func enter() -> void:
	# 只要真正进入跳跃状态，立刻消费土狼时间（双保险）
	# 防止 coyote_timer 还有剩余时被再次利用
	player.coyote_timer = 0.0

	# 登墙跳：wall_normal 由 WallSlide/WallClimb 在进入 Jump 前写入，这里消费并清零
	if player.wall_normal != Vector2.ZERO:
		player.velocity.y = player.jump_velocity
		player.velocity.x = player.wall_normal.x * player.wall_jump_h_speed
		# 立即翻转朝向，面向逃离方向（蔚蓝同款行为）
		player.anim.flip_h = player.wall_normal.x < 0
		player.wall_normal = Vector2.ZERO
	elif not is_bouncing:
		player.velocity.y = player.jump_velocity

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
	# 登墙跳锁定期内不覆盖横向速度，让推力弧线自然衰减
	if player.wall_jump_lock_timer <= 0.0:
		var speed_factor := 1.0
		if player.wall_last_jump_normal != Vector2.ZERO \
				and not is_zero_approx(player.direction.x) \
				and signf(player.direction.x) != signf(player.wall_last_jump_normal.x):
			speed_factor = player.wall_return_speed_factor
		player.velocity.x = player.direction.x * player.air_speed * speed_factor

	if not is_bouncing and Input.is_action_just_released("jump") and player.velocity.y < 0:
		player.velocity.y *= EARLY_RELEASE_MULTIPLIER

	if player.velocity.y >= 0:
		return fall_state

	return null
#endregion
