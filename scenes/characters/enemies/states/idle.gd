extends EnemyState

## 基类占位状态：只负责站住（重力 + move_and_slide），不含任何 AI 过渡。
## 子类的巡逻 / 追击逻辑应该在自己的场景里替换掉本状态，
## 或新增 patrol 状态并把 target_move 之类指向它。

func enter(_from: StringName) -> void:
	_play_action(EnemyStateNames.IDLE)

## 站着不动，但每帧要把水平速度清掉：否则从 patrol 切过来时会带着残余速度继续滑行
func update(delta: float) -> void:
	enemy.velocity.x = 0.0
	super.update(delta)

func get_transition(_delta: float) -> StringName:
	return &""
