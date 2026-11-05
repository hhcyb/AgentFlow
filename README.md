# AgentFlow

AgentFlow 是一个运行在 Windows 上的本地多 Agent 研发工作台。工程采用 Tauri 2、React、TypeScript 和 Rust；生产前端作为静态资源打包进应用，不依赖外部浏览器或 HTTP 后端。

## 当前结构

- `src/`：React 界面与受限 Tauri Command 客户端。
- `src-tauri/`：桌面生命周期和显式业务命令。
- `crates/agentflow-core/`：领域状态、SQLite 存储、runner 调度、Git Worktree/Checkpoint 与工作流验证器。
- `crates/agentflow-mock-cli/`：成功、失败、延迟、无效输出、子进程和大日志 fixture。
- `crates/agentflow-runner/`：独立 CLI 执行进程。
- `scripts/`：环境探测与 runner 生命周期验证脚本（PowerShell）。
- `docs/STATUS.md`：已验证能力、阻塞与下一步。

React 不直接执行 shell、操作 Git 或写执行状态。工作流发布与执行合法性由 Rust Core 校验；runner 只通过版本化文件协议写入自己的 Attempt 目录。

## Windows 实现要点

| 能力 | 实现 |
|---|---|
| 子进程终止 | `taskkill /F /T` 结束 Agent 及其派生的整棵进程树 |
| 进程存活检测 | Win32 `OpenProcess` + `GetExitCodeProcess` |
| 子进程环境 | 清空后只注入系统 `PATH` 与 `SystemRoot` |
| CLI 查找 | 用户 `.local\bin`、WinGet、npm 全局目录、`%LOCALAPPDATA%`，最后 `where` |
| 目录选择 / 终端登录 | PowerShell 目录对话框 / `cmd` 新窗口 |
| 代理 | 环境变量优先，其次 Windows 系统代理设置 |
| SQLite | 随程序编译（`rusqlite` bundled） |

## 本地构建

要求 Windows 10 1809 及以上或 Windows 11、Rust stable（MSVC 工具链）、Node.js、npm 和 Git for Windows。以下命令在 PowerShell 中执行：

```powershell
npm install
npm run typecheck
cargo test --workspace
cargo build -p agentflow-runner -p agentflow-mock-cli
powershell -ExecutionPolicy Bypass -File scripts\verify-runner.ps1
cargo run -p agentflow-core --example verify_scheduler -- `
  "$PWD\target\debug\agentflow-runner.exe" `
  "$PWD\target\debug\agentflow-mock-cli.exe"
cargo run -p agentflow-core --example verify_workflow -- `
  "$PWD\target\debug\agentflow-runner.exe" `
  "$PWD\target\debug\agentflow-mock-cli.exe"
```

`verify-runner.ps1` 验证 runner 的父进程退出后继续运行、陈旧 token 拒绝、取消结束进程树、非零退出、无效输出与双流大日志。`verify_workflow` 使用 mock Agent 输出、真实独立进程和 Git Checkpoint 验证多步持久化、自动测试/Review 返工、逐候选隔离 Review、人工批准和取消。自动执行目前支持标准 mock 模板；Tauri 业务命令已接通，React 操作界面与真实 Agent 接入仍在实施。

开发模式启动与打包：

```powershell
npm run tauri dev
npm run tauri build
```

打包目标为 NSIS 与 MSI 安装包。

## 已知限制

- `taskkill /T` 依据父进程关系结束进程树，中间进程先退出时孤儿孙进程可能残留；后续计划改用 Job Object。
- 多 agy 账号通过设置 `HOME` 隔离，CLI 是否完全遵循 `HOME` 尚待真实账号验证。
- 安装包（NSIS / MSI）尚未实际构建验证。

详见 [`docs/STATUS.md`](docs/STATUS.md)。
