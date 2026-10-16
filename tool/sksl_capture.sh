#!/usr/bin/env bash
# 桌面端 SkSL 预编译着色器 —— 采集脚本（必须在**目标设备**上运行）。
#
# 背景：Windows / Linux 用 Skia，首次绘制新图元时会**运行时编译**着色器，
# 表现为"动画/滚动第一帧卡一下"。SkSL bundle 把这些着色器提前编译好打包进产物，
# 从而消除这类抖动。bundle 与 GPU 驱动强相关，因此**只能**在目标机器上采集。
#
# 用法：
#   tool/sksl_capture.sh            # 采集到 sksl/warmup.sksl.json
#   git add sksl/warmup.sksl.json && git commit -m "perf: SkSL 预热包"
#   之后 CI 构建 Windows / Linux 会自动追加 --bundle-sksl-path。
#
# 注意：Android / iOS 用 Impeller，着色器在构建期 AOT 编译，**不需要**本脚本。
set -euo pipefail

OUT="${1:-sksl/warmup.sksl.json}"
mkdir -p "$(dirname "$OUT")"

echo "==> 以 profile 模式启动，动效缓存写到 $OUT"
echo "==> 启动后请把主要交互走一遍：列表滚动 / 页面切换 / 下拉刷新 / 打开设置页"
echo "==> 然后**正常退出**应用（不要 kill 进程），缓存才会落盘。"
flutter run --profile --cache-sksl --write-sksl-on-exit "$OUT"

echo "==> 完成：$OUT"
ls -lh "$OUT" 2>/dev/null || echo "（未见文件 —— 请确认是否正常退出应用）"
