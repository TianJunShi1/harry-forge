# Harry Forge — 代码库说明

Godot 4.6 2D 平台跳跃游戏，像素风格，银河恶魔城玩法。
分辨率：480×270（SubViewport 内部渲染，窗口以最大整数倍缩放显示）。

## 渲染架构

```
main.tscn  ← 真正的主场景入口（project.godot 的 run/main_scene）
└─ PixelRenderer (Node2D)           general/camera/pixel_renderer.tscn
   ├─ SubViewport (481×271)         游戏内容在此渲染，尺寸 = game_size + 1px slack
   │  └─ playground.tscn / 关卡     PixelRenderer.level 赋值，不再是 main_scene
   │     ├─ GameCamera2D            关卡摄像机（整数像素对齐）
   │     ├─ TileMapLayer / 地图
   │     └─ Player
   └─ DisplaySprite (Sprite2D)      SubViewport 贴图，以当前整数倍缩放居中显示
```

PixelRenderer 在每帧从 GameCamera 读取 `subpixel_offset`，对 DisplaySprite 反向平移，
恢复亚像素平滑感（消除像素抖动/shimmer）。

## 目录结构

```
Player/          玩家角色：状态机 + 物理
  Scripts/       player.gd（主脚本）
  States/        Idle / Run / Jump / Fall / Crouch
  Sprites/       帧动画素材
Interactable/    可交互物体
  BouncePad/     弹跳板
Level/           地图场景
  00_chapter1/   第 0 章第 1 幕
  tileset/       图块集
general/         通用工具
  camera/
    pixel_renderer.tscn  像素完美渲染容器场景
  game_camera.tscn       关卡摄像机场景（放在关卡根节点）
  camera_bounds.tscn     摄像机区域预制体（CameraZone）
  scripts/
    pixel_renderer.gd    PixelRenderer 脚本（自动整数倍缩放）
    game_camera.gd       GameCamera2D 脚本
    camera_bounds.gd     CameraZone 脚本
icon/            编辑器图标
main.tscn        主场景入口（含 PixelRenderer）
playground.tscn  测试关卡（PixelRenderer.level 引用，不再是 main_scene）
```

## 玩家状态机

`Player` 持有所有共享参数（速度、重力、土狼时间等），状态只负责自己的逻辑。

状态切换方式：`physics_process` / `process` / `handle_input` 返回目标 `Playerstate` 即切换，返回 `null` 保持当前状态。

| 文件 | 状态 |
|------|------|
| Idle.gd | 待机 |
| Run.gd | 跑动 |
| Jump.gd | 跳跃 |
| Fall.gd | 下落（土狼时间 + 跳跃缓冲） |
| Crouch.gd | 下蹲（单向平台穿透） |

## 摄像机系统

### 核心原则

- **Camera 不属于 Player**。`Camera2D` 放在关卡场景根节点（实例化 `general/game_camera.tscn`）。
- **Player 不知道 Camera 的存在**，Camera 主动去找 Player（`"player"` 组）。
- 区域进入/退出由 `CameraZone`（`general/camera_bounds.tscn`）负责通知 Camera。
- **平滑频率**：Camera 的 `_smoothed_position` 更新跑在 `_physics_process` 内，与 Player `move_and_slide` 同频（60Hz）；这样高刷屏上不会出现相机用 display rate 追物理阶梯函数产生的 60Hz 节拍微抖。PixelRenderer 仍在 `_process` 读取 `subpixel_offset` 做屏幕级补偿，offset 在两个物理 tick 之间保持常数。
- **Zoom 频率**：`displayed_zoom` 插值跑在 `_process`（display rate）。Zoom 与 physics 解耦，display rate 更新让缩放动画在高刷屏上完全平滑。
- **Zoom 渲染架构（蔚蓝式）**：`Camera2D.zoom` **永远保持 Vector2.ONE**，缩放不在 SubViewport 内部做。`displayed_zoom` 仅作为数值由 PixelRenderer 读取，应用到 `DisplaySprite.scale = _current_scale × displayed_zoom`。
  - 内层 SubViewport 始终 1:1 渲染，绝对 pixel-perfect、无 shimmer
  - 外层 DisplaySprite 用 NEAREST 在物理像素上做缩放：整数 zoom（2.0/3.0）每个像素完美整数倍；非整数 zoom（1.3）有的物理像素 3px 宽有的 4px 宽，但**每个像素仍绝对锐利**（蔚蓝的"sharp non-integer zoom"效果）
  - `subpixel_offset` 补偿公式：`offset × _current_scale × zoom_factor`（effective_scale 物理像素）
  - 注意：本架构下 zoom < 1 表现为"显示缩小+黑边"，不再是"看到更多世界"。"看更多"需用其他机制（如调整 SubViewport 大小，未实现）

### 使用步骤

1. 在关卡根节点实例化 `res://general/game_camera.tscn`。
   - 或直接 Camera 加入 `"game_camera"` 组。
   - Camera 自动寻找 `"player"` 组第一个节点，无需手动指定。
2. 摆放 `res://general/camera_bounds.tscn` 划定房间边界。

### GameCamera2D 参数速查

| 参数 | 默认 | 说明 |
|------|------|------|
| `follow_smoothing` | 4.0 | 跟随平滑度（越大越快，典型 2~8） |
| `look_ahead_distance` | 24 px | 朝移动方向偏移的距离 |
| `look_ahead_turn_speed` | 3.0 | 转向时前视生效速度 |
| `look_ahead_return_speed` | 1.2 | 停止移动后前视回中速度 |
| `bounds_softness` | 60 px | 软边界宽度（0=硬边界） |
| `default_zoom` | (1,1) | 无区域覆盖时的缩放 |
| `zoom_smoothing` | 3.0 | Zoom 过渡平滑度 |
| `look_y_enabled` | true | 是否启用视线偏移（W/S 静止时上下看） |
| `look_y_distance` | 48 px | 上/下观察最大位移 |
| `look_y_engage_speed` | 1.5 | 按键后偏移建立速度 |
| `look_y_return_speed` | 3.0 | 松键后回中速度 |
| `draw_debug` | false | 调试时显示边界和聚焦点 |

### CameraZone 参数速查

| 参数 | 说明 |
|------|------|
| `mode` | FOLLOW（跟随）/ LOCK_TO_CENTER（隐藏房间锁定） |
| `bounds_source` | AUTO_FROM_COLLISION（用 CollisionShape2D）/ CUSTOM_FROM_MARKER（用 BoundsCenter Marker2D） |
| `custom_bounds_size` | 仅 CUSTOM_FROM_MARKER 时生效，摄像机边界大小 |
| `zoom_override` | 进入此区域时切换的 zoom（Vector2.ZERO = 沿用默认） |
| `hidden_room_zoom` | 隐藏房间专用 zoom 标量（仅 LOCK_TO_CENTER 生效；蔚蓝式外层缩放，任意值都锐利无 LINEAR 模糊） |
| `zone_priority` | 区域优先级，嵌套时高优先级覆盖低优先级 |
| `transition_duration` | 过渡时长（秒） |

### 隐藏房间配置示例

```
CameraZone (Area2D)
  mode = LOCK_TO_CENTER
  bounds_source = CUSTOM_FROM_MARKER
  custom_bounds_size = Vector2(256, 180)  ← 这个房间的边界大小
  hidden_room_zoom = 2.0                  ← 进入时镜头放大 2x；整数值才能保持 pixel-perfect
  zone_priority = 10                      ← 高于外层普通区域
  transition_duration = 0.6
  CollisionShape2D   ← 做大一些，提前触发
  BoundsCenter (Marker2D) ← 放在房间中心
```

### 剧情/POI 聚焦点（代码调用）

```gdscript
# 让镜头在玩家和目标物体之间混合（weight=1 各占 50%）
camera.add_focus_point(poi.get_instance_id(), poi.global_position, 1.0, 0.5)

# 聚焦点在移动时更新位置
camera.update_focus_point(poi.get_instance_id(), poi.global_position)

# 淡出并移除
camera.remove_focus_point(poi.get_instance_id(), 0.5)
```

### 不同场景 Zoom

在 `CameraZone` 的 `zoom_override` 设置目标 zoom，Camera 会在过渡时长内丝滑插值。
注意：Godot 4 的 `Camera2D.zoom > 1` 是**放大**（看到更少），`< 1` 是**缩小**（看到更多）。

### 玩家复活 / 瞬移

```gdscript
# 瞬移后跳过平滑，防止镜头从旧位置慢慢追过来
camera.snap_to_target()
```

## 关卡切换

`PixelRenderer` 是**唯一**的关卡装载入口；外部代码不应直接向 `SubViewport` add_child。

```gdscript
# 切换关卡
pixel_renderer.load_level(load("res://Level/00_chapter1/01.tscn"))

# 卸载当前关卡（黑屏）
pixel_renderer.unload_level()

# 取当前关卡引用（可为 null）
var lvl := pixel_renderer.get_current_level()
```

切换后 PixelRenderer 会重新在新关卡子树里查找 `game_camera` 组里的 GameCamera2D。
GameCamera 同样用 `node_added` signal 监听 `"player"` 组节点加入树（不再每帧轮询），
玩家也可以晚于关卡实例化加入。

> **注意**：玩家跨关卡持久化（保留血量、物品等）当前**未实现**。
> 未来如果需要，建议把 Player 提到 SubViewport 的直接子节点，或引入 SaveManager autoload。

## 物理层

| 层 | 名称 |
|----|------|
| 1 | Player |
| 2 | Ground |
| 3 | OneWayPlatform |
| 4 | BouncePad |

## 关卡切换系统

`LevelManager`（autoload）是切换关卡的**唯一入口**。`LevelTransition` 触发器位于关卡内，`SpawnPoint` 标识落点。

### 架构

```
main.tscn
├─ PixelRenderer              [现有]
│  └─ SubViewport → <当前关卡>
└─ TransitionLayer (CanvasLayer, layer=100)
   └─ FadeRect (ColorRect, 全屏黑, alpha 由 LevelManager tween)

Autoload:
  LevelManager  fade / load_level / spawn / snap_camera / grace 期编排
  GameState     跨场景持久数据（flags / clues / inventory）
```

### 使用步骤

1. 在**源关卡**里实例化 `res://general/level_transition/Level_transition.tscn`，设置：
   - `target_level`: 目标 `.tscn`
   - `target_spawn_id`: 目标关卡中 SpawnPoint 的 `spawn_id`
2. 在**目标关卡**里实例化 `res://general/level_transition/spawn_point.tscn`，设置：
   - `spawn_id`: 与源触发器的 `target_spawn_id` 对应
   - `spawn_facing`: 落地朝向（0=保留 / 1=向左 / 2=向右）

### 代码触发（剧情序列用）

```gdscript
LevelManager.transition_to(load("res://Level/01_chapter2/02.tscn"), &"from_event")
```

### 跨场景持久数据

```gdscript
GameState.set_flag(&"unlocked_door_a", true)
GameState.collect_clue(&"clue_torn_letter")
if GameState.has_clue(&"clue_torn_letter"):
    ...
```

### 容错与 grace 期

- `LevelTransition` 在 grace 期（默认 0.3 s）内不触发，避免落点 bounce-back
- `spawn_id` 找不到会退回第一个 `SpawnPoint` + push_warning；都没有则玩家留在编辑器默认位置
- `target_level == null` 时 `LevelTransition` 拒触发 + push_warning

### SpawnPoint 参数

| 参数 | 说明 |
|------|------|
| `spawn_id` | 标识符（与 `LevelTransition.target_spawn_id` 对应） |
| `spawn_facing` | 0=保留朝向，1=向左（flip_h=true），2=向右（flip_h=false） |

### LevelTransition 参数

| 参数 | 说明 |
|------|------|
| `target_level` | 目标关卡 PackedScene |
| `target_spawn_id` | 目标关卡里 SpawnPoint 的 spawn_id |
| `ignore_grace` | true=即使在 grace 期内也触发（慎用） |

## 代码约定

- **注释语言**：中文（解释 WHY，不解释 WHAT）
- **命名**：snake_case 变量/函数，PascalCase 类名
- **状态切换**：状态函数返回目标状态节点，返回 `null` 保持当前
- **摄像机分离**：Player 不持有 Camera 引用；Camera 通过组自动发现 Player
- **安全调用**：跨帧状态切换用 `call_deferred`（如 `apply_bounce`）
