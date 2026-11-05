# Agent CLI 能力矩阵

探测日期：2026-11-05（`scripts\probe-environment.ps1 codex agy`）

## 环境

| 项目 | 实际值 | 验证状态 |
|---|---|---|
| 操作系统 | Windows 11 专业版 10.0.26200 | 已探测 |
| CPU | AMD64 | 已探测 |
| Rust | rustc 1.98.1，x86_64-pc-windows-msvc | 已探测 |
| Node.js / npm | Node 24.16.0 / npm 11.13.0 | 已探测 |
| Tauri CLI | 2.11.4，版本由 `package-lock.json` 锁定 | 已探测 |
| Git | 2.54.0.windows.1 | 已探测 |
| 安装包工具（NSIS / WiX） | 未探测 | 安装包构建待验证 |

## Codex CLI

| 能力 | 证据 | 状态 |
|---|---|---|
| 可执行路径 | `%APPDATA%\npm\codex.cmd`（npm 全局安装） | 已探测 |
| 版本 | `codex-cli 0.146.1` | 已探测 |
| 非交互执行 | `codex exec` 子命令 | 接口已确认，Windows 上真实执行待验证 |
| 结构化事件 | `codex exec --json` 输出 JSONL | 仅帮助文本确认，schema 未验证 |
| 结构化最终输出 | `codex exec --output-schema <FILE>` | 仅帮助文本确认 |
| profile 配置 | `-p` 从 `$CODEX_HOME/<name>.config.toml` 加载 | 仅帮助文本确认 |
| 用量与限额 | 官方 `codex app-server` 的 `account/usage/read`、`account/rateLimits/read` | 已实现解析与回归测试，Windows 上真实读取待验证 |
| 三账号并行隔离 | 尚无三套测试账号/profile | 未验证 |
| 取消与进程树 | runner `taskkill /T` 已用 mock CLI 验证 | 真实 CLI 待验证 |

注意：`codex.cmd` 是批处理入口，参数会经过 cmd.exe 解析。Rust 标准库会对 `.cmd` 参数做安全转义，无法安全转义时直接报错（CVE-2024-24576 修复后的行为）；后续改为通过 stdin 传递 prompt 以彻底避开命令行解析。

## agy

| 能力 | 证据 | 状态 |
|---|---|---|
| 可执行路径 | `C:\Windows\agy.exe` | 已探测 |
| 版本 | `1.2.9` | 已探测 |
| `--version` 行为 | 不会自动退出，探测脚本以 10 秒超时结束 | 已探测 |
| 结构化输出 | `--output-format json` 返回 status、response、conversation_id 与 Token 用量 | 已实现解析与回归测试，Windows 上真实调用待验证 |
| 配额 | 只读 `/usage` 的 `command.data.groups[].buckets[]` | 已实现解析与回归测试，Windows 上真实读取待验证 |
| 多账号隔离 | 每个账号独立 HOME（`%USERPROFILE%\.agy-accounts\accountN`） | Windows 上 CLI 是否完全遵循 `HOME` 待验证 |

## 后续真实验证所需输入

1. 每种 CLI 至少一套可用于验证的账号，并由用户在 App 的“终端登录”中完成供应商登录。
2. 允许执行的无破坏、低成本身份标记任务及测试工作目录。
3. 若 CLI 需要代理，确认环境变量或 Windows 系统代理已设置；不需要向实现过程提供明文凭据。
