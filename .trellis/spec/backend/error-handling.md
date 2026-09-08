# 错误与恢复

`Sources/RemoteMic/MacShortcutsService.swift` 使用 `MacShortcutsError` 区分 unavailable、failed、timedOut、invalidList；进程调用设置超时，参数通过 Process.arguments 传递。

新增系统调用应明确成功、失败、取消、超时与恢复路径，校验外部数据后再更新模型。进程提交、事件收到和音频入队分别记录其阶段，最终成功按可观察结果判断。

音频恢复遵守 [语音合同](../../../Testing/HardwareVoiceAudioContract.md)：首字低延迟、尾音有序排空；强制中断记录原因与丢失边界。先复现并检查日志，再修复非简单 Bug，流程见 [AGENTS.md](../../../AGENTS.md)。
