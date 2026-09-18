#!/usr/bin/env bash
# 安装测试：user / project / prefix / no-rc / rc 注入 / macOS(brew) 分支模拟 / 卸载
# 运行：bash tests/test_install.sh
set -u

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$TESTS_DIR/.." && pwd)"
INSTALL_SH="$REPO_ROOT/install.sh"
UNINSTALL_SH="$REPO_ROOT/uninstall.sh"
# shellcheck source=lib/assertions.sh
source "$TESTS_DIR/lib/assertions.sh"

BEGIN_MARK="# >>> ccm function begin >>>"
END_MARK="# <<< ccm function end <<<"

TEST_HOME=""

new_test_home() {
    TEST_HOME="$(mktemp -d)"
    mkdir -p "$TEST_HOME/xdg/data" "$TEST_HOME/xdg/bin"
}

teardown() {
    [[ -n "$TEST_HOME" && -d "$TEST_HOME" ]] && rm -rf "$TEST_HOME"
}

# install_run <args...> —— 在隔离 HOME/XDG 下执行安装器
install_run() {
    HOME="$TEST_HOME" XDG_DATA_HOME="$TEST_HOME/xdg/data" XDG_BIN_HOME="$TEST_HOME/xdg/bin" \
        bash "$INSTALL_SH" "$@" --yes
}

# ---- source 守卫与内部函数（macOS/Linux 分支） ---------------------------------

test_install_sh_sourceable_without_main() {
    new_test_home
    local out
    out="$(HOME="$TEST_HOME" bash -c 'source "$1" >/dev/null 2>&1; echo SOURCED-OK' _ "$INSTALL_SH")"
    assert_contains "install.sh: 可被 source 且不触发安装" "$out" "SOURCED-OK"
    assert_not_contains "install.sh: source 时不出现安装计划输出" "$out" "Install plan"
    teardown
}

test_find_user_bin_dir_priority() {
    new_test_home
    local out
    out="$(HOME="$TEST_HOME" XDG_BIN_HOME="$TEST_HOME/xdg/bin" bash -c '
        source "$1" >/dev/null 2>&1 || true
        find_user_bin_dir' _ "$INSTALL_SH" 2>/dev/null || true)"
    # source 守卫缺失时 main 已执行/退出，此处输出可能为空 —— 由上一条测试负责 RED
    if [[ "$TESTS_FAIL" -gt 0 ]]; then
        echo "    (跳过：依赖 source 守卫)"
        return 0
    fi
    assert_eq "find_user_bin_dir: XDG_BIN_HOME 最优先" "$out" "$TEST_HOME/xdg/bin"
    teardown
}

test_find_user_bin_dir_local_share_fallback() {
    if grep -q 'BASH_SOURCE\[0\].*==.*\$0' "$INSTALL_SH"; then :; else
        echo "    (跳过：依赖 source 守卫)"
        return 0
    fi
    new_test_home
    mkdir -p "$TEST_HOME/.local/bin"
    local out
    out="$(HOME="$TEST_HOME" bash -c '
        source "$1" >/dev/null 2>&1
        find_user_bin_dir' _ "$INSTALL_SH")"
    assert_eq "find_user_bin_dir: ~/.local/bin 存在时优先于 ~/bin" "$out" "$TEST_HOME/.local/bin"

    new_test_home
    mkdir -p "$TEST_HOME/bin"
    out="$(HOME="$TEST_HOME" bash -c '
        source "$1" >/dev/null 2>&1
        find_user_bin_dir' _ "$INSTALL_SH")"
    assert_eq "find_user_bin_dir: 仅 ~/bin 存在时用 ~/bin" "$out" "$TEST_HOME/bin"

    new_test_home
    out="$(HOME="$TEST_HOME" bash -c '
        source "$1" >/dev/null 2>&1
        find_user_bin_dir' _ "$INSTALL_SH")"
    assert_eq "find_user_bin_dir: 两者皆无时默认 ~/.local/bin" "$out" "$TEST_HOME/.local/bin"
    teardown
}

test_find_system_bin_dir_macos_brew() {
    if ! grep -q 'BASH_SOURCE\[0\].*==.*\$0' "$INSTALL_SH"; then
        echo "    (跳过：依赖 source 守卫)"
        return 0
    fi
    new_test_home
    mkdir -p "$TEST_HOME/brew-prefix/bin" "$TEST_HOME/stub-bin"
    printf '#!/usr/bin/env bash\necho %s\n' "$TEST_HOME/brew-prefix" > "$TEST_HOME/stub-bin/brew"
    chmod +x "$TEST_HOME/stub-bin/brew"

    # macOS 场景：brew 存在 → 选 brew prefix/bin
    local out
    out="$(HOME="$TEST_HOME" PATH="$TEST_HOME/stub-bin:$PATH" bash -c '
        source "$1" >/dev/null 2>&1
        find_system_bin_dir' _ "$INSTALL_SH")"
    assert_eq "macOS 分支: brew 存在时系统 bin 为 brew prefix/bin" "$out" "$TEST_HOME/brew-prefix/bin"

    # Linux 场景：无 brew → /usr/local/bin
    out="$(HOME="$TEST_HOME" bash -c '
        source "$1" >/dev/null 2>&1
        find_system_bin_dir' _ "$INSTALL_SH")"
    assert_eq "Linux 分支: 无 brew 时系统 bin 为 /usr/local/bin" "$out" "/usr/local/bin"
    teardown
}

test_detect_rc_files_variants() {
    if ! grep -q 'BASH_SOURCE\[0\].*==.*\$0' "$INSTALL_SH"; then
        echo "    (跳过：依赖 source 守卫)"
        return 0
    fi
    new_test_home
    touch "$TEST_HOME/.zshrc"
    local out
    out="$(HOME="$TEST_HOME" bash -c '
        source "$1" >/dev/null 2>&1
        detect_rc_files' _ "$INSTALL_SH")"
    assert_contains "detect_rc_files: macOS 主场景 .zshrc 被识别" "$out" ".zshrc"

    new_test_home
    touch "$TEST_HOME/.bashrc" "$TEST_HOME/.profile"
    out="$(HOME="$TEST_HOME" bash -c '
        source "$1" >/dev/null 2>&1
        detect_rc_files' _ "$INSTALL_SH")"
    assert_contains "detect_rc_files: Linux 主场景 .bashrc 被识别" "$out" ".bashrc"
    assert_contains "detect_rc_files: .profile 兜底被识别" "$out" ".profile"
    teardown
}

# ---- user 模式安装 ------------------------------------------------------------

test_user_install_artifacts() {
    new_test_home
    touch "$TEST_HOME/.zshrc"
    local out
    out="$(install_run --user)"
    assert_contains "user 安装: 提示完成" "$out" "Installation complete"

    local data="$TEST_HOME/xdg/data/ccm"
    assert_file_exists "user 安装: data/ccm.sh 就位" "$data/ccm.sh"
    assert_file_executable "user 安装: ccm.sh 可执行" "$data/ccm.sh"
    assert_file_exists "user 安装: lang/zh.json 就位" "$data/lang/zh.json"
    assert_file_exists "user 安装: lang/en.json 就位" "$data/lang/en.json"

    local bin="$TEST_HOME/xdg/bin"
    assert_file_executable "user 安装: bin/ccm 可执行" "$bin/ccm"
    assert_file_executable "user 安装: bin/ccc 可执行" "$bin/ccc"

    # rc 注入
    assert_contains "user 安装: rc 注入了函数块" "$(cat "$TEST_HOME/.zshrc")" "$BEGIN_MARK"

    # 注入块本身必须是合法 bash（提取后语法检查）
    local block
    block="$(awk "/^$BEGIN_MARK\$/{f=1;next} /^$END_MARK\$/{f=0} f" "$TEST_HOME/.zshrc")"
    if [[ -n "$block" ]] && printf '%s\n' "$block" | bash -n 2>/dev/null; then
        _t_ok "user 安装: 注入块通过 bash -n 语法检查"
    else
        _t_fail "user 安装: 注入块语法错误" "$(printf '%s\n' "$block" | bash -n 2>&1 | head -3)"
    fi

    # zsh 可用时同步检查（macOS 默认 shell）
    if command -v zsh >/dev/null 2>&1; then
        if printf '%s\n' "$block" | zsh -n 2>/dev/null; then
            _t_ok "user 安装: 注入块通过 zsh -n 语法检查（macOS 兼容）"
        else
            _t_fail "user 安装: 注入块 zsh 语法错误" "$(printf '%s\n' "$block" | zsh -n 2>&1 | head -3)"
        fi
    else
        echo "    (提示: 本机无 zsh，跳过 zsh -n 检查)"
    fi
    teardown
}

test_user_install_wrapper_smoke() {
    new_test_home
    touch "$TEST_HOME/.zshrc"
    install_run --user >/dev/null 2>&1
    local out rc
    out="$(HOME="$TEST_HOME" bash "$TEST_HOME/xdg/bin/ccm" status 2>&1)"
    rc=$?
    if [[ "$rc" -eq 0 ]]; then _t_ok "user 安装: bin/ccm wrapper 转发命令成功"; else _t_fail "user 安装: wrapper 应转发成功" "exit=$rc out=[$out]"; fi
    teardown
}

test_rc_function_knows_openai() {
    new_test_home
    touch "$TEST_HOME/.zshrc"
    install_run --user >/dev/null 2>&1
    local rc_content
    rc_content="$(cat "$TEST_HOME/.zshrc")"
    assert_matches "rc 注入块: _is_known_model 认识 openai" "$rc_content" 'openai\|gpt\|gpt6|deepseek\|ds\|glm'
    assert_contains "rc 注入块: known-model 列表含 gpt6" "$rc_content" "gpt6"
    teardown
}

test_generated_ccc_wrapper_knows_openai() {
    new_test_home
    touch "$TEST_HOME/.zshrc"
    install_run --user >/dev/null 2>&1
    local ccc_content
    ccc_content="$(cat "$TEST_HOME/xdg/bin/ccc")"
    assert_contains "生成的 ccc wrapper: known-model 含 openai" "$ccc_content" "openai"
    assert_contains "生成的 ccc wrapper: known-model 含 gpt6" "$ccc_content" "gpt6"
    teardown
}

# ---- 其他安装模式 ---------------------------------------------------------------

test_no_rc_install() {
    new_test_home
    touch "$TEST_HOME/.zshrc"
    install_run --no-rc >/dev/null 2>&1
    assert_not_contains "--no-rc: 不注入函数块" "$(cat "$TEST_HOME/.zshrc")" "$BEGIN_MARK"
    assert_file_executable "--no-rc: 二进制仍安装" "$TEST_HOME/xdg/bin/ccm"
    teardown
}

test_project_install() {
    new_test_home
    local proj="$TEST_HOME/myproj"
    mkdir -p "$proj"
    (
        cd "$proj" &&
        HOME="$TEST_HOME" XDG_DATA_HOME="$TEST_HOME/xdg/data" XDG_BIN_HOME="$TEST_HOME/xdg/bin" \
            bash "$INSTALL_SH" --project --yes >/dev/null 2>&1
    )
    assert_file_executable "project 安装: .ccm/bin/ccm 可执行" "$proj/.ccm/bin/ccm"
    assert_file_executable "project 安装: .ccm/bin/ccc 可执行" "$proj/.ccm/bin/ccc"
    assert_file_exists "project 安装: .ccm/ccm.sh 就位" "$proj/.ccm/ccm.sh"
    assert_file_exists "project 安装: .ccm/activate 就位" "$proj/.ccm/activate"
    assert_not_contains "project 安装: 不写用户 rc" "$(cat "$TEST_HOME/.zshrc" 2>/dev/null || echo '')" "$BEGIN_MARK"

    local proj_ccc
    proj_ccc="$(cat "$proj/.ccm/bin/ccc")"
    assert_contains "project ccc wrapper: known-model 含 openai" "$proj_ccc" "openai"
    teardown
}

test_prefix_install() {
    new_test_home
    local prefix="$TEST_HOME/custom/bin"
    install_run --prefix "$prefix" --no-rc >/dev/null 2>&1
    assert_file_executable "--prefix: 自定义 bin/ccm 就位" "$prefix/ccm"
    assert_file_executable "--prefix: 自定义 bin/ccc 就位" "$prefix/ccc"
    teardown
}

test_reinstall_replaces_block_not_duplicates() {
    new_test_home
    touch "$TEST_HOME/.zshrc"
    install_run --user >/dev/null 2>&1
    install_run --user >/dev/null 2>&1
    local count
    count="$(grep -cF "$BEGIN_MARK" "$TEST_HOME/.zshrc" || true)"
    assert_eq "重复安装: 函数块不重复（幂等）" "$count" "1"
    teardown
}

# ---- 卸载 ---------------------------------------------------------------------

test_uninstall_removes_user_install() {
    # 防护：若真实系统路径存在 ccm 拆装目标则跳过（避免误删系统安装）
    if [[ -f /usr/local/bin/ccm || -f /usr/local/bin/ccc ]]; then
        echo "    (跳过：检测到系统级 ccm/ccc，避免测试误删)"
        return 0
    fi
    new_test_home
    touch "$TEST_HOME/.zshrc"
    install_run --user >/dev/null 2>&1
    HOME="$TEST_HOME" XDG_DATA_HOME="$TEST_HOME/xdg/data" XDG_BIN_HOME="$TEST_HOME/xdg/bin" \
        bash "$UNINSTALL_SH" >/dev/null 2>&1
    assert_not_contains "卸载: rc 函数块被移除" "$(cat "$TEST_HOME/.zshrc")" "$BEGIN_MARK"
    if [[ ! -e "$TEST_HOME/xdg/bin/ccm" ]]; then _t_ok "卸载: wrapper ccm 被移除"; else _t_fail "卸载: wrapper ccm 应被移除"; fi
    if [[ ! -e "$TEST_HOME/xdg/data/ccm" ]]; then _t_ok "卸载: data 目录被移除"; else _t_fail "卸载: data 目录应被移除"; fi
    teardown
}

run_tests "install"
