#!/usr/bin/env bash
# 把插件按 Godot Asset Store 要求打包：
#   zip 根目录 -> addons/<addon name>/<addon contents>
#   zip -X      -> 不生成 __MACOSX / AppleDouble 资源分支
set -euo pipefail

ADDON="sprite_frames_to_animation_player"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="$(sed -n 's/^version="\(.*\)"$/\1/p' "$ROOT/addons/$ADDON/plugin.cfg")"
OUT="$ROOT/dist/${ADDON}-v${VERSION}.zip"

mkdir -p "$ROOT/dist"
rm -f "$OUT"

cd "$ROOT"
zip -X -r -q "$OUT" "addons/$ADDON" \
  -x '*.DS_Store' '*/.DS_Store' '*__MACOSX*' '*.uid' '*/.git/*' '*/.godot/*'

# 校验：zip 里不能出现 __MACOSX / .DS_Store / .uid 文件
if unzip -Z1 "$OUT" | grep -Eq '(^|/)(__MACOSX|\.DS_Store)(/|$)|\.uid$'; then
  echo "打包失败：zip 内含有 __MACOSX、.DS_Store 或 .uid 文件" >&2
  exit 1
fi

echo "已生成: $OUT"
unzip -l "$OUT"
