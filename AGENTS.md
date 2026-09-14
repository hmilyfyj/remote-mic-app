# 仓库开发规则

## 产品命名规范

- 正式产品全称为「无线麦SayAll.app」；中文简称为「无线麦」，英文简称为「SayAll」。
- 新增面向用户的品牌文案应优先使用正式全称或适合语境的简称，不得把 `Remote Mic` 作为新的产品品牌。
- `Remote Mic`、`RemoteMic`、`Remote-Mic-*` 可继续用于历史兼容名称、代码标识符、Bundle ID、可执行文件、安装器和发布资产；不得因品牌统一误改这些兼容边界。

## 跨应用数据访问边界

- 禁止读取、解析、解密、复制或依赖其他 App 的内部文件、数据库、沙盒容器、历史记录、私有运行库、私有协议或未公开数据格式。
- 禁止通过独立 Helper、动态库加载、直接访问 `~/Library` / App bundle 内部路径或其他绕过方式规避该限制；其他 App 集成只能使用公开 API、公开协议、用户可见的辅助功能界面或用户明确选择的文件。
- 创建或更新 PR 前必须检查变更是否触及上述边界；一旦发现，必须停止创建或合入 PR，并拆除相关实现。自动化测试、模拟数据、签名包或用户授权都不能把读取其他 App 内部文件变成允许行为。

## iOS 仓库边界

- iOS App 已由独立私有仓库维护；本仓库不得重新创建 `Apps/RemoteMicIOS/`、iOS 工程或 iOS 专属 CI。
- 本仓库只维护 Mac 端附近连接、授权、按键执行和音频接收。
- 修改共享手机协议时必须保持字段可选并兼容旧版 iOS，同时在独立 iOS 仓库完成对应验证；纯 iOS UI、TestFlight 和 iOS 设计素材不在本仓库处理。

## Web 与服务器仓库边界

- Web 前端和公网中继服务已分别由独立私有仓库维护；本仓库不得重新创建 `Apps/MobileWeb/` 或 Web/服务端专属 CI。
- 本仓库继续维护 Mac 端的 Web 会话客户端、协议解析、批准流程、按键执行、音频接收和发布配置，不得因源码拆分改变这些现有行为。
- 修改 Web 协议时必须保持已发布 Mac 版本兼容，并在前端、服务端和本仓库分别完成对应测试；生产域名、服务器、证书和凭据仍不得进入 Git。

## 按改动范围读取

| 场景 | 规则 |
|---|---|
| 创建分支、提交、Push、合并或发布 | [BRANCH_MANAGEMENT.md](BRANCH_MANAGEMENT.md)；文档改动也在独立 worktree，不直接修改 main |
| 新增文件、普通开发、日志、界面、Bug 或用户反馈 | [DEVELOPMENT_RULES.md](DEVELOPMENT_RULES.md) 的对应章节 |
| 硬件适配、语音键、音频与跨平台行为 | [HARDWARE_RULES.md](HARDWARE_RULES.md) |
| Onboarding 设计、实现、文案或截图 | [ONBOARDING_RULES.md](ONBOARDING_RULES.md) |
| 测试包、Feature Flag、安装包与发布 | [DELIVERY_RULES.md](DELIVERY_RULES.md) |

这些规则保留产品不变量、真实设备验证及签名公证要求；按涉及场景读取，不在每次任务预读所有手册。Onboarding 的完整截图矩阵仍适用其规定范围。

## 完成边界

已授权的开发包含必要规划、实现和受影响验证，不重复询问是否建任务或开始；明确的只读反馈诊断与先评估要求按指定边界执行。区分自动化、截图、构建和真机证据，不能互相替代。

详细研究与计划只进入 HD838A/private-marketing-toolkit 私有仓库，不复制到公开源码仓库；本地路径按实际 checkout 定位。Trellis 使用与维护见 [TRELLIS.md](TRELLIS.md)，按任务读取相关 spec。
