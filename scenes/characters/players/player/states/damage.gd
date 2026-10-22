extends PlayerState

## 受击状态：播放 Audio/damage + ActionAnimationPlayer/damage，期间锁输入，
## 位移完全交给受击击退（见 PlayerInitial._apply_damage_knockback）。
##
## 击退方向由伤害来源位置决定（away = 玩家 - 来源）：
##   来源在左 → 往右弹开；来源在右 → 往左弹开；
##   来源在下方 → 附加向上弹力；来源在上方 → 附加向下弹力。

## 受击硬直时长（秒）。<= 0 表示跟随玩家的 invincible_time（默认）。
## 设计上硬直与无敌帧本就该等长：硬直结束即恢复可控，不会出现"能动但还是无敌"
## 或"无敌结束了还被锁着"的割裂感。所以默认不再硬编码 0.3，而是跟随 invincible_time，
## 调手感只改 player.invincible_time 一处即可；确有需要才在这里显式覆盖。
@export var hold_time: float = 0.0

## 硬直结束且已落地后的去向（可在检查器改指向 land 等）
@export var target_grounded: StringName = PlayerStateNames.IDLE

## 实际硬直时长：未显式指定时取 player.invincible_time
func _get_hold_time() -> float:
	if hold_time > 0.0:
		return hold_time
	return player.invincible_time if player != null else 0.0

func enter(_from: StringName) -> void:
	_play_audio(PlayerStateNames.DAMAGE)
	# 把 damage 动画等比拉伸 / 压缩到硬直时长，动画资源不必跟着 invincible_time 重做
	_play_action_for(PlayerStateNames.DAMAGE, _get_hold_time())
	# 挥砍被打断时判定区与刀光可能停在开启 / 可见状态，硬直期间强制收尾。
	# （攻击状态自己的 exit() 也会收一次，这里是双保险，覆盖外部直接 set_state 的情况）
	player.end_attack()
	# 清掉输入驱动的水平残留速度，让水平位移完全由击退接管
	player.velocity.x = 0.0

## 受击期间锁输入：跳过基类的 _handle_move_input()——它每帧把 velocity.x 覆写成
## direction * speed，会把击退冲掉。这里改为由 knockback 的衰减驱动水平速度，
## 于是"猛地弹开 → 迅速收住"，且硬直结束时水平速度已归零，不会带着残余惯性滑走。
## 垂直不接管：向上 / 向下的弹力在受击瞬间写入 velocity.y，之后交给重力走弧线。
func update(delta: float) -> void:
	player.velocity.x = player.knockback.x
	player._apply_gravity(delta)
	player._apply_movement()

func handle_input(_event: InputEvent) -> void:
	pass

func get_transition(_delta: float) -> StringName:
	if elapsed <= _get_hold_time():
		return &""
	return airborne_transition() if not player.is_on_floor() else target_grounded
