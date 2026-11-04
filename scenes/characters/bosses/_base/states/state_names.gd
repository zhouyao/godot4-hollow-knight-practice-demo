class_name BossStateNames


# BOSS 状态名常量。与 EnemyStateNames 同规格：状态节点的名字必须与这里的字面量一致，
# 因为 StateMachine 是按**子节点名**索引状态的（见 StateMachine._collect_states）。
#
# 这里只保留"场景里真的有对应状态节点"的名字：常量写在这里但场景里没有节点，
# 切过去只会 push_warning 并静默停在原状态，排查成本很高。
# 加 / 删状态节点时，本文件要同步。

# ---- 流程层 ----
## 沉睡 / 待机：未开战，可能挂在锁链上或站着不动。
const DORMANT: StringName = &"dormant"
## 苏醒坠落：挣脱锁链 → 下落的一次性演出（HollowKnight 的 dormant_end 动画）。
const DORMANT_END: StringName = &"dormant_end"
## 苏醒吼叫 / 入场演出：HollowKnight 实际使用的入场节点名。
const SCREAM: StringName = &"scream"
## 入场浮现：玩家踏入领地后 BOSS 从虚无中现身（SoulMaster 使用；dormant 负责候场与复位）。
const ENTRANCE: StringName = &"entrance"
## 击败演出：播完由 death 状态收尾（掉落 / 关碰撞 / 停 BGM）。
const DEATH: StringName = &"death"

## 战斗中的决策中枢：BOSS 没有单独的 combat 节点，idle 本身就是"选下一招"的地方。
const IDLE: StringName = &"idle"

# ---- 招式层 ----
# 全部由 idle 决策选出，各自播完回 idle。
## 近身挥砍。
const SLASH: StringName = &"slash"
## 瞬移（出现在玩家身边后接 slash）。
const TELEPORT: StringName = &"teleport"
## 召唤：四魂球环绕齐射（summon_start 起手生成 → summon 循环漂移）。
const SUMMON: StringName = &"summon"
## 下砸冲击波：瞬移到玩家头顶悬停 → 高速下坠 → 落地 AoE + 左右各一道贴地冲击波。
const QUAKE: StringName = &"quake"
## 冲刺本体（相位推进在状态内部，不额外拆节点）。
const DASH: StringName = &"dash"
## 招架反击（起手 / 窗口 / 反击 / 收尾都在状态内部的相位里）。
const COUNTER: StringName = &"counter"
## 后撤步：面朝玩家、朝反方向位移。
const EVADE: StringName = &"evade"
## 逼近：小步走向玩家。
const WALK: StringName = &"walk"
## 二阶段·跳跃下砸（朝玩家头顶跃击，原地版 Desolate Dive）：状态节点名即 down_smash。
const DOWN_SMASH: StringName = &"down_smash"
## 二阶段·瞬移下杀（瞬移到玩家头顶快速下砸，Desolate Dive 瞬移版）：状态节点名即 teleport_smash。
const TELEPORT_SMASH: StringName = &"teleport_smash"
