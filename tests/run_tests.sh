#!/usr/bin/env bash
# CCM 测试总入口：聚合 provider 测试与安装测试
# 运行：bash tests/run_tests.sh
set -u

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$TESTS_DIR/.." && pwd)"

TOTAL_RC=0

echo "================================================================"
echo " CCM 测试套件"
echo "================================================================"

# 语法静态检查（所有 shell 入口）
echo "==> bash -n 静态语法检查"
for f in ccm.sh ccm ccc install.sh uninstall.sh quick-install.sh; do
    if bash -n "$REPO_ROOT/$f" 2>/tmp/ccm_syntax_err; then
        echo "    ✅ $f"
    else
        echo "    ❌ $f: $(head -1 /tmp/ccm_syntax_err)"
        TOTAL_RC=1
    fi
done

# 测试套件
for suite in test_providers.sh test_install.sh; do
    echo ""
    echo "================================================================"
    bash "$TESTS_DIR/$suite" || TOTAL_RC=1
done

echo ""
echo "================================================================"
if [[ "$TOTAL_RC" -eq 0 ]]; then
    echo " ✅ 全部测试通过"
else
    echo " ❌ 存在失败用例"
fi
echo "================================================================"
exit "$TOTAL_RC"
