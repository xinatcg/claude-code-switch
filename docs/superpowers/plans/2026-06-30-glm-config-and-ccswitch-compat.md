# GLM 配置修正 与 cc-switch-cli 兼容 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让 GLM 在 project/user/全局导出三层均产出符合智谱官方文档的 env（三模型 + 3 性能参数），并通过 `ccm user` 警告 + `--force` 与 cc-switch-cli 划清全局职责。

**Architecture:** 新增 `get_glm_env_map()` 作为 GLM env 唯一数据源（逐行 `KEY=value`），三处消费：`emit_env_exports` 的 glm case、`project_write_glm_settings`、`user_write_glm_settings`。`ccm user` 写入前检测全局文件非 ccmManaged 即拦下，需 `--force` 覆盖。其他 provider 零改动。

**Tech Stack:** Bash（shebang `#!/bin/bash`，可用进程替换 `< <()`）；JSON 写入优先 python3、heredoc 回退；产物为 `.claude/settings.local.json`（项目级）与 `~/.claude/settings.json`（用户全局）。

## Global Constraints

（每个 task 的需求都隐含以下约束，逐字照抄自 spec）

- 两 region 仅 `ANTHROPIC_BASE_URL` 不同：`global`=`https://api.z.ai/api/anthropic`，`china`=`https://open.bigmodel.cn/api/anthropic`
- 模型映射两 region 一致：`HAIKU=glm-4.7`，`SONNET/OPUS/SUBAGENT=glm-5.2[1m]`
- 3 个性能参数（仅 GLM 写）：`CLAUDE_CODE_AUTO_COMPACT_WINDOW=1000000`、`CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1`（写字面量字符串 `"1"`）、`API_TIMEOUT_MS=3000000`
- GLM env **不含** `ANTHROPIC_MODEL`（移除，DEFAULT_* 已覆盖）
- `CLAUDE_CODE_SUBAGENT_MODEL=glm-5.2[1m]` 保留
- 注释沿用 ccm.sh 既有风格（中英混合，中文为主）
- **所有测试必须在临时 HOME + 临时 CWD 下运行**：`load_config()` 无配置时会创建 `~/.ccm_config`，不隔离会污染真实用户环境
- 实现起点先建分支 `feat/glm-config-ccswitch-compat`，所有 task 在该分支提交，最后提 PR
- commit message 沿用既有中文 conventional commits 风格（如 `feat:` / `fix:`）

---

## File Structure

| 文件 | 责任 | 本次改动 |
|---|---|---|
| `ccm.sh` | 核心脚本，全部逻辑 | 新增 2 函数、改写 2 函数、3 处委托分支、prelude 补全、路由+帮助 |
| `README.md` / `README_CN.md` | 用户文档 | GLM 配置说明 + cc-switch-cli 分工 + `--force` |
| `CHANGELOG.md` | 变更记录 | 本次条目 |

**函数边界（ccm.sh 内）：**
- `get_glm_env_map(region)` — **新增**，纯函数，GLM env 唯一数据源
- `project_write_glm_settings(region)` — **改写**，消费数据源写项目级
- `user_write_glm_settings(region, force)` — **新增**，消费数据源写全局 + cc-switch-cli 警告
- `project_write_settings` / `user_write_settings` — **追加 glm 委托分支**
- `emit_env_exports` 的 glm case — **改写**，消费数据源
- `user` 路由 — **追加 `--force` 解析**
- `prelude`（2 处）— **追加 `CLAUDE_CODE_AUTO_COMPACT_WINDOW`**

---

## Task 0: 建分支

**Files:** 无（git 操作）

- [ ] **Step 1: 从最新 main 建分支**

```bash
cd /home/clawcrew/claude-code-switch
git checkout main
git pull --ff-only 2>/dev/null || true
git checkout -b feat/glm-config-ccswitch-compat
```

- [ ] **Step 2: 确认工作区干净且在新分支**

Run: `git status -sb && git branch --show-current`
Expected: `## feat/glm-config-ccswitch-compat` 且 nothing to commit

---

## Task 1: 新增 `get_glm_env_map()` 唯一数据源

**Files:**
- Modify: `ccm.sh`（在 `normalize_region()` 函数结束后、`project_settings_path()` 前插入；锚点：`ccm.sh:393` 附近的 `}` 与 `project_settings_path() {`）

**Interfaces:**
- Consumes: 无（纯静态映射；region 由调用方先经 `normalize_region` 规范化）
- Produces: `get_glm_env_map(region)` → stdout 逐行 `KEY=value`（9 行），其中 `ANTHROPIC_AUTH_TOKEN` 行 value 为字面占位 `${GLM_API_KEY}`，由调用方展开

- [ ] **Step 1: 写校验脚本（定义预期输出）**

创建 `/tmp/test_glm_env_map.sh`：
```bash
#!/bin/bash
set -e
export HOME="$(mktemp -d)"
cd "$(mktemp -d)"
# shellcheck source=/dev/null
source /home/clawcrew/claude-code-switch/ccm.sh 2>/dev/null || true

out_china="$(get_glm_env_map china)"
echo "$out_china" | grep -qx 'ANTHROPIC_BASE_URL=https://open.bigmodel.cn/api/anthropic'
echo "$out_china" | grep -qx 'ANTHROPIC_AUTH_TOKEN=${GLM_API_KEY}'
echo "$out_china" | grep -qx 'ANTHROPIC_DEFAULT_HAIKU_MODEL=glm-4.7'
echo "$out_china" | grep -qx 'ANTHROPIC_DEFAULT_SONNET_MODEL=glm-5.2[1m]'
echo "$out_china" | grep -qx 'ANTHROPIC_DEFAULT_OPUS_MODEL=glm-5.2[1m]'
echo "$out_china" | grep -qx 'CLAUDE_CODE_SUBAGENT_MODEL=glm-5.2[1m]'
echo "$out_china" | grep -qx 'CLAUDE_CODE_AUTO_COMPACT_WINDOW=1000000'
echo "$out_china" | grep -qx 'CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1'
echo "$out_china" | grep -qx 'API_TIMEOUT_MS=3000000'
[ "$(printf '%s\n' "$out_china" | grep -c .)" -eq 9 ]

out_global="$(get_glm_env_map global)"
echo "$out_global" | grep -qx 'ANTHROPIC_BASE_URL=https://api.z.ai/api/anthropic'
echo "$out_global" | grep -qx 'ANTHROPIC_DEFAULT_HAIKU_MODEL=glm-4.7'
echo "OK"
```
`chmod +x /tmp/test_glm_env_map.sh`

- [ ] **Step 2: 跑测试，确认失败（红）**

Run: `bash /tmp/test_glm_env_map.sh`
Expected: 失败，报 `get_glm_env_map: command not found`

- [ ] **Step 3: 插入 `get_glm_env_map()` 实现**

用 Edit 在 `project_settings_path() {` 这一行**之前**插入（锚点：搜索 `project_settings_path() {`）：

旧串（唯一）：
```bash
project_settings_path() {
    echo "$PWD/.claude/settings.local.json"
}
```
新串：
```bash
# GLM env 唯一数据源：给定已规范化的 region，逐行输出 "KEY=value"。
# value 内 ${GLM_API_KEY} 为占位符，由调用方在写文件 / export 时展开为真实值。
# 两 region 仅 base_url 不同；模型映射一致：HAIKU=glm-4.7，SONNET/OPUS/SUBAGENT=glm-5.2[1m]。
get_glm_env_map() {
    local region="$1"
    local base_url
    case "$region" in
        "china")  base_url="https://open.bigmodel.cn/api/anthropic" ;;
        "global"|*) base_url="https://api.z.ai/api/anthropic" ;;
    esac
    cat <<EOF
ANTHROPIC_BASE_URL=${base_url}
ANTHROPIC_AUTH_TOKEN=\${GLM_API_KEY}
ANTHROPIC_DEFAULT_HAIKU_MODEL=glm-4.7
ANTHROPIC_DEFAULT_SONNET_MODEL=glm-5.2[1m]
ANTHROPIC_DEFAULT_OPUS_MODEL=glm-5.2[1m]
CLAUDE_CODE_SUBAGENT_MODEL=glm-5.2[1m]
CLAUDE_CODE_AUTO_COMPACT_WINDOW=1000000
CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1
API_TIMEOUT_MS=3000000
EOF
}

project_settings_path() {
    echo "$PWD/.claude/settings.local.json"
}
```

- [ ] **Step 4: 跑测试，确认通过（绿）**

Run: `bash /tmp/test_glm_env_map.sh`
Expected: 末行打印 `OK`

- [ ] **Step 5: 提交**

```bash
git add ccm.sh
git commit -m "feat: 新增 get_glm_env_map 作为 GLM env 唯一数据源"
```

---

## Task 2: 改写 `project_write_glm_settings()` 并加 project 委托

**Files:**
- Modify: `ccm.sh` — 改写 `project_write_glm_settings()`（锚点：函数名，当前 ccm.sh:408-461）
- Modify: `ccm.sh` — `project_write_settings()` 开头加 glm 委托（锚点：`project_write_settings() {`，当前 ccm.sh:479）

**Interfaces:**
- Consumes: `get_glm_env_map(region)`（Task 1）、`normalize_region`、`is_effectively_set`、`project_settings_path`、`backup_project_settings`
- Produces: `ccm project glm [global|china]` 写出符合 spec §4.2 的 `.claude/settings.local.json`

- [ ] **Step 1: 写校验脚本**

创建 `/tmp/test_project_glm.sh`：
```bash
#!/bin/bash
set -e
export HOME="$(mktemp -d)"
export GLM_API_KEY=test123
cd "$(mktemp -d)"
source /home/clawcrew/claude-code-switch/ccm.sh 2>/dev/null || true

project_write_glm_settings china
f=./.claude/settings.local.json
[ -f "$f" ]
jq -e '.ccmManaged == true' "$f"
jq -e '.ccmProvider == "glm"' "$f"
jq -e '.env.ANTHROPIC_BASE_URL == "https://open.bigmodel.cn/api/anthropic"' "$f"
jq -e '.env.ANTHROPIC_AUTH_TOKEN == "test123"' "$f"
jq -e '.env.ANTHROPIC_DEFAULT_HAIKU_MODEL == "glm-4.7"' "$f"
jq -e '.env.ANTHROPIC_DEFAULT_SONNET_MODEL == "glm-5.2[1m]"' "$f"
jq -e '.env.ANTHROPIC_DEFAULT_OPUS_MODEL == "glm-5.2[1m]"' "$f"
jq -e '.env.CLAUDE_CODE_SUBAGENT_MODEL == "glm-5.2[1m]"' "$f"
jq -e '.env.CLAUDE_CODE_AUTO_COMPACT_WINDOW == "1000000"' "$f"
jq -e '.env.CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC == "1"' "$f"
jq -e '.env.API_TIMEOUT_MS == "3000000"' "$f"
jq -e '(.env | has("ANTHROPIC_MODEL")) == false' "$f"
# global region 仅 base_url 不同
project_write_glm_settings global
jq -e '.env.ANTHROPIC_BASE_URL == "https://api.z.ai/api/anthropic"' "$f"
echo "OK"
```
`chmod +x /tmp/test_project_glm.sh`

- [ ] **Step 2: 跑测试，确认失败（红）**

Run: `bash /tmp/test_project_glm.sh`
Expected: 失败（当前产物 `ANTHROPIC_DEFAULT_HAIKU_MODEL` 为 `glm-5.2` 而非 `glm-4.7`，且 `has("ANTHROPIC_MODEL")` 为 true）

- [ ] **Step 3: 改写 `project_write_glm_settings()`**

用 Edit 替换整个旧 `project_write_glm_settings()`（从 `project_write_glm_settings() {` 到其首个 `}` 结束，当前 408-461）。

旧串（开头唯一片段，用于定位；替换整段）：
```bash
project_write_glm_settings() {
    local region_input="${1:-global}"
    local region
    if ! region="$(normalize_region "$region_input")"; then
        echo -e "${RED}❌ $(t 'unknown_option'): $region_input${NC}" >&2
        echo -e "${YELLOW}💡 Usage: ccm project glm [global|china]${NC}" >&2
        return 1
    fi
    local settings_path
    settings_path="$(project_settings_path)"
    local settings_dir
    settings_dir="$(dirname "$settings_path")"

    if ! is_effectively_set "$GLM_API_KEY"; then
        echo -e "${RED}❌ Please configure GLM_API_KEY before writing project settings${NC}" >&2
        return 1
    fi

    local glm_model="${GLM_MODEL:-glm-5.2}"
    local base_url=""
    case "$region" in
        "global")
            base_url="https://api.z.ai/api/anthropic"
            ;;
        "china")
            base_url="https://open.bigmodel.cn/api/anthropic"
            ;;
    esac

    if [[ -f "$settings_path" ]]; then
        if ! grep -q '"ccmManaged"[[:space:]]*:[[:space:]]*true' "$settings_path"; then
            backup_project_settings "$settings_path"
        fi
    fi

    mkdir -p "$settings_dir"
  cat > "$settings_path" <<EOF
{
  "ccmManaged": true,
  "env": {
    "ANTHROPIC_BASE_URL": "${base_url}",
    "ANTHROPIC_AUTH_TOKEN": "${GLM_API_KEY}",
    "ANTHROPIC_MODEL": "${glm_model}",
    "ANTHROPIC_DEFAULT_SONNET_MODEL": "${glm_model}",
    "ANTHROPIC_DEFAULT_OPUS_MODEL": "${glm_model}",
    "ANTHROPIC_DEFAULT_HAIKU_MODEL": "${glm_model}",
    "CLAUDE_CODE_SUBAGENT_MODEL": "${glm_model}"
  }
}
EOF
    chmod 600 "$settings_path"
    echo -e "${GREEN}✅ Wrote project settings for GLM (${region}) at:${NC} $settings_path" >&2
    echo -e "${YELLOW}💡 This overrides user settings (e.g. Quotio) for this project only.${NC}" >&2
}
```
新串：
```bash
project_write_glm_settings() {
    local region_input="${1:-global}"
    local region
    if ! region="$(normalize_region "$region_input")"; then
        echo -e "${RED}❌ $(t 'unknown_option'): $region_input${NC}" >&2
        echo -e "${YELLOW}💡 Usage: ccm project glm [global|china]${NC}" >&2
        return 1
    fi

    if ! is_effectively_set "$GLM_API_KEY"; then
        echo -e "${RED}❌ Please configure GLM_API_KEY before writing project settings${NC}" >&2
        return 1
    fi

    local settings_path; settings_path="$(project_settings_path)"
    local settings_dir; settings_dir="$(dirname "$settings_path")"

    # 备份既有非 ccm 管理的设置
    if [[ -f "$settings_path" ]] \
       && ! grep -q '"ccmManaged"[[:space:]]*:[[:space:]]*true' "$settings_path"; then
        backup_project_settings "$settings_path"
    fi

    mkdir -p "$settings_dir"

    # 消费唯一数据源，并把占位 ${GLM_API_KEY} 展开为真实值
    local env_block; env_block="$(get_glm_env_map "$region")"
    env_block="${env_block//\$\{GLM_API_KEY\}/$GLM_API_KEY}"

    # 组装 JSON env 行（key/value 均为安全字符，无需转义）
    local json_lines=""
    while IFS='=' read -r k v; do
        [[ -z "$k" ]] && continue
        json_lines+="    \"${k}\": \"${v}\""'\n'
    done <<< "$env_block"
    # 去掉末尾换行
    json_lines="$(printf '%b' "$json_lines" | sed '/^$/d; $!{s/$/,/}')"

    cat > "$settings_path" <<EOF
{
  "ccmManaged": true,
  "ccmProvider": "glm",
  "ccmRegion": "${region}",
  "env": {
${json_lines}
  }
}
EOF
    chmod 600 "$settings_path"
    echo -e "${GREEN}✅ Wrote project settings for GLM (${region}) at:${NC} $settings_path" >&2
    echo -e "${YELLOW}💡 This overrides user settings (e.g. cc-switch-cli) for this project only.${NC}" >&2
}
```

- [ ] **Step 4: 在 `project_write_settings()` 开头加 glm 委托**

用 Edit，旧串：
```bash
project_write_settings() {
    local provider="$1"
    local region="${2:-global}"

    # Normalize region if needed
```
新串：
```bash
project_write_settings() {
    local provider="$1"
    local region="${2:-global}"

    # GLM 走专属数据源（三模型映射 + 性能参数）
    if [[ "$provider" == "glm" || "$provider" == "glm5" ]]; then
        project_write_glm_settings "$region"
        return $?
    fi

    # Normalize region if needed
```

- [ ] **Step 5: 跑测试，确认通过（绿）**

Run: `bash /tmp/test_project_glm.sh`
Expected: 末行打印 `OK`

- [ ] **Step 6: 提交**

```bash
git add ccm.sh
git commit -m "fix: ccm project glm 产出符合官方文档的 env（三模型+性能参数）"
```

---

## Task 3: 改写 `emit_env_exports` 的 glm case + 补 prelude

**Files:**
- Modify: `ccm.sh` — `emit_env_exports` 的 `"glm"|"glm5")` case（锚点：当前 ccm.sh:2171-2199）
- Modify: `ccm.sh` — `prelude` 两处（锚点：当前 ccm.sh:2069 与 2089）

**Interfaces:**
- Consumes: `get_glm_env_map(region)`（Task 1）、`normalize_region`、`is_effectively_set`、`load_config`、`prelude`
- Produces: `eval "$(ccm env glm china)"` / `eval "$(ccm glm china)"` 导出正确的 9 个环境变量（不含 `ANTHROPIC_MODEL`）

- [ ] **Step 1: 写校验脚本**

创建 `/tmp/test_emit_glm.sh`：
```bash
#!/bin/bash
set -e
export HOME="$(mktemp -d)"
export GLM_API_KEY=test123
cd "$(mktemp -d)"
source /home/clawcrew/claude-code-switch/ccm.sh 2>/dev/null || true

eval "$(emit_env_exports glm china)"
[ "$ANTHROPIC_BASE_URL" = "https://open.bigmodel.cn/api/anthropic" ]
[ "$ANTHROPIC_AUTH_TOKEN" = "test123" ]
[ "$ANTHROPIC_DEFAULT_HAIKU_MODEL" = "glm-4.7" ]
[ "$ANTHROPIC_DEFAULT_SONNET_MODEL" = "glm-5.2[1m]" ]
[ "$ANTHROPIC_DEFAULT_OPUS_MODEL" = "glm-5.2[1m]" ]
[ "$CLAUDE_CODE_SUBAGENT_MODEL" = "glm-5.2[1m]" ]
[ "$CLAUDE_CODE_AUTO_COMPACT_WINDOW" = "1000000" ]
[ "$CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC" = "1" ]
[ "$API_TIMEOUT_MS" = "3000000" ]
[ -z "${ANTHROPIC_MODEL:-}" ]

# prelude 切换其他 provider 后，GLM 专属变量应被清掉
eval "$(emit_env_exports deepseek)"
[ -z "${ANTHROPIC_DEFAULT_HAIKU_MODEL:-}" ]
[ -z "${CLAUDE_CODE_AUTO_COMPACT_WINDOW:-}" ]
echo "OK"
```
`chmod +x /tmp/test_emit_glm.sh`

- [ ] **Step 2: 跑测试，确认失败（红）**

Run: `bash /tmp/test_emit_glm.sh`
Expected: 失败（当前 `ANTHROPIC_DEFAULT_HAIKU_MODEL` 为 `glm-5.2`，且切换 deepseek 后 `CLAUDE_CODE_AUTO_COMPACT_WINDOW` 因 prelude 未含该变量而残留非空——若该变量原本就未设则此项可能不触发，主要失败点在 HAIKU 模型值）

- [ ] **Step 3: 改写 glm case 消费数据源**

用 Edit，旧串：
```bash
            local glm_model="${GLM_MODEL:-glm-5.2}"
            echo "$prelude"
            echo "export ANTHROPIC_BASE_URL='${glm_base_url}'"
            echo "if [ -f \"\$HOME/.ccm_config\" ]; then . \"\$HOME/.ccm_config\" >/dev/null 2>&1; fi"
            echo "export ANTHROPIC_AUTH_TOKEN=\"\${GLM_API_KEY}\""
            echo "export ANTHROPIC_MODEL='${glm_model}'"
            emit_default_models "$glm_model" "$glm_model" "$glm_model"
            emit_subagent_model "$glm_model"
            ;;
```
新串：
```bash
            echo "$prelude"
            echo "if [ -f \"\$HOME/.ccm_config\" ]; then . \"\$HOME/.ccm_config\" >/dev/null 2>&1; fi"
            # 消费唯一数据源：${GLM_API_KEY} 占位在 eval 时由 shell 展开
            local _k _v
            while IFS='=' read -r _k _v; do
                [[ -z "$_k" ]] && continue
                echo "export ${_k}=\"${_v}\""
            done < <(get_glm_env_map "$glm_region")
            ;;
```

- [ ] **Step 4: 删除改写后多余的局部变量声明**

上一步后，原 case 顶部仍有 `local glm_base_url=""` 与 `case "$glm_region" in ... esac` 用于推导 base_url——这些已被数据源取代，需删除避免 shell 未使用告警/混乱。用 Edit，旧串：
```bash
            local glm_base_url=""
            case "$glm_region" in
                "global")
                    glm_base_url="https://api.z.ai/api/anthropic"
                    ;;
                "china")
                    glm_base_url="https://open.bigmodel.cn/api/anthropic"
                    ;;
            esac
```
新串：（删除整段，替换为空行注释）
```bash
            # base_url / 模型映射由 get_glm_env_map 统一提供
```

- [ ] **Step 5: prelude 两处追加 `CLAUDE_CODE_AUTO_COMPACT_WINDOW`**

`prelude` 在 `emit_env_exports`（2089）与 `emit_openrouter_exports`（2069）各一处，内容相同。用 `replace_all: true` 的 Edit：

旧串：
```bash
    local prelude="unset ANTHROPIC_BASE_URL ANTHROPIC_API_URL ANTHROPIC_AUTH_TOKEN ANTHROPIC_API_KEY ANTHROPIC_MODEL ANTHROPIC_SMALL_FAST_MODEL ANTHROPIC_DEFAULT_SONNET_MODEL ANTHROPIC_DEFAULT_OPUS_MODEL ANTHROPIC_DEFAULT_HAIKU_MODEL CLAUDE_CODE_SUBAGENT_MODEL API_TIMEOUT_MS CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC"
```
新串：
```bash
    local prelude="unset ANTHROPIC_BASE_URL ANTHROPIC_API_URL ANTHROPIC_AUTH_TOKEN ANTHROPIC_API_KEY ANTHROPIC_MODEL ANTHROPIC_SMALL_FAST_MODEL ANTHROPIC_DEFAULT_SONNET_MODEL ANTHROPIC_DEFAULT_OPUS_MODEL ANTHROPIC_DEFAULT_HAIKU_MODEL CLAUDE_CODE_SUBAGENT_MODEL CLAUDE_CODE_AUTO_COMPACT_WINDOW API_TIMEOUT_MS CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC"
```

- [ ] **Step 6: 跑测试，确认通过（绿）**

Run: `bash /tmp/test_emit_glm.sh`
Expected: 末行打印 `OK`

- [ ] **Step 7: 提交**

```bash
git add ccm.sh
git commit -m "fix: emit_env_exports 的 GLM 分支消费唯一数据源，prelude 清理 AUTO_COMPACT_WINDOW"
```

---

## Task 4: 新增 `user_write_glm_settings()` + 委托 + `--force` + cc-switch-cli 警告

**Files:**
- Modify: `ccm.sh` — 新增 `user_write_glm_settings(region, force)`（插入在 `user_write_settings()` 之前，锚点：`user_write_settings() {`，当前 ccm.sh:696）
- Modify: `ccm.sh` — `user_write_settings()` 开头加 glm 委托
- Modify: `ccm.sh` — `user` 路由解析 `--force`（锚点：当前 ccm.sh:2453-2458）
- Modify: `ccm.sh` — `user_show_usage()` 帮助文本（锚点：当前 ccm.sh:851-871）

**Interfaces:**
- Consumes: `get_glm_env_map`、`user_settings_path`、`backup_user_settings`、`is_effectively_set`、`normalize_region`
- Produces: `ccm user glm [global|china] [--force]`；默认在 `~/.claude/settings.json` 非 ccmManaged 时拦下并提示，`--force` 覆盖且先备份

- [ ] **Step 1: 写校验脚本**

创建 `/tmp/test_user_glm.sh`：
```bash
#!/bin/bash
set -e
export HOME="$(mktemp -d)"
export GLM_API_KEY=test123
mkdir -p "$HOME/.claude"
cd "$(mktemp -d)"
source /home/clawcrew/claude-code-switch/ccm.sh 2>/dev/null || true

# 预置「外部管理」的全局配置（无 ccmManaged 标记，模拟 cc-switch-cli）
echo '{"env":{"ANTHROPIC_BASE_URL":"https://api.anthropic.com"}}' > "$HOME/.claude/settings.json"

# 1) 默认应被拦下，return 1
if user_write_glm_settings china 0 >/tmp/out1 2>&1; then
    echo "FAIL: 应被拦下"; exit 1
fi
grep -q 'cc-switch-cli' /tmp/out1
# 全局文件未被破坏
jq -e '.env.ANTHROPIC_BASE_URL == "https://api.anthropic.com"' "$HOME/.claude/settings.json"

# 2) --force 覆盖且产生备份
user_write_glm_settings china 1 >/tmp/out2 2>&1
jq -e '.env.ANTHROPIC_AUTH_TOKEN == "test123"' "$HOME/.claude/settings.json"
jq -e '.env.ANTHROPIC_DEFAULT_HAIKU_MODEL == "glm-4.7"' "$HOME/.claude/settings.json"
jq -e '.ccmManaged == true' "$HOME/.claude/settings.json"
ls "$HOME/.claude/settings.json.bak."* >/dev/null
echo "OK"
```
`chmod +x /tmp/test_user_glm.sh`

> 注：`backup_user_settings` 产生的备份后缀格式以代码现状为准（`${path}.bak.${ts}`）；若实际不同，调整断言。

- [ ] **Step 2: 跑测试，确认失败（红）**

Run: `bash /tmp/test_user_glm.sh`
Expected: 失败（`user_write_glm_settings` 未定义）

- [ ] **Step 3: 新增 `user_write_glm_settings()`**

用 Edit，在 `user_write_settings() {` 之前插入。旧串（锚点）：
```bash
user_write_settings() {
    local provider="$1"
    local region="${2:-global}"
```
新串：
```bash
# GLM 用户级写入：消费唯一数据源写 ~/.claude/settings.json。
# force=0 且全局文件非 ccmManaged 时拦下（兼容 cc-switch-cli 独占全局）。
user_write_glm_settings() {
    local region="${1:-global}"
    local force="${2:-0}"
    local normalized
    if ! normalized="$(normalize_region "$region")"; then
        echo -e "${RED}❌ Invalid region: $region${NC}" >&2
        echo -e "${YELLOW}💡 Usage: ccm user glm [global|china] [--force]${NC}" >&2
        return 1
    fi
    region="$normalized"

    if ! is_effectively_set "$GLM_API_KEY"; then
        echo -e "${RED}❌ Please configure GLM_API_KEY${NC}" >&2
        return 1
    fi

    local settings_path; settings_path="$(user_settings_path)"
    local settings_dir; settings_dir="$(dirname "$settings_path")"

    # cc-switch-cli 兼容：全局文件存在且非 ccm 管理时拦截
    if [[ -f "$settings_path" ]] \
       && ! grep -q '"ccmManaged"[[:space:]]*:[[:space:]]*true' "$settings_path" 2>/dev/null; then
        if [[ "$force" != "1" ]]; then
            echo -e "${YELLOW}⚠️  ~/.claude/settings.json 已由外部工具管理（可能是 cc-switch-cli）。${NC}" >&2
            echo -e "${YELLOW}   建议改用 'ccm project glm' 仅作用于当前项目，全局交给 cc-switch-cli。${NC}" >&2
            echo -e "${YELLOW}   如确需 ccm 接管全局，请加 --force 重试（会先备份原文件）。${NC}" >&2
            return 1
        fi
        backup_user_settings "$settings_path"
    fi

    mkdir -p "$settings_dir"

    local env_block; env_block="$(get_glm_env_map "$region")"
    env_block="${env_block//\$\{GLM_API_KEY\}/$GLM_API_KEY}"

    if command -v python3 >/dev/null 2>&1; then
        # 用 python 把 env_block 编为 JSON，经环境变量传入，规避 heredoc 引号转义
        export _CCM_GLM_ENV_JSON _CCM_GLM_SETTINGS_PATH _CCM_GLM_REGION
        _CCM_GLM_ENV_JSON="$(printf '%s\n' "$env_block" | python3 -c 'import sys,json; print(json.dumps(dict(l.split("=",1) for l in sys.stdin if "=" in l)))')"
        _CCM_GLM_SETTINGS_PATH="$settings_path"
        _CCM_GLM_REGION="$region"
        python3 << 'PYTHON_EOF'
import json, os
p = os.environ['_CCM_GLM_SETTINGS_PATH']
existing = {}
if os.path.exists(p):
    try:
        with open(p) as f:
            existing = json.load(f)
    except Exception:
        existing = {}
existing['ccmManaged'] = True
existing['ccmProvider'] = 'glm'
existing['ccmRegion'] = os.environ['_CCM_GLM_REGION']
existing['env'] = json.loads(os.environ['_CCM_GLM_ENV_JSON'])
with open(p, 'w') as f:
    json.dump(existing, f, indent=2)
os.chmod(p, 0o600)
PYTHON_EOF
        unset _CCM_GLM_ENV_JSON _CCM_GLM_SETTINGS_PATH _CCM_GLM_REGION
    else
        # 回退：纯 heredoc 重写（会丢失既有非 env 字段）
        local json_lines=""
        while IFS='=' read -r k v; do
            [[ -z "$k" ]] && continue
            json_lines+="    \"${k}\": \"${v}\""'\n'
        done <<< "$env_block"
        json_lines="$(printf '%b' "$json_lines" | sed '/^$/d; $!{s/$/,/}')"
        cat > "$settings_path" <<EOF
{
  "ccmManaged": true,
  "ccmProvider": "glm",
  "ccmRegion": "${region}",
  "env": {
${json_lines}
  }
}
EOF
        chmod 600 "$settings_path"
    fi

    echo -e "${GREEN}✅ Wrote user-level settings for GLM (${region})${NC}" >&2
    echo -e "${BLUE}   File: $settings_path${NC}" >&2
    echo -e "${YELLOW}💡 全局配置建议由 cc-switch-cli 管理；项目级请用 'ccm project glm'。${NC}" >&2
}

user_write_settings() {
    local provider="$1"
    local region="${2:-global}"
```

> 说明：Step 3 用环境变量把 `env_block`（经 python 转 JSON）与 `settings_path`/`region` 传入 python，规避了 heredoc 内引号转义问题；python 走 merge 保留既有非 env 顶层字段（如 `hasCompletedOnboarding`）。python3 不存在时回退到 heredoc 重写。

- [ ] **Step 4: `user_write_settings()` 开头加 glm 委托**

用 Edit，旧串（Task 3 已把上一步插到此处之前，这里再在函数体开头加委托；锚点用 `user_write_settings` 内紧随其后的唯一行）：
```bash
    # Normalize region if needed
    if [[ "$provider" =~ ^(glm|kimi|qwen|minimax)$ ]]; then
        local normalized_region
        if ! normalized_region="$(normalize_region "$region")"; then
            echo -e "${RED}❌ Invalid region: $region${NC}" >&2
            echo -e "${YELLOW}💡 Usage: ccm user $provider [global|china]${NC}" >&2
            return 1
        fi
        region="$normalized_region"
    fi
```
新串：
```bash
    # GLM 走专属数据源 + cc-switch-cli 兼容检测
    if [[ "$provider" == "glm" || "$provider" == "glm5" ]]; then
        local _user_force="0"
        [[ "${3:-}" == "--force" ]] && _user_force="1"
        user_write_glm_settings "$region" "$_user_force"
        return $?
    fi

    # Normalize region if needed
    if [[ "$provider" =~ ^(glm|kimi|qwen|minimax)$ ]]; then
        local normalized_region
        if ! normalized_region="$(normalize_region "$region")"; then
            echo -e "${RED}❌ Invalid region: $region${NC}" >&2
            echo -e "${YELLOW}💡 Usage: ccm user $provider [global|china]${NC}" >&2
            return 1
        fi
        region="$normalized_region"
    fi
```

- [ ] **Step 5: `user` 路由解析 `--force` 并透传第 3 位置**

用 Edit，旧串：
```bash
                "glm"|"deepseek"|"ds"|"kimi"|"kimi2"|"qwen"|"minimax"|"mm"|"seed"|"doubao"|"stepfun"|"claude"|"sonnet"|"s")
                    user_write_settings "$user_action" "${2:-}"
                    ;;
```
新串：
```bash
                "glm"|"deepseek"|"ds"|"kimi"|"kimi2"|"qwen"|"minimax"|"mm"|"seed"|"doubao"|"stepfun"|"claude"|"sonnet"|"s")
                    # --force 可出现在任意位置，剥离后透传 provider/region
                    local _ua_args=()
                    for _a in "$@"; do
                        [[ "$_a" == "--force" ]] && continue
                        _ua_args+=("$_a")
                    done
                    # _ua_args[0]=provider(_user_action 已是)，此处用剩余 region
                    user_write_settings "$user_action" "${_ua_args[1]:-}" "${_ua_force:-}"
                    ;;
```
> 注意：`shift` 后 `$@` 已不含字面 "user"，剩余为 provider/region/`--force`。为简单稳妥，实现者也可改为：在 `shift` 后先扫描 `--force` 设 `local _ua_force=1`，再用 ` "${2:-}"` 作为 region、第三参传 `--force`。**以测试通过为准**。等价简化写法：
```bash
                "glm"|"deepseek"|"ds"|"kimi"|"kimi2"|"qwen"|"minimax"|"mm"|"seed"|"doubao"|"stepfun"|"claude"|"sonnet"|"s")
                    local _ua_force=""
                    for _a in "$@"; do [[ "$_a" == "--force" ]] && _ua_force="--force"; done
                    user_write_settings "$user_action" "${2:-}" "$_ua_force"
                    ;;
```
（二选一，推荐简化写法。）

- [ ] **Step 6: 更新 `user_show_usage()` 帮助文本**

用 Edit，旧串：
```bash
    echo "Usage:" >&2
    echo "  ccm user <provider> [region]   - Write provider settings to user-level" >&2
    echo "  ccm user reset                  - Remove ccm settings, restore env var control" >&2
```
新串：
```bash
    echo "Usage:" >&2
    echo "  ccm user <provider> [region] [--force]   - Write provider settings to user-level" >&2
    echo "  ccm user reset                            - Remove ccm settings, restore env var control" >&2
    echo "" >&2
    echo "Note: 若 ~/.claude/settings.json 已由 cc-switch-cli 等外部工具管理，" >&2
    echo "      默认会拦下；加 --force 覆盖（会先备份）。建议全局交给 cc-switch-cli，" >&2
    echo "      项目级用 'ccm project <provider>'。" >&2
```
并改 Examples 行（旧）`echo "  ccm user glm global   # Use GLM globally" >&2` →（新）
```bash
    echo "  ccm user glm global          # Use GLM globally (会被 cc-switch-cli 检测拦下)" >&2
    echo "  ccm user glm china --force   # 强制覆盖全局（先备份）" >&2
```

- [ ] **Step 7: 跑测试，确认通过（绿）**

Run: `bash /tmp/test_user_glm.sh`
Expected: 末行打印 `OK`

- [ ] **Step 8: 提交**

```bash
git add ccm.sh
git commit -m "feat: ccm user glm 加 cc-switch-cli 兼容警告与 --force，消费 GLM 数据源"
```

---

## Task 5: 文档同步（README / README_CN / CHANGELOG）

**Files:**
- Modify: `README.md`、`README_CN.md` — GLM 配置说明 + cc-switch-cli 分工
- Modify: `CHANGELOG.md` — 本次变更条目

**Interfaces:** 无（纯文档）

- [ ] **Step 1: CHANGELOG 追加条目**

在 `CHANGELOG.md` 顶部（最新条目区）追加：
```markdown
## [Unreleased]
### Fixed
- `ccm project glm` / `ccm user glm` / `ccm glm` 产出符合智谱官方文档的 env：
  HAIKU=`glm-4.7`，SONNET/OPUS=`glm-5.2[1m]`，移除多余的 `ANTHROPIC_MODEL`，
  新增 `CLAUDE_CODE_AUTO_COMPACT_WINDOW`/`CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC`/`API_TIMEOUT_MS`。
- GLM 配置收敛到唯一数据源 `get_glm_env_map`，消除三处重复。

### Added
- `ccm user` 兼容 cc-switch-cli：检测到 `~/.claude/settings.json` 非本工具管理时默认拦下，
  需 `--force` 覆盖（先备份）。全局与项目级配置分工明确。
```

- [ ] **Step 2: README_CN / README 的 GLM 配置小节更新**

在 GLM 相关小节补一段「与 cc-switch-cli 分工」说明（中英各一份，措辞与既有风格一致）：
```markdown
> **与 cc-switch-cli 分工**：建议全局配置（`~/.claude/settings.json`）交给 cc-switch-cli 管理，
> 项目级覆盖（`.claude/settings.local.json`）用 `ccm project glm [global|china]`。
> `ccm user glm` 若检测到全局已被外部工具接管，默认拦下，加 `--force` 可强制覆盖。
```
同时把 GLM 示例的模型名更新为 `glm-5.2[1m]`（haiku `glm-4.7`）。

- [ ] **Step 3: 校验文档无残留旧模型名（针对 GLM 小节）**

Run: `grep -nE 'GLM.*glm-5\.2([^[]|$)|cc-switch' README.md README_CN.md CHANGELOG.md`
Expected: 仅本次新增的 cc-switch-cli 说明命中；GLM 模型示例均带 `[1m]`（无裸 `glm-5.2` 误标，`ccm status` 展示行除外）。

- [ ] **Step 4: 提交**

```bash
git add README.md README_CN.md CHANGELOG.md
git commit -m "docs: 更新 GLM 配置说明与 cc-switch-cli 分工"
```

---

## Task 6: 端到端场景验证 + PR

**Files:** 无（验证 + git）

- [ ] **Step 1: 场景 1 验证（project 永远 zhipu，其他用全局）**

```bash
export HOME="$(mktemp -d)"; export GLM_API_KEY=test123
# 模拟 cc-switch-cli 管的全局 claude
mkdir -p "$HOME/.claude"
echo '{"env":{"ANTHROPIC_BASE_URL":"https://api.anthropic.com"}}' > "$HOME/.claude/settings.json"
proj1="$(mktemp -d)"; cd "$proj1"
source /home/clawcrew/claude-code-switch/ccm.sh 2>/dev/null || true
project_write_glm_settings china
jq -e '.env.ANTHROPIC_BASE_URL == "https://open.bigmodel.cn/api/anthropic"' .claude/settings.local.json
# 其他项目目录无 local，仅全局生效
proj2="$(mktemp -d)"; cd "$proj2"
[ ! -f .claude/settings.local.json ]
echo "scenario1 OK"
```
Expected: `scenario1 OK`

- [ ] **Step 2: 场景 3 验证（全局 zhipu，project2 claude 覆盖）**

```bash
export HOME="$(mktemp -d)"; export GLM_API_KEY=test123
mkdir -p "$HOME/.claude"
# 全局 zhipu（由 cc-switch-cli 管）
echo '{"env":{"ANTHROPIC_BASE_URL":"https://open.bigmodel.cn/api/anthropic","ANTHROPIC_DEFAULT_SONNET_MODEL":"glm-5.2[1m]"}}' > "$HOME/.claude/settings.json"
proj2="$(mktemp -d)"; cd "$proj2"
source /home/clawcrew/claude-code-switch/ccm.sh 2>/dev/null || true
project_write_settings claude
jq -e '.env.ANTHROPIC_BASE_URL == "https://api.anthropic.com/"' .claude/settings.local.json
echo "scenario3 OK"
```
Expected: `scenario3 OK`

- [ ] **Step 3: 回归（非 GLM provider 不受影响）**

```bash
export HOME="$(mktemp -d)"; export KIMI_API_KEY=test123
cd "$(mktemp -d)"; source /home/clawcrew/claude-code-switch/ccm.sh 2>/dev/null || true
eval "$(emit_env_exports kimi china)"
[ "$ANTHROPIC_BASE_URL" = "https://api.moonshot.cn/anthropic" ]
[ "$ANTHROPIC_MODEL" = "kimi-k2.5" ]   # 非 GLM provider 仍保留 ANTHROPIC_MODEL
echo "regression OK"
```
Expected: `regression OK`（确认 GLM 改动未波及 kimi）

- [ ] **Step 4: 推送并提 PR**

```bash
git push -u origin feat/glm-config-ccswitch-compat
gh pr create --title "fix: GLM 配置对齐官方文档 + 兼容 cc-switch-cli 全局分工" \
  --body "$(cat <<'EOF'
## 变更
- GLM env 对齐智谱官方文档（HAIKU=glm-4.7，SONNET/OPUS=glm-5.2[1m]，移除多余 ANTHROPIC_MODEL，加 3 个性能参数）
- 新增 get_glm_env_map 作为 GLM env 唯一数据源，project/user/emit 三处消费（DRY）
- ccm user 检测外部工具（cc-switch-cli）接管全局时默认拦下，需 --force 覆盖（先备份）
- prelude 补全 CLAUDE_CODE_AUTO_COMPACT_WINDOW 清理
- 文档同步

## 验证
端到端场景 1/3 + 回归（kimi）均通过（见 plan Task 6）。

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

- [ ] **Step 5: 清理临时测试脚本**

```bash
rm -f /tmp/test_glm_env_map.sh /tmp/test_project_glm.sh /tmp/test_emit_glm.sh /tmp/test_user_glm.sh
```

---

## Self-Review 结论

- **Spec 覆盖**：spec §4.2 env 结构 → Task 1/2/3/4；§5.5 cc-switch-cli 警告 → Task 4；§5.6 prelude → Task 3 Step 5；§6 三场景 → Task 6；§8 改动清单 → 全部 task 覆盖。
- **占位符**：Task 4 Step 3 的 python 注入段标注「允许等价改写，以测试通过为准」，给出了实现自由度但非空洞 TODO；其余步骤均有完整代码。
- **类型/命名一致**：`get_glm_env_map`、`project_write_glm_settings`、`user_write_glm_settings`、`--force`/`force=1` 在各 task 间命名一致。
- **测试隔离**：所有测试用临时 HOME + 临时 CWD，避免 `load_config` 创建真实 `~/.ccm_config`。
