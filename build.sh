#!/bin/bash
# 构建 Linux 最小化二进制（默认 amd64，可通过 GOARCH 覆盖）
#
# 用法: bash build.sh
#      GOARCH=arm64 bash build.sh
# 输出: build/icloud-hme

set -e

OUTPUT_DIR="build"
BINARY_NAME="icloud-hme"
TARGET_ARCH="${GOARCH:-amd64}"

echo "==> 清理旧的构建文件"
rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"

echo "==> 构建 Linux ${TARGET_ARCH} 最小化二进制"
CGO_ENABLED=0 GOOS=linux GOARCH="${TARGET_ARCH}" \
  go build -trimpath \
    -ldflags="-s -w -buildid=" \
    -gcflags="-l=4" \
    -o "$OUTPUT_DIR/$BINARY_NAME" \
    .

echo "==> 压缩二进制 (upx)"
if command -v upx >/dev/null 2>&1; then
  upx --best --lzma "$OUTPUT_DIR/$BINARY_NAME" || true
else
  echo "    (upx 未安装,跳过压缩)"
fi

echo ""
echo "==> 构建完成"
echo "    文件: $OUTPUT_DIR/$BINARY_NAME"
ls -lh "$OUTPUT_DIR/$BINARY_NAME"
