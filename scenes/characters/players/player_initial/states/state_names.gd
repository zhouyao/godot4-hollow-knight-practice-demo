## 玩家状态名常量：状态之间的迁移目标不要写字面量，统一引用这里，
## 重命名 / 拼错时能被编译器或查找引用发现，而不是运行时静默失效。
class_name PlayerStateNames

const IDLE: StringName = &"idle"
const WALK: StringName = &"walk"
const JUMP: StringName = &"jump"
const FALL: StringName = &"fall"
const LAND: StringName = &"land"
const DEATH: StringName = &"death"
