# 按语音来源切换麦克风测试手册

## 2026-09-08 首次按住就绪超时修复

分支 `fix/448-audio-route-readiness`：切换后的输出恢复上限调整为 2.5 秒，仍需连续健康 150ms 后立即启动；首段 PCM 与尾音排空保留。旧 1 秒阈值的失败回放已变为通过，45 项专项与 553 项完整测试报告通过。根因和自动化边界见 [Bug 记录](../Bugs/2026-09-08-source-microphone-route-timeout.md)。

本机真实 CoreAudio 测试通过：空闲输出恢复及 10 轮往返、共 20 次输入切换，逐次验证虚拟输出绑定、静音样本实际播放、队列排空和零中断，结束后恢复原输入。此次系统测试耗时约 30 秒；真实遥控器与输入法首尾文字仍按 Q01–Q06 验收。

实测准备：开启来源切麦，先确认选定虚拟输出与恢复设备在线；保持当前输入法和恢复延迟设置，使用本次本地候选。

| 用例 | 操作 | 预期与失败判定 |
| --- | --- | --- |
| Q01 首次按住 | 闲置后按住并立即说完整短句，重复 20 次 | 每次首次尝试可用；出现约两秒取消或必须重按即失败；记录首字响应和文字完整性 |
| Q02 连续两句 | 第一段松键后立即再按，说不同短句 | 两段顺序与首尾文字完整，零正常路径中断 |
| Q03 极速松键 | 按下后快速说短词并松开 | 已收到的音频播放完成后结束，后续按键可用 |
| Q04 输出异常 | 等待期间断开遥控器或让目标设备不可用，再恢复连接 | 有明确失败原因、恢复设备正确，旧回调不启动下一段 |
| Q05 恢复设置 | 原设备/指定设备与 0/2/10 秒延迟分别使用 | 延迟从正常排空与 Fn 停止后起算；切换恢复上限独立适用 |
| Q06 稳定基线 | 功能缺失/关闭/开启/再关闭，正常短句与长句 | 默认语音语义一致，快速按下、连续语音、尾字保持完整 |

日志查找同一 SOURCE_SESSION operation_id 的 requested → output_ready → trigger_submitted → drained → completed；正常结束 `completion=normal` 且 `audio_interrupted_samples=0`。ROUTE_SETTLE 带独立等待编号，失败分别记录 timed_out、generation_changed、audio_pending、output_missing、restart_failed。输入法窗口与文字结果单独实测，记录故障时间以对应日志。

## 版本与状态

最新恢复设置候选（2026-09-06）：完整 Swift Testing 报告 536 项通过（两个需主动开启的 Core Audio 实机用例默认跳过），项目自检 51 项通过；Release 本地 Mac 构建、App 结构与 ad-hoc 签名、仓库边界、依赖 pin 和差异校验通过。六张生产设置视图已逐张检查：指定设备的中英文浅色/深色四张，上一次设备中文浅色与离线设备英文深色各一张，尺寸为 800×650 压力渲染。

已更新本机“应用程序”中的 `SayAll Local.app` 并启动；生产窗口 1020×772，启动日志确认输入监控与辅助功能权限可用、遥控器已就绪、虚拟输出重新绑定后健康。旧本地版保存在 `~/Applications/SayAll-Backups/20260906-restore-preferences/`。本次保持本机 ad-hoc 安装，Developer ID、公证和对外发布未执行。用户先前已确认基础切麦与唤醒可用；新增恢复设备、延迟及拔插组合请按 R01–R08 实测，自动化与静态截图的结果范围如上。

以下为初次候选与唤醒修复的历史记录：

- 分支：`feature/448-source-microphone`，基础提交：`3935c058b95e028bbda2f582256a1df7a1ee6eae`。
- 状态：本地实现候选。功能默认关闭，代码保留本地；本次交付包含源码补丁和本手册。
- 自动化环境：macOS 26.3.1 (a)，Build 25D771280a，Apple Silicon，Swift 6.3，Swift 5 语言模式。
- Mac 本地构建：`REMOTE_MIC_LOCAL_ONLY=1` 排除手机、手表、Web 连接和私有依赖；完整 Swift 构建、520 项测试和 51 项自检通过。完整移动端版本仍需私有依赖授权。
- 已生成仅供本机界面检查的 ad-hoc App。可分发签名、公证包尚未生成；真实 RC003、MiRemoteV、内置/USB 麦克风和第三方语音工具尚未实测，工具版本待记录。

2026-09-06 唤醒失败回归：用户实测开启后会话被 `audio_interrupted` 提前取消。本机 macOS 26.3.1 (a) / 25D771280a 已复现默认输入切换使 AVAudioEngine 丢失虚拟输出绑定。已增加切换后的输出恢复：在无待播放音频时复用引擎、重置播放器，等待输出绑定连续稳定 150 ms 后提交 Fn；上限为 1 s，期间保留首段 PCM。恢复原输入后同样确认输出就绪。该等待会增加唤醒延迟，真实首字和第三方识别仍需复测。

本机真实 Core Audio 集成测试已通过 10 轮往返（20 次输入切换），每次检查 MiRemoteV 2ch 绑定、静音样本实际播放完成、队列排空和零中断；测试结束恢复原系统输入。该结果覆盖本机原输入设备，内置/USB 与实际 RC003 发声、目标工具唤醒和文字结果仍需按 M01-M15 验收。

专用实机测试会临时改变系统输入，先退出无线麦，执行：

```bash
REMOTE_MIC_LOCAL_ONLY=1 REMOTE_MIC_TEST_AUDIO_ROUTE=1 swift test --filter SourceMicrophoneRouteIntegrationTests
```

普通 `swift test` 默认跳过这两个实机用例；专用运行另含空闲音频恢复检查，确认恢复后持续健康。日志链路新增 `AUDIO ROUTE_SETTLE` 和 `phase=output_ready`，应先确认输出就绪，再看到 `phase=trigger_submitted`；持续无法恢复时应明确失败并恢复原输入。详见 `Bugs/2026-09-06-source-microphone-activation-cancelled.md`。
- Release App 构建与 `scripts/verify-app.sh` 默认结构校验通过，Developer ID 和公证校验未执行。最终文案变更后，82 项受影响测试复核通过。
- 已检查生产首次引导实体路径浅色/深色共 18 张截图，以及设置页 800 x 650 压力渲染。实际鼠标导航、权限授权、录音和第三方文字上屏仍待现场验证。

## 候选行为与边界

1. 在“按键映射”开启“按语音来源切换麦克风（实验）”；选择 Fn 模式和 MiRemoteV 2ch。开关只保存于本机，配置导入导出保持原有字段，其他机器需要主动开启。
2. 遥控器 F5 先中和并读回核对，语音开始后保存原输入 UID，确认默认输入已切到 MiRemoteV 2ch，随后发送带标记的软件 Fn。
3. 正常停止等待已接收音频实际播放排空，按住模式释放 Fn，点按模式完成第二次 Fn 点按，然后确认恢复原输入。引擎保持就绪，正常路径保持缓存完整。
4. 前一段结束期间可暂存同一遥控器的下一段，完成原会话后重新保存输入并开始下一段。最多一个待处理会话，各阶段缓存最多 80,000 个 16 kHz 单声道样本；超限有明确失败日志。其他遥控器及手机、Apple Remote 的同时语音请求按忙碌处理。
5. 未标记的全局 Fn 保留 `source=unknown`，其设备归属属于系统观测边界。空闲时原样通过；已经占有语音时拒绝遥控器抢占。遥控器占有期间，冲突 Fn 的按下和释放成对抑制。点按工具的外部录音状态依据 Fn 边沿跟踪；手动点击第三方录音按钮、第三方自动停止和开启功能前已经存在的录音状态需要人工确认。
6. 系统输入变化后保留当前新选择并结束本次尝试。原输入拔出时选择可用回退；恢复失败保留记录供重试或下次启动。重启时仅当当前输入仍与记录中的受管目标一致才恢复，其他输入保持当前选择。
7. 切换确认最多 1 秒，目标窗口等待最多 3 秒，排空最多 6 秒，会话最多 120 秒。超时、断连、配置变更、权限或输出异常进入强制结束，日志记录中断样本。停止 Fn 失败后阻断继续切麦，请手动停止语音工具并重启无线麦。
8. 全局 Fn 点按的人工同步、Core Audio 合并/延迟通知及异常退出后用户重新选择同一虚拟设备的意图，均需要真实流程核查。当前系统接口能确认设备值和事件提交，第三方最终采集来源和文字结果由人工验收。

## 测试前准备

### 恢复设置验收（2026-09-06）

入口：“按键映射” → “按语音来源切换麦克风”。开启后可选择“恢复上一次设备”或“恢复指定设备”，通过滑块或数字输入设置 0–10 秒延迟，步进 0.1 秒。默认恢复本段语音开始前的设备，延迟 0 秒。设置保存于本机，修改后从下一段语音生效。

恢复时序：PCM 实际播放排空 → Fn 停止完成 → 等待设定秒数 → 切换并确认输入 → 等待输出重新就绪。设备切换与确认本身另需少量时间。指定设备离线时依次选择本段原输入、其他可用输入；恢复失败保留恢复记录。用户手动改选始终保留新选择。等待期间继续占有遥控器语音会话并抑制冲突键盘 Fn；新一段遥控器语音会提前结束等待，恢复后按新配置开始下一段。取消、休眠、退出和启动恢复立即处理恢复，跳过自定义延迟。

| 编号 | 操作 | 预期 |
| --- | --- | --- |
| R01 | 原输入 A，选择恢复上一次设备，延迟 0 秒；完成一段后将原输入改为 B，再完成一段 | 分别回到 A、B |
| R02 | 原输入 A，指定设备 B，延迟 2 秒；按住、点按各完成一段 | 尾音和 Fn 停止后才开始 2 秒等待，随后恢复 B |
| R03 | 指定 B，在等待期间拔掉 B；再次同时移除原设备 A | 首次回 A，第二次选择其他可用输入或报告失败 |
| R04 | 等待期间手动选择 C；等候超过设置延迟 | 保留 C，旧计时器不会改回 |
| R05 | 设置 10 秒等待，期间立即开始下一段；下一段快速松键 | 等待提前结束，两段首尾音完整，无陈旧恢复操作 |
| R06 | 本段开始后修改恢复设备与延迟 | 当前段使用旧配置，下一段使用新配置 |
| R07 | 等待中休眠、关闭功能、退出；带恢复记录重新启动 | 及时恢复，Fn 无残留；启动兼容旧记录 |
| R08 | 重启应用；输入负数、超过 10 的值；刷新设备列表 | 模式和设备持久化，延迟限定在 0–10 秒，列表更新 |

界面验证使用隔离设置库的生产渲染器：设置 `REMOTE_MIC_SETTINGS_SCREENSHOT_MICROPHONE_RESTORE=previous|specified|missing`，结合 `REMOTE_MIC_SETTINGS_SCREENSHOT_SIZE=800x650`、中英文和浅色/深色参数。此模式仅渲染按键映射恢复区，设备使用测试样本，保持真实用户配置。生产窗口最低 1020×772，800×650 为压力渲染。

1. 在 Mac 本地模式下，以 `REMOTE_MIC_LOCAL_ONLY=1` 执行完整 `swift test`、`swift build` 和项目自检。按项目签名、公证流程生成可安装包，记录完整源码 SHA、App 版本、Build、系统和工具版本。
2. 准备持续连接的 RC003、MiRemoteV 2ch、内置麦克风和 USB 麦克风。授予辅助功能和输入监控权限，使用真实前台输入框。
3. 在目标工具的用户可见设置中选择“系统默认输入”。先手动切换系统默认输入并分别开始录音，确认工具每次采用新设备；固定绑定设备或持续持有旧设备的工具记录为待适配。
4. 确认语音工具已停止录音。按住 Fn 工具使用长按模式；点按 Fn 工具开启“语音键模拟 Fn 点按”。开始每组测试前核对系统默认输入为原设备 A。
5. 两路音源分别提供不同的固定测试句，避免声音串入另一麦克风。测试记录只保留“来源正确/错误、首字/尾字完整性、延迟”，分享日志时省去语音正文。

## 真机用例

| 编号 | 操作 | 预期与失败判定 |
| --- | --- | --- |
| M01 | 保持遥控器连接，使用内置麦克风作为 A；遥控器说一句，松键后键盘 Fn 说另一句，交替 20 次 | 每次遥控器使用虚拟输入，结束准确回 A；键盘使用 A。任何来源错误、残留按键、恢复错误均失败 |
| M02 | 换 USB 麦克风作为 A，重复 M01 | 每次恢复 USB；记录设备插拔结果 |
| M03 | 按住 Fn、点按 Fn 两种工具配置分别执行极速按下/释放 10 次和短句 10 次 | 从第一次开始只有正确的一组开始/停止；首字尾字完整 |
| M04 | 长句；说一句、停三秒、再说一句；与基础版本对照 | 三秒静默保持会话，顺序完整，无异常爆音。记录硬件按下至首 PCM/首字、松键至恢复耗时 |
| M05 | 前一段尾音排空时立即开始下一段并快速松键 | 两段按顺序完整输出，两段 Fn 配对、原输入恢复均正确；排空期间的下一段首字缺失判失败 |
| M06 | 遥控器与实体键盘 Fn 同时按下，改变先后顺序；外部 Fn 保持按住跨过遥控器结束 | 当前会话持续，冲突事件成对处理；后续新 Fn 可用。点按状态失步、开始/停止多一次均失败 |
| M07 | 第二只遥控器、手机或 Apple Remote 在 RC003 会话中请求语音 | 忙碌请求不改变当前来源和恢复设备；一只设备断连不得误停止另一来源 |
| M08 | 语音中系统输入从虚拟设备改到 USB；再改回虚拟设备 | 第一次观察到改选后自动恢复解除，当前尝试停止；旧回调不覆盖新选择 |
| M09 | 会话中拔出原 USB；原输入全部不可用；拔出虚拟设备 | 有候选时回退并提示；无候选时提示恢复失败；保留待恢复记录，无假成功 |
| M10 | 语音中断蓝牙、取消、关闭实验开关、改输出设备、撤销权限或休眠 | 记录强制结束原因和样本数，Fn 停止，恢复或明确提示失败；恢复后第一段可用 |
| M11 | 等待切换、等待目标、排空、开始点按、停止点按期间分别退出 App | 每次按键生命周期闭合；退出时的强制中断有记录；下次启动核对恢复记录 |
| M12 | 仅在测试环境强制退出候选 App，再启动；另一次先人工改选其他输入再启动 | 当前仍为受管目标时恢复原输入；人工改选的其他输入保持原值。记录保存失败时应在切麦前拒绝 |
| M13 | Fn 注入失败、输出入队失败、输出超时、切换确认超时、恢复失败 | 失败来源明确、终态一次；停止失败后明确要求人工检查工具并重启 |
| M14 | 工具前台/后台、目标窗口延迟打开、首次“普通快捷键动作 → 目标就绪 → STREAM_START → AUDIO → STREAM_STOP” | 第一次即完整输出；第二次才成功判失败；目标内部状态记 unknown |

每次记录：系统版本、App SHA/版本/Build、工具版本、模式、用例、序号、原输入类别、实际收音类别、恢复输入类别、首字延迟、尾字完整、状态、对应 operation_id。设备 UID、设备名、语音正文和个人信息省去。

## 稳定功能与界面回归

- 配置键缺失、明确关闭、开启、使用后关闭四种状态，分别回放 RC003 无主动 `MIC_OPEN` 的 `STREAM_START → AUDIO → STREAM_STOP`，检查普通按键及原 Fn 长按/点按路径。
- 恢复默认映射、导入/导出配置、重新连接、权限恢复，以及 Apple Remote 独立语音路径均需回归。实验开关关闭时核对基础版本行为。Mac 本地模式的手机、Web 与手表路径不适用，M07 使用第二只实体遥控器执行。
- 在实际设置窗口逐一点击全部受影响入口，检查中英文、浅色/深色、开关与状态提示和页面滚动。另做 `800 × 650` 压力检查；生产窗口最低尺寸若更大，分别记录实际交互与压力渲染结果。
- 首版能力差异：RC003/Fn/MiRemoteV 为 macOS 候选；其他遥控器型号、Command、其他虚拟设备的自动切麦显示尚未支持；Windows 自动切麦本轮未实现。现有普通按键能力沿用原实现，触摸属于 RC003 物理不存在的能力。两个平台各自按硬件合同验收。

## 自动化与日志

在 worktree 根目录执行：

```sh
zsh scripts/test-source-microphone.sh
REMOTE_MIC_LOCAL_ONLY=1 zsh scripts/test.sh
REMOTE_MIC_LOCAL_ONLY=1 swift test
REMOTE_MIC_LOCAL_ONLY=1 swift build
plutil -lint Resources/en.lproj/Localizable.strings Resources/zh-Hans.lproj/Localizable.strings
git diff --check
```

`test-source-microphone.sh` 将生产控制器、Fn 监听器和同一组 Swift Testing 测试链接到独立验证包，使用真实系统模块编译，音频/设备/时钟采用注入环境。此命令支持在私有依赖不可访问时验证状态机；完整宿主类型检查、CoreBluetooth 回调、系统事件投递及 UI 仍由后两条完整构建命令和真机用例承担。

初次候选已通过 26 项独立会话测试和 51 项项目自检。自检涵盖开关四态持久化、恢复记录保留/清理、映射读回成功及失败、原 ATVV/HID/Fn 基线；当时完整宿主构建受私有依赖阻塞。后续已通过本地 Mac 构建路径，最新验证结果见文首。

按 [`RuntimeLogging.md`](RuntimeLogging.md) 收集候选 App 日志，筛选 `AUDIO SOURCE_SESSION`、`VOICE SOURCE` 及同一时间段的 `AUDIO PLAYBACK`。新会话日志使用进程内 `operation_id`，包含切换、首 PCM、排空、停止、恢复与唯一终态。`VOICE SOURCE source=unknown` 表示全局 Fn 的设备归属仍未知。

模拟正常流程的脱敏日志字段示例：

```text
AUDIO SOURCE_SESSION operation_id=1 phase=requested source=remote mode=hold
AUDIO SOURCE_SESSION operation_id=1 phase=switched elapsed_ms=0
AUDIO SOURCE_SESSION operation_id=1 phase=trigger_submitted external_capture=unknown
AUDIO SOURCE_SESSION operation_id=1 phase=first_pcm session_start_to_first_pcm_ms=0 trigger_down_to_first_pcm_ms=unknown trigger_down_to_first_transcript_observation_ms=unknown
AUDIO SOURCE_SESSION operation_id=1 phase=remote_stopped
AUDIO SOURCE_SESSION operation_id=1 phase=draining audio_received_samples=3 audio_scheduled_samples=3
AUDIO SOURCE_SESSION operation_id=1 phase=drained audio_pending_samples=0 audio_interrupted_samples=0
AUDIO SOURCE_SESSION operation_id=1 phase=restored fallback=false
AUDIO SOURCE_SESSION operation_id=1 phase=completed result=completed completion=normal elapsed_ms=10 external_capture=unknown
```

正常会话必须同时满足 pending 为 0、interrupted 为 0、一次终态且恢复正确。`completion=forced`、超时或任意中断样本属于失败。`session_start_to_first_pcm_ms` 起点是应用会话创建；硬件真实按下耗时和首字耗时需要设备级测量，当前自动日志用 `unknown` 明确标注。第三方采集到完整文字仍需 M01～M14 的人工证据。
