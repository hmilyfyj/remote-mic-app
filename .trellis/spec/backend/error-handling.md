# 错误与恢复

`Sources/RemoteMic/MacShortcutsService.swift` 使用 `MacShortcutsError` 区分 unavailable、failed、timedOut、invalidList；进程调用设置超时，参数通过 Process.arguments 传递。

新增系统调用应明确成功、失败、取消、超时与恢复路径，校验外部数据后再更新模型。进程提交、事件收到和音频入队分别记录其阶段，最终成功按可观察结果判断。

音频恢复遵守 [语音合同](../../../Testing/HardwareVoiceAudioContract.md)：首字低延迟、尾音有序排空；强制中断记录原因与丢失边界。先复现并检查日志，再修复非简单 Bug，流程见 [AGENTS.md](../../../AGENTS.md)。

输入切换后的输出就绪上限应与系统实际重配耗时、会话等待和 PCM 容量一起核对。`AudioRouteWaiter` 提供可回放的生产等待循环，测试覆盖临界超时、稳定窗口重置、取消和下一会话；ROUTE_SETTLE 细分超时与设备/代次/重启失败。真实 CoreAudio 测试与用户语音文字验收分别记录。

仅麦克风模式必须同时覆盖硬件按键中和与软件事件发送入口；输出、取消和恢复阶段保持零键盘事件，硬件中和失败时阻断语音启动并维持用户模式。来源切麦会话跳过输入法等待，继续音频排空与设备恢复。
