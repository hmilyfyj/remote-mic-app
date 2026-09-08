# 状态所有权

参考 `Sources/RemoteMic/MacShortcutsService.swift`：@MainActor ObservableObject 持有 @Published private(set) 的列表、加载状态和按标识划分的运行状态。`MacShortcutEditor.swift` 用 @ObservedObject 观察服务，搜索条件保存在 @State。

持久化设置遵循 AppSettings 的统一读写与校验。异步结果回写时检查所属操作/会话，切换页面、切换设备、取消及重复触发后应保持可解释状态。
