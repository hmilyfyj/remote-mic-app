# Trellis 开发工具

本项目接入 `@mindfoldhq/trellis@0.6.16`，采用官方 Codex 集成。版本记录在 `.trellis/.version`，模板指纹在 `.trellis/.template-hashes.json`。

## 日常使用

在已拉取此分支的项目目录打开 Codex，使用 `$trellis-start` 开始会话；继续任务用 `$trellis-continue`，开发前用 `$trellis-before-dev`，检查用 `$trellis-check`。技能在新会话中发现。

已有 Python 3.9+（本机已验证 3.9.6） 即可运行仓库内任务脚本，当前开发者按本地身份初始化：

```sh
python3 .trellis/scripts/init_developer.py fengit
python3 .trellis/scripts/get_context.py
python3 .trellis/scripts/get_context.py --mode packages
```

其他协作者将 `fengit` 替换为自己的开发者名。命令行独立操作任务时，为该终端设置唯一且稳定的上下文标识；Codex hook 会话可使用自身会话标识：

```sh
export TRELLIS_CONTEXT_ID=terminal-my-task
python3 .trellis/scripts/task.py create "任务标题" --slug my-task --description "目标和验收范围" --base-branch main --no-start
# 使用上一条实际输出的任务目录替换 <task-dir>。
# 先填写 prd.md；复杂任务同时完成 design.md 和 implement.md，并自审。
python3 .trellis/scripts/task.py add-context <task-dir> implement .trellis/spec/guides/index.md "共用规范"
python3 .trellis/scripts/task.py add-context <task-dir> check .trellis/spec/backend/quality-guidelines.md "验证入口"
python3 .trellis/scripts/task.py validate <task-dir>
python3 .trellis/scripts/task.py start <task-dir>
python3 .trellis/scripts/task.py current --source
```

context 按任务补入实际相关的规范和代码路径。参考 `python3 .trellis/scripts/task.py --help` 与 `.trellis/workflow.md`。完成后按会话的收尾规范验证、提交和归档；`task.py finish` 只清除当前指针。

## 目录与边界

- `.trellis/spec/frontend/`：SwiftUI 界面；`.trellis/spec/backend/`：Mac 核心；`.trellis/spec/guides/`：共用规范与验证证据。
- `.trellis/scripts/`、`.agents/skills/`、`.codex/hooks*` 和 `.codex/agents/`：官方开发工具，独立于 App 构建。
- `.trellis/tasks/`、`.trellis/workspace/`、`.developer` 与 `.runtime/`：Git 忽略的本地执行记录。详细研究和完整产品计划遵守 [AGENTS.md](AGENTS.md) 的私有仓库规则。
- `session_auto_commit: false`：日志、归档写本地文件；提交按当前用户授权执行。Codex `dispatch_mode: inline`：默认在当前会话实现和检查。

原有 AGENTS.md、Codex environment 与产品约束保留。通用模板里的技术栈示例以本项目 spec 中的 Swift/macOS 命令为准。

## Codex hooks

项目提供 `UserPromptSubmit` 与 `SubagentStart` hooks。自动注入取决于 Codex 版本、用户级 hooks 开关与项目/钩子信任状态；0.129+ 使用用户配置 `[features] hooks = true` 并在 `/hooks` 审核。本次安装只写项目文件。手动 `$trellis-start` 和 Python context 命令可直接读取规范与任务。

## 安装来源与升级

本次在已有官方 CLI 0.6.16 上执行：

```sh
trellis init --codex --no-monorepo --user fengit --yes --skip-existing
```

新 clone 已包含工具文件，初始化个人身份即可。需要 CLI 时使用 `npx --yes @mindfoldhq/trellis@0.6.16 --help`，避免每次安装漂移到不同版本。
升级在独立 worktree 中先查看目标版本的 `update --help`，审查其更新差异、备份和本项目定制。保留 AGENTS.md、spec、忽略规则与配置，不使用强制覆盖。升级后验证 context、任务生命周期、hooks、Python 和 JSON/TOML，再提交版本及模板指纹变化。

## 本次工具接入检查

运行任务 context validate、start/current、phase/packages 读取和隔离仓库的开发者/任务烟测；检查 Python 语法、JSON/TOML、spec 链接、Git ignore、原文件保留及仓库边界。App 源码与安装包未变化，本次证据仅覆盖开发工具接入。
