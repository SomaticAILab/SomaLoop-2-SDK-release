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

本分发包 0.1.6-beta / build 20 的设置枚举为 `SettingKind.time/personalInfo/stepGoal/automaticMeasurement/reminders/alarms/basic`。其中 `stepGoal` 为 `unsupported`，不可调用。闹钟只有完整列表才返回 `SettingSnapshot`；部分数据使用 `readHistoryBatch`。通用 `updateSettings` 尚未开放，不能因为存在方法就将设置写入作为可用功能。校时走独立 `synchronizeClock`，调用前检查 `clockWrite` 能力；写入失败时仍可能改变设备时间，保留 `lastClockWriteAttempt` 和新的时间周期标识。

每日步数目标是 App 的偏好设置，由 App 保存并根据 SDK 返回的实际步数计算进度；需要跨设备同步时可由服务端保存。实际步数读取不依赖 `stepGoal`。iOS / Android 的待发布源码分支已移除该枚举，尚未合入源码主分支，也没有对应新分发包；此处 build 20 的枚举说明仍适用于当前二进制。后续升级到移除该枚举的版本时，删除旧引用，在解码前迁移或排除持久化的 `stepGoal` 值，并重新编译消费者。版本区别见 [变更记录](../CHANGELOG.md)。

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

## 2026-10-02 · 仅源码的新接口与行为预告

**以下不属于本分发包 0.1.6-beta / build 20 的接口或运行时行为。** 原 build 20 的上方入口表、固件/能力及设置说明继续有效；须取得重新构建并验证的新 SDK，按新构建身份核对主库/研究库，并重新编译 Swift／Kotlin／Java 消费者后，才可使用新增入口。

| 源码变化 | 升级后的契约与边界 |
| --- | --- |
| 最低固件与读取 | 仅有效四字节 BCD ≥0.0.8.8，含最低且无上限；全部 15 类历史及闹钟读取为 `compatibleCandidate`。该状态表示兼容路径，不等于所有内容、平台或医学准确性均已验证；较高固件不自动拥有精确联合解析/时间配置。 |
| 历史清除 | 仅 0.0.8.8 保留实验候选；新增 `prepareHistoryErasure(..., allowExperimental)` 和 `eraseHistory(..., confirm, allowExperimental)`。两阶段分别显式启用，执行另需确认；旧签名在发帧前拒绝。原 build 20 未获得这一默认关闭保护，仍适用原接口。 |
| 马达待停止 | `pendingHaptics`、`abandonPendingHaptics`、带会话 ID 的 `exportHaptics`；待处理按设备保存。审计放弃要求理由及明确确认，不发帧、不证明停止。精确原 MAC/固件/日期恢复保护保留。 |
| 联合采集 | 健康/续期以有效联合帧为准，独立 PPG 另行统计；每次联合启动首次帧宽限 15 秒。分类记录 SDK 断连请求和传输通知，不能相加当作物理断连数。停止/识别 ACK 缺失不能用持续数据代替确认。 |
| 附加读取视图 | `batteryReading`、`measurementValues`、Swift ECG `frames` 和双端 `receptionSummary`／`sampleCount`；Java 使用 `ApiViews`。不补造读取时间、标准 HRV、采样率、期望样本数或录制完整性。 |
| 能力/模式/参数 | 可读 `historyByKind`、显式 `serverMode`、`HapticPattern.validationIssues`；旧能力键、模式序列化与错误码保留。断连/关闭中普通能力不可用，马达还要求前台，实际操作仍检查互斥。 |
| 设备时钟 | `hasLargeOffsetWarning` 仅在已知绝对钟差至少 1 小时时标记；时区未知保持未知。先保存历史和校时前上下文，再显式校时，不统一平移旧历史。 |
| 历史上传 | 显式 `SomaContractRevision`／`historyForContract` 保留旧默认；选择已核对的新契约后开放 sleepDebug/systemEvents 原始记录，缺年/秒的 powerDebug 仍以日历精度不足拒绝。 |
| 导出与重放 | 相同已确认停止且无 cleanup 的最终状态稳定导出；活动前缀不用于反复最终上传。`ReplayMismatch`／`lastMismatch` 提供零基索引及期望/实际命令，数学样例不属于设备验收。 |
| 品牌与步数目标 | 源码展示统一 Somatic AI SDK / Somatic AI，模块/包名/坐标不改。删除 `stepGoal` 的迁移要求保持；本包仍含不可调用的旧枚举。 |

本轮没有新二进制发布。律师确认实际许可主体及四项补充条款仍待完成，正式 `LICENSE` 保持原样；英文文档、远程二进制 Swift Package 与托管 Maven 未交付。源码测试、模拟传输与旧制品的 CI／消费者证据分别绑定其自身身份，不能相互替代。完整区别见[仓库变更记录](../CHANGELOG.md)和[文档来源记录](../documentation-revision.json)。
