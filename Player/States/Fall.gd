@icon("res://icon/state.svg")
class_name PlayerstateFall extends Playerstate

@onready var idle_state: PlayerstateIdle = %Idle
@onready var run_state: PlayerstateRun = %Run
@onready var jump_state: PlayerstateJump = %Jump
@onready var wall_slide_state: PlayerstateWallSlide = %WallSlide
# 【修改】删除本地 anim 引用，改用 player.anim 统一访问
# 【修改】删除本地 air_speed，改用 player.air_speed 统一管理

# --- 手感调节参数 ---
# 【修改】删除 coyote_duration 和 fall_timer，土狼时间已统一由 player.coyote_timer 管理
var buffer_duration: float = 0.15 # 跳跃缓冲时间：落地前多久按下会被记住
var buffer_timer: float = 0.0     # 缓冲倒计时器
var _buffer_used: bool = false    # 【新增】防止空中反复刷新缓冲，缓冲只能激活一次

func init() -> void:
	pass

func enter() -> void:
	# 【修改】改用 player.anim，加空判断防止场景重构时报空引用
	if player.anim:
		player.anim.play("fall")
	# 每次进入下落状态时，重置缓冲计时器
	# 【修改】fall_timer 已删除，土狼时间由 player.coyote_timer 统一管理
	buffer_timer = 0.0
	_buffer_used = false

func exit() -> void:
	pass

func handle_input(_event: InputEvent) -> Playerstate:
	if _event.is_action_pressed("jump"):
		# 1. 地面土狼时间
		if player.coyote_timer > 0.0:
			return jump_state

		# 2. 壁面土狼时间：贴墙或刚离墙的宽容窗口内直接登墙跳，无需先进入 WallSlide
		#    和土狼时间同理——记住"最近贴过的墙"，让跳跃更响应
		if player.wall_coyote_timer > 0.0 and player.wall_jump_lock_timer <= 0.0:
			player.wall_normal = player.wall_coyote_normal
			player.wall_last_jump_normal = player.wall_coyote_normal
			player.wall_jump_lock_timer = player.wall_jump_lock_duration
			player.wall_coyote_timer = 0.0
			return jump_state

		# 3. 跳跃缓冲：高空按下时记住，落地后立即起跳
		if not _buffer_used:
			buffer_timer = buffer_duration
			_buffer_used = true

	return null

func process(_delta: float) -> Playerstate:
	# 【修改】加空判断，贯彻"场景重构时更稳"的思路
	if player.anim and player.anim.animation == "fall" and not player.anim.is_playing():
		player.anim.play("fall_loop")
	
	# 锁定期内保持登墙跳设定的朝向，不被输入方向覆盖
	if player.wall_jump_lock_timer <= 0.0:
		player.update_facing()
	return null

func physics_process(delta: float) -> Playerstate:
	var speed_factor := 1.0
	if player.wall_last_jump_normal != Vector2.ZERO \
			and not is_zero_approx(player.direction.x) \
			and signf(player.direction.x) != signf(player.wall_last_jump_normal.x):
		speed_factor = player.wall_return_speed_factor
	var target := player.direction.x * player.air_speed * speed_factor
	player.velocity.x = move_toward(player.velocity.x, target, player.air_acceleration * delta)

	# 贴墙检测：锁定期结束、贴墙中、按住朝墙方向
	if player.wall_jump_lock_timer <= 0.0 and player.is_on_wall() and not player.is_on_floor() and player.velocity.y > 0:
		var wall_n := player.get_wall_normal()
		# direction.x 与法线方向相反 = 朝向墙壁
		if not is_zero_approx(player.direction.x) and signf(player.direction.x) != signf(wall_n.x):
			return wall_slide_state

	if buffer_timer > 0:
		buffer_timer -= delta

	# 检查是否落地
	if player.is_on_floor():
		# 落地时检查缓冲计时器。如果还有剩余时间，说明玩家刚才提前按了跳跃！
		if buffer_timer > 0:
			return jump_state # 立刻再次起跳！
			
		# 如果没有缓冲输入，就正常进入待机或跑动
		# 【修改】改用 player.has_horizontal_input()，不直接接触 INPUT_DEADZONE 常量
		if player.has_horizontal_input():
			return run_state
		else:
			return idle_state
			
	return null
