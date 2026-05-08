class_name SpawnPoint extends Marker2D

## 关卡落点标记。关卡切换时 LevelManager 按 spawn_id 找到此节点，
## 将新 Player 传送到这里并应用 spawn_facing。

@export var spawn_id: StringName = &"default"
## 落地朝向：0=保留来源关卡的朝向快照；1=向左；2=向右
@export_enum("保留", "向左", "向右") var spawn_facing: int = 0


func _ready() -> void:
	add_to_group("spawn_points")
