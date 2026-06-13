#!/bin/env bash
# ============================================================
# milk-word-counter 测试启动器
# 用法: bash test/run_tests.sh [--wait]
# ============================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
TEST_BASE=$(mktemp -d "/tmp/wc_test_XXXXXX")

export XDG_CONFIG_HOME="$TEST_BASE"

echo "[test] XDG_CONFIG_HOME=$XDG_CONFIG_HOME"
echo "[test] 运行测试..."
echo ""

cd "$PROJECT_DIR"

# 优化 1：使用 || true 绕过 set -e，确保测试失败时脚本不会直接崩溃
lua5.3 "$SCRIPT_DIR/test_word_counter.lua" && RET=0 || RET=$?

echo ""
if [[ " $* " =~ " --wait " ]]; then
    echo "[test] 测试已结束，状态码为: $RET"
    echo ""
    read -n 1 -s -r -p "按任意键继续..."
    echo ""
fi

# 清理临时文件
rm -rf "$TEST_BASE"

# 返回测试的实际结果
exit $RET