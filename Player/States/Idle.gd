@icon("res://icon/state.svg")
class_name PlayerstateIdle extends Playerstate

# --- 节点与状态引用 ---
@onready var run_state: PlayerstateRun = %Run
@onready var anim: AnimatedSprite2D = $"../../AnimatedSprite2D" # 请确保节点名称对应


#region /// 核心状态生命周期
## 当这个状态第一次被收集并初始化时执行（只执行一次）
func init() -> void:
	pass

## 当进入这个状态时执行
func enter() -> void:
	if anim:
		anim.play("idle")

## 当退出这个状态时执行
func exit() -> void:
	pass
#endregion


#region /// 帧更新与输入处理
## 处理输入事件。返回目标 Playerstate 以切换状态，返回 null 保持当前状态。
func handle_input(_event : InputEvent) -> Playerstate:
	return null

## 渲染帧更新（_process）。返回目标 Playerstate 以切换状态，返回 null 保持当前状态。
func process(_delta: float) -> Playerstate:
	return null

## 物理帧更新（_physics_process）。返回目标 Playerstate 以切换状态，返回 null 保持当前状态。
func physics_process(_delta: float) -> Playerstate:
	# 1. 检查是否有左右方向输入，如果有，切换到跑动状态
	if player.direction.x != 0:
		return run_state
		
	# 2. 施加地面摩擦力减速
	player.velocity.x = move_toward(player.velocity.x, 0, 1000 * _delta)
	
	return null
#endregionion
