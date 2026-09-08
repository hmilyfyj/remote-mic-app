# 配置存储与兼容

此文件沿用 Trellis 的工具命名，覆盖本项目的本地配置存储。
`Sources/RemoteMic/AppSettings.swift` 使用 UserDefaults，并以带 formatVersion 的 Codable 配置支持导入导出；新增字段参照已有可选字段处理旧配置兼容。

变更需要覆盖缺失字段、旧配置、无效值、设备独立配置和导入导出往返。读取范围遵守 [AGENTS.md](../../../AGENTS.md) 的跨应用数据边界；研究仅使用公开 API 与用户明确选择的文件。
