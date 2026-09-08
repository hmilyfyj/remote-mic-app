# 验证命令与证据

按改动选择检查；命令在仓库根目录执行。

```sh
# Mac 本地模式：排除移动端私有依赖
REMOTE_MIC_LOCAL_ONLY=1 swift test
SKIP_SWIFT_PACKAGE_BUILD=1 REMOTE_MIC_LOCAL_ONLY=1 zsh scripts/test.sh
# 仓库边界与基本补丁检查
zsh scripts/check-repository-boundaries.sh
git diff --check
```

App 包变更使用 `REMOTE_MIC_LOCAL_ONLY=1 zsh scripts/build-app.sh` 和 `zsh scripts/verify-app.sh`；正式发布遵守 [RELEASING.md](../../../RELEASING.md)，本地模式的结果限定于其启用范围。

纯文档/工具接入执行链接、配置解析、脚本烟测和 diff 检查。SwiftPM 运行后检查 `Package.resolved`，仅纳入有意的依赖变更。
硬件与语音改动按 [硬件合同](../../../Testing/HardwareCompatibilityContract.md) 和对应 Testing 手册真实验收。记录 RED/GREEN（行为修复）、BASELINE/GUARD（回归）或 MANUAL（实测）的适用证据。
