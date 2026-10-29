# Misted / 雾隐

2D 横版动作 Demo（Godot 4.7）。

## 测试

本项目使用 [GdUnit4](https://github.com/MikeSchulze/gdUnit4)（版本 `6.2.2`，已随仓库放在 `addons/gdUnit4`）作为单元/集成测试框架。

### 启用状态

插件已在 `project.godot` 中启用：

```ini
[editor_plugins]
enabled=PackedStringArray("res://addons/camera_director/plugin.cfg", ..., "res://addons/gdUnit4/plugin.cfg", ...)
```

无需额外安装，打开编辑器后底部会出现 **GdUnit4** 面板。

### 测试文件放哪里

- 由 `项目设置 → gdunit4/settings/test/test_lookup_folder` 控制，默认是 `test`。
- 也就是说测试套件应放在 `res://<模块目录>/test/` 下，例如 `res://scenes/characters/players/test/`。
- 测试套件脚本必须 `extends GdUnitTestSuite`。

### 在编辑器中运行

1. 底部面板切换到 **GdUnit4** 标签页。
2. 在 Inspector 树中选择整个项目、某个目录或单个套件/用例。
3. 点击 ▶ 运行；也支持右键 `res://` 目录/脚本 → **Run Test(s)**，或在脚本编辑器中选中函数名 → **Create Test** 自动生成套件。

常用设置（`项目设置 → gdunit4`）：

| 设置 | 说明 | 默认值 |
| --- | --- | --- |
| `settings/test/test_lookup_folder` | 测试目录名 | `test` |
| `settings/test/test_timeout_seconds` | 单用例超时 | 300 |
| `settings/report/godot/script_error` | 脚本报错记为失败 | 开 |
| `settings/report/verbose_orphans` | 检测孤儿节点 | 开 |
| `settings/test/flaky_check_enable` | 失败重跑并标记 FLAKY | 关 |

### 命令行运行（CI）

使用插件自带的 `runtest.sh`，先指定 Godot 可执行文件：

```bash
export GODOT_BIN=/Applications/Godot.app/Contents/MacOS/Godot
./addons/gdUnit4/runtest.sh -a res://scenes
```

或用参数形式：`./addons/gdUnit4/runtest.sh --godot_binary /Applications/Godot.app/Contents/MacOS/Godot -a res://`。

常用参数：

| 参数 | 说明 |
| --- | --- |
| `-a <目录\|套件路径>` | 加入要执行的测试（可多次指定） |
| `-i <套件名\|套件名:用例名>` | 加入忽略列表 |
| `-c` | 首次失败不中断，跑完整个测试集 |
| `-conf <file>` | 使用指定测试配置，默认 `GdUnitRunner.cfg` |
| `-rd <目录>` | 报告输出目录，默认 `res://reports/` |
| `-rc <数量>` | 保留的历史报告数量，默认 20 |
| `--info` / `--help` / `--help-advanced` | 版本信息 / 帮助 |

Windows 下用 `addons/gdUnit4/runtest.cmd`。

### 报告

执行后会在 `res://reports/report_<序号>/` 生成 HTML 与 JUnit XML 报告，打开其中的 `index.html` 即可查看结果；仓库根目录下的 `reports/` 即为这些产物。

### 编写测试示例

```gdscript
# res://scenes/characters/players/test/player_test.gd
class_name PlayerTest
extends GdUnitTestSuite

const __source := "res://scenes/characters/players/player.gd"

func before_test() -> void:
	pass

func after_test() -> void:
	pass

func test_take_damage_reduces_health() -> void:
	var player := auto_free(load(__source).new())
	add_child(player)
	player.health = 100
	player.take_damage(30)
	assert_int(player.health).is_equal(70)

func test_attack_emits_signal() -> void:
	var player := auto_free(load(__source).new())
	add_child(player)
	player.attack()
	# 等待信号发出，默认超时 2000ms，可用 wait_until(500) 自定义
	await assert_signal(player).is_emitted("attacked")
```

注意点：

- 用 `auto_free()` / 手动 `free()` 释放临时节点，否则会被孤儿节点检查报告为失败。
- 断言：`assert_int` / `assert_float` / `assert_str` / `assert_bool` / `assert_array` / `assert_object` / `assert_signal` / `assert_file`。
- 生命周期钩子：`before()` / `after()`（套件级）、`before_test()` / `after_test()`（用例级）。
- 需要跳帧时用 `await await_idle_frame()`；`await assert_signal(...).is_emitted(...)` 会等待信号发出（默认超时 2000ms，可用 `wait_until(500)` 调整）。
