extends Node

## 关卡切换编排器（autoload）。
## 注意：不能用 class_name —— autoload 名 LevelManager 已是全局标识符，
## 再加 class_name 会与之冲突（"hides an autoload singleton" 报错）。

signal transition_started(target_level: PackedScene, target_spawn_id: StringName)
signal transition_finished

@export var fade_duration: float = 0.3
## 落地后触发器免疫期（秒），防止瞬间触发反向触发器产生 bounce-back
@export var post_transition_grace: float = 0.3

var _renderer: PixelRenderer = null
var _fade_rect: ColorRect = null
var _is_transitioning: bool = false
var _grace_timer: float = 0.0


func _process(delta: float) -> void:
	if _grace_timer > 0.0:
		_grace_timer -= delta


## 由 main.tscn 的脚本在 _ready 中调用，注册 PixelRenderer 和 FadeRect。
func register_renderer(r: PixelRenderer, fade: ColorRect) -> void:
	_renderer = r
	_fade_rect = fade


func is_transitioning() -> bool:
	return _is_transitioning


func is_in_grace_period() -> bool:
	return _grace_timer > 0.0


## 触发关卡切换。在 fade 期间重入调用会被静默丢弃。
func transition_to(packed: PackedScene, spawn_id: StringName = &"") -> void:
	if _is_transitioning:
		return
	if _renderer == null or _fade_rect == null:
		push_error("LevelManager.transition_to: register_renderer 尚未调用，无 PixelRenderer 或 FadeRect。")
		return
	_run_transition(packed, spawn_id)


func _run_transition(packed: PackedScene, spawn_id: StringName) -> void:
	_is_transitioning = true
	transition_started.emit(packed, spawn_id)

	# 冻结当前关卡的玩家输入（画面变黑期间玩家不应操作）
	var old_player := _find_player_in_current_level()
	if old_player:
		old_player.set_process_unhandled_input(false)

	# Fade out：游戏画面 → 黑屏
	var fade_out := create_tween()
	fade_out.tween_property(_fade_rect, "color:a", 1.0, fade_duration)
	await fade_out.finished

	# 快照：记录旧玩家朝向，供落点没有强制 facing 时恢复
	var flip_h_snapshot: bool = false
	if is_instance_valid(old_player) and old_player.anim:
		flip_h_snapshot = old_player.anim.flip_h

	# 切换关卡
	_renderer.load_level(packed)
	# 等一帧：让新场景所有节点完成 _enter_tree + _ready（包括 Player 加入 "player" 组）
	await get_tree().process_frame

	var new_level := _renderer.get_current_level()
	var new_player: Player = null

	if is_instance_valid(new_level):
		new_player = _find_player_in(new_level)
		if new_player:
			var spawn := _find_spawn(new_level, spawn_id)
			_apply_spawn(new_player, spawn, flip_h_snapshot)
			var cam := _find_camera_in(new_level)
			if cam:
				# 显式重新挂接：load_level 同步 add_child 时新 GameCamera._ready 已跑，
				# 但那时老关卡的 Player 还没 queue_free，相机 follow_target 误指向老 Player；
				# await process_frame 后老 Player 失效 → snap_to_target 因 is_instance_valid
				# 失败而 return，相机停在 (0,0) 画面空白。这里把 follow_target 直接换成新 Player
				# 并 snap，绕开 race。
				cam.assign_follow_target(new_player, true)
			# fade-in 期间完全冻结新玩家：物理（重力/移动）+ 输入事件均暂停，
			# 避免黑屏期间玩家滑离出生点或从边缘落坑。
			new_player.set_physics_process(false)
			new_player.set_process_unhandled_input(false)
		else:
			push_error("LevelManager: 新关卡中找不到 Player 节点，跳过 teleport。")
	else:
		push_error("LevelManager: load_level 后 get_current_level() 为空，关卡加载失败。")

	# Fade in：黑屏 → 游戏画面
	var fade_in := create_tween()
	fade_in.tween_property(_fade_rect, "color:a", 0.0, fade_duration)
	await fade_in.finished

	# 解冻新玩家（物理 + 输入同步恢复）
	if is_instance_valid(new_player):
		new_player.set_physics_process(true)
		new_player.set_process_unhandled_input(true)

	transition_finished.emit()
	_is_transitioning = false
	# grace period 在 is_transitioning 清零之后才开始计时，
	# 确保玩家拿到控制权后的 post_transition_grace 秒内触发器不响应，
	# 防止落在传送门上的 bounce-back。
	_grace_timer = post_transition_grace


func _apply_spawn(player: Player, spawn: SpawnPoint, flip_h_fallback: bool) -> void:
	if spawn:
		player.global_position = spawn.global_position
		match spawn.spawn_facing:
			1:  # 向左
				if player.anim:
					player.anim.flip_h = true
			2:  # 向右
				if player.anim:
					player.anim.flip_h = false
			_:  # 保留快照朝向
				if player.anim:
					player.anim.flip_h = flip_h_fallback
	else:
		if player.anim:
			player.anim.flip_h = flip_h_fallback


func _find_player_in_current_level() -> Player:
	if not is_instance_valid(_renderer):
		return null
	var lvl := _renderer.get_current_level()
	return _find_player_in(lvl) if is_instance_valid(lvl) else null


func _find_player_in(root: Node) -> Player:
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is Player:
			return n
		for c in n.get_children():
			stack.append(c)
	return null


func _find_spawn(root: Node, spawn_id: StringName) -> SpawnPoint:
	var first: SpawnPoint = null
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is SpawnPoint:
			if first == null:
				first = n
			if spawn_id != &"" and n.spawn_id == spawn_id:
				return n
		for c in n.get_children():
			stack.append(c)
	if first == null:
		push_warning("LevelManager: 新关卡中没有 SpawnPoint，玩家位置保持编辑器默认值。")
	elif spawn_id != &"":
		push_warning("LevelManager: 找不到 spawn_id='%s' 的 SpawnPoint，退回到第一个。" % spawn_id)
	return first


func _find_camera_in(root: Node) -> GameCamera2D:
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is GameCamera2D:
			return n
		for c in n.get_children():
			stack.append(c)
	return null
