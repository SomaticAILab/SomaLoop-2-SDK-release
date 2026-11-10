# API 与错误处理

0.2.1 新增 `HistorySyncOptions` 逐页回调与软预算、`historyAnchorSupport`，以及 iOS `setConnectionRecoveryTarget(id:expectedMAC:)`。调用、完成／中断语义和平台限制见[分页同步与后台连接](分页同步与后台连接.md)。

## 0.2.0 新接口与迁移

主库、实验库与 Demo 使用同一版本并重新编译；原模块与包名保持。最低固件准入不等于每项能力可用，新增历史枚举也须处理未知值。0088 生成时间规则不能直接套用到升级后生成的 0128 历史。

`CaptureRecoverySupervisor` 是显式启用的恢复管理入口。Swift 用 `init(storageRoot:exportRoot:bluetoothMode:)`，Kotlin 用 `CaptureRecoverySupervisor(context, storageRoot, exportRoot)` 创建，再根据当前用户意图调用 `begin`。通过 `events()` 和 `status()` 观察，`begin` 返回不等于已有有效帧。暂停调用 `pauseOrStop()`，等待 `operationStillActive=false` 且阶段为 `paused/completed` 后再 `close()`。权限或蓝牙环境恢复后调用 `retryAfterEnvironmentChange()`；不要另建同设备的连接／看门狗循环。监督器不保证系统挂起、强退后自动执行，不自动继承上次进程的采集授权。

`FirmwareUpdater` 负责固件下载校验、停止与导出交接、传输和升级后核验。App 从可信配置提供 `FirmwareReleaseSource(catalogURL, catalogSHA256)`；Swift 使用对应具名参数。`checkForUpdate` 只检查发行信息，用户选择升级后调用 `update`；由监督器持有采集时使用 Swift `supervisor.updateFirmware(using:from:)` / Kotlin `supervisor.updateFirmware(updater, source)`。Java 使用 `FirmwareUpdaterJava` 的回调入口。0128 固件服务已上线，build 40 可配置清单 URL `https://api-staging.somaticai.cn/firmware/somaloop2/0128-261016/catalog.json` 与可信 SHA-256 `c221383a54a00599fb1e82e5fb49ef6e1c74bb9385ae027f299109a4f5827c44`。SDK 按清单下载 ZIP 并校验，仅允许审核来源 `00000808-260604` 升级至 `00010208-261016`。固件包通过服务端分发。

build 41 可直接使用 Swift `FirmwareReleaseSource.somaloop2Firmware0128` 或 Kotlin/Java `FirmwareReleaseSource.SOMALOOP_2_FIRMWARE_0128`。检查清单后，以 Swift `release.isUpdateAvailable(for: profile)` 或 Kotlin/Java `release.isUpdateAvailable(profile)` 判断设备是否属于审核过的升级来源。Swift 宿主可向 `FirmwareUpdater` 传入 `networkConfiguration: URLSessionConfiguration` 设置本次下载的网络策略，SDK 复制该配置并继续校验下载内容。

升级期间保持前台；`cancel()` 不代表回滚，进程重启后的 `resume` 需宿主显式调用。`bootloaderSelectionRequired` 要求用户识别本次扫描中的物理目标，不能按名字或信号强度自动选择；`retirementUnconfirmed` 保留连接所有权，不能靠新建实例绕过。只有升级后身份和目标版本核验通过才显示完成；之后创建新采集会话。生产 HTTPS 供包、手机升级和断电恢复尚未完成设备验收。

可选实验模块的 `FirmwareRRIParser(device)` 消费完整 `SDKEvent` 序列，或同一已识别会话、按原顺序输入的 `JournalRecord`；切换会话须 `reset()` 或新建解析器。Swift 用 `init(device:)`，Kotlin／Java 使用构造函数和 `consume`。解析器不连接设备或启动流；输出 `intervalRaw`、`confidenceRaw`、`timePointRaw`、首末接收定位，单位保持 `unknown`、质量为 `firmwareUnvalidated`、`timingVerified=false`，不能直接送入正式 HRV 算法。

历史记录级装批、`historyWithDeviceTiming` 的契约修订选择及 `PairedTimingContract` 见[数据与时间语义](数据与时间语义.md)。实际限制和证据范围见[功能支持范围](验收状态.md)。

Swift 使用 actor 和 `async/await`；Kotlin 主要使用 `suspend` 与 `Flow`；Java 使用 `SomaLoopJava.Callback<T>` 和事件订阅。

本文的“宿主”指接入 SDK 的 App。`compatibleCandidate` 表示调用路径开放，具体设备的数据、后台运行和长时间采集仍需分别验证；`unknown` 表示信息不足，不等于零或关闭。

## 入口

| 任务 | Swift | Kotlin / Java |
| --- | --- | --- |
| 事件 | `events()` | Kotlin `events()`；Java `observe(listener)` |
| 恢复出厂 | `prepareFactoryReset`、`requestFactoryReset`、`readFactoryResetAttempt`、`verifyFactoryResetRecovery` | 同名；Java 使用 Callback，见[恢复出厂](恢复出厂.md) |
| 扫描与连接 | `scan`、`stopScan`、`connect`、`disconnect` | 同名 |
| 宿主系统连接列表 | `retrieveConnectedDevices` | 无对应入口（仅 Apple 平台） |
| 能力 | `capabilities`、`capabilitySnapshot` | 同名 |
| 电量 / 接触状态 | `readBattery`、`readWearState` | 同名；Java 使用 Callback |
| 时钟纪元 | `currentClockEpoch`、`lastClockWriteAttempt` | Kotlin 同名属性；Java `currentClockEpoch()` |
| 停止结果 / 本地恢复 | `stopCaptureWithResult`、`abandonPendingCapture` | 同名；Java 使用 Callback |
| 采集恢复 / 生命周期 | `resumePendingSession`、`resumeSession`、`setHostBackground`、`shutdown` | 同名 |
| 数据接收状态 | `captureHealth` | `captureHealth`、`captureDataStatus` |
| PPI HRV | `PPIHRV.calculate`、`fromHistory`、`fromBatch` | 同名 |
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

`DecodedPacket.kind` / `historyKind`、`measurements`、`alarmLabel` 与扫描候选视图已包含在 0.1.16 / build 33 发布包中。它们由 SDK 解释包分类、单位和文本，App 无需解析命令字、布局名或原始字节；更早版本按对应发布报告核对接口范围。

| 类型化视图 | 用法 |
| --- | --- |
| `DiscoveredDevice.discoveryKind` / `discoveryEvidence` | `candidate` 或 `unknown`，依据为广播名称或服务；连接后再核对能力 |
| `DecodedPacket.kind` | `history/realtime/ppg/acc/ecg/control/debug/unknown`；历史读取的控制回复仍为 `control` |
| `DecodedPacket.historyKind` | 仅历史记录有值，用于选择具体 `HistoryKind` |
| packet / history record 的 `measurements` | 皮温、距离、热量和步数；保留原值、可空数值、单位与质量 |
| packet / history record 的 `alarmLabel` | 严格 UTF-8 解码的文字及 `decoded/invalidUTF8` 状态 |

Java 通过 `PublicDataViewsKt.getKind(packet)`、`getHistoryKind(packet)`、`getDiscoveryKind(device)`、`getDiscoveryEvidence(device)`、`getMeasurements` 和 `getAlarmLabel` 访问这些视图。后两个方法均支持 `DecodedPacket` / `HistoryRecord`；Kotlin 使用同名扩展属性。

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

raw ECG 和马达默认可调用。联合采集、设备校时、内建历史时间规则和恢复出厂适用于 0.0.8.8 及以上固件。raw ACC 为 C，可通过 `startCapture(accOnly)` 持久采集，实时诊断为 U。`heartRateStateSnapshots` 是新增实验历史，需精确新固件配置及显式实验启用，不属于默认 15 类。

`allowExperimental`／`allowUntested` 读取重载保留兼容，仅控制历史和设置读取；它们不绕过最低固件、`unsupported` 或严格解码，也不启用校时、清除或研究流。

## 结果处理

- 历史批次先保存 `records`，再检查 `complete`、`interruption` 和 `continuationAvailable`。手动续页限原连接和同类未结束读取；跨连接使用 checkpoint 对账。
- 设置读取支持 `time/personalInfo/automaticMeasurement/reminders/alarms/basic`。闹钟仅在取得完整列表后返回快照，部分结果使用历史批次；每日步数目标由 App／服务端维护。
- 主动测量和限时原始 ECG 的合法时长为 30…300 秒。ECG 保存设备原始计数、帧序号、接收统计和 `stopConfirmed`；`interruption` 与停止结果分别处理。
- 校时调用 `synchronizeClock`，先检查 `clockWrite`。写入异常后读取 `lastClockWriteAttempt`，保留已发生的时间变化和新的时间周期。宿主取消对应 Task／协程后，SDK 在预读和写入意图保存后检查取消；iOS 的排队写入还在转交传输层前检查同步撤销标记。通过提交检查并转交传输层后的命令不能保证撤回；失败或取消后保留不确定状态，不自动重试。

采集、历史、主动测量、设置、清除和马达播放共用客户端操作互斥。先结束已有操作，再开始下一项。事件订阅须在操作前建立并及时消费，消费过慢会以 `queueOverflow` 结束订阅。

## 停止与恢复

马达使用普通 `playHaptics` 入口，在前台播放；取消、后台切换和异常均尝试关闭。可用 `HapticPattern.validationIssues` 检查参数，`compile` 对无效参数抛出 `invalidArgument`。

待关闭记录按设备持久保存，恢复关闭核对原 MAC、固件和日期。身份变化时保留待处理记录，相关操作返回 `stopUnconfirmed`；其他设备不受该条记录阻挡。正常停止应答观察和报告保存成功后自动解除占用，无需人工确认，`userConfirmedStopped=false` 不代表忙。仅异常处理收到真实用户反馈后才调用 `confirmHapticsStopped`。`abandonPendingHaptics` 需要非空理由及明确确认，只清理本地待处理项并保存审计，不发送关闭命令。详见[采集与马达](采集与马达节拍.md)。

历史清除不可逆，0.0.8.8 及以上开放实验入口，默认关闭。准备与执行各传 `allowExperimental=true`，执行另传 `confirm=true`；省略实验开关的旧签名返回 `unverifiedCapability`。准备凭证绑定当前连接、设备及类型，执行后重新连接并读回；取消和失败不回滚已发出的请求。详细范围和示例见[历史清除](历史清除.md)。

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
| `stopUnconfirmed` | 重试停止或重连原设备完成关闭；用户确认仅为异常处理 |

Swift 使用 `SDKError`；Kotlin 使用 `SDKException.code`，Java 回调使用 `ErrorCode`。按错误码处理，不解析自由文本。部分结果对象可同时含 `interruption`，应与方法返回值一并保存。

## 电量、接触状态与独立 ACC

`startCapture(accOnly)` 使用持久会话，只开启 ACC；默认一天、最多七天，支持同身份恢复及导出。`ACCFrame` 含六组有符号 XYZ 原始计数，不提供已校准单位或样本时间。

`readBattery` 是空闲时的单条读取；`chargingStateRaw` 和 `voltage.rawValue` 分别保留 SDK 解码的原始充电码和无符号电压值。充电状态、缩放及单位未经确认，枚举为 `unknown`，物理值和单位为 `null`。采集中仍返回 `busy`，只有收到实际电量通知时才发电量事件，不保证固件主动推送。

| `readWearState` 条件 | 行为 |
| --- | --- |
| 固件 | 支持 0.0.8.8 及以上，不设上限；0.1.2.8 及以上使用新固件协议，其余使用 0.0.8.8 协议 |
| 观察时长 | 1–10 秒，默认 5 秒；另计写入和关闭超时 |
| 检查方式 | 短暂打开 PPG / 调试，返回固件接触状态，不留采集目录 |
| 已有操作 / 无信号 / 关闭失败 | 分别为 `busy` / `unknown` / `stopUnconfirmed` 并断连 |

本版本包含 `lastWearCheckDiagnostics`，保存当前客户端最近一次获准检查的关闭诊断；Java 包装器使用 `lastWearCheckDiagnostics()`。报告包含最多五个步骤的 `phase`、写入开始/完成偏移、匹配应答接收偏移、`outcome`、`failureStage` 和错误码，以及 `stopConfirmed` / `disconnectReason`。偏移来自主机单调时钟，写入完成不等于设备确认，`stopConfirmed` 也不证明物理传感器状态。

`00010208-261016` 的调试关闭按原生写完成处理，并同时要求 PPG 停止／退出 ACK 和 3 秒无流数据；不要求调试关闭 ACK。`00000808-260604` 保留原逐命令 ACK 规则，不能套用新固件的短测结论。任一必要条件未满足仍按停止未确认处理。

遇到 `stopUnconfirmed` 时先保存该诊断，等待断连状态，再由 App 显式连接原设备并核对身份；不要紧接着发起 ECG 或其他操作，也不要把重连成功当成上次停止已获确认。该检查不创建持久会话，报告不是可调用 `resumePendingSession` 恢复的待清理任务；不要自动重复佩戴检测造成重连循环。报告仅保存在内存，下一次获准检查会替换；跨检查的 `deviceTag` 不用于关联设备。固件主动佩戴事件的未知码义保持不变。

采集中的 `skinContact` 事件解释完整的固件接触报告；被动接触状态事件保留原码和 `state=unknown`，App 不按非零值推断已佩戴，`touchValue` 阈值也未确认。未接触时提示调整佩戴或停止 PPG。升级需重新编译并补齐新枚举分支。

## SDKEvent 总表

| Swift case | Kotlin / Java 类型 | 处理 |
| --- | --- | --- |
| discovery | Discovery | 按设备 id 更新扫描列表；候选分类不代替连接后的能力核对 |
| connection | Connection | 更新连接状态，不把连接成功当作已有测量数据 |
| device | Device | 保存当前识别信息和能力 |
| raw | Raw | 原始收发日志，接收时间见 JournalRecord |
| packetDiagnostic | Diagnostic | 保留未知/异常包形状 |
| packet | Packet | 已解码包，不重复计入类型化结果 |
| paired | Paired | 完整联合帧 |
| ppg | PPG | `PPGRecord(frame, receive)`；接收记录含宿主时间及原始日志定位 |
| accRecord | ACCRecord | `ACCRecord(frame, receive)`；独立 ACC 的推荐保存/上传入口 |
| acc | ACC | 兼容的 `ACCFrame` 事件；与 accRecord 来自同一通知，不重复上传 |
| skinContact | SkinContact | 固件接触状态，可为 unknown |
| battery | Battery | 类型化电量和接收 Unix 秒 |
| capture | Capture | 会话状态及 stopResult |
| captureHealth | Health | idle / waitingForFirstPacket / receiving / noData / recovering / stopped |
| clock | Clock | 时钟读取快照 |
| clockSynchronized | ClockSynchronized | 校时结果 |
| clockWriteAttempt | ClockWriteAttempted | 已记录的校时尝试及新纪元 |
| haptics | Haptics | 马达报告与待停止状态 |
| error | Failure | 按错误码处理；不能仅因收到错误丢弃已收数据 |

事件不是每个请求的唯一返回通道。停止结果应检查方法结果或 capture 会话；异步事件接收任务应先于扫描/读取启动。Swift 升级时补齐 switch 分支，Kotlin/Java 同样保留未知扩展处理。

`ppg` 和 `accRecord` 为 0.1.13/build29 新增事件。其 `receive` 使用实际接收并落盘的 `JournalRecord`，不会在分发事件时重新生成时间；与同通知的 `raw` 事件共享文件和行定位。用类型化事件保存测量，`raw` 留作诊断；详细去重约定和测试构造器见[数据与时间语义](数据与时间语义.md#实时帧与接收记录)。

## 设备名称读取与改名

0.1.14/build31 新增 `readDeviceName()` 与 `setDeviceName(name)`，均要求设备已连接、通过正常固件准入且客户端空闲；采集、历史同步和其他独占操作中返回 `busy`。能力键为 `deviceNameRead`、`deviceNameWrite`，在支持固件范围内为兼容候选，无实验开关或设备地址白名单；`settingsWrite` 不因此开放其他设置。

本版本适配 `00010208-261016` 的名称读取；该固件的名称写入为 `unsupported`，在发送前拒绝。最低版本准入不代表允许改名，应分别检查两个能力键。

`readDeviceName()` 返回 `DeviceNameReading`：`name` 是设备名称字段中首个 NUL 之前的可打印 ASCII 文本，空字符串保留；编码无法解释时为 `nil/null`，完整通知保存在 `rawHex`。这个字段**不保证等于当前广播名**，也不能当作改名后的校验值。扫描结果的 `DiscoveredDevice.name` 才是扫描时取得的名称，也可能受系统缓存影响；设备身份继续用连接后读回的 MAC 核对。

`setDeviceName` 接受 **1–12 个可打印 ASCII 字符，不能全为空格**。例如 `TBSoma`；中文、控制字符、空字符串和超长输入返回 `invalidArgument`，不自动截断、去掉字符或添加前缀。写入前重新读取并核对当前连接的 MAC；不一致返回 `protocolMismatch`，不发送改名命令。

成功返回 `DeviceNameChangeReceipt(requestedName, responseRawHex)`，表示收到校验正确且与本次请求匹配的应答，`advertisementVerified` 始终为 `false`。SDK 不把期望名称写入 `DeviceProfile.advertisedName`，不自动断开、重扫或恢复出厂。调用方可在收到应答后主动 `disconnect()`、`scan()`，用实际扫描结果展示新名称，再连接核对同一设备。0.1.15/build32 恢复了 `JCV8` 出厂广播前缀识别（包括 `JCV8B`），同时保留 `V5 ` 名称前缀和已知服务 UUID 识别；名称前缀匹配不区分大小写，不要求同时广播服务 UUID。0.1.14/build31 不含恢复逻辑，升级时使用 0.1.15/build32 对应二进制。候选不代表身份已确认。其他名称仍按原文返回，`unknown` 不阻止连接；不会按名称删除扫描结果。不要仅依靠旧名称前缀过滤设备，否则改名后可能找不到。

固件 `00000808-260604` 的独立 Mac 探针实测：写入 `TBSoma` 后，广播为 `V5 TBSoma`，而读取接口仍返回旧名称字段。`V5 ` 是固件行为，SDK 不保证所有固件都添加这个前缀；前缀移除、恢复原厂名称、重启持久性未验证。该次独立探针结果不冒充本构建或手机验收。

**超时、取消、连接中断或写入错误不等于设备未改名。** 单次调用不会自动重发；在决定重试前重新扫描并核对实际状态。固件可能在名称改变后主动断连；没有匹配应答时接口仍报告实际错误，不能宣称改名失败或广播验证成功。

### iOS 蓝牙配置错误

0.1.16 / build 33 新增 `SomaLoopClient(storageRoot:bluetoothMode:firmwarePolicy:connectionClockSync:) throws`，`BluetoothMode` 可选 `.foregroundOnly` 或 `.stateRestoration(identifier:)`。`BluetoothConfigurationError` 是独立的宿主配置错误类型（不在 SDKError 中）：`missingUsageDescription`、`missingBackgroundCentral`、`invalidRestorationIdentifier`。旧非抛错初始化保持兼容，`bluetoothConfigurationError` 可同步读取；无效配置不创建系统蓝牙控制器，扫描/连接抛相同错误。详见 [iOS 配置与分页示例](iOS接入.md)。
