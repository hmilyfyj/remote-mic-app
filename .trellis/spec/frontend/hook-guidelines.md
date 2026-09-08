# 异步行为与生命周期

此文件沿用 Trellis 的工具命名，内容对应 SwiftUI 生命周期。
参考 `Sources/RemoteMic/MacShortcutEditor.swift` 的 `Task { await service.refresh() }` 与 `MacShortcutsService.swift` 的 @MainActor 状态更新；阻塞进程工作在服务内的后台队列执行。

新增观察器、Task、计时器与系统资源时明确拥有者及清理时机，验证取消、退出和重复操作。语音键按下/释放时序遵守 [AGENTS.md](../../../AGENTS.md) 的即时响应与手势边界。
