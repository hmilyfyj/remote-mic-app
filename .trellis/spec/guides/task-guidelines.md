# 任务与验证记录

小任务写清目标、实际代码位置、范围和可测试验收；复杂任务先完成 prd.md、design.md、implement.md 的自审，再开始实现。当前明确的开发委托可作为创建任务与常规实现授权。

本仓库忽略 `.trellis/tasks/` 和 `.trellis/workspace/`，仅保存本地简短执行记录与验收证据；详细研究、内部判断及完整产品计划继续遵守 AGENTS.md 的私有仓库规则。公开 spec 只沉淀可复用开发约束。

每项 AC 对应验证命令或实测步骤、预期结果、实际结果与覆盖边界。行为修复记录 RED/GREEN；保持现有行为记录 BASELINE/GUARD；手工验收记录 MANUAL。纯文档修改检查链接、差异与指令准确性。

具体任务 context 同时引用有关 spec 与代码事实，执行 `python3 .trellis/scripts/task.py validate <task-dir>`。任务归档与记录遵守会话绑定的收尾规范，自动提交在本仓库关闭。
