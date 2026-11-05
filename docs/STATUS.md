# 实施状态

当前阶段：P6/P8/P9 收口。执行引擎（调度、runner、恢复、Git Checkpoint、返工与审批）已在 Windows 上通过单元测试与端到端验证；工作流自动执行目前接入 mock Agent，真实 Agent 适配器接入工作流仍在实施。

## P2 持久化

- SQLite（`rusqlite` bundled）单连接串行写入，启用外键、WAL、`synchronous=NORMAL` 与 5 秒 busy timeout。
- `schema_migrations` 版本化迁移，在 `IMMEDIATE` 事务内应用；迁移外键检查失败会回滚。
- 状态更新使用旧状态条件更新；状态变化与结构化事件在同一事务内提交。

## P3 runner、调度与恢复

- Run 先持久化为 `queued`，后台调度器每 200 ms 一轮，调用独立 `agentflow-runner`。
- Attempt 领取、账号/工作区锁和 Run/Step 状态在 SQLite `IMMEDIATE` 事务中原子提交。
- FIFO、全局并发上限 3、同账号串行、超时和 token 校验取消。
- runner 通过版本化文件协议写入 identity、heartbeat 与 result，均为原子替换；取消与超时使用 `taskkill /F /T` 结束整棵进程树。
- identity/result 导入、stdout 结构校验、终态幂等和终态后事务化释放资源锁。
- App 数据目录单实例锁。启动时只重新派发 `prepared`；runner 进程存活检测使用 Win32 API；状态不确定的执行转 `interrupted` 并保留锁。

## P5 Git 工作区与 Checkpoint

- Git preflight 记录 canonical 源仓库、common directory、固定 base SHA 和源目录 dirty 提示。
- 每 Run/每 generation 创建独立分支和 Worktree，仓库管理命令在 Core 内串行。
- Checkpoint 显式提交受控文件，禁用 hook/交互签名，支持空改动和 commit/DB 窗口幂等补记。
- Review 使用 detached Worktree；恢复创建新 generation，旧工作区与失败现场保留。
- 越界路径、外部符号链接、非本次 staged 内容被核心层拒绝。

## P6 工作流与返工

- 版本化工作流定义：角色绑定、必需输入、预置 Command、声明式条件、RepeatBlock 和执行预算。
- Rust 验证器拒绝无账号角色、无默认边、缺必需输入、悬空边、任意环、嵌套/超预算返工和不支持的节点版本；发布版本按 SHA-256 digest 不可变存储。
- DevelopmentLoop 状态机实现测试失败、Review 拒绝、人工拒绝的受限返工，区分测试 infrastructure error。
- 测试、Review 和人工批准都校验当前 candidate SHA；批准额外校验 workflow digest，候选变更后旧批准失效。
- 节点之间、prepared 阶段和等待审批时可取消；状态未知的执行不释放锁。

尚缺：自动执行仅支持标准 mock 模板，需要统一通用图定义与执行路径，并把真实 Agent 适配器接入工作流节点。

## 对话、账号与用量

- 对话 CLI 使用 provider 业务请求：Rust 解析固定二进制和账号 HOME、校验工作区与模型白名单，并强制 Codex `workspace-write` 与 agy sandbox；未知 provider、伪造模型和危险参数有回归测试。
- agy 三个账号使用独立 HOME 目录（`%USERPROFILE%\.agy-accounts\accountN`）；检测只检查凭据文件存在性，不读取 Token 内容。
- 用量只读取官方接口：Codex `app-server` 的 `account/usage/read` 与 `account/rateLimits/read`，agy `--output-format json` 与只读 `/usage`；无可信数据时显示“不可用”。
- 代理优先使用环境变量，未设置时读取 Windows 系统代理设置。

尚缺：对话请求仍由 Tauri 进程等待 CLI 结果，尚未迁移到独立 runner；真实账号调用在 Windows 上的验收待完成。

## 验证证据（Windows 11 专业版 10.0.26200，2026-11-05）

- `cargo test --workspace`：45 项通过（Core 34、App 7、mock CLI 4）。
- `cargo run -p agentflow-core --example verify_scheduler`：三账号并行、同账号串行、取消、失败和调度宿主被结束后结果补记，通过。
- `cargo run -p agentflow-core --example verify_workflow`：宿主进程被结束后结果补记、测试返工、Review 返工、三轮 Checkpoint、绑定 SHA 的审批，通过。
- `scripts\verify-runner.ps1`：父进程退出后继续运行、陈旧 token 拒绝、取消结束包含派生子进程的进程树、非零退出、无效输出、双流超过 500 KB 大日志，通过。
- `npm run typecheck`：通过。

## 尚未完成

- 真实 Agent 适配器接入工作流节点；第二种真实 CLI 的完整验收。
- 系统托盘、关闭窗口继续执行、明确退出停止的完整桌面生命周期。
- Windows 安装包（NSIS / MSI）构建验证与 Authenticode 签名。
- 定时任务自动触发、长期目标、备份恢复。
- 进程树终止改用 Job Object。

下一步：把受限对话 CLI 调用迁移到独立 runner 与持久化 Attempt，随后统一通用图执行与任务画布定义。
