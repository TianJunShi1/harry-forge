class_name NpcSample extends Node2D

## wait 动画随机触发间隔范围（秒）
@export var idle_variation_interval: Vector2 = Vector2(6.0, 14.0)
@export var outline_color: Color = Color(1.0, 1.0, 1.0, 1.0)

@onready var _anim: AnimatedSprite2D = $AnimatedSprite2D
@onready var _zone: Area2D = $DetectionZone

var _player: Player = null
var _is_talking: bool = false
var _variation_timer: float = 0.0
var _outline_node: AnimatedSprite2D


func _ready() -> void:
	_zone.body_entered.connect(_on_body_entered)
	_zone.body_exited.connect(_on_body_exited)
	_anim.animation_looped.connect(_on_animation_looped)
	_anim.play(&"idle")
	_reset_variation_timer()
	_setup_outline()


func _process(delta: float) -> void:
	if _player != null:
		_anim.flip_h = _player.global_position.x < global_position.x
		if Input.is_action_just_pressed(&"action"):
			_is_talking = not _is_talking
			_anim.play(&"talk" if _is_talking else &"idle")
			if not _is_talking:
				_reset_variation_timer()

	if _anim.animation == &"idle":
		_variation_timer -= delta
		if _variation_timer <= 0.0:
			_anim.play(&"wait")

	# 同步描边节点的帧和朝向
	if _outline_node and _outline_node.visible:
		_outline_node.animation = _anim.animation
		_outline_node.frame = _anim.frame
		_outline_node.flip_h = _anim.flip_h


func _on_animation_looped() -> void:
	if _anim.animation == &"wait":
		_anim.play(&"idle")
		_reset_variation_timer()


func _on_body_entered(body: Node2D) -> void:
	if body is not Player:
		return
	_player = body as Player
	_set_outline(true)


func _on_body_exited(body: Node2D) -> void:
	if body is not Player:
		return
	_player = null
	_set_outline(false)
	if _is_talking:
		_is_talking = false
		_anim.play(&"idle")
		_reset_variation_timer()


func _reset_variation_timer() -> void:
	_variation_timer = randf_range(idle_variation_interval.x, idle_variation_interval.y)


func _setup_outline() -> void:
	var mat := ShaderMaterial.new()
	mat.shader = load("res://Npc/shaders/npc_outline.gdshader")
	mat.set_shader_parameter(&"outline_color", outline_color)

	_outline_node = AnimatedSprite2D.new()
	_outline_node.sprite_frames = _anim.sprite_frames
	_outline_node.position = _anim.position
	_outline_node.material = mat
	# 绝对 z_index -1：渲染在 TileMapLayer（z=0）之下，tiles 会自然遮挡描边
	_outline_node.z_as_relative = false
	_outline_node.z_index = -1
	_outline_node.visible = false
	add_child(_outline_node)


func _set_outline(enabled: bool) -> void:
	if _outline_node:
		_outline_node.visible = enabled
