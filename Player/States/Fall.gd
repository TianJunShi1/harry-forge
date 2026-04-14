@icon("res://icon/state.svg")
class_name PlayerstateFall extends Playerstate

@onready var idle_state: PlayerstateIdle = %Idle
@onready var run_state: PlayerstateRun = %Run
@onready var jump_state: PlayerstateJump = %Jump 
@onready var anim: AnimatedSprite2D = $"../../AnimatedSprite2D" 

var air_speed: float = 160.0 

# --- 手感调节参数 ---
var coyote_duration: float = 0.16 # 土狼时间：离开边缘后允许起跳的时间
var fall_timer: float = 0.0       # 记录下落了多久

var buffer_duration: float = 0.15 # 跳跃缓冲时间：落地前多久按下会被记住
var buffer_timer: float = 0.0     # 缓冲倒计时器


func init() -> void:
	pass

func enter() -> void:
	if anim:
		anim.play("fall")
	# 每次进入下落状态时，重置两个计时器
	fall_timer = 0.0
	buffer_timer = 0.0

func exit() -> void:
	pass


func handle_input(_event : InputEvent) -> Playerstate:
	return null

func process(_delta: float) -> Playerstate:
	if anim.animation == "fall" and not anim.is_playing():
		anim.play("fall_loop")
		
	if player.direction.x < 0:
		anim.flip_h = true
	elif player.direction.x > 0:
		anim.flip_h = false
	return null

func physics_process(delta: float) -> Playerstate:
	player.velocity.x = player.direction.x * air_speed
	
	fall_timer += delta 
	
	# 【跳跃缓冲计时逻辑】如果计时器被激活了（大于0），就开始倒计时
	if buffer_timer > 0:
		buffer_timer -= delta
	
	# 【核心按键监听】
	if Input.is_action_just_pressed("ui_accept"):
		# 1. 尝试触发土狼时间 (按晚了的宽容)
		if fall_timer <= coyote_duration and (player.previous_state == idle_state or player.previous_state == run_state):
			player.velocity.y = 0 
			return jump_state 
			
		# 2. 如果不满足土狼跳，说明是在高空下落时按的。
		# 此时将这一次跳跃输入“记忆”下来，开启跳跃缓冲计时！(按早了的宽容)
		buffer_timer = buffer_duration
			
			
	# 检查是否落地
	if player.is_on_floor():
		# 【新增逻辑】：落地时检查缓冲计时器。如果还有剩余时间，说明玩家刚才提前按了跳跃！
		if buffer_timer > 0:
			return jump_state # 立刻再次起跳！
			
		# 如果没有缓冲输入，就正常进入待机或跑动
		if player.direction.x == 0:
			return idle_state
		else:
			return run_state
			
	return null
