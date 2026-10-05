#!/usr/bin/env bash
# Claude 账号管理测试：切换前回写轮换后的凭证、活跃进程拦截、身份校验、有效期展示
# 运行：bash tests/test_accounts.sh
set -u

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$TESTS_DIR/.." && pwd)"
CCM_SH="$REPO_ROOT/ccm.sh"
# shellcheck source=lib/assertions.sh
source "$TESTS_DIR/lib/assertions.sh"

# ---- 测试基建 -------------------------------------------------------------
TEST_HOME=""
PS_FILE=""
NOW_MS=$(( $(date +%s) * 1000 ))
DAY_MS=86400000

new_test_home() {
    TEST_HOME="$(mktemp -d)"
    mkdir -p "$TEST_HOME/.claude"
    echo "CCM_LANGUAGE=en" > "$TEST_HOME/.ccm_config"
    # 默认无活跃 Claude 进程
    PS_FILE="$TEST_HOME/ps.txt"
    : > "$PS_FILE"
}

teardown() {
    [[ -n "$TEST_HOME" && -d "$TEST_HOME" ]] && rm -rf "$TEST_HOME"
}

# creds_json <tag> <refreshTokenExpiresAt-ms>：生成一份紧凑的 claudeAiOauth JSON
creds_json() {
    local tag="$1" rt_exp="$2"
    printf '{"accessToken":"at-%s/+x","refreshToken":"rt-%s/+x","expiresAt":%s,"refreshTokenExpiresAt":%s,"scopes":["user:inference"],"subscriptionType":"pro"}' \
        "$tag" "$tag" "$((NOW_MS + 8 * 3600 * 1000))" "$rt_exp"
}

# login_as <tag> <rt_exp> <uuid> <email>：模拟 Claude Code /login 后的磁盘状态
login_as() {
    local tag="$1" rt_exp="$2" uuid="$3" email="$4"
    printf '{"claudeAiOauth":%s,"mcpOAuth":{"keep":"me"}}' "$(creds_json "$tag" "$rt_exp")" > "$TEST_HOME/.claude/.credentials.json"
    printf '{"numStartups":7,"oauthAccount":{"accountUuid":"%s","emailAddress":"%s"}}' "$uuid" "$email" > "$TEST_HOME/.claude.json"
}

# rotate_to <tag>：模拟续期——refresh token 被替换，但 refreshTokenExpiresAt 不变
rotate_to() {
    local tag="$1" rt_exp
    rt_exp=$(jq -r '.claudeAiOauth.refreshTokenExpiresAt' "$TEST_HOME/.claude/.credentials.json")
    printf '{"claudeAiOauth":%s,"mcpOAuth":{"keep":"me"}}' "$(creds_json "$tag" "$rt_exp")" > "$TEST_HOME/.claude/.credentials.json"
}

current_rt() { jq -r '.claudeAiOauth.refreshToken' "$TEST_HOME/.claude/.credentials.json"; }
saved_rt() { jq -r --arg n "$1" '.[$n]' "$TEST_HOME/.ccm_accounts" | base64 -d | jq -r '.refreshToken'; }

ccm_run() {
    OUT="$(HOME="$TEST_HOME" CCM_PS_OVERRIDE_FILE="$PS_FILE" bash "$CCM_SH" "$@" 2>/tmp/ccm_test_stderr.$$)"
    RC=$?
    ERR="$(cat /tmp/ccm_test_stderr.$$ 2>/dev/null)"
    rm -f /tmp/ccm_test_stderr.$$
}

assert_rc() {
    local desc="$1" expected="$2"
    if [[ "$RC" -eq "$expected" ]]; then _t_ok "$desc"; else _t_fail "$desc" "exit=$RC err=[$ERR]"; fi
}

assert_rc_nonzero() {
    local desc="$1"
    if [[ "$RC" -ne 0 ]]; then _t_ok "$desc"; else _t_fail "$desc" "exit=0 out=[$OUT]"; fi
}

# 准备两个已保存账号 a、b，当前登录为 a
setup_two_accounts() {
    new_test_home
    login_as b1 "$((NOW_MS + 20 * DAY_MS))" uuid-b b@example.com
    ccm_run save-account b
    login_as a1 "$((NOW_MS + 25 * DAY_MS))" uuid-a a@example.com
    ccm_run save-account a
}

# ---- 测试用例 -------------------------------------------------------------

test_resave_existing_account_updates_snapshot() {
    new_test_home
    login_as a1 "$((NOW_MS + 25 * DAY_MS))" uuid-a a@example.com
    ccm_run save-account a
    rotate_to a2
    ccm_run save-account a
    assert_rc "save-account: 覆盖已存在账号退出码 0" 0
    assert_eq "save-account: 覆盖后快照为新 token（base64 含 / 时也正确）" "$(saved_rt a)" "rt-a2/+x"
    assert_not_contains "save-account: 无 sed 报错" "$ERR" "unknown option"
    teardown
}

test_switch_writes_back_rotated_token() {
    setup_two_accounts
    rotate_to a2
    ccm_run switch-account b
    assert_rc "switch: 退出码 0" 0
    assert_eq "switch: 切走前把 a 轮换后的 token 写回快照" "$(saved_rt a)" "rt-a2/+x"
    assert_eq "switch: 当前凭证换成 b" "$(current_rt)" "rt-b1/+x"
    assert_eq "switch: 保留 mcpOAuth" "$(jq -r '.mcpOAuth.keep' "$TEST_HOME/.claude/.credentials.json")" "me"
    ccm_run switch-account a
    assert_eq "switch: 切回 a 拿到的是最新 token" "$(current_rt)" "rt-a2/+x"
    teardown
}

test_switch_updates_oauth_account_in_claude_json() {
    setup_two_accounts
    ccm_run switch-account b
    assert_eq "switch: ~/.claude.json oauthAccount 换成 b" "$(jq -r '.oauthAccount.emailAddress' "$TEST_HOME/.claude.json")" "b@example.com"
    assert_eq "switch: ~/.claude.json 其他字段不变" "$(jq -r '.numStartups' "$TEST_HOME/.claude.json")" "7"
    teardown
}

test_switch_blocked_when_claude_running() {
    setup_two_accounts
    echo "4242 claude claude --resume" > "$PS_FILE"
    ccm_run switch-account b
    assert_rc_nonzero "switch: 有活跃 Claude 进程时拒绝"
    assert_contains "switch: 提示中列出进程 PID" "$ERR" "4242"
    assert_eq "switch: 拒绝时凭证不变" "$(current_rt)" "rt-a1/+x"
    teardown
}

test_claude_account_shortcut_blocked_when_running() {
    setup_two_accounts
    echo "4243 node claude" > "$PS_FILE"
    ccm_run claude:b
    assert_rc_nonzero "claude:<account>: 有活跃 Claude 进程时拒绝"
    assert_not_contains "claude:<account>: 拒绝时不输出 export" "$OUT" "export ANTHROPIC"
    teardown
}

test_switch_blocked_when_current_login_unsaved() {
    setup_two_accounts
    # 用户手动 /login 了一个未保存的新账号 z
    login_as z1 "$((NOW_MS + 30 * DAY_MS))" uuid-z z@example.com
    ccm_run switch-account b
    assert_rc_nonzero "switch: 当前登录未保存时拒绝（避免丢失登录）"
    assert_contains "switch: 提示先 save-account" "$ERR" "save-account"
    assert_eq "switch: 不把 z 的凭证写进 a 的快照" "$(saved_rt a)" "rt-a1/+x"
    assert_eq "switch: 凭证不变" "$(current_rt)" "rt-z1/+x"
    teardown
}

test_relogin_same_account_is_written_back() {
    setup_two_accounts
    # 同一账号 a 重新 /login：新 grant（过期时间变了），但 accountUuid 相同
    login_as a9 "$((NOW_MS + 29 * DAY_MS))" uuid-a a@example.com
    ccm_run switch-account b
    assert_rc "switch: 同账号重新登录后允许切换" 0
    assert_eq "switch: 回写重新登录后的 token" "$(saved_rt a)" "rt-a9/+x"
    teardown
}

test_legacy_snapshot_matched_by_grant() {
    # 升级前的数据：没有状态文件、没有 meta，只靠 refreshTokenExpiresAt 认出同一次登录
    setup_two_accounts
    rm -f "$TEST_HOME/.ccm_current_account" "$TEST_HOME/.ccm_accounts_meta"
    rotate_to a2
    ccm_run switch-account b
    assert_rc "legacy: 无状态文件时按 grant 匹配后允许切换" 0
    assert_eq "legacy: 回写到匹配的快照 a" "$(saved_rt a)" "rt-a2/+x"
    teardown
}

test_current_account_shows_details() {
    setup_two_accounts
    rotate_to a2
    ccm_run current-account
    assert_rc "current-account: 退出码 0" 0
    assert_contains "current-account: 轮换后仍识别为 a" "$OUT" "Account name: a"
    assert_contains "current-account: 显示邮箱" "$OUT" "a@example.com"
    assert_contains "current-account: 显示 refresh token 剩余天数" "$OUT" "24d"
    assert_contains "current-account: 显示凭证位置" "$OUT" ".claude/.credentials.json"
    assert_contains "current-account: 显示活跃进程情况" "$OUT" "Claude processes"
    teardown
}

test_list_accounts_marks_active_after_rotation() {
    setup_two_accounts
    rotate_to a2
    ccm_run list-accounts
    assert_contains "list-accounts: 轮换后 a 仍标为 active" "$(grep 'a@example.com' <<<"$OUT")" "active"
    assert_not_contains "list-accounts: b 不标 active" "$(grep 'b@example.com' <<<"$OUT")" "active"
    assert_contains "list-accounts: 显示 b 的邮箱" "$OUT" "b@example.com"
    assert_contains "list-accounts: 显示 refresh 剩余天数" "$OUT" "19d"
    teardown
}

test_list_accounts_flags_expired_refresh() {
    new_test_home
    login_as old1 "$((NOW_MS - DAY_MS))" uuid-o o@example.com
    ccm_run save-account old
    ccm_run list-accounts
    assert_contains "list-accounts: refresh 过期时提示需重新登录" "$OUT" "EXPIRED"
    teardown
}

# ---- 运行 -----------------------------------------------------------------
echo "==> 账号管理测试 (test_accounts.sh)"
if ! command -v jq >/dev/null 2>&1; then
    echo "    ⚠️  需要 jq，跳过"
    exit 0
fi
test_resave_existing_account_updates_snapshot
test_switch_writes_back_rotated_token
test_switch_updates_oauth_account_in_claude_json
test_switch_blocked_when_claude_running
test_claude_account_shortcut_blocked_when_running
test_switch_blocked_when_current_login_unsaved
test_relogin_same_account_is_written_back
test_legacy_snapshot_matched_by_grant
test_current_account_shows_details
test_list_accounts_marks_active_after_rotation
test_list_accounts_flags_expired_refresh

echo ""
echo "    通过: $TESTS_PASS  失败: $TESTS_FAIL"
[[ "$TESTS_FAIL" -eq 0 ]]
