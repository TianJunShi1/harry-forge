class_name HUD extends CanvasLayer

## HeartTemplate 相对游戏显示区域左上角的偏移（游戏像素）。
@export var heart_offset: Vector2 = Vector2(8, 8)
## 每颗心之间的间距（游戏像素）。
@export var heart_spacing: int = 20

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


func _build_hearts(count: int) -> void:
	for h in _hearts:
		if is_instance_valid(h):
			h.queue_free()
	_hearts.clear()
	_prev_hp = -1
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
		# 初始状态：无动画，直接设置
		for i in _hearts.size():
			_set_state(i, i < current)
		_prev_hp = current
		return

	if current < _prev_hp:
		for i in range(current, _prev_hp):
			_play_damage(_hearts[i])
	elif current > _prev_hp:
		for i in range(_prev_hp, current):
			_play_heal(_hearts[i])

	_prev_hp = current


# 减血：used_to_half → used_half_to_empty → empty（任一动画不存在则直接跳到 empty）
func _play_damage(heart: AnimatedSprite2D) -> void:
	if not is_instance_valid(heart):
		return
	var frames := heart.sprite_frames
	if frames == null or not frames.has_animation(&"used_to_half"):
		heart.play(&"empty")
		return
	heart.play(&"used_to_half")
	heart.animation_finished.connect(func() -> void:
		if not is_instance_valid(heart):
			return
		if heart.sprite_frames.has_animation(&"used_half_to_empty"):
			heart.play(&"used_half_to_empty")
			heart.animation_finished.connect(func() -> void:
				if is_instance_valid(heart):
					heart.play(&"empty")
			, CONNECT_ONE_SHOT)
		else:
			heart.play(&"empty")
	, CONNECT_ONE_SHOT)


# 回血：reset → full（动画不存在则直接跳到 full）
func _play_heal(heart: AnimatedSprite2D) -> void:
	if not is_instance_valid(heart):
		return
	var frames := heart.sprite_frames
	if frames == null or not frames.has_animation(&"reset"):
		heart.play(&"full")
		return
	heart.play(&"reset")
	heart.animation_finished.connect(func() -> void:
		if is_instance_valid(heart):
			heart.play(&"full")
	, CONNECT_ONE_SHOT)


func _set_state(idx: int, full: bool) -> void:
	if not is_instance_valid(_hearts[idx]):
		return
	var anim := &"full" if full else &"empty"
	if _hearts[idx].sprite_frames and _hearts[idx].sprite_frames.has_animation(anim):
		_hearts[idx].play(anim)
