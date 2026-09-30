# API 与错误处理

Somatic AI SDK 的 Swift 方法使用 actor 和 `async/await`；Kotlin 读取/写入主要为 `suspend`；Java 通过 `SomaLoopJava.Callback<T>` 接收结果。下表中的名称为实际公开 API，参数与示例见两端接入文档。

## 入口

| 任务 | Swift | Kotlin / Java |
| --- | --- | --- |
| 事件 | `events()` | Kotlin `events()`；Java `observe(listener)` |
| 扫描与连接 | `scan`、`stopScan`、`connect`、`disconnect` | 同名 |
| 当前宿主系统连接列表 | `retrieveConnectedDevices` | 无对应公共入口 |
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
| 限时原始 ECG | `SomaLoopResearch.recordECG` | Kotlin 同类方法；Java `recordECG` |
| 实验性历史清除 | `prepareHistoryErasure`、`eraseHistory` | 同名 |

`readDeviceInfoPartial()` 同时返回 `packets` 与按查询项记录的 `errors`。一项失败不丢弃其他成功项。简化的 `readDeviceInfo()` 只有全部查询都无成功结果时才抛错；数组非空不表示每项都成功。

## 能力和固件

| `CapabilityState` | 应用处理 |
| --- | --- |
| `compatibleCandidate` | 有兼容调用路径，仍须处理真实设备结果；不代表当前制品完成全部真机测试 |
| `experimental` | 历史/设置读取需明确 `allowExperimental=true` 或适用的 `allowUntested=true` |
| `untested` | 不能靠实验开关放行；仅历史/设置读取有显式未验证读取重载 |
| `unsupported` | 不可调用，两个读取开关都不放行 |
| `verifiedReference` | 保留兼容旧记录；不作为当前所有设备或功能的验证结论 |

读取能力快照中的分项状态与可用原因，不用 profile 汇总状态开启全部按钮。固件准入、当前连接状态、忙碌互斥和分项能力是不同条件。

默认固件策略接受有效版本至 0.0.8.8，宿主可收紧或配置额外版本；被允许连接不自动获得范围外功能。支持范围内 raw ECG 和马达为兼容候选，不依赖固定设备地址或实验能力开关。主动测量可对成功识别且就绪的设备发起，实际数据仍由设备返回决定。联合采集仅支持已有精确固件配置，不能通过其他功能的可用状态推断其可用。

历史类型包括 `activity`、`steps`、`sleep`、`heartRate`、`singleHeartRate`、`hrv`、`alarms`、`sport`、`temperature`、`ppi`、`spo2`、`sleepActivity`、`sleepDebug`、`systemEvents`、`powerDebug`。最后三类为诊断记录，不应当作已解释的健康指标。`singleHeartRate`、`sport` 和三类诊断历史为实验读取；其他类型也可能随固件需要实验读取，以快照为准。

`allowUntested=true` 仅用于历史和设置读取，先满足宿主固件准入，再允许 `experimental` / `untested` 的只读尝试，不改变验证状态、时间规则或错误语义。它不作用于设置写入、校时、清除和研究流。

设置读取使用 `SettingKind.time/personalInfo/stepGoal/automaticMeasurement/reminders/alarms/basic`。`stepGoal` 当前为 `unsupported`。闹钟只有完整列表才返回 `SettingSnapshot`；部分数据使用 `readHistoryBatch`。通用 `updateSettings` 尚未开放，不能因为存在方法就将设置写入作为可用功能。校时走独立 `synchronizeClock`，调用前检查 `clockWrite` 能力；写入失败时仍可能改变设备时间，保留 `lastClockWriteAttempt` 和新的时间周期标识。

## 调用约束

采集、历史读取、主动测量、设置、清除和马达播放不能同时占用同一客户端。先完成已有操作或显式停止，再执行下一项。主动测量和有限 ECG 的时长为 30 至 300 秒。

事件订阅应在发起操作前建立。观察者有有界缓冲，消费过慢可能 `queueOverflow` 并结束订阅；UI 事件不是可靠持久日志。连接 `ready`、采集 `receiving` 和物理效果已经验证是不同结论。

## 错误

| 错误码 | 处理建议 |
| --- | --- |
| `permissionDenied`、`bluetoothUnavailable` | 处理系统权限/蓝牙状态，避免连续重试 |
| `disconnected` | 保留部分结果；重新连接并核对身份后再决定新操作 |
| `busy` | 等待或停止当前操作；历史未完成续页也会占用客户端 |
| `timeout` | 保留实际已收结果，不改写为完整或空数据 |
| `cancelled` | 取消不代表已经执行的写入被回滚，检查清除/采集/研究的停止和报告 |
| `invalidArgument` | 校正参数；清除时包括未确认、空/重复类型和过期凭证 |
| `unsupportedProfile`、`unverifiedCapability` | 检查固件准入与分项能力，不通过改标签伪造可用性 |
| `malformedPacket`、`protocolMismatch` | 保存诊断上下文；不补造缺失数据或复用失效读取状态 |
| `queueOverflow` | 降低订阅处理负担并记录中断，避免无限排队 |
| `storageFailure` | 处理空间、权限或文件问题；保存停止状态，不能报告导出成功 |
| `timingViolation`、`linkTooSlow` | 马达时序/链路检查未通过；保留报告，不放宽阈值掩盖失败 |
| `stopUnconfirmed` | 关闭尚未确认，检查待关闭报告和使用者反馈 |

Swift 使用 `SDKError`；Kotlin 的 `SDKException.code` 和 Java 回调使用 `ErrorCode`。不要以自由文本匹配错误类别。部分结果对象可能同时含 `interruption`，方法返回成功不代表业务结果完整。

详见[数据语义](数据与时间语义.md)、[采集与马达](采集与马达节拍.md)及[实验性历史清除](历史清除.md)。
