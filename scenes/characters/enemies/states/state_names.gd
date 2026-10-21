## 敌人状态名常量。写状态过渡时统一用这里的常量，别写裸字符串。
class_name EnemyStateNames

# ---- 基类自带的状态 ----
const IDLE: StringName = &"idle"
const DEATH: StringName = &"death"

# ---- 以下留给子类实现，基类不含这些状态节点 ----
# 常量先给好，子类在自己的场景里加同名状态节点即可直接用。
const PATROL: StringName = &"patrol"
const CHASE: StringName = &"chase"
const ATTACK: StringName = &"attack"
const HURT: StringName = &"hurt"
