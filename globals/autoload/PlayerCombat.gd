extends Node

## 玩家是否正处于攻击动作中（供 Boss 加权决策读取）。
## 注：本脚本只作为 autoload 单例使用，故意不加 class_name —— 否则会污染全局标识符，
## 导致静态分析器把 "PlayerCombat" 当作类类型，从而找不到实例属性 is_attacking。
##
## 由 PlayerInitial 监听自身 state_machine.state_changed 统一置位，
## 覆盖所有"进攻型"玩家状态（挥砍 / 冲刺斩 / 法术 / 蓄力…）。
## 新增攻击招式只需要在对应玩家状态里写 `is_attack = true`，
## 无需改动此处 —— 因此 Boss 侧完全不关心玩家具体是哪个攻击状态，
## 将来加多少攻击态都不用改 Boss 代码。


## 玩家此刻是否正在攻击。Boss 决策中枢（idle.gd）只读这一个布尔。
var is_attacking: bool = false
