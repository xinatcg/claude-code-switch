# GLM 配置修正 与 cc-switch-cli 兼容 — 设计文档

- 日期：2026-06-30
- 状态：待主公复审
- 范围：`ccm.sh`（核心脚本）、帮助文本、README/CHANGELOG（文档同步）
- 实施流程：本 spec 获批 → writing-plans 出实施计划 → 开分支 → 实现 → PR

---

## 1. 背景与问题

### 1.1 GLM 项目级配置偏离官方文档
`ccm project glm` 经由通用函数 `project_write_settings()`（ccm.sh:479）写入 `.claude/settings.local.json`，但产物与智谱 GLM 最新官方文档不一致：

| 字段 | 当前 ccm 产物 | 官方文档要求 |
|---|---|---|
| `ANTHROPIC_DEFAULT_HAIKU_MODEL` | `glm-5.2` | `glm-4.7` |
| `ANTHROPIC_DEFAULT_SONNET_MODEL` | `glm-5.2` | `glm-5.2[1m]` |
| `ANTHROPIC_DEFAULT_OPUS_MODEL` | `glm-5.2` | `glm-5.2[1m]` |
| `ANTHROPIC_MODEL` | `glm-5.2`（多写） | （文档未列，应移除） |
| `CLAUDE_CODE_AUTO_COMPACT_WINDOW` | 缺 | `1000000` |
| `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC` | 缺 | `1` |
| `API_TIMEOUT_MS` | 缺 | `3000000` |

同样的过时映射散布在全链路：`emit_env_exports`（ccm.sh:2191）、`get_provider_config`（ccm.sh:599）、`user_write_settings`（ccm.sh:763）。

### 1.2 cc-switch-cli 协作缺位
ccm 自带 `ccm user <provider>` 写入用户全局 `~/.claude/settings.json`，与外部工具 **cc-switch-cli** 抢占同一文件，存在互相覆盖风险。期望分工：
- **cc-switch-cli** 独占全局（`~/.claude/settings.json`）
- **ccm** 只管项目级（`.claude/settings.local.json`）

---

## 2. 目标 / 非目标

### 目标
1. GLM 在 project / user / 全局导出（`emit_env_exports`）三个层级均产出符合官方文档的 env。
2. GLM env 的三模型映射 + 性能参数有**唯一数据源**，消除三处重复。
3. `ccm user` 在 cc-switch-cli 已接管全局时给出明确警告，需 `--force` 才覆盖；`ccm project` 保持纯项目级，天然兼容。
4. 主公给出的三个使用场景全部跑通。

### 非目标
- 不重构其他 provider（kimi/qwen/deepseek…）的配置与写入逻辑。
- 不为其他 provider 添加 GLM 专属的 3 个性能参数。
- 不接管 OAuth（Claude Pro 订阅）切换——那是 cc-switch-cli 的职责。
- 不实现自动 fallback。

---

## 3. 现状分析（关键代码定位）

| 函数 | 行号 | 现状 |
|---|---|---|
| `project_settings_path()` | 397 | `$PWD/.claude/settings.local.json` |
| `project_write_glm_settings()` | 408 | 旧 GLM 专属函数，已被通用版取代但仍残留 |
| `project_write_settings()` | 479 | 通用写入，单 model 模板，GLM 走此路径 |
| `get_provider_config()` | 585 | 返回 `base_url\|model\|token_var`，单 model |
| `user_write_settings()` | 696 | 通用写入全局，python 合并/heredoc 回退 |
| `emit_env_exports()` glm case | 2171 | 手工 echo，三模型同值 |
| `USER_SETTINGS_PATH` | 571 | `$HOME/.claude/settings.json` |
| `ccm user` 路由 | 2453 | 无 cc-switch-cli 检测 |

**根因**：`get_provider_config()` 的「单 model」表达力无法承载 GLM 的「haiku≠sonnet + 性能参数」。

---

## 4. 设计方案（方案 C：GLM 专属辅助函数 + 唯一数据源）

### 4.1 核心思想
新增 GLM env 的**唯一数据源函数** `get_glm_env_map()`，三处消费：
- `emit_env_exports` 的 glm case → 转 `export` 行
- `project_write_settings` 的 glm 分支 → 写 `.claude/settings.local.json`
- `user_write_settings` 的 glm 分支 → 写 `~/.claude/settings.json`（带 cc-switch-cli 警告）

GLM 配置定义集中，其他 provider 的通用路径零改动。

### 4.2 GLM env 最终结构（两 region 统一）

```jsonc
// .claude/settings.local.json (GLM, region=china)
"env": {
  "ANTHROPIC_BASE_URL": "https://open.bigmodel.cn/api/anthropic",
  "ANTHROPIC_AUTH_TOKEN": "<GLM_API_KEY>",
  "ANTHROPIC_DEFAULT_HAIKU_MODEL": "glm-4.7",
  "ANTHROPIC_DEFAULT_SONNET_MODEL": "glm-5.2[1m]",
  "ANTHROPIC_DEFAULT_OPUS_MODEL": "glm-5.2[1m]",
  "CLAUDE_CODE_SUBAGENT_MODEL": "glm-5.2[1m]",
  "CLAUDE_CODE_AUTO_COMPACT_WINDOW": "1000000",
  "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC": "1",
  "API_TIMEOUT_MS": "3000000"
}
```

- 两 region 仅 `ANTHROPIC_BASE_URL` 不同：
  - `global` → `https://api.z.ai/api/anthropic`
  - `china` → `https://open.bigmodel.cn/api/anthropic`
- 模型映射两 region 一致：`HAIKU=glm-4.7`，`SONNET/OPUS/SUBAGENT=glm-5.2[1m]`
- **移除** `ANTHROPIC_MODEL`（DEFAULT_* 已充分覆盖，贴合官方文档）
- `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC` 写字面量 `"1"`（与官方一致，JSON 字符串）

---

## 5. 详细设计

### 5.1 `get_glm_env_map()` — GLM env 唯一数据源

**职责**：给定 region，输出 GLM 的 env 键值对，格式为稳定的逐行 `KEY=value`（value 原样，不含换行）。token 占位使用字面量 `${GLM_API_KEY}`，由调用方在最终写入/export 时解析。

**伪代码**：
```bash
# 入参：region（global|china，已规范化）
# 出参（stdout）：逐行 "KEY=value"，调用方按场景消费
get_glm_env_map() {
    local region="$1"
    local base_url
    case "$region" in
        global) base_url="https://api.z.ai/api/anthropic" ;;
        china)  base_url="https://open.bigmodel.cn/api/anthropic" ;;
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
```

> 设计要点：token 用占位符 `${GLM_API_KEY}`，避免在数据源函数里展开密钥，使该函数可同时服务「写文件（需真实值）」与「emit export（也需真实值，但通过 shell 展开）」两种场景，且不把密钥塞进函数返回值。

### 5.2 `emit_env_exports` 的 glm case 改造

```bash
"glm"|"glm5")
    if ! is_effectively_set "$GLM_API_KEY"; then echo ...; return 1; fi
    local glm_region
    glm_region="$(normalize_region "$arg")" || { echo ...; return 1; }
    echo "$prelude"
    echo "if [ -f \"\$HOME/.ccm_config\" ]; then . \"\$HOME/.ccm_config\" >/dev/null 2>&1; fi"
    # 消费唯一数据源：值内 ${GLM_API_KEY} 由 shell 在 eval 时展开
    while IFS='=' read -r k v; do
        echo "export ${k}=\"${v}\""
    done < <(get_glm_env_map "$glm_region")
    ;;
```

> 说明：`ANTHROPIC_AUTH_TOKEN` 行输出 `export ANTHROPIC_AUTH_TOKEN="${GLM_API_KEY}"`，与现有其他 provider 写法一致，由调用方 `eval` 时展开。`prelude` 已 `unset` 这 9 个变量中的 8 个，需确认 `prelude` 也 `unset CLAUDE_CODE_AUTO_COMPACT_WINDOW`（当前未列入，见 §5.6）。

### 5.3 `project_write_settings` 的 glm 分支

在 `project_write_settings()` 开头加 glm 特例：
```bash
if [[ "$provider" == "glm" || "$provider" == "glm5" ]]; then
    project_write_glm_settings "$region"   # 复用命名，但内部改为消费 get_glm_env_map
    return $?
fi
```
`project_write_glm_settings()` 改写为：
- 校验 `GLM_API_KEY`、规范化 region
- 备份既有非 ccmManaged 文件
- 用 python（优先）或 heredoc 写 `.claude/settings.local.json`：
  ```jsonc
  {
    "ccmManaged": true,
    "ccmProvider": "glm",
    "ccmRegion": "<region>",
    "env": { ...get_glm_env_map 展开，token 替换为真实 $GLM_API_KEY... }
  }
  ```
- `chmod 600`，输出成功提示（沿用现有多行提示格式）

### 5.4 `user_write_settings` 的 glm 分支 + cc-switch-cli 警告

同样在 `user_write_settings()` 开头加 glm 特例委托 `user_write_glm_settings()`，写 `~/.claude/settings.json`。**额外**在写入前执行 cc-switch-cli 兼容检测（见 §5.5）。

### 5.5 `ccm user` cc-switch-cli 兼容检测

**策略**：保守——不依赖 cc-switch-cli 的特定标记，凡 `~/.claude/settings.json` 存在且**非 ccmManaged** 即视为外部管理（可能是 cc-switch-cli）。

```bash
# user_write_glm_settings / 通用 user_write_settings 写入前
local global_settings; global_settings="$(user_settings_path)"
if [[ -f "$global_settings" ]] \
   && ! grep -q '"ccmManaged"[[:space:]]*:[[:space:]]*true' "$global_settings"; then
    if [[ "$force" != "1" ]]; then
        echo -e "${YELLOW}⚠️ ~/.claude/settings.json 已由外部工具管理（可能是 cc-switch-cli）。${NC}" >&2
        echo -e "${YELLOW}   建议改用 'ccm project glm' 仅作用于当前项目。${NC}" >&2
        echo -e "${YELLOW}   如确需 ccm 接管全局，请加 --force 重试。${NC}" >&2
        return 1
    fi
    backup_user_settings "$global_settings"   # --force 时先备份再覆盖
fi
```

`--force` 解析：在 `ccm user` 路由（ccm.sh:2453）识别 `--force` 标志，置 `force=1` 后传给 `user_write_settings`。

> 此检测对所有 `ccm user <provider>` 通用（不止 GLM），与"全局交给 cc-switch-cli"的分工一致，无需额外成本。

### 5.6 `prelude` 与 unset 清单补齐
`emit_env_exports` 的 `prelude`（ccm.sh:2089、2069）需追加 `CLAUDE_CODE_AUTO_COMPACT_WINDOW`，确保切换 provider 时清掉 GLM 残留的该变量。其余 8 个变量已在清单内。

### 5.7 帮助文本与文档同步
- `show_help`（ccm.sh:1788 区）：GLM 模型描述更新为 `glm-5.2[1m] / glm-4.7 (haiku)`。
- `ccm project` / `ccm user` 用法（project_show_usage / user_show_usage）：GLM 行补"含 1M 上下文与稳定性参数"。
- README / README_CN / CHANGELOG：记录 GLM 配置更新 + cc-switch-cli 兼容说明。

---

## 6. 三个使用场景验证（设计层面）

> 前提：Claude Code 的 `env` 为分层合并，`.claude/settings.local.json`（项目本地）覆盖 `~/.claude/settings.json`（用户全局）。

**场景 1**：project1 永远 zhipu，其他用全局默认
- `ccm project glm china`（在 project1 内）→ 写 project1 的 `settings.local.json`
- 其他项目：无 local，回退 cc-switch-cli 管的全局 ✅

**场景 2**：全局 = claude 官方订阅；project1 = zhipu
- cc-switch-cli 设全局 claude；`ccm project glm china` 设 project1
- project1 内 local 的 GLM env 覆盖全局 claude env ✅

**场景 3**：全局 = zhipu；project1 = zhipu；project2 = claude 官方
- cc-switch-cli 设全局 zhipu；`ccm project glm china`（project1，可与全局一致）；`ccm project claude`（project2）
- project2 local 写 `ANTHROPIC_BASE_URL=https://api.anthropic.com/`（claude 官方，无 token，依赖订阅登录态）覆盖全局 zhipu ✅
  > 注：项目级 claude 依赖用户已有的 OAuth 登录态；env 层面只把 base_url 指回官方，订阅鉴权由 Claude Code 自身处理，属预期行为。

---

## 7. 测试策略（手动 + 结构校验）

无自动化测试框架（纯 Bash 脚本），采用结构化手测脚本：

1. **GLM env 正确性**
   - `eval "$(ccm env glm china)"; env | grep ANTHROPIC` → 验证 9 个变量值，含 `[1m]`、3 性能参数，无 `ANTHROPIC_MODEL`。
   - `eval "$(ccm env glm global)"` → 仅 base_url 为 z.ai，其余同。
2. **project 写入**
   - 临时目录 `cd $(mktemp -d)`，`ccm project glm china` → `jq .env .claude/settings.local.json` 比对 §4.2 结构。
   - `ccm project reset` → 文件删除，回退全局。
3. **user 写入 + 警告**
   - 预置 `~/.claude/settings.json`（无 ccmManaged）→ `ccm user glm china` 应警告并 return 1。
   - 加 `--force` → 写入成功且备份产生。
4. **cc-switch-cli 兼容**：模拟全局非 ccmManaged，跑场景 1/2/3 的 env 合并，确认 local 覆盖 user。
5. **回归**：`ccm kimi china` / `ccm qwen` / `ccm deepseek` 产物与改动前一致（非 GLM provider 零影响）。

测试用例清单将写入实施计划。

---

## 8. 改动清单

| 文件 | 改动 |
|---|---|
| `ccm.sh` | 新增 `get_glm_env_map()`；改写 `project_write_glm_settings()`、`emit_env_exports` glm case；新增 `user_write_glm_settings()`；`project_write_settings` / `user_write_settings` 加 glm 委托；`user` 路由加 `--force` 与 cc-switch-cli 检测；`prelude` 追加 `CLAUDE_CODE_AUTO_COMPACT_WINDOW`；帮助文本 |
| `README.md` / `README_CN.md` | GLM 配置说明、cc-switch-cli 分工说明 |
| `CHANGELOG.md` | 本次变更条目 |

非改动：其他 provider 的 `get_provider_config` / 写入分支 / emit 分支。

---

## 9. 风险与回滚

| 风险 | 缓解 |
|---|---|
| `[1m]` 后缀在某 region 不被识别 | 两 region 均为智谱官方端点，模型体系统一；手测场景验证 |
| 移除 `ANTHROPIC_MODEL` 影响老用户 | 官方文档未列该项，`DEFAULT_*` 已覆盖；属修正而非破坏 |
| `ccm user --force` 误覆盖 cc-switch-cli 全局 | 默认拦截 + 强制备份机制；提示引导用 project |
| GLM 配置三处消费不一致 | 唯一数据源 `get_glm_env_map`，单一出处 |

**回滚**：改动集中在 GLM 相关函数与少量路由，git revert 单个 PR 即可还原。

---

## 10. 开放问题（spec 复审时确认）

1. `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC` 写 `"1"`（字符串）还是 `1`（数字）？→ 当前按官方文档写 `"1"`。
2. 是否需要在 `ccm status` 中展示 cc-switch-cli 接管状态？→ 非目标，暂不加。
