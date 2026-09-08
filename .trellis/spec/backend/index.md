# Mac 核心逻辑规范

此处 backend 指 Mac 进程内的音频、设备、配置与系统集成。仓库范围见 [AGENTS.md](../../../AGENTS.md)。

## Pre-Development Checklist
- 先读 [目录](directory-structure.md)、[错误处理](error-handling.md)。
- 改持久化时读 [配置存储](database-guidelines.md)，改功能时读 [日志](logging-guidelines.md)。
- 硬件、语音和系统集成遵守 [共用入口](../guides/index.md) 中的合同。

## Quality Check
执行 [质量检查](quality-guidelines.md) 中适用的命令，记录自动化与实机验收各自结果。
