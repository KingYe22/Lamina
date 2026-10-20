#!/bin/bash
# 清除隔离标记并打开 Lamina。优先打开「应用程序」里的副本。
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
if [[ -d "/Applications/Lamina.app" ]]; then
  TARGET="/Applications/Lamina.app"
elif [[ -d "$HERE/Lamina.app" ]]; then
  TARGET="$HERE/Lamina.app"
else
  echo "找不到 Lamina.app。请先把 Lamina.app 拖进「应用程序」文件夹，再双击本文件。"
  exit 1
fi
xattr -cr "$TARGET"
open "$TARGET"
