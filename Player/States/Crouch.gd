@icon("res://icon/state.svg")
class_name PlayerstateCrouch extends Playerstate

# --- 节点与状态引用 ---
# 【修改】统一改用 %UniqueName 写法，不再使用相对路径 $"../Idle" 等
@onready var idle_state: PlayerstateIdle = %Idle
@onready var jump_state: PlayerstateJump = %Jump   # 【修改】类型细化为 PlayerstateJump
@onready var fall_state: PlayerstateFall = %Fall   # 【修改】类型细化为 PlayerstateFall
# 【修改】删除本地 anim 引用，改用 player.anim 统一访问
@onready var one_way_platform_ray_cast: RayCast2D = $"../../OneWayPlatformRayCast"

# 下蹲时的摩擦力
var friction: float = 1000.0 

#region /// 核心状态生命周期
func init() -> void:
	pass

func enter() -> void:
	# 【修改】改用 player.anim，加空判断防止场景重构时报空引用
	if player.anim:
		player.anim.play("crouch")

func exit() -> void:
	pass
#endregion

#region /// 帧更新与输入处理
func handle_input(_event : InputEvent) -> Playerstate:
	# 【保留功能】：在平地上蹲伏时，依然可以通过按跳跃键直接起跳
	# 【修改】ui_accept 统一改为 jump
	# 保留 player.is_on_floor() 检查，理由同 Idle/Run：防止帧时序问题
	if _event.is_action_pressed("jump") and player.is_on_floor():
		return jump_state
	return null

func process(_delta: float) -> Playerstate:
	return null

func physics_process(_delta: float) -> Playerstate:
	# 【新增】离地立即切换到下落状态，防止在某些边缘情况下卡在蹲伏状态
	if not player.is_on_floor():
		return fall_state
		
	# 【新增功能】：进入下蹲状态后，如果脚下检测到是单向平台，直接下落
	# 注意：position.y += 1.0 是原型阶段的临时方案，用于推出碰撞体积触发穿透
	# 后续可改为临时关闭单向平台碰撞层，更稳定
	if one_way_platform_ray_cast.is_colliding():
		player.position.y += 1.0 
		return fall_state
		
	# 如果松开 S 键（或者方向不再向下），返回待机状态
	# 【修改】改用 INPUT_DEADZONE 做阈值判断，防止手柄漂移导致无法站起
	if player.direction.y <= player.INPUT_DEADZONE:
		return idle_state
		
	# 平地上的摩擦力滑行逻辑（依然保留）
	player.velocity.x = move_toward(player.velocity.x, 0, friction * _delta)
	
	return null
#endregion
