# CCM 测试方案

零依赖纯 Bash 测试套件，目标：在人工安装验证之前，尽可能把问题挡在本地。

## 运行方式

```bash
bash tests/run_tests.sh          # 全量（语法检查 + 两个套件）
bash tests/test_providers.sh     # 仅 provider 套件
bash tests/test_install.sh       # 仅安装套件
```

任何失败即非零退出码，可直接接入 CI（建议 ubuntu + macos 矩阵）。

## 套件一：Provider 测试（`test_providers.sh`）

所有测试在隔离的临时 `HOME` 下运行，不污染真实 `~/.ccm_config`；`ccc` 测试用 stub `claude` 捕获最终环境变量。

### OpenAI（sub2API 网关）新功能

| 用例 | 验证点 |
|---|---|
| 未配置 key | 非零退出 + 提示指向 `OPENAI_API_KEY` |
| 导出全集 | BASE_URL / AUTH_TOKEN（引用变量不泄密）/ MODEL / SONNET / OPUS / HAIKU / SUBAGENT / prelude 清理 |
| eval 端到端 | 真实 eval 后各变量值正确、token 正确展开 |
| URL 归一化 | 尾部 `/`、`/v1`、`/v1/` 后缀剥离；https 保留；缺省 `http://localhost:8080` |
| 模型覆盖 | `OPENAI_MODEL` 全槽位生效 |
| 别名 | `gpt` / `gpt6` 与 `openai` 输出完全一致 |
| `ccm env openai` | env 入口可用 |
| help | 帮助文本包含 openai |
| `ccc openai` | stub claude 收到 gpt-6-astra + 网关地址 + token |

### OpenRouter GLM 升级

- `ccm open glm` → `z-ai/glm-5.3`，且不再出现 `z-ai/glm-5.2`
- `ccm open glm-5.3` 别名可用

### 既有 provider 回归守护

- deepseek / glm(china) / minimax(global) 的 BASE_URL 与模型映射不变
- `ccm status` 冒烟
- **`ccc deepseek` 非 bailian 路径回归**：守护 `bailian_variant` 未初始化导致 `set -u` 崩溃的既有 bug（本次测试抓获并修复）

## 套件二：平台安装测试（`test_install.sh`）

全部在隔离 `HOME` + `XDG_DATA_HOME` / `XDG_BIN_HOME` 沙箱内执行，不触碰真实系统。

### Linux / macOS 双平台覆盖策略

| 平台差异点 | 覆盖方式 |
|---|---|
| `find_user_bin_dir`：XDG_BIN_HOME > `~/.local/bin` > `~/bin` | 直接断言三场景（macOS 与 Linux 通用逻辑） |
| `find_system_bin_dir`：macOS brew 优先 | **stub `brew` 命令**（假 `brew --prefix`）模拟 macOS；无 brew 时断言回落 `/usr/local/bin`（Linux） |
| `detect_rc_files`：zshrc/bashrc/profile 组合 | 预置各类 rc 文件断言识别顺序（macOS 主场景 `.zshrc` 优先） |
| rc 注入块语法 | 提取注入块做 `bash -n`；本机装有 zsh 时追加 `zsh -n`（macOS 默认 shell 兼容） |
| sudo 分支 | `needs_sudo` 仅在目录不可写时触发；沙箱内目录可写，不触发真 sudo |

### 安装行为

- **user 模式**：data 目录（ccm.sh + lang）就位、bin wrapper 可执行、rc 注入、注入块含 openai/gpt6、重复安装幂等（块不重复）
- **--no-rc**：不注入但二进制仍安装
- **project 模式**：`.ccm/bin` + `.ccm/activate`，不写用户 rc，project wrapper 含 openai
- **--prefix**：自定义目录生效
- **生成的 ccc wrapper**（user/system 与 project 两份模板）：known-model 列表含 openai/gpt6
- **wrapper 冒烟**：`bin/ccm status` 转发成功
- **卸载**：rc 块、wrapper、data 目录全部清除（检测到系统级 ccm 时自动跳过，防误删）

### `install.sh` 可测性改动

新增 source 守卫（被 source 时不执行 `main`），使内部函数可被单元测试直接调用。

## 本机自动化无法覆盖、需真机手测的清单

1. **macOS 真机**：`./install.sh`（默认 user 模式，zsh 环境 + 真实 Homebrew 路径 + 钥匙串）
2. **macOS 真机**：`./install.sh --system`（触发真实 sudo 提权）
3. **真 claude CLI**：`ccc openai` 实际启动 Claude Code 并对话（stub 只验证环境变量传递）
4. **真实 sub2API 网关连通**：配置真实 `OPENAI_BASE_URL` / `OPENAI_API_KEY` 后 `ccm openai` + 发起一次对话，验证组路由与协议转换
5. **OpenRouter 真实计费链路**：`ccm open glm` 实调 `z-ai/glm-5.3`

## 历史战绩

- 首轮运行即抓获既有 bug：`ccc` 中 `bailian_variant` 未初始化，导致所有非 bailian 的 `ccc <model>` 调用在 `set -u` 下崩溃（含 `ccc deepseek`）。
