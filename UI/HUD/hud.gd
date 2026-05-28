class_name HUD extends CanvasLayer

## HeartTemplate 相对游戏显示区域左上角的偏移（游戏像素）。
@export var heart_offset: Vector2 = Vector2(8, 8)
## 每颗心之间的间距（游戏像素）。
@export var heart_spacing: int = 10

@onready var _template: AnimatedSprite2D = $HeartTemplate

var _hearts: Array[AnimatedSprite2D] = []
# HeartTemplate 在 hud.tscn 里设置的 position 作为游戏像素偏移基准
var _template_game_pos: Vector2


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
	for i in count:
		var h := _template.duplicate() as AnimatedSprite2D
		h.show()
		add_child(h)
		_hearts.append(h)


func _process(_delta: float) -> void:
	var renderer := get_tree().get_first_node_in_group(&"pixel_renderer") as PixelRenderer
	if not is_instance_valid(renderer):
		return
	# HUD 在 SubViewport 外，使用屏幕坐标 + PixelRenderer 的游戏显示原点
	var eff := renderer.get_effective_scale()
	var origin := renderer.get_display_origin()
	for i in _hearts.size():
		if not is_instance_valid(_hearts[i]):
			continue
		_hearts[i].scale = Vector2(eff, eff)
		_hearts[i].position = origin + Vector2(_template_game_pos.x + i * heart_spacing, _template_game_pos.y) * eff


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
