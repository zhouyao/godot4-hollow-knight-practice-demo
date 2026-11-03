class_name BossStateNames


# BOSS 状态名常量。与 EnemyStateNames 同规格：状态节点的名字必须与这里的字面量一致，
# 因为 StateMachine 是按**子节点名**索引状态的（见 StateMachine._collect_states）。

# ---- 流程层 ----
# 战斗的主干：沉睡 → 入场 → 出招 → （阶段切换）→ 击败。
## 沉睡 / 待机：未开战，可能挂在锁链上或站着不动。
const DORMANT: StringName = &"dormant"
## 苏醒坠落：四根 BossChain 被砍断后的"挣脱锁链 → 下落"一次性演出，
## 对应 HollowKnight ActionAnimationPlayer 的 dormant_end 动画（第 9 帧起施加重力）。纯演出，落地即停。
const DORMANT_END: StringName = &"dormant_end"
## 入场演出：挣脱锁链、苏醒、从天而降等一次性表演。
const INTRO: StringName = &"intro"
## 苏醒吼叫：HollowKnight 实际使用的入场演出节点名（与 INTRO 同义，历史命名）。
const SCREAM: StringName = &"scream"
## 出招枢纽：唯一负责"选下一招"的状态，选完立刻切到对应招式状态。
const COMBAT: StringName = &"combat"
## 阶段切换：血量跨阈值时插入的过场（吼叫、变身、换配色）。
const PHASE_TRANSITION: StringName = &"phase_transition"
## 击败：死亡演出，播完竞技场解锁。
const DEFEAT: StringName = &"defeat"
## 击败演出（HollowKnight 等把 defeat 演出节点直接命名为 death，复用敌人/玩家的 death 命名惯例）。
const DEATH: StringName = &"death"

const IDLE: StringName = &"idle"

# ---- 招式层 ----
# 全部由 combat 选出，各自播完回到 combat（或先经 recover 再回）。
## 三连斩。
const SLASH: StringName = &"slash"
## 收招硬直：多数招式的共同出口，用来给玩家反击窗口。
const RECOVER: StringName = &"recover"
## 瞬移。
const TELEPORT: StringName = &"teleport"
## 冲刺起手。
const DASH_ANTIC: StringName = &"dash_antic"
## 冲刺本体（按累计位移收尾，不按时长）。
const DASH: StringName = &"dash"
## 冲刺收尾硬直。
const DASH_RECOVER: StringName = &"dash_recover"
## 反击架势：挨打就转 riposte。
const COUNTER: StringName = &"counter"
## 反击：架势期间被击中后的回击。
const RIPOSTE: StringName = &"riposte"
## 跳跃起手。
const JUMP_ANTIC: StringName = &"jump_antic"
## 跳跃本体（抛物线由初速与重力推算）。
const JUMP: StringName = &"jump"
## 后撤步：面朝玩家、朝反方向位移。
const EVADE: StringName = &"evade"
## 逼近：小步走向玩家。
const WALK: StringName = &"walk"
## 下砸起跳（原地版）。
const DSTAB_JUMP: StringName = &"dstab_jump"
## 下砸瞬移（凌空版）。
const DSTAB_TELEPORT: StringName = &"dstab_teleport"
## 下砸悬停前摇。
const DSTAB_ANTIC: StringName = &"dstab_antic"
## 下砸下落。
const DSTAB: StringName = &"dstab"
## 下砸落地。
const DSTAB_LAND: StringName = &"dstab_land"

## 二阶段·跳跃下砸（朝玩家头顶跃击，原地版 Desolate Dive）：状态节点名即 down_smash。
const DOWN_SMASH: StringName = &"down_smash"

## 二阶段·瞬移下杀（瞬移到玩家头顶快速下砸，Desolate Dive 瞬移版）：状态节点名即 teleport_smash。
const TELEPORT_SMASH: StringName = &"teleport_smash"
