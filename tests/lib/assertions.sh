#!/usr/bin/env bash
# CCM 测试断言库：零外部依赖，供各测试文件 source 使用
# 用法：source "$(dirname "${BASH_SOURCE[0]}")/lib/assertions.sh"

TESTS_PASS=0
TESTS_FAIL=0
TESTS_FAILED_NAMES=()

_t_ok() {
    TESTS_PASS=$((TESTS_PASS + 1))
    echo "    ✅ $1"
}

_t_fail() {
    TESTS_FAIL=$((TESTS_FAIL + 1))
    TESTS_FAILED_NAMES+=("$1")
    echo "    ❌ $1"
    [[ -n "${2:-}" ]] && echo "       $2"
}

# assert_eq <desc> <actual> <expected>
assert_eq() {
    local desc="$1" actual="$2" expected="$3"
    if [[ "$actual" == "$expected" ]]; then
        _t_ok "$desc"
    else
        _t_fail "$desc" "expected: [$expected]  actual: [$actual]"
    fi
}

# assert_contains <desc> <haystack> <needle>
assert_contains() {
    local desc="$1" haystack="$2" needle="$3"
    if [[ "$haystack" == *"$needle"* ]]; then
        _t_ok "$desc"
    else
        _t_fail "$desc" "missing: [$needle]"
    fi
}

# assert_not_contains <desc> <haystack> <needle>
assert_not_contains() {
    local desc="$1" haystack="$2" needle="$3"
    if [[ "$haystack" != *"$needle"* ]]; then
        _t_ok "$desc"
    else
        _t_fail "$desc" "unexpected: [$needle]"
    fi
}

# assert_matches <desc> <haystack> <regex>
assert_matches() {
    local desc="$1" haystack="$2" regex="$3"
    if [[ "$haystack" =~ $regex ]]; then
        _t_ok "$desc"
    else
        _t_fail "$desc" "not matching: [$regex]"
    fi
}

# assert_file_exists <desc> <path>
assert_file_exists() {
    local desc="$1" path="$2"
    if [[ -f "$path" ]]; then
        _t_ok "$desc"
    else
        _t_fail "$desc" "file not found: $path"
    fi
}

# assert_file_executable <desc> <path>
assert_file_executable() {
    local desc="$1" path="$2"
    if [[ -x "$path" ]]; then
        _t_ok "$desc"
    else
        _t_fail "$desc" "not executable: $path"
    fi
}

# assert_dir_exists <desc> <path>
assert_dir_exists() {
    local desc="$1" path="$2"
    if [[ -d "$path" ]]; then
        _t_ok "$desc"
    else
        _t_fail "$desc" "dir not found: $path"
    fi
}

# assert_cmd_ok <desc> <cmd...>  —— 命令退出码为 0
assert_cmd_ok() {
    local desc="$1"
    shift
    if "$@" >/dev/null 2>&1; then
        _t_ok "$desc"
    else
        _t_fail "$desc" "command failed (exit=$?): $*"
    fi
}

# assert_cmd_fail <desc> <cmd...> —— 命令退出码非 0
assert_cmd_fail() {
    local desc="$1"
    shift
    if "$@" >/dev/null 2>&1; then
        _t_fail "$desc" "command unexpectedly succeeded: $*"
    else
        _t_ok "$desc"
    fi
}

# run_tests —— 执行当前文件中所有 test_ 开头的函数并汇总
run_tests() {
    local suite_name="${1:-$(basename "${BASH_SOURCE[1]}")}"
    local fns
    fns=$(declare -F | awk '{print $3}' | grep '^test_' || true)
    echo ""
    echo "==> Suite: $suite_name"
    local fn
    for fn in $fns; do
        echo "  -- $fn"
        "$fn"
    done
    echo ""
    echo "==> $suite_name 结果: ${TESTS_PASS} passed, ${TESTS_FAIL} failed"
    if [[ "$TESTS_FAIL" -gt 0 ]]; then
        printf '    失败用例:\n'
        local n
        for n in "${TESTS_FAILED_NAMES[@]}"; do printf '      - %s\n' "$n"; done
        exit 1
    fi
    exit 0
}
