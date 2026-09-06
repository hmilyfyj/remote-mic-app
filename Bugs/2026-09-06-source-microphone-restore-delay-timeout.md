# 长语音结束后的恢复延迟被会话超时截断

## 复现与证据

在恢复延迟候选实现中，设置延迟 10 秒，语音持续 119 秒后正常结束。注入时钟再推进 9 秒，预期仍处于恢复等待；实际已恢复输入，终态为 `session_timeout`。`completedLongVoiceReceivesFullRestoreDelay` 在修复前出现三条断言失败：输入提前恢复、阶段提前 idle、终态异常。

## 根因与修复

`SourceMicrophoneSessionController.start` 创建的 120 秒会话 watchdog 在尾音排空和 Fn 停止后仍有效。`restoreAfterDelay` 进入 cooldown 前取消旧阶段任务，再创建恢复延迟任务。120 秒上限继续保护语音活动阶段；完整结束的语音使用独立恢复等待。

## 验证边界

回归用例验证 119 秒结束后完整等待 10 秒、恢复原设备和正常唯一终态。控制器使用注入时钟、音频和设备环境；真实遥控器长录音及第三方工具文字结果另按 `Testing/SourceMicrophoneSwitching.md` 验收。
