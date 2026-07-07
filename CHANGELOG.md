# Changelog

## [2.4.6](https://github.com/xinatcg/claude-code-switch/compare/v2.4.5...v2.4.6) (2026-07-07)


### Bug Fixes

* ccm project/user glm 的 JSON 组装改 BSD sed 兼容（修 macOS） ([3113a72](https://github.com/xinatcg/claude-code-switch/commit/3113a7221591287b5fb446e75a1e3a6bab762ea5))

## [2.4.5](https://github.com/xinatcg/claude-code-switch/compare/v2.4.4...v2.4.5) (2026-07-07)


### Bug Fixes

* rc 注入的 ccm() case 加 version（原走 eval 报 command not found: 2.4.4） ([e160008](https://github.com/xinatcg/claude-code-switch/commit/e1600087263c4d386544ad5c6ed91482cb728329))

## [2.4.4](https://github.com/xinatcg/claude-code-switch/compare/v2.4.3...v2.4.4) (2026-07-07)


### Bug Fixes

* install.sh 默认 GITHUB_REPO 改为 xinatcg（原 foreveryh 拉到旧版 ccm.sh） ([e58b08e](https://github.com/xinatcg/claude-code-switch/commit/e58b08e7d0102809dd2885035cb639de53362d32))

## [2.4.3](https://github.com/xinatcg/claude-code-switch/compare/v2.4.2...v2.4.3) (2026-07-07)


### Bug Fixes

* install.sh ccm/ccc 生成改直接 heredoc 写临时文件（修 macOS bash 3.2） ([6df1314](https://github.com/xinatcg/claude-code-switch/commit/6df131474c30b8e790e37084b722cd0087edc524))

## [2.4.2](https://github.com/xinatcg/claude-code-switch/compare/v2.4.1...v2.4.2) (2026-07-07)


### Bug Fixes

* install.sh 在 macOS bash 3.2 下 ccc 生成报 account unbound ([a174782](https://github.com/xinatcg/claude-code-switch/commit/a174782c7b33c115fda30feea012ce4548664563))

## [2.4.1](https://github.com/xinatcg/claude-code-switch/compare/v2.4.0...v2.4.1) (2026-06-30)


### Bug Fixes

* 标记 CCM_VERSION 供 release-please 自动更新 ([e529e18](https://github.com/xinatcg/claude-code-switch/commit/e529e1826ba013cfc768ad75c3a3829af100985b))

## [2.4.0](https://github.com/xinatcg/claude-code-switch/compare/v2.3.0...v2.4.0) (2026-06-30)


### Features

* **docs:** 增加 Releases 自动发版说明 ([5580634](https://github.com/xinatcg/claude-code-switch/commit/5580634fbb9952fdbc0c6f7b28a1a4665e8f86da))

## [Unreleased]

### Fixed
- `ccm project glm` / `ccm user glm` / `ccm glm` 产出符合智谱官方文档的 env：
  HAIKU=`glm-4.7`，SONNET/OPUS=`glm-5.2[1m]`，移除多余的 `ANTHROPIC_MODEL`，
  新增 `CLAUDE_CODE_AUTO_COMPACT_WINDOW`/`CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC`/`API_TIMEOUT_MS`。
- GLM 配置收敛到唯一数据源 `get_glm_env_map`，消除三处重复。

### Added
- `ccm user` 兼容 cc-switch-cli：检测到 `~/.claude/settings.json` 非本工具管理时默认拦下，
  需 `--force` 覆盖（先备份）。全局与项目级配置分工明确。

## [2.3.0] - 2026-01-26

### Changed
- ⬆️ **Model upgrade**: Updated GLM from version 4.6 to 4.7
  - Official API: `glm-5`
  - Upgraded all references in documentation and configuration

## [2.2.0] - 2025-10-27

### Added - Claude Pro Account Management 🔐
- ✨ **Multiple Claude Pro account support**: Manage and switch between multiple Claude Pro subscription accounts
  - `ccm save-account <name>` - Save current logged-in account credentials
  - `ccm switch-account <name>` - Switch to a saved account without re-login
  - `ccm list-accounts` - List all saved accounts with status
  - `ccm delete-account <name>` - Delete saved account
  - `ccm current-account` - Show current account information
- 🚀 **Quick account switching**: `ccm opus:account` or `ccm haiku:account` syntax
  - Switch account and select model in one command
  - Works with `ccc` launcher: `ccc opus:work`
- 🔒 **Secure credential storage**: Primary storage in macOS Keychain with local backup
  - Local backup stored in `~/.ccm_accounts` (chmod 600) with base64 encoding
  - Automatic token refresh support
  - Persists across system reboots
  - Keychain service name configurable via `CCM_KEYCHAIN_SERVICE`
- 🌐 **Multi-language support**: Added 24 new translation keys for account management
  - English and Chinese translations
  - Seamless integration with existing i18n system

### Added
- 🔍 **Debug utilities**: `ccm debug-keychain` command for troubleshooting Keychain issues
- 🛠️ **Enhanced ccc launcher**: Support for account-only and model:account syntax
  - `ccc <account>` - Switch account and launch with default model
  - `ccc <model>:<account>` - Switch account and use specific model

### Changed
- 📚 Updated documentation:
  - Added comprehensive account management guide in README.md and README_CN.md
  - Updated help text (`ccm help`) with account commands
  - Added troubleshooting section for common issues
- 🔧 Enhanced Claude model functions:
  - `switch_to_claude()`, `switch_to_opus()`, `switch_to_haiku()` now support account parameter
  - Better error handling and user feedback
- 🎯 Improved installer: Updated to handle new account management commands

### Fixed
- 🔧 Fixed eval pattern issues with colored terminal output
- 🐛 Resolved account file permission handling
- ✨ Improved JSON parsing robustness for account storage

### Use Case
This update enables users to bypass Claude Pro usage limits by managing multiple Pro accounts, which is more cost-effective than upgrading to Claude Max. Each account has independent usage quotas (5 hours/day, weekly limits).

## [2.0.0] - 2025-10-01

### Added - Plan B Implementation
- ✨ **New `ccc` command**: One-command launcher that switches model and starts Claude Code
  - `ccc deepseek` - Switch to DeepSeek and launch
  - Supports all Claude Code options (e.g., `--dangerously-skip-permissions`)
- 🔄 Enhanced `ccm` command: Improved environment management
  - Better environment variable propagation
- 📦 Improved installer: Now installs both `ccm()` and `ccc()` functions

### Changed
- 🏗️ **Major refactor**: Consolidated all functionality into `ccm.sh` and `install.sh`
- 🎨 Improved user experience with two workflow options:
  - **Method 1**: `ccm` for environment management only
  - **Method 2**: `ccc` for one-command launch (recommended)
- 📝 Updated all documentation to reflect Plan B design
- 🧹 Cleaned up project structure (removed 16 obsolete files)

### Removed
- Deprecated scripts (functionality integrated into main scripts):
- Obsolete test scripts (moved to backup)

### Fixed
- 修复 GLM 模型版本配置（从 4.5 升级到 4.6）
- Fixed authentication conflicts (use only `ANTHROPIC_AUTH_TOKEN`)

---

## Usage Examples

### Quick Start with ccc (Recommended)

```bash
# Switch to DeepSeek and launch Claude Code in one command
ccc deepseek

# With Claude Code options
ccc kimi --dangerously-skip-permissions
```

### Traditional ccm Workflow

```bash
# Switch environment
ccm deepseek

# Verify
ccm status

# Then launch Claude Code manually
claude
```

### Verify Configuration

```bash
# Check current settings
ccm status

# Should display:
# 📊 Current model configuration:
#    BASE_URL: https://api.deepseek.com/anthropic
#    AUTH_TOKEN: [Set]
#    MODEL: deepseek-chat
```
