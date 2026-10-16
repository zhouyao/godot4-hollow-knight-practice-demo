GODOT ?= /Applications/Godot.app/Contents/MacOS/Godot

.PHONY: help test import run

help:
	@echo "test    跑全部测试（单元 + 绑定集成 + 场景冒烟）"
	@echo "import  用 headless 模式重新导入资源"
	@echo "run     启动项目"

test:
	$(GODOT) --headless --path . --script res://tests/test_settings.gd
	$(GODOT) --headless --path . --scene res://tests/test_bindings.tscn --quit-after 120
	$(GODOT) --headless --path . --scene res://tests/smoke.tscn --quit-after 60

import:
	$(GODOT) --headless --path . --import

run:
	$(GODOT) --path .
