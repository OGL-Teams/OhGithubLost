#!/bin/sh
# 输入层一键构建（可复现）：音轨 / 字体子集 / 数据校验
# 用法：sh tools/build_assets.sh          # 完整构建
#       sh tools/build_assets.sh --verify # 仅校验已有产物
set -eu
cd "$(dirname "$0")/.."
for bin in ffmpeg ffprobe pyftsubset python3; do
    command -v "$bin" >/dev/null 2>&1 || { echo "缺少 $bin" >&2; exit 1; }
done
python3 -c 'import fontTools, brotli' 2>/dev/null || {
    echo '缺少 fonttools / brotli，请先: apk add py3-fonttools py3-brotli' >&2
    exit 1
}
exec python3 tools/build_assets.py "$@"
