# SwiftUI 组件

`Sources/RemoteMic/MacShortcutEditor.swift` 的现有模式：View struct 持有被观察的 service/localization、selected 值与 onSelect 回调，搜索文字为局部 @State。

沿用现有状态与回调边界，系统工作交给服务。文案通过 LocalizationStore 提供中英文。中文最终显示至少 12pt，按语义分组并优先页面内操作，依据 [设计规范](../../../design-qa.md) 验证控件和层级。
