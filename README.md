# godot4-hollow-knight-practice-demo

> 一个用 **Godot 4.7** 制作的 2D 横版动作练习 Demo，以《Hollow Knight（空洞骑士）》为学习参照，练习其操作手感、战斗节奏与关卡系统的实现方式。
>
> **本项目是非官方、非商业的同人练习作品，与 Team Cherry 无任何关联。** 仓库中大量美术、音频、视频、字体与文本素材取自或改编自原作游戏，请先阅读文末的「免责声明」。

## 项目简介

这是一个持续迭代中的个人练习项目，目标是「用 Godot 4 复刻一遍，从中学会怎么做」：不是完整游戏，也不是可直接发布的作品。代码为自写实现，素材主要用于还原视觉与听觉表现，便于对照原作验证手感与表现层效果。

- 引擎：Godot **4.7**，`GL Compatibility` 渲染器，1920×1080 / `canvas_items` 拉伸
- 主场景：`main.tscn`（主菜单）→ `scenes/worlds/game_root.tscn`（游戏）
- 导出产物名：`Misted`（Windows `.exe` / macOS `.dmg` 预设）

### 已实现的主要内容

| 模块 | 内容 |
| --- | --- |
| 玩家 | 状态机驱动的移动、跳跃（含二段跳「帝王之翼」）、上/前/下挥砍、冲刺、格挡、治疗、坐下、受伤击退与死亡 |
| 战斗 | 敌人基类与多种敌人行为、投射物、掉落与拾取、灵魂/能量 HUD、伤害与击退反馈 |
| 技能 | 5 槽可拖拽技能条，技能定义含能量消耗与冷却（Shader 冷却遮罩），已配置格挡 / 治疗 / 冲刺 |
| BOSS | 空洞骑士、灵魂大师两只 BOSS，含独立状态机、入场演出、雾门与竞技场行为 |
| 关卡 | 常驻根场景 + 按区域异步换关；入口点、转场门、长椅存档点、宝箱、雨区/草区/视差背景、视野剔除、相机边界与缩放区 |
| 系统 | 4 槽存档（区域 / 入口 / flags / 技能）、主菜单、存档页、暂停、设置（画面、音量、按键重绑定）、简中 / 繁中 / 英文本地化、UI 音效与音频总线 |

当前关卡示例：`moss_hole`、`moss_hole_0`、`tear_city`、`ruin_house`、`grimm_tent`、`soul_master_room`、`opening_cinematic`，以及 `levels/_dev/` 下的开发用关。

> 项目仍在开发中：NPC 系统、护符 / 法术系统尚未实现，部分关卡仅为调试示例。功能以实际代码为准，完整系统与组件索引见 `docs/level_system_guide.md`。

## 截图

以下均为项目实际运行画面（1920×1080 窗口），点击任意图片可查看原图。

<table>
  <tr>
    <td align="center" width="33%">
      <a href="screenshot/01-key-bindings.webp"><img src="screenshot/01-key-bindings.webp" width="100%" alt="按键设置"></a>
      <sub><b>按键设置</b><br>键盘 / 手柄键位重绑定</sub>
    </td>
    <td align="center" width="33%">
      <a href="screenshot/02-save-slots.webp"><img src="screenshot/02-save-slots.webp" width="100%" alt="存档选择"></a>
      <sub><b>存档选择</b><br>4 槽存档与进度摘要</sub>
    </td>
    <td align="center" width="33%">
      <a href="screenshot/03-moss-hole-treasure.webp"><img src="screenshot/03-moss-hole-treasure.webp" width="100%" alt="苔藓洞窟"></a>
      <sub><b>苔藓洞窟</b><br>草区场景、宝箱与血量提示</sub>
    </td>
  </tr>
  <tr>
    <td align="center" width="33%">
      <a href="screenshot/04-pause-menu.webp"><img src="screenshot/04-pause-menu.webp" width="100%" alt="暂停菜单"></a>
      <sub><b>暂停菜单</b><br>继续 / 保存 / 音频 / 退回主菜单</sub>
    </td>
    <td align="center" width="33%">
      <a href="screenshot/05-tears-city-rain.webp"><img src="screenshot/05-tears-city-rain.webp" width="100%" alt="泪城雨区"></a>
      <sub><b>泪城</b><br>雨区、视差背景与雕像</sub>
    </td>
    <td align="center" width="33%">
      <a href="screenshot/06-tears-city-battle.webp"><img src="screenshot/06-tears-city-battle.webp" width="100%" alt="泪城战斗"></a>
      <sub><b>雨区战斗</b><br>灵魂槽、血量与底部技能条</sub>
    </td>
  </tr>
  <tr>
    <td align="center" width="33%">
      <a href="screenshot/07-bench.webp"><img src="screenshot/07-bench.webp" width="100%" alt="长椅存档点"></a>
      <sub><b>长椅存档点</b><br>坐下回血与存档</sub>
    </td>
    <td align="center" width="33%">
      <a href="screenshot/08-grimm-tent.webp"><img src="screenshot/08-grimm-tent.webp" width="100%" alt="格里姆帐篷"></a>
      <sub><b>格里姆帐篷</b><br>剧团舞台与观众</sub>
    </td>
    <td align="center" width="33%">
      <a href="screenshot/09-hollow-knight-boss.webp"><img src="screenshot/09-hollow-knight-boss.webp" width="100%" alt="空洞骑士 BOSS 战"></a>
      <sub><b>BOSS 战</b><br>空洞骑士入场演出</sub>
    </td>
  </tr>
</table>

## 环境与运行

依赖只有 Godot 4.7 本身；`addons/` 下的插件已随仓库提供，并在 `project.godot` 中启用，无需额外安装。

1. 用 Godot 4.7 打开项目根目录的 `project.godot`（首次打开若导入异常，先执行一次 `Godot --headless --editor --quit` 刷新导入缓存）。
2. 按 **F5** 运行，进入 `main.tscn` 主菜单；选择「开始游戏」→ 新建 / 选择存档槽 → 进入游戏。
3. 在编辑器中按 **F6** 可直接运行某个 `level_*.tscn` 单关调试（会自动补玩家与相机，但不含 HUD）。

命令行快速验证场景可加载：

```bash
Godot --headless --path . res://scenes/worlds/game_root.tscn --quit-after 180
```

存档文件位于用户数据目录（macOS 示例）：`~/Library/Application Support/Godot/app_userdata/Misted/saves/slot_N.json`。

导出预设自带 Windows Desktop (`../Misted.exe`) 与 macOS (`../Misted.dmg`) 两项，需自行安装对应平台导出模板。**导出与分发受文末免责声明约束，请勿公开发布构建产物。**

## 操作

| 动作 | 键盘 | 手柄 |
| --- | --- | --- |
| 移动 / 抬头 / 低头 | `W` `A` `S` `D`（按住 `W` 攻击为上劈；空中按住 `S` 攻击为下劈） | 十字键 |
| 跳跃 | `Space` | `A` |
| 攻击 | `J` | `X` |
| 技能面板（查看 / 配置技能） | `P` | `Y` |
| 释放技能槽 1–5 | `1` `2` `3` `4` `5` | — |
| 暂停 / 返回 / 关闭 | `Esc` | — |

按键可在设置页重绑定（`Esc` / `Tab` / `Enter` 为保留键）。

## 目录结构

```
.
├── main.tscn / project.godot     入口与主场景
├── assets/                      精灵图、逐帧动画、音效、BGM、过场视频、字体、主题
├── scenes/
│   ├── characters/              玩家、敌人、BOSS 及其状态机
│   ├── worlds/                  game_root、关卡底座、区域与转场组件
│   ├── menus/ ui/ effects/      菜单、HUD、特效
│   ├── props/ drops/ projectiles/ debug/
├── globals/                     autoload 单例、设置、状态机
├── resources/                   角色 / 技能 / 掉落 / 关卡等 .tres 与 .json 数据
├── shaders/                     灵魂槽、冷却遮罩、无敌闪烁等 6 个 gdshader
├── localization/                translations.csv 与 en / zh_CN / zh_TW
├── addons/                      camera_director、environment_fx、zone_director、
│                                sprite_frames_to_animation_player、gdUnit4
├── docs/                        关卡 / 转场系统使用清单
├── screenshot/                  README 展示截图（带 .gdignore，不导入、不打进导出包）
├── reports/                     GdUnit4 历史测试报告产物
└── tools/                       插件打包辅助脚本
```

## 架构速览

`main.tscn` 进入主菜单后预加载 `game_root.tscn`；游戏运行期间 `game_root` **常驻不卸载**，切关只替换 `WorldHost` 里的 Area，玩家、HUD、技能条与相机在切关时保持连续。会话、转场黑场、存档、技能、战斗等由 12 个 autoload 单例协同。

新区域制作流程、入口 / 门 / 长椅 / 雾门 / 相机边界的配置、存档字段、调试命令与已知问题，全部记录在本项目的权威文档：

- [关卡 / 转场系统使用清单](docs/level_system_guide.md)
- 各插件自带说明：`addons/camera_director/README.md`、`addons/environment_fx/README.md`、`addons/zone_director/README.md`、`addons/sprite_frames_to_animation_player/README.md`

## 测试

项目使用随仓库提供的 [GdUnit4](https://github.com/MikeSchulze/gdUnit4) **6.2.3** 作为单元 / 集成测试框架，插件已在 `project.godot` 中启用，打开编辑器后底部会出现 **GdUnit4** 面板。

- 测试套件应放在 `res://<模块目录>/test/` 下，脚本 `extends GdUnitTestSuite`；目录名由项目设置 `gdunit4/settings/test/test_lookup_folder` 控制（默认 `test`）。
- 根目录 `/test/` 已在 `.gitignore` 中排除，**当前仓库未随附测试套件源码**；`reports/` 中保留的是历史运行产物，不代表当前可执行的用例集。
- 编辑器中运行：底部 **GdUnit4** 面板选择项目 / 目录 / 套件 → ▶；也可右键目录或脚本 → **Run Test(s)**。
- 命令行运行（CI）：

```bash
export GODOT_BIN=/Applications/Godot.app/Contents/MacOS/Godot
./addons/gdUnit4/runtest.sh -a res://scenes
```

常用参数：`-a <目录|套件>` 加入测试、`-i <套件[:用例]>` 忽略、`-c` 首次失败不中断、`-rd <目录>` 指定报告目录（默认 `res://reports/`）、`--help-advanced` 查看全部参数；Windows 使用 `runtest.cmd`。运行后在 `reports/report_<序号>/` 生成 HTML 与 JUnit XML 报告。

最小套件结构示意（实际场景与 API 以当前代码为准）：

```gdscript
class_name PlayerTest
extends GdUnitTestSuite

func test_take_damage_reduces_health() -> void:
	var player := auto_free(load("res://scenes/characters/players/player/player.tscn").instantiate())
	add_child(player)
	player.health = 100
	player.take_damage(30)
	assert_int(player.health).is_equal(70)
```

临时节点请用 `auto_free()` 释放，否则会被孤儿节点检查判为失败；断言与异步等待使用 `assert_*` / `await assert_signal(...)` 系列。

## 素材与第三方

- `assets/` 内的逐帧精灵、背景、UI 图、音效、BGM、过场视频、字体，以及角色名、地名与部分界面文案，**大部分提取或改编自《Hollow Knight》原作游戏**，仅用于本地对照与学习，权利归属见文末免责声明。
- 引擎：[Godot Engine](https://godotengine.org/)；插件：`camera_director`、`environment_fx`、`zone_director`、`sprite_frames_to_animation_player`、`gdUnit4`（其中部分插件自带 MIT 许可证，见 `addons/*/LICENSE`，各插件按其自身条款使用）。
- 仓库未附带项目级开源许可证，也未对原作素材授予任何使用许可。

---

## 免责声明 / Disclaimer

1. **性质**：本项目是非官方、非商业、仅供个人学习与技术练习使用的同人仿作 Demo，初衷是练习 Godot 4 与 2D 动作游戏的实现方式。本项目与 Team Cherry、*Hollow Knight* 系列及其发行 / 授权方**不存在任何关联**，未获得其授权、赞助、许可或认可，亦不代表官方立场。
2. **素材权利**：本仓库 `assets/` 等目录中的图片、逐帧动画、背景、UI、音效、音乐、视频、字体，以及角色名称、关卡地名、相关文本等素材，部分或全部取自、截取或改编自《Hollow Knight》原作游戏。上述素材的著作权、商标权及其他一切相关权益**均归 Team Cherry 及相应权利人所有**。本项目不对这些素材主张任何权利，也不因仓库公开而向任何人授予使用、复制或再分发的许可。
3. **使用限制**：本仓库内容及其导出构建**仅可用于个人本地学习、研究与演示**，禁止用于任何商业或盈利目的、公开分发、二次发布、素材提取再利用，或任何可能使人误认为官方作品 / 官方授权的用途。请勿将本仓库或其中的原作素材上传到其他平台、素材库或用于 AI 训练等对外用途。因使用、复制、修改、分发本仓库内容而产生的侵权及其他法律风险，由使用者自行承担。
4. **代码与许可**：除上述原作素材外，项目自写代码也未设定项目级开源许可证；如需使用、引用或二次开发，请先联系仓库维护者并取得相关权利人的授权。第三方插件各自遵循其目录中声明的许可证，不在本声明范围内。
5. **侵权处理**：若 Team Cherry 或其他权利人认为本仓库内容侵害其合法权益，请通过本仓库的 Issue 联系维护者；我们将在核实后第一时间移除相关素材、停止公开或删除仓库，并配合后续处理。给权利人带来的困扰，谨此致歉。

**English summary:** This repository is an **unofficial, non-commercial, fan-made practice demo** built with Godot 4 for personal learning only. It is **not affiliated with, endorsed by, or licensed by Team Cherry**. Many assets (sprites, animations, backgrounds, UI, audio, video, fonts, character and location names, and text) are extracted or adapted from the game *Hollow Knight*; **all copyrights, trademarks and related rights remain with Team Cherry and the respective rights holders**. No rights are claimed and no license is granted. The repository and any builds must not be used commercially, redistributed, or published as an official work; use is at your own risk. Rights holders may contact the maintainer via Issues for removal, and the relevant content will be taken down promptly.

*本声明仅为情况说明，不构成法律意见。*
