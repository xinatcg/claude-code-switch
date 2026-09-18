#!/usr/bin/env bash
# Provider 功能测试：ccm openai（sub2API 网关）+ ccm open glm 5.3 + 既有 provider 回归
# 运行：bash tests/test_providers.sh
set -u

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$TESTS_DIR/.." && pwd)"
CCM_SH="$REPO_ROOT/ccm.sh"
CCC_SH="$REPO_ROOT/ccc"
# shellcheck source=lib/assertions.sh
source "$TESTS_DIR/lib/assertions.sh"

# ---- 测试基建 -------------------------------------------------------------
# 每个测试函数自行调用 new_test_home 获取隔离的 HOME（内含已写好 key 的 .ccm_config）
TEST_HOME=""

new_test_home() {
    TEST_HOME="$(mktemp -d)"
    cat > "$TEST_HOME/.ccm_config" <<'EOF'
CCM_LANGUAGE=en
OPENAI_API_KEY=sk-test-openai-key
OPENROUTER_API_KEY=sk-test-or-key
DEEPSEEK_API_KEY=sk-test-ds-key
GLM_API_KEY=test-glm-key
MINIMAX_API_KEY=test-mm-key
EOF
}

teardown() {
    [[ -n "$TEST_HOME" && -d "$TEST_HOME" ]] && rm -rf "$TEST_HOME"
}

# ccm_run <args...> —— 在隔离 HOME 下运行 ccm.sh，stdout 存入 OUT、stderr 存入 ERR、退出码存入 RC
ccm_run() {
    OUT="$(HOME="$TEST_HOME" bash "$CCM_SH" "$@" 2>/tmp/ccm_test_stderr.$$)"
    RC=$?
    ERR="$(cat /tmp/ccm_test_stderr.$$ 2>/dev/null)"
    rm -f /tmp/ccm_test_stderr.$$
}

# eval_run <args...> —— 真实 eval ccm 输出（子 shell 内），随后打印关键变量
# 注意：GLM 等分支本就不导出 ANTHROPIC_MODEL，故用 ${VAR:-} 避免与父 shell 的 set -u 冲突
eval_run() (
    set -e
    HOME="$TEST_HOME"
    eval "$(bash "$CCM_SH" "$@")"
    echo "BASE_URL=${ANTHROPIC_BASE_URL:-}"
    echo "AUTH_TOKEN=${ANTHROPIC_AUTH_TOKEN:-}"
    echo "MODEL=${ANTHROPIC_MODEL:-}"
    echo "SONNET=${ANTHROPIC_DEFAULT_SONNET_MODEL:-}"
    echo "OPUS=${ANTHROPIC_DEFAULT_OPUS_MODEL:-}"
    echo "HAIKU=${ANTHROPIC_DEFAULT_HAIKU_MODEL:-}"
    echo "SUBAGENT=${CLAUDE_CODE_SUBAGENT_MODEL:-}"
)

# ---- OpenAI (sub2API) 新功能 ------------------------------------------------

test_openai_without_key_fails() {
    new_test_home
    sed -i '/OPENAI_API_KEY/d' "$TEST_HOME/.ccm_config"
    ccm_run openai
    if [[ "$RC" -ne 0 ]]; then
        _t_ok "openai: 未配置 key 时非零退出"
    else
        _t_fail "openai: 未配置 key 时应非零退出" "exit=0, stdout=[$OUT]"
    fi
    assert_contains "openai: 错误提示指向 OPENAI_API_KEY" "$ERR" "OPENAI_API_KEY"
    teardown
}

test_openai_exports_full_set() {
    new_test_home
    ccm_run openai
    if [[ "$RC" -eq 0 ]]; then _t_ok "openai: 退出码 0"; else _t_fail "openai: 退出码应为 0" "exit=$RC err=[$ERR]"; fi
    assert_contains "openai: 导出 ANTHROPIC_BASE_URL" "$OUT" "export ANTHROPIC_BASE_URL="
    assert_contains "openai: AUTH_TOKEN 引用 OPENAI_API_KEY（不打印密钥）" "$OUT" 'export ANTHROPIC_AUTH_TOKEN="${OPENAI_API_KEY}"'
    assert_contains "openai: MODEL 为 gpt-6-astra" "$OUT" "export ANTHROPIC_MODEL='gpt-6-astra'"
    assert_contains "openai: SONNET 槽位 gpt-6-astra" "$OUT" "export ANTHROPIC_DEFAULT_SONNET_MODEL='gpt-6-astra'"
    assert_contains "openai: OPUS 槽位 gpt-6-astra" "$OUT" "export ANTHROPIC_DEFAULT_OPUS_MODEL='gpt-6-astra'"
    assert_contains "openai: HAIKU 槽位 gpt-6-astra" "$OUT" "export ANTHROPIC_DEFAULT_HAIKU_MODEL='gpt-6-astra'"
    assert_contains "openai: SUBAGENT 槽位 gpt-6-astra" "$OUT" "export CLAUDE_CODE_SUBAGENT_MODEL='gpt-6-astra'"
    assert_contains "openai: 清理旧变量 prelude" "$OUT" "unset ANTHROPIC_BASE_URL"
    teardown
}

test_openai_eval_end_to_end() {
    new_test_home
    local result
    result="$(eval_run openai)"
    assert_contains "openai eval: BASE_URL 默认 localhost:8080" "$result" "BASE_URL=http://localhost:8080"
    assert_contains "openai eval: AUTH_TOKEN 展开为配置 key" "$result" "AUTH_TOKEN=sk-test-openai-key"
    assert_contains "openai eval: MODEL=gpt-6-astra" "$result" "MODEL=gpt-6-astra"
    teardown
}

test_openai_base_url_normalization() {
    new_test_home
    echo 'OPENAI_BASE_URL=http://gw.example.com:9000/' >> "$TEST_HOME/.ccm_config"
    assert_contains "openai 归一化: 剥离尾部斜杠" "$(eval_run openai)" "BASE_URL=http://gw.example.com:9000"

    new_test_home
    echo 'OPENAI_BASE_URL=http://gw.example.com:9000/v1' >> "$TEST_HOME/.ccm_config"
    assert_contains "openai 归一化: 剥离 /v1 后缀" "$(eval_run openai)" "BASE_URL=http://gw.example.com:9000"

    new_test_home
    echo 'OPENAI_BASE_URL=http://gw.example.com:9000/v1/' >> "$TEST_HOME/.ccm_config"
    assert_contains "openai 归一化: /v1/ 同时剥离" "$(eval_run openai)" "BASE_URL=http://gw.example.com:9000"

    new_test_home
    echo 'OPENAI_BASE_URL=https://s2a.internal/v1' >> "$TEST_HOME/.ccm_config"
    assert_contains "openai 归一化: https 保留、/v1 剥离" "$(eval_run openai)" "BASE_URL=https://s2a.internal"
    teardown
}

test_openai_model_override() {
    new_test_home
    echo 'OPENAI_MODEL=gpt-6-astra-pro' >> "$TEST_HOME/.ccm_config"
    local result
    result="$(eval_run openai)"
    assert_contains "openai 覆盖: MODEL 生效" "$result" "MODEL=gpt-6-astra-pro"
    assert_contains "openai 覆盖: SONNET 同步生效" "$result" "SONNET=gpt-6-astra-pro"
    assert_contains "openai 覆盖: SUBAGENT 同步生效" "$result" "SUBAGENT=gpt-6-astra-pro"
    teardown
}

test_openai_aliases() {
    new_test_home
    local base alias_gpt alias_gpt6
    base="$(ccm_run openai; echo "$OUT")"
    ccm_run gpt
    alias_gpt="$OUT"
    ccm_run gpt6
    alias_gpt6="$OUT"
    assert_eq "openai 别名: gpt 输出一致" "$alias_gpt" "$base"
    assert_eq "openai 别名: gpt6 输出一致" "$alias_gpt6" "$base"
    teardown
}

test_openai_via_env_command() {
    new_test_home
    ccm_run env openai
    if [[ "$RC" -eq 0 ]]; then
        assert_contains "ccm env openai: 可用" "$OUT" "gpt-6-astra"
    else
        _t_fail "ccm env openai: 应可用" "exit=$RC err=[$ERR]"
    fi
    teardown
}

test_openai_help_lists_provider() {
    new_test_home
    ccm_run help
    assert_contains "help 文本包含 openai" "$OUT$ERR" "openai"
    teardown
}

# ---- OpenRouter GLM 升级 ----------------------------------------------------

test_open_glm_uses_5_3() {
    new_test_home
    ccm_run open glm
    if [[ "$RC" -eq 0 ]]; then _t_ok "open glm: 退出码 0"; else _t_fail "open glm: 退出码应为 0" "exit=$RC err=[$ERR]"; fi
    assert_contains "open glm: 主模型 z-ai/glm-5.3" "$OUT" "export ANTHROPIC_MODEL='z-ai/glm-5.3'"
    assert_not_contains "open glm: 不再出现 z-ai/glm-5.2" "$OUT" "z-ai/glm-5.2"
    teardown
}

test_open_glm_5_3_alias() {
    new_test_home
    ccm_run open glm-5.3
    if [[ "$RC" -eq 0 ]]; then _t_ok "open glm-5.3 别名: 可用"; else _t_fail "open glm-5.3 别名: 应可用" "exit=$RC err=[$ERR]"; fi
    teardown
}

# ---- ccc 启动器 -------------------------------------------------------------

test_ccc_openai_launches_claude_with_gpt6() {
    new_test_home
    local stub_dir="$TEST_HOME/stub"
    mkdir -p "$stub_dir"
    cat > "$stub_dir/claude" <<EOF
#!/usr/bin/env bash
{
  echo "MODEL=\$ANTHROPIC_MODEL"
  echo "BASE_URL=\$ANTHROPIC_BASE_URL"
  echo "AUTH_TOKEN=\$ANTHROPIC_AUTH_TOKEN"
  echo "ARGS=\$*"
} > "$TEST_HOME/claude_invoked.env"
exit 0
EOF
    chmod +x "$stub_dir/claude"

    HOME="$TEST_HOME" PATH="$stub_dir:$PATH" "$CCC_SH" openai >/dev/null 2>&1
    local rc=$?
    if [[ "$rc" -eq 0 ]]; then _t_ok "ccc openai: 启动成功（stub claude）"; else _t_fail "ccc openai: 应成功启动" "exit=$rc"; fi
    local captured
    captured="$(cat "$TEST_HOME/claude_invoked.env" 2>/dev/null || echo 'NOT-INVOKED')"
    assert_contains "ccc openai: claude 收到 gpt-6-astra" "$captured" "MODEL=gpt-6-astra"
    assert_contains "ccc openai: claude 收到网关 BASE_URL" "$captured" "BASE_URL=http://localhost:8080"
    assert_contains "ccc openai: claude 收到 AUTH_TOKEN" "$captured" "AUTH_TOKEN=sk-test-openai-key"
    teardown
}

test_ccc_known_model_regression() {
    # 回归守护：bailian_variant 未初始化曾导致所有 `ccc <model>` 在 set -u 下崩溃
    new_test_home
    local stub_dir="$TEST_HOME/stub"
    mkdir -p "$stub_dir"
    cat > "$stub_dir/claude" <<EOF
#!/usr/bin/env bash
echo "MODEL=\$ANTHROPIC_MODEL" > "$TEST_HOME/claude_invoked.env"
exit 0
EOF
    chmod +x "$stub_dir/claude"

    HOME="$TEST_HOME" PATH="$stub_dir:$PATH" "$CCC_SH" deepseek >/dev/null 2>&1
    if [[ $? -eq 0 ]]; then _t_ok "ccc deepseek: 非 bailian 路径不再因 unbound variable 崩溃"; else _t_fail "ccc deepseek: 应成功启动（回归 bailian_variant bug）"; fi
    assert_contains "ccc deepseek: claude 收到 deepseek-chat" "$(cat "$TEST_HOME/claude_invoked.env" 2>/dev/null || echo '')" "MODEL=deepseek-chat"
    teardown
}

# ---- 既有 provider 回归守护 ---------------------------------------------------

test_regression_deepseek() {
    new_test_home
    local result
    result="$(eval_run deepseek)"
    assert_contains "回归 deepseek: BASE_URL 不变" "$result" "BASE_URL=https://api.deepseek.com/anthropic"
    assert_contains "回归 deepseek: MODEL 不变" "$result" "MODEL=deepseek-chat"
    teardown
}

test_regression_glm_china() {
    new_test_home
    local result
    result="$(eval_run glm china)"
    assert_contains "回归 glm china: BASE_URL 不变" "$result" "BASE_URL=https://open.bigmodel.cn/api/anthropic"
    # 既有行为：GLM 分支不导出 ANTHROPIC_MODEL，仅设 SONNET/OPUS/SUBAGENT
    assert_contains "回归 glm china: SONNET 为 glm-5.3[1m]" "$result" "SONNET=glm-5.3[1m]"
    assert_contains "回归 glm china: HAIKU 保持 glm-4.7" "$result" "HAIKU=glm-4.7"
    teardown
}

test_regression_minimax_global() {
    new_test_home
    local result
    result="$(eval_run minimax global)"
    assert_contains "回归 minimax global: BASE_URL 不变" "$result" "BASE_URL=https://api.minimax.io/anthropic"
    assert_contains "回归 minimax global: MODEL 不变" "$result" "MODEL=MiniMax-M2.5"
    teardown
}

test_regression_status_smoke() {
    new_test_home
    ccm_run status
    if [[ "$RC" -eq 0 ]]; then _t_ok "回归 status: 退出码 0"; else _t_fail "回归 status: 应退出 0" "exit=$RC err=[$ERR]"; fi
    teardown
}

run_tests "providers"
