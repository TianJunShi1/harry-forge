@icon("res://icon/state.svg")
class_name Playerstate extends Node

# 缓存的玩家节点引用，由 Player 在 _ready 时自动赋值
var player : Player
#region ///

#endregion


#region /// 核心状态生命周期
## 当这个状态第一次被收集并初始化时执行（只执行一次）
func init() -> void:
	pass

## 当进入这个状态时执行
func enter() -> void:
	pass

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
	return null
#endregion
