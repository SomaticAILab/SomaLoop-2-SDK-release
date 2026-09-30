# Somatic AI SDK

Somatic AI 可穿戴设备的 iOS / Android SDK，提供二进制库、Swift / Kotlin / Java 示例及接入文档。展示名称统一为 **Somatic AI SDK**；为兼容已有应用，模块 `SomaLoopSDK`、`SomaLoopExperimental` 和包名 `com.somaticai.somaloop` 保持不变。

当前私有评估候选：**0.1.6-beta / build 20**，暂不公开发布。仅使用通过授权私有渠道取得的完整压缩包及校验文件，核对 SHA-256 后解压。主库、可选研究库、Demo 和文档须使用同一构建。

本候选仅供内部评估与开发测试，不授权生产或商业使用、应用商店发布、向终端用户部署或随应用对外分发。商业使用及任何对外分发须另行签署书面协议，具体范围见 [SDK 评估许可](LICENSE)。

## 接入

| 平台 | 安装方式 | 文档 |
| --- | --- | --- |
| iOS 15+ | Xcode 添加随包的本地 Swift Package；内含 XCFramework | [iOS 接入](docs/iOS接入.md) |
| Android API 26+ | Gradle 引用随包的本地 Maven 仓库 | [Android / Java 接入](docs/Android接入.md) |

当前没有远程 Swift Package URL 或托管 Maven 发布地址。`ios/` 和 `android/` 各含可构建的 Demo；手机签名、系统权限和设备选择由接入方完成。

## 功能与使用范围

SDK 提供设备发现与连接、分项能力查询、历史数据读取、设备时钟、主动测量、PPG 与联合采集、限时原始 ECG、马达节拍和本地导出。能连接设备不表示每项功能均可用，调用前读取能力快照并处理真实返回结果。

- [API 与错误处理](docs/API与错误码.md)：调用入口、实验/未验证读取和能力边界。
- [数据与时间语义](docs/数据与时间语义.md)：返回字段、单位、缺失值、睡眠时间和 ECG 限制。
- [采集与马达节拍](docs/采集与马达节拍.md)：停止、取消、恢复及导出。
- [实验性历史清除](docs/历史清除.md)：不可逆操作、显式确认、部分执行和读回验证。
- [验收状态](docs/验收状态.md)：软件测试与真机证据的范围。

本 SDK 面向非医疗用途。设备标签和原始计数不构成诊断、治疗建议或经独立医学验证的结论。历史清除仍为实验性；原始 ECG 的真实波形、采样率、增益和准确性尚未完成真机验收。

评估范围及副本限制见 [SDK 评估许可](LICENSE)，第三方声明见 [NOTICE](legal/NOTICE.md)。取得候选包或通过测试不构成生产、商业使用或对外分发授权；第三方组件自身许可授予的权利不受 SDK 评估限制缩减。

## 构建核对

[build-identity.json](build-identity.json)记录本包构建身份，[release-report.json](release-report.json)记录对应制品的验证结果；[SHA256SUMS](SHA256SUMS)用于检查包内文件。运行时 `SomaLoop.version` 和 `SomaLoop.buildRevision` 应与本包身份一致。保留历史采集中的原构建身份，不用当前版本覆盖旧记录。

## 版本记录

0.1.6-beta / build 20 使用独立交付文档和仅评估许可，保持私有候选状态，保留兼容的公开 API，并明确实验性清除与未完成的硬件验收。详细变更见 [CHANGELOG](CHANGELOG.md)。
