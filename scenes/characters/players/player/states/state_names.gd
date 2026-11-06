class_name PlayerStateNames


const IDLE: StringName = &"idle"
const LOOK_UP: StringName = &"look_up"
const LOOK_DOWN: StringName = &"look_down"
const WALK: StringName = &"walk"
const JUMP: StringName = &"jump"
## 帝王之翼：空中振翅（二段跳），上升段专用状态。
const DOUBLE_JUMP: StringName = &"double_jump"
const FALL: StringName = &"fall"
const LAND: StringName = &"land"
const SLASH_FORWARD: StringName = &"slash_forward"
const SLASH_DOWN: StringName = &"slash_down"
const SLASH_UP: StringName = &"slash_up"
const DASH: StringName = &"dash"
## 空中冲刺动画：与 dash 同帧数但姿势不同，空中触发 dash 时播它。
const DASH_AIR: StringName = &"dash_air"
const HURT: StringName = &"hurt"
const DEATH: StringName = &"death"
const FREEZE: StringName = &"freeze"
const BLOCK: StringName = &"block"
const CURE: StringName = &"cure"
## 坐下（长椅 / 椅子）：坐下期间回血回能，按方向键即可起身。
const SIT: StringName = &"sit"
