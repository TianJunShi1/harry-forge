class_name HUD extends CanvasLayer

## 心形 UI 间距（游戏像素）。与 HeartTemplate 的图像宽度对齐。
@export var heart_spacing: int = 10

@onready var _template: AnimatedSprite2D = $HeartTemplate

var _hearts: Array[AnimatedSprite2D] = []


func _ready() -> void:
	_template.hide()
	var player := get_tree().get_first_node_in_group(&"player") as Player
	if is_instance_valid(player):
		_connect_player(player)
	# 关卡切换后 player 重新入树时重连
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
	for i in count:
		var h := _template.duplicate() as AnimatedSprite2D
		h.position = Vector2(_template.position.x + i * heart_spacing, _template.position.y)
		h.show()
		add_child(h)
		_hearts.append(h)


func _on_hp_changed(current: int, _maximum: int) -> void:
	for i in _hearts.size():
		if not is_instance_valid(_hearts[i]):
			continue
		var target := &"full" if i < current else &"empty"
		var frames := _hearts[i].sprite_frames
		if frames == null or not frames.has_animation(target):
			continue
		if _hearts[i].animation != target:
			_hearts[i].play(target)
