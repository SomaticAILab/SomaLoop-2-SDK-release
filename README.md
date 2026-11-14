# SomaLoop 2 SDK

SomaLoop 2 SDK 提供可穿戴设备的 iOS / Android 原生接入，提供二进制库、Swift / Kotlin / Java 示例及接入文档。

版本：**0.2.1 / build 43**。支持有效四字节 BCD 固件 **≥0.0.8.8（含）**，不设上限。公开模块为 `SomaLoopSDK`、`SomaLoopExperimental`，Android 包名为 `com.somaticai.somaloop`。

公开提供下载，按 [SDK 评估许可](LICENSE) 用于内部评估；商业使用或再分发需另行授权。

## 接入

远程仓库接入、版本锁定及随包本地方式见[远程依赖接入](docs/远程依赖接入.md)。0.2.1 新增的逐页保存、停止锚点证据分级及 iOS 绑定设备恢复见[分页同步与后台连接](docs/分页同步与后台连接.md)。

| 平台 | 安装方式 | 文档 |
| --- | --- | --- |
| iOS 15+ | Xcode 添加随包的本地 Swift Package，引用 XCFramework | [iOS 接入](docs/iOS接入.md) |
| Android API 26+ | Gradle 引用随包的本地 Maven 仓库 | [Android / Java 接入](docs/Android接入.md) |

`ios/` 和 `android/` 各含 Demo。主库、可选研究库及 Demo 使用同一构建；手机安装时配置签名和系统权限。

## 功能

| 功能 | 用法 |
| --- | --- |
| 设备发现与连接 | 扫描、选择设备、连接后查询分项能力 |
| 恢复出厂 | `prepareFactoryReset` / `requestFactoryReset` / `verifyFactoryResetRecovery`；先准备充电底座，详见[恢复出厂](docs/恢复出厂.md) |
| 设备名称 | `readDeviceName` 读取设备字段，`setDeviceName` 改名；实际广播名需重新扫描确认 |
| 设备信息与设置 | 读取信息、时钟和设置快照；闹钟返回完整列表 |
| 历史读取 | 15 类历史（包含 alarms）及独立闹钟设置读取默认可调用，保存记录并检查完成／中断状态 |
| 采集与测量 | PPG、联合 PPG + ACC、独立 ACC、限时原始 ECG、心率／血氧／HRV 主动测量 |
| 马达节拍 | 播放、停止、取消、待停止恢复和会话导出 |
| 本地数据 | 会话持久化、恢复、导出和诊断摘要 |
| 实验性历史清除 | 准备和执行各显式启用实验功能，执行另需确认 |

15 类历史（包含 alarms）及独立闹钟设置读取默认可用。联合采集、主动佩戴检查、设备校时、恢复出厂、raw ACC（C）和内建睡眠／连续心率时间规则适用于 0.0.8.8 及以上固件，实时诊断为 U（`untested`）。新固件的 `heartRateStateSnapshots` 历史另需显式实验启用，不计入默认 15 类。具体准入通过能力快照查询。每日步数目标由 App／服务端维护。

本包的实际二进制身份和软件验证见 `build-identity.json` 与 `release-report.json`；设备实测和剩余限制见[功能支持范围](docs/验收状态.md)。0128 实测仍存在原始采集期间连续心率历史缺口、独立 PPG 序号缺口和链路中断，采样时钟未确认。

## 使用流程

1. 建立事件订阅并扫描设备。
2. 连接选定设备，读取能力快照。
3. 在客户端空闲时读取数据或发起采集、测量、马达操作。
4. 用 `stopCaptureWithResult()` 停止采集，检查 `outcome` 和 `cleanupPending`。
5. 用 `exportSession` 导出包含原始日志、会话状态和校验和的目录。

设备电量、接触状态、历史读取和 60 秒 ACC 示例见两端接入文档；同一客户端一次执行一项操作。正式 HRV 输出通过 `PPIHRV.fromBatch` 从完整 PPI 历史计算，字段、缺失处理及应用示例见[数据与时间语义](docs/数据与时间语义.md)。

历史清除是不可逆操作，0.0.8.8 及以上开放实验入口。马达是普通功能；停止恢复核对原会话的设备、固件和日期。

- [API 与错误处理](docs/API与错误码.md)
- [数据与时间语义](docs/数据与时间语义.md)
- [采集与马达节拍](docs/采集与马达节拍.md)
- [历史清除](docs/历史清除.md)

使用范围见 [SDK 评估许可](LICENSE)，第三方声明见 [NOTICE](legal/NOTICE.md)。

版本变更见 [CHANGELOG](CHANGELOG.md)。



## 文档修订 · 2026-11-14

当前接入文档已按 build 43 的实际实现修正恢复出厂、设备 HRV、心率状态历史、联合解析、佩戴检查及睡眠时间规则的兼容范围。范围继承的调用支持与具体设备验证分别记录。正式二进制及其原始校验和见 [0.2.1 / build 43 Release](https://github.com/SomaticAILab/SomaLoop-2-SDK-release/releases/tag/v0.2.1-build43)。
