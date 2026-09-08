# Swift 类型与兼容

以 `Package.swift` 中 Swift tools 6.2 和目标平台为编译依据。
参考 `MacShortcutsService.RunState` 用 enum 表达运行状态，MacShortcut 使用 UUID 标识；跨异步边界保持 actor 隔离，外部数据经类型校验后使用。

配置 Codable 新字段按 `AppSettings.swift` 的兼容处理扩展，覆盖旧值与缺失字段。macOS 新 API 参照 `SettingsView.swift` 的可用性与兼容封装，验证所有受支持的目标。
