# Misted / 雾隐

Godot 4.7.2 的 2D 演示项目，当前实现的是**菜单系统**：主菜单与系统设置（按键重绑定 + 音量 + 语言）。

## 运行

```bash
# 需要 Godot 4.7（GL Compatibility 渲染器）
godot --path .          # 或双击 project.godot 用编辑器打开
make run
```

首次用编辑器打开时会自动导入资源；命令行下可执行：

```bash
make import   # godot --headless --path . --import
```

## 测试

```bash
make test     # 或 ./run_tests.sh
```

也可以用 `GODOT=/path/to/godot ./run_tests.sh` 指定引擎可执行文件。三组测试：

| 测试 | 运行方式 | 覆盖内容 |
|------|----------|----------|
| `tests/test_settings.gd` | `--script` | Settings 的纯函数：事件清洗、按键比较、显示名换算 |
| `tests/test_bindings.gd` | `--scene` | 需要 InputMap / autoload 的部分：绑定冲突、保留键、音量边界、滑条步进 |
| `tests/smoke.gd` | `--scene` | 全部场景能否入树完成 `_ready`，关键节点是否挂对了脚本 |

`--script` 模式不会注册 autoload，凡是用到 `Settings` / `UiAudio` 的测试都必须走 `--scene`。

## 目录

```
globals/                工具与 autoload
  Globals.gd            autoload：场景路径与切换入口，场景之间互不 preload
  Settings.gd           autoload：音量 + 按键绑定 + 语言的读写、冲突处理、落盘
  UiAudio.gd            autoload：共享的 UI 音效播放器
  Tr.gd                 给场景树套用当前语言的工具（非 autoload）
scenes/menus/           主菜单 / 系统设置
scenes/menus/components/ 可复用控件
  buttons/                FocusButton、ResetButton
  rows/                   MenuRow 及音量行、按键行
assets/ui/              MistedTheme：字号与颜色的唯一来源
localization/           translations.csv -> .translation
tests/                  单元测试与冒烟测试
```

## 设计要点

- **音量**：`Settings.VOLUME_STEP` 是唯一的步进定义，滑条的 `step` 在 `_ready()` 里由它推导。音量改动任何时候都是先改内存与音频总线，再由一次"提交"负责写盘与播放预览音。鼠标拖动会发 `drag_ended`，松手即提交；方向键 / 手柄没有结束事件，靠 `Settings.COMMIT_DEBOUNCE` 的静止判定自动补一次提交。无论哪条路径，退出前都由 `Settings.flush()` 兜底（`Globals.quit_game()` 与 root 的 `close_requested` 各接一处），保证 debounce 窗口里的改动不会被丢掉。
- **按键绑定**：修改后立即写入 `InputMap`；`Esc` / `Tab` / `Enter` 与手柄 `B` / `Start` 是保留输入，不允许绑定——键盘侧对应 `ui_accept` / `ui_cancel`，手柄侧的 B 就是每个菜单的取消键，绑走之后玩家按跳跃键会直接退出菜单，等于把自己锁住。保留名单只留这两颗，再多（例如作为确认键的 A）会让跳跃、攻击没法绑。名单本身变了也不怕：`Settings.purge_reserved_bindings()` 会在启动时把旧存档里已经绑上的保留输入换回默认。抢占别人的按键时会给出提示，并给对方补回默认键。
- **菜单导航**：`Esc` / 手柄 B 为取消（先退出按键监听，再返回主菜单）。按钮按下立即响应；确认音由 autoload 播放，切场景不会被掐断。
- **语言**：可切换的语言写在 `Settings.LOCALE_OPTIONS`，设置菜单「语言」页的下拉框由它生成，加一门语言只改这一处（外加 `translations.csv` 补一列）。首次进入跟随系统语言，之后以存档为准；切换后立即生效并落盘，菜单靠 `Settings.locale_changed` 重刷文案，不重载场景。选项文字用语言自己的写法（简体中文 / English），不跟随当前语言翻译。
- **外观**：字号与颜色集中在 `assets/ui/MistedTheme.gd`，场景通过 `theme_type_variation` 取用 `DisplayLabel` / `TitleLabel` / `MutedLabel` / `HintLabel` / `RowButton` 五种变体。`OptionButton` 默认会继承 `Button` 的 80 号字，行内使用时必须挂 `RowButton` 变体。
- **文案**：翻译表在 `localization/translations.csv`，新增文案记得补一行。注意 Godot 4.7 实测**不会**对 `.tscn` 里写死的 `text` 自动翻译，所以菜单场景在 `_ready()` 末尾统一调一次 `Tr.apply(self)`。语言可以来回切，`Tr` 会把场景里的原始文案（也就是翻译表的 key）记在节点的 meta 上，每次都从 key 重新翻译。

## 待办

- 主玩法场景尚未创建，主菜单「开始」暂时只在控制台打一条 warning，接入后改成 `Globals.go_to_game()`。
