@icon("res://icon/state.svg")
class_name PlayerstateFall extends Playerstate

@onready var idle_state: PlayerstateIdle = %Idle
@onready var run_state: PlayerstateRun = %Run
@onready var jump_state: PlayerstateJump = %Jump 
# 【修改】删除本地 anim 引用，改用 player.anim 统一访问
# 【修改】删除本地 air_speed，改用 player.air_speed 统一管理

# --- 手感调节参数 ---
# 【修改】删除 coyote_duration 和 fall_timer，土狼时间已统一由 player.coyote_timer 管理
var buffer_duration: float = 0.15 # 跳跃缓冲时间：落地前多久按下会被记住
var buffer_timer: float = 0.0     # 缓冲倒计时器

func init() -> void:
	pass

func enter() -> void:
	# 【修改】改用 player.anim，加空判断防止场景重构时报空引用
	if player.anim:
		player.anim.play("fall")
	# 每次进入下落状态时，重置缓冲计时器
	# 【修改】fall_timer 已删除，土狼时间由 player.coyote_timer 统一管理
	buffer_timer = 0.0

func exit() -> void:
	pass

func handle_input(_event: InputEvent) -> Playerstate:
	# 【修改】跳跃输入移到 handle_input，比 physics_process 轮询更可靠
	# 同时把 ui_accept 统一改为 jump
	if _event.is_action_pressed("jump"):
		# 1. 尝试触发土狼时间（按晚了的宽容）
		# 【修改】改用 player.coyote_timer，比 was_on_floor 布尔值更可靠
		# was_on_floor 在走出边缘的瞬间可能已经是 false，导致土狼跳失效
		# coyote_timer 在地面时持续重置，离地后才开始倒数，窗口判断更准确
		if player.coyote_timer > 0.0:
			return jump_state
			
		# 2. 不满足土狼跳，说明是在高空下落时按的
		# 将这次跳跃输入"记忆"下来，开启跳跃缓冲计时（按早了的宽容）
		buffer_timer = buffer_duration
		
	return null

func process(_delta: float) -> Playerstate:
	# 【修改】加空判断，贯彻"场景重构时更稳"的思路
	if player.anim and player.anim.animation == "fall" and not player.anim.is_playing():
		player.anim.play("fall_loop")
	
	# 【修改】朝向翻转改为调用 player.update_facing()
	player.update_facing()
	return null

func physics_process(delta: float) -> Playerstate:
	# 【修改】air_speed 改为读取 player.air_speed
	player.velocity.x = player.direction.x * player.air_speed
	
	# 【跳跃缓冲计时逻辑】如果计时器被激活了（大于0），就开始倒计时
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
