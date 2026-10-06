# iOS 接入

SomaLoop 2 SDK 0.1.11 / build 27 支持 iOS 15 及以上。主模块为 `SomaLoopSDK`；限时原始 ECG 等研究入口使用 `SomaLoopExperimental`。

## 安装

1. 保持交付包 `ios/SomaLoopSDK-Package` 完整，在 Xcode 的 **Add Package Dependencies → Add Local** 中选中该目录，添加 `SomaLoopSDK` 产品；需要研究入口时另加 `SomaLoopExperimental`。
2. 在 `Info.plist` 设置 `NSBluetoothAlwaysUsageDescription`。需要后台蓝牙时启用 **Background Modes → Uses Bluetooth LE accessories**，并按下述生命周期接入。
3. 为 SDK 提供可写会话目录。SDK 文件在设备首次解锁后可访问；系统重启后首次解锁前不能保证恢复。
4. 运行 Demo 时，先在 `ios/SomaLoopSDKDemo` 执行 `xcodegen generate`，再打开生成的 `SomaLoopSDKDemo.xcodeproj`，并配置签名团队。

XCFramework 包含设备及模拟器架构。升级时替换完整 Package，保持主库与研究库版本一致。`SomaLoop.version` 为版本号，`SomaLoop.buildRevision` 为源码与构建输入指纹；数字构建号见随包 `build-identity.json` 的 `buildNumber`。

## 发现与连接

```swift
import Foundation
import SomaLoopSDK

let root = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    .appendingPathComponent("SomaticAISessions")
let client = SomaLoopClient(
    storageRoot: root,
    restorationIdentifier: "your.app.somaticai.central"
)

// 先注册事件流，再开始扫描；宿主持有观察任务并处理任务结束。
let events = await client.events()
let observation = Task {
    do {
        for try await event in events {
            switch event {
            case .discovery(let device):
                print(device.id, device.name ?? "未命名设备")
            case .error(let code, let detail):
                print(code, detail)
            default: break
            }
        }
    } catch {
        print("事件订阅结束", error)
    }
}
try await client.scan()
```

扫描没有“所有设备已返回”的完成通知。列表按 `DiscoveredDevice.id` 更新，名称不能用作数据库身份键或功能准入依据。设备选择完成后调用：

```swift
func connectSelected(_ device: DiscoveredDevice, client: SomaLoopClient) async throws {
    await client.stopScan()
    try await client.connect(device)
    let capabilities = await client.capabilitySnapshot()
    print(capabilities)
}
```

`retrieveConnectedDevices()` 可查询同一宿主当前已连接的兼容服务外设，返回列表本身不会建立本客户端连接，仍需 `connect(_:)`。`scan()` 也合并这份系统列表。系统查询得到的 `rssi == 127` 表示未知，应排除出信号强弱排序。此查询不是已配对列表，也看不到仅连接在另一台手机上的设备。

## 读取

以下代码由宿主在连接就绪、客户端空闲时调用：

```swift
func readTemperature(client: SomaLoopClient) async throws -> HistoryBatch {
    let batch = try await client.readHistoryBatch(.temperature)
    let records = try batch.typedRecords
    print(records.count, batch.notificationCount, batch.complete)
    // 先保存 records，再检查 interruption 和 continuationAvailable。
    return batch
}

func readSport(client: SomaLoopClient) async throws -> HistoryBatch {
    try await client.readHistoryBatch(.sport)
}
```

`complete` 与 `interruption == nil` 必须同时检查。需要续页时，仅在原连接、同类未结束读取中使用 `continuation: true`；跨连接恢复使用带 checkpoint 的 `synchronizeHistory`。详细字段和时间规则见[数据语义](数据与时间语义.md)。

SDK 支持有效四字节 BCD 固件版本 ≥0.0.8.8，全部 15 类历史及闹钟读取为 C，默认直接读取。闹钟入口为 `readSettings(.alarms)`，只有完整列表才返回；需要保留部分结果时使用历史批次入口。各接口的固件范围和读取选项见 [API 与错误码](API与错误码.md)。

## 限时原始 ECG

```swift
import SomaLoopExperimental

func recordRawECG(client: SomaLoopClient) async throws -> ECGRecording {
    let recording = try await SomaLoopResearch(client: client).recordECG(seconds: 60)
    print(recording.packets.count, recording.stopConfirmed, recording.interruption as Any)
    // 保存 packets；frames 和 receptionSummary 提供帧及接收统计。
    return recording
}
```

合法时长为 30 至 300 秒。raw ECG 在支持范围内默认可用，调用时客户端须已连接且空闲。`recording.frames` 提供类型化原始帧，包括设备原始计数与序号；`recording.receptionSummary` 统计实际接收样本数和相邻序号不连续次数。

保存完整或部分结果，并分别处理 `interruption` 和 `stopConfirmed`：前者描述录制中断，后者表示停止是否得到确认。请求时长与接收样本数应分别保存。字段定义见 [ECG 返回语义](数据与时间语义.md#原始-ecg)。

## 生命周期

每个逻辑蓝牙控制器长期持有一个客户端。正常断连和重连复用它；不同存活客户端使用不同且稳定的 `restorationIdentifier`，同一控制器跨进程沿用原标识。

每个实际 `storageRoot` 只供一个客户端使用，多个客户端使用不同目录。交接同一目录前，先等待原客户端的 `shutdown()` 完成；`shutdown()` 完成本轮停止尝试及会话存储关闭后释放目录；交接前也要等待宿主发起的其他 SDK 调用结束。目录被占用或失效时操作返回 `storageFailure`。保留 `.somatic-storage.lock`、会话目录及待停止记录，不通过删除文件解除占用；锁文件存在本身不表示仍被占用。目录保护独立于蓝牙控制器标识和设备身份核对，交付状态见[0.1.8 变更](../CHANGELOG.md)。

需要继续本地待处理采集时，在启动初期调用 `resumePendingSession()`；多条待处理会话返回 `busy`，应明确选择 `resumeSession(directory:)`。恢复可能重连设备并继续尚未请求停止的会话，宿主界面应展示相应采集状态。

选择会话时，`storageRoot` 必须对应原会话的父目录，会话须为它的直接子目录；符号链接别名按实际目录核对。待停止意图由恢复流程处理，恢复继续核对原设备 MAC、固件及日期。

界面前后台切换调用 `setHostBackground(_:)`。用户停止时立即调用 `stopCapture()`；即使设备离线也会先保存停止意图，身份匹配后处理关闭。不要在普通前后台切换时调用 `shutdown()`。

整体结束使用时调用 `shutdown()`，结束观察任务并释放引用。蓝牙管理器释放和物理断链回调可能晚于方法返回。强制退出、禁用蓝牙、没电及系统后台调度可能中断会话；宿主应保存停止意图并处理恢复结果。会话文件与恢复流程见 [采集与马达节拍](采集与马达节拍.md)。

## 0.1.9：独立 ACC、电量与接触状态

连接就绪且客户端空闲时读取电量或短时检查接触状态；完成后再开始采集：

```swift
let battery = try await client.readBattery()
let contact = try await client.readWearState(timeoutSeconds: 5)
let session = try await client.startCapture(mode: .accOnly, durationSeconds: 3600)
// 宿主需要停止时：
try await client.stopCapture()
```

独立 ACC 会话支持保存、导出及同身份恢复，最多七天；Demo 提供独立 ACC 按钮和包数/样本数。`readWearState` 会短暂启动 PPG 接触检测，其观察时长不含写入与关闭确认时间。采集中读取电量或主动检查接触状态会返回 `busy`；电量充电码、物理单位及未确认的佩戴事件保持未知。升级须补齐新增枚举分支，并按[API 与错误码](API与错误码.md)处理停止未确认。

## PPI RMSSD（0.1.11 正式算法）

`let results = try PPIHRV.fromBatch(ppiBatch)` 从一次完整的 PPI 历史读取返回数值或 null／原因。有效 `rmssdMilliseconds` 可映射到 `hrv_rmssd`；缺失时跳过评分和提醒更新。默认策略、分组边界与质量存储见[数据与时间语义](数据与时间语义.md)。使用本版本完整二进制包，并重新编译消费者。
