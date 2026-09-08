# 核心目录

- `Package.swift`：Swift tools 6.2，平台与可选依赖入口。
- `Sources/RemoteMic/`：Mac 宿主；`SourceMicrophoneSessionController.swift` 管理来源麦克风会话，`MacShortcutsService.swift` 管理系统快捷指令调用。
- `Sources/AppleRemoteAudioCore/`、`Sources/AppleRemoteHCIProtocol/`：音频与协议模块。
- `Tests/RemoteMicTests/`：宿主测试；`Testing/`：功能实测手册；`scripts/`：构建与验证。

新增文件先读 [FILE_NAMING.md](../../../FILE_NAMING.md)，优先扩展已有职责对应模块。
