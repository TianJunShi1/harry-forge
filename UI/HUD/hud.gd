class_name HUD extends CanvasLayer

## HeartTemplate 相对游戏显示区域左上角的偏移（游戏像素）。
@export var heart_offset: Vector2 = Vector2(8, 8)
## 每颗心之间的间距（游戏像素）。
@export var heart_spacing: int = 20

# ── 动画名称常量 ──────────────────────────────────────────────────────────────
# 静态状态
const A_EMPTY        := &"empty"
const A_HALF         := &"half"
const A_FULL         := &"full"
# 受伤过渡（非循环）
const A_DMG_TO_HALF  := &"used_to_half"       # 满 → 半
const A_DMG_TO_EMPTY := &"used_half_to_empty"  # 半 → 空
# 回血过渡（非循环）
const A_HEAL_TO_HALF := &"empty_to_half"       # 空 → 半
const A_HEAL_TO_FULL := &"half_to_full"        # 半 → 满
const A_HEAL_FULL    := &"reset"               # 空 → 满（整颗回复）
# ─────────────────────────────────────────────────────────────────────────────

@onready var _template: AnimatedSprite2D = $HeartTemplate

var _hearts: Array[AnimatedSprite2D] = []
var _template_game_pos: Vector2
var _prev_hp: int = -1


func _ready() -> void:
	process_priority = 2
	_template_game_pos = _template.position
	_template.hide()
	var player := get_tree().get_first_node_in_group(&"player") as Player
	if is_instance_valid(player):
		_connect_player(player)
	get_tree().node_added.connect(_on_node_added)


func _on_node_added(node: Node) -> void:
	if node is Player:
		_connect_player(node as Player)


func _connect_player(player: Player) -> void:
	if player.hp_changed.is_connected(_on_hp_changed):
		return
	_build_hearts(player.max_hp)
	player.hp_changed.connect(_on_hp_changed)
	_on_hp_changed(player.current_hp, player.max_hp)


func _build_hearts(max_hp: int) -> void:
	for h in _hearts:
		if is_instance_valid(h):
			h.queue_free()
	_hearts.clear()
	_prev_hp = -1
	# 每颗心 = 2 HP 单位；显示心的数量 = max_hp / 2
	var count := max_hp / 2
	for i in count:
		var h := _template.duplicate() as AnimatedSprite2D
		h.show()
		add_child(h)
		_hearts.append(h)


func _process(_delta: float) -> void:
	var renderer := get_tree().get_first_node_in_group(&"pixel_renderer") as PixelRenderer
	if not is_instance_valid(renderer):
		return
	var eff := renderer.get_effective_scale()
	var origin := renderer.get_display_origin()
	for i in _hearts.size():
		if not is_instance_valid(_hearts[i]):
			continue
		_hearts[i].scale = Vector2(eff, eff)
		_hearts[i].position = origin + Vector2(_template_game_pos.x + i * heart_spacing, _template_game_pos.y) * eff


func _on_hp_changed(current: int, _maximum: int) -> void:
	if _prev_hp < 0:
		for i in _hearts.size():
			_play_immediate(_hearts[i], _heart_state(current, i))
		_prev_hp = current
		return

	for i in _hearts.size():
		var old_state := _heart_state(_prev_hp, i)
		var new_state := _heart_state(current, i)
		if old_state != new_state:
			_play_transition(_hearts[i], old_state, new_state)

	_prev_hp = current


## 根据 HP 值计算第 i 颗心的显示状态
func _heart_state(hp: int, i: int) -> StringName:
	var units := hp - i * 2
	if units >= 2: return A_FULL
	if units == 1: return A_HALF
	return A_EMPTY


## 按 old→new 状态选择并串联动画
func _play_transition(heart: AnimatedSprite2D, old: StringName, new_state: StringName) -> void:
	if not is_instance_valid(heart):
		return
	match [old, new_state]:
		# ── 受伤 ──
		[A_FULL, A_HALF]:
			_chain(heart, [A_DMG_TO_HALF, A_HALF])
		[A_FULL, A_EMPTY]:
			_chain(heart, [A_DMG_TO_HALF, A_DMG_TO_EMPTY, A_EMPTY])
		[A_HALF, A_EMPTY]:
			_chain(heart, [A_DMG_TO_EMPTY, A_EMPTY])
		# ── 回血 ──
		[A_EMPTY, A_HALF]:
			_chain(heart, [A_HEAL_TO_HALF, A_HALF])
		[A_HALF, A_FULL]:
			_chain(heart, [A_HEAL_TO_FULL, A_FULL])
		[A_EMPTY, A_FULL]:
			_chain(heart, [A_HEAL_FULL, A_FULL])
		# ── 兜底 ──
		_:
			_play_immediate(heart, new_state)


## 串联播放动画列表：非循环动画播完后自动播下一个，最后一个直接 play（静态或循环）
func _chain(heart: AnimatedSprite2D, anims: Array) -> void:
	if anims.is_empty() or not is_instance_valid(heart):
		return
	var first: StringName = anims[0]
	var rest: Array = anims.slice(1)
	if not _has_anim(heart, first):
		# 跳过不存在的动画，继续处理剩余
		_chain(heart, rest)
		return
	heart.play(first)
	if rest.is_empty():
		return
	heart.animation_finished.connect(func() -> void:
		if is_instance_valid(heart):
			_chain(heart, rest)
	, CONNECT_ONE_SHOT)


func _play_immediate(heart: AnimatedSprite2D, anim: StringName) -> void:
	if is_instance_valid(heart) and _has_anim(heart, anim):
		heart.play(anim)


func _has_anim(heart: AnimatedSprite2D, anim: StringName) -> bool:
	return heart.sprite_frames != null and heart.sprite_frames.has_animation(anim)
