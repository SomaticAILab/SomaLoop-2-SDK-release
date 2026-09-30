# iOS 接入

Somatic AI SDK 支持 iOS 15 及以上。模块名保持 `SomaLoopSDK`；限时原始 ECG 等研究入口使用 `SomaLoopExperimental`。

以下接入步骤仅用于获授权的内部评估与开发测试。当前交付为私有候选，使用范围见 [SDK 评估许可](../LICENSE)。

## 安装

1. 保持交付包 `ios/SomaLoopSDK-Package` 完整，在 Xcode 的 **Add Package Dependencies → Add Local** 中选中该目录，添加 `SomaLoopSDK` 产品；需要研究入口时另加 `SomaLoopExperimental`。
2. 在 `Info.plist` 设置 `NSBluetoothAlwaysUsageDescription`。需要后台蓝牙时启用 **Background Modes → Uses Bluetooth LE accessories**，并按下述生命周期接入。
3. 为 SDK 提供可写会话目录。SDK 文件在设备首次解锁后可访问；系统重启后首次解锁前不能保证恢复。
4. 可打开随包 `ios/SomaLoopSDKDemo/SomaLoopSDKDemo.xcodeproj`。安装到手机时自行配置签名团队。

XCFramework 包含设备及模拟器架构。升级时替换完整 Package，主库与研究库来自同一构建；用 `SomaLoop.version`、`SomaLoop.buildRevision` 对照包根目录的构建报告。

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

func readExperimentalSport(client: SomaLoopClient) async throws -> HistoryBatch {
    try await client.readHistoryBatch(.sport, allowExperimental: true)
}
```

`complete` 与 `interruption == nil` 必须同时检查。需要续页时，仅在原连接、同类未结束读取中使用 `continuation: true`；跨连接恢复使用带 checkpoint 的 `synchronizeHistory`。详细字段和时间规则见[数据语义](数据与时间语义.md)。

对于宿主已经准入、但分项读取状态仍为 `untested` 的设备，可显式调用 `readHistoryBatch(.systemEvents, allowUntested: true)`；此参数也允许实验读取。闹钟入口为 `readSettings(.alarms, allowExperimental: true)`，只有完整列表才返回，部分结果使用历史批次入口获取。`allowUntested` 不放行 `unsupported`，不授予设置写入、校时、清除或研究流权限。

## 限时原始 ECG

```swift
import SomaLoopExperimental

func recordRawECG(client: SomaLoopClient) async throws -> ECGRecording {
    let recording = try await SomaLoopResearch(client: client).recordECG(seconds: 60)
    print(recording.packets.count, recording.stopConfirmed, recording.interruption as Any)
    return recording
}
```

合法时长为 30 至 300 秒。支持范围内的 raw ECG 是兼容候选，不需要固件实验能力开关；仍需满足宿主准入、连接和互斥条件。原始计数没有已验证的电压换算或逐样本时间。保存部分结果，分别判断 `interruption` 和 `stopConfirmed`，不得只按方法成功返回判定录制完整或设备已停止。参见[ECG 返回语义](数据与时间语义.md#原始-ecg)。

## 生命周期

每个逻辑蓝牙控制器长期持有一个客户端。正常断连和重连复用它；不同存活客户端使用不同且稳定的 `restorationIdentifier`，同一控制器跨进程沿用原标识。

需要继续本地待处理采集时，在启动初期调用 `resumePendingSession()`；多条待处理会话返回 `busy`，应明确选择 `resumeSession(directory:)`。恢复可能重连设备并继续尚未请求停止的会话，因此宿主应把恢复行为纳入自己的采集授权与界面状态。

界面前后台切换调用 `setHostBackground(_:)`。用户停止时立即调用 `stopCapture()`；即使设备离线也会先保存停止意图，身份匹配后处理关闭。不要在普通前后台切换时调用 `shutdown()`。

整体结束使用时调用 `shutdown()`，结束观察任务并释放引用。返回不保证蓝牙管理器立即销毁或物理断链回调已发生。强制退出、禁用蓝牙、没电及系统后台调度仍可能中断会话。手机后台与长时间采集范围见[验收状态](验收状态.md)。
