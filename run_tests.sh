#!/usr/bin/env bash
# 一键跑全部测试。Godot 可执行文件可用 GODOT 环境变量覆盖，例如：
#   GODOT=$(which godot) ./run_tests.sh
set -uo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GODOT_BIN="${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}"

if ! command -v "$GODOT_BIN" >/dev/null 2>&1; then
	echo "找不到 Godot：${GODOT_BIN}"
	echo "请安装 Godot 4 或用 GODOT=/path/to/godot 指定。" >&2
	exit 2
fi

cd "$PROJECT_DIR"

status=0
run() {
	local name="$1"; shift
	echo "── ${name}"
	if "$GODOT_BIN" --headless --path . "$@"; then
		echo "   ✅ 通过"
	else
		echo "   ❌ 失败"
		status=1
	fi
}

# 纯函数单测可以脱离场景树跑
run "Settings 单元测试" --script res://tests/test_settings.gd
# 下面两个依赖 autoload，必须走 --scene
run "按键绑定集成测试" --scene res://tests/test_bindings.tscn --quit-after 120
run "场景冒烟测试" --scene res://tests/smoke.tscn --quit-after 60

exit "$status"
