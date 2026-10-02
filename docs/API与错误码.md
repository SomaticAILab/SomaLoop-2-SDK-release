# API 与错误处理

Swift 使用 actor 和 `async/await`；Kotlin 主要使用 `suspend` 与 `Flow`；Java 使用 `SomaLoopJava.Callback<T>` 和事件订阅。

## 入口

| 任务 | Swift | Kotlin / Java |
| --- | --- | --- |
| 事件 | `events()` | Kotlin `events()`；Java `observe(listener)` |
| 扫描与连接 | `scan`、`stopScan`、`connect`、`disconnect` | 同名 |
| 宿主系统连接列表 | `retrieveConnectedDevices` | 无对应入口（仅 Apple 平台） |
| 能力 | `capabilities`、`capabilitySnapshot` | 同名 |
| 设备信息 | `readDeviceInfoPartial`、`readDeviceInfo` | 同名 |
| 历史批次 | `readHistoryBatch` | 同名 |
| 逐页流 | `syncHistory` | Kotlin 同名；Java 使用批次或同步结果入口 |
| 历史对账与 checkpoint | `synchronizeHistory` | `syncHistoryRecords` |
| 设置快照 | `readSettings` | 同名 |
| 读钟 / 校时 | `readDeviceClock`、`synchronizeClock` | 同名 |
| 主动测量 | `measure` | 同名 |
| 持续采集 | `startCapture`、`stopCapture`、`captureHealth` | 同名 |
| 会话 / 导出 | `currentSession`、`exportSession`、`exportDiagnostics` | 同名 |
| 马达节拍 | `playHaptics`、`stopHaptics`、`currentHaptics`、`confirmHapticsStopped` | 同名 |
| 马达待处理管理 | `pendingHaptics`、`abandonPendingHaptics`、带 `sessionID` 的 `exportHaptics` | 同名；Java 使用回调重载 |
| 限时原始 ECG | `SomaLoopResearch.recordECG` | Kotlin 同类方法；Java `recordECG` |
| 实验性历史清除 | `prepareHistoryErasure`、`eraseHistory` | 同名 |

`readDeviceInfoPartial()` 返回成功的 `packets` 和按查询项记录的 `errors`。`readDeviceInfo()` 只有全部查询均无成功结果时才抛错。

`DeviceInfoResult.batteryReading`、`DecodedPacket.measurementValues` 和 `ECGRecording.receptionSummary` 提供类型化值及接收统计；Swift 另有 `ECGRecording.frames`，Java 对应 `ApiViews` 静态方法。字段与单位见[数据语义](数据与时间语义.md)。

## 固件与能力

最低固件为有效四字节 BCD **≥0.0.8.8（含）**，不设上限。宿主准入策略可收紧范围。连接就绪后读取能力快照，按分项状态和 `available` 控制操作；断连、关闭、忙碌和马达后台状态仍会限制调用。

| 状态 | 调用方式 |
| --- | --- |
| C：`compatibleCandidate` | 默认可调用，仍须满足连接、权限和互斥条件 |
| E：`experimental` | 按接口显式启用；历史清除的准备和执行各需 `allowExperimental=true` |
| U：`untested` | 默认不开放；历史／设置读取保留 `allowUntested` 重载 |
| `unsupported` | 不可调用，读取开关不放行 |
| `verifiedReference` | 保留兼容的状态值 |

历史类型为 `activity`、`steps`、`sleep`、`heartRate`、`singleHeartRate`、`hrv`、`alarms`、`sport`、`temperature`、`ppi`、`spo2`、`sleepActivity`、`sleepDebug`、`systemEvents`、`powerDebug`。这 15 类和闹钟设置读取均为 C，默认无需读取开关。`historyByKind` 以这些名称为键；原 `history` 表保留。Java 使用 `ApiViews.historyByKind(snapshot)`。

raw ECG 和马达默认可调用。联合采集、校时及历史时间规则仅使用 **0.0.8.8／固件日期 260604** 配置；raw ACC 为 E，通过研究入口显式选择，实时诊断为 U。

`allowExperimental`／`allowUntested` 读取重载保留兼容，仅控制历史和设置读取；它们不绕过最低固件、`unsupported` 或严格解码，也不启用校时、清除或研究流。

## 结果处理

- 历史批次先保存 `records`，再检查 `complete`、`interruption` 和 `continuationAvailable`。手动续页限原连接和同类未结束读取；跨连接使用 checkpoint 对账。
- 设置读取支持 `time/personalInfo/automaticMeasurement/reminders/alarms/basic`。闹钟仅在取得完整列表后返回快照，部分结果使用历史批次；每日步数目标由 App／服务端维护。
- 主动测量和限时原始 ECG 的合法时长为 30…300 秒。ECG 保存设备原始计数、帧序号、接收统计和 `stopConfirmed`；`interruption` 与停止结果分别处理。
- 校时调用 `synchronizeClock`，先检查 `clockWrite`。写入异常后读取 `lastClockWriteAttempt`，保留已发生的时间变化和新的时间周期。

采集、历史、主动测量、设置、清除和马达播放共用客户端操作互斥。先结束已有操作，再开始下一项。事件订阅须在操作前建立并及时消费，消费过慢会以 `queueOverflow` 结束订阅。

## 停止与恢复

马达使用普通 `playHaptics` 入口，在前台播放；取消、后台切换和异常均尝试关闭。可用 `HapticPattern.validationIssues` 检查参数，`compile` 对无效参数抛出 `invalidArgument`。

待关闭记录按设备持久保存，恢复关闭核对原 MAC、固件和日期。身份变化时保留待处理记录，相关操作返回 `stopUnconfirmed`；其他设备不受该条记录阻挡。用户确认停止后调用 `confirmHapticsStopped`。`abandonPendingHaptics` 需要非空理由及明确确认，只清理本地待处理项并保存审计，不发送关闭命令。详见[采集与马达](采集与马达节拍.md)。

历史清除不可逆，仅 0.0.8.8 开放实验入口，默认关闭。准备与执行各传 `allowExperimental=true`，执行另传 `confirm=true`；省略实验开关的旧签名返回 `unverifiedCapability`。准备凭证绑定当前连接、设备及类型，执行后重新连接并读回；取消和失败不回滚已发出的请求。详细范围和示例见[历史清除](历史清除.md)。

## 错误

| 错误码 | 处理方式 |
| --- | --- |
| `permissionDenied`、`bluetoothUnavailable` | 处理系统权限和蓝牙状态 |
| `disconnected` | 保存部分结果，重新连接并核对身份 |
| `busy` | 等待或停止当前操作 |
| `timeout` | 保存已收结果和超时状态 |
| `cancelled` | 查询已发起操作的停止状态或清除报告 |
| `invalidArgument` | 校正参数、确认值或凭证有效期 |
| `unsupportedProfile`、`unverifiedCapability` | 检查固件准入和分项能力 |
| `malformedPacket`、`protocolMismatch` | 保存诊断上下文，重新建立有效读取状态 |
| `queueOverflow` | 减轻事件处理负担并保存中断信息 |
| `storageFailure` | 处理目录权限、文件或空间问题，保留待停止状态 |
| `timingViolation`、`linkTooSlow` | 停止马达操作并保留报告 |
| `stopUnconfirmed` | 处理持久待关闭项和用户停止确认 |

Swift 使用 `SDKError`；Kotlin 使用 `SDKException.code`，Java 回调使用 `ErrorCode`。按错误码处理，不解析自由文本。部分结果对象可同时含 `interruption`，应与方法返回值一并保存。
