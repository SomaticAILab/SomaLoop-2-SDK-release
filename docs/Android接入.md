# Android / Java 接入

SomaLoop 2 SDK 0.1.15 / build 32 支持 Android API 26 及以上，包名为 `com.somaticai.somaloop`。

## 安装与构建

随包 `android/SomaLoopSDKDemo` 通过相邻的 `repository` 使用本地 Maven 包；其他宿主按自己的目录调整路径。

```kotlin
// settings.gradle.kts
dependencyResolutionManagement {
    repositories {
        maven { url = uri("../repository") }
        google()
        mavenCentral()
    }
}

// app/build.gradle.kts
dependencies {
    implementation("com.somaticai.somaloop:sdk:0.1.15")
    implementation("com.somaticai.somaloop:experimental:0.1.15") // 研究入口，可选
}
```

升级时替换完整交付包，保持主库、研究库与依赖清单版本一致。`SomaLoop.version` 为版本号，`SomaLoop.buildRevision` 为源码与构建输入指纹；数字构建号见随包 `build-identity.json` 的 `buildNumber`。

Demo 工具链为 JDK 17、Gradle 8.11.1、AGP 8.10.1、Kotlin 2.1.10，compile/target SDK 36。随包本地 Maven 仓库同时提供清单列出的运行依赖，Gradle 从配置的本地/远程仓库解析，并非全部在线下载。包内运行依赖见 `android/dependencies.json`；宿主统一已有 Kotlin/协程依赖版本，避免重复引入 JAR。Android Studio、平台 SDK 和构建插件需要自行准备。

在 `android/SomaLoopSDKDemo` 执行 `./gradlew :app:assembleDebug`，或通过 Android Studio 运行 Demo。

## 权限、服务与连接

- API 26–30 申请位置权限；部分系统还要求位置开关开启。
- API 31+ 申请 `BLUETOOTH_SCAN` 和 `BLUETOOTH_CONNECT`。
- API 33+ 按应用的通知流程申请 `POST_NOTIFICATIONS`。

可见 Activity 显式发起采集，前台服务采用 `connectedDevice` 类型并提供可见停止入口。Manifest 声明不替代运行时授权，不能从任意后台状态启动前台服务。

Demo 的 `MainActivity.kt` 展示服务绑定、授权和用户设备选择。绑定后从 `LocalBinder.client` 取得唯一客户端；在宿主管理的协程作用域中持续消费事件：

```kotlin
import com.somaticai.somaloop.*
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.flow.collect
import kotlinx.coroutines.launch

fun observeAndScan(scope: CoroutineScope, client: SomaLoopClient) {
    scope.launch(start = CoroutineStart.UNDISPATCHED) {
        try {
            client.events().collect { event -> println(event) }
        } catch (error: Exception) {
            println("事件订阅结束: $error")
        }
    }
    scope.launch { client.scan() }
}

suspend fun connectSelected(client: SomaLoopClient, device: DiscoveredDevice) {
    client.stopScan()
    client.connect(device)
    println(client.capabilitySnapshot())
}
```

事件处理应迅速完成，重计算移到其他工作队列。扫描列表按设备 `id` 更新，不能只靠广播名启用功能。示例片段中的调用异常还需纳入宿主统一错误处理。

0.1.13/build29 新增 `device.discoveryKind` / `discoveryEvidence` 扩展属性：`candidate` 表示广播信息匹配，`unknown` 表示暂无依据；连接后再核对实际能力，不按候选标记直接启用功能。Java 对应 `PublicDataViewsKt.getDiscoveryKind(device)` / `getDiscoveryEvidence(device)`。本版本目前为本地开发候选，旧发布包不包含这些新增接口。

连接就绪并取得权限后，可从可见 Activity 调用 `SomaLoopCaptureService.startCapture(activity, CaptureMode.paired, 60.0)`；停止入口调用 `client.stopCapture()`。Activity 销毁只解除绑定，不在旋转屏幕时关闭服务持有的采集客户端。服务重建可能恢复本地未结束会话；用户强制停止应用后不承诺自动恢复。

自建服务可用 `SomaLoopClient(context, storageRoot)`，但须承担相同权限、通知和生命周期责任。用 `setHostBackground(true/false)` 上报实际前后台，整个服务结束使用时才 `shutdown()`。

每个实际 `storageRoot` 只供一个客户端使用，多个客户端使用不同目录。交接同一目录前，在协程中等待原客户端的 `shutdown()` 完成；`shutdown()` 完成本轮停止尝试及会话存储关闭后释放目录；交接前也要等待宿主发起的其他 SDK 调用结束。目录被占用或失效时操作返回 `storageFailure`。保留 `.somatic-storage.lock`、会话目录及待停止记录，不通过删除文件解除占用；锁文件存在本身不表示仍被占用。目录保护独立于设备身份核对，交付状态见[版本记录](../CHANGELOG.md)。

恢复待处理会话使用 `resumePendingSession()`；多条会话时用 `resumeSession(directory)` 明确选择。`storageRoot` 必须对应原会话的父目录，会话须为它的直接子目录，符号链接别名按实际目录核对。停止意图由恢复流程处理，恢复继续核对原设备 MAC、固件及日期。

## Kotlin 读取

```kotlin
suspend fun readTemperature(client: SomaLoopClient): HistoryBatch {
    val batch = client.readHistoryBatch(HistoryKind.temperature)
    val records = batch.records.map { HistoryDecoder.decode(it) }
    println("${records.size} records; complete=${batch.complete}")
    // 保存部分 records，再检查 interruption 和 continuationAvailable。
    return batch
}

suspend fun readSport(client: SomaLoopClient): HistoryBatch =
    client.readHistoryBatch(HistoryKind.sport)
```

SDK 支持有效四字节 BCD 固件版本 ≥0.0.8.8，全部 15 类历史（包含 alarms）及独立闹钟设置读取为 C，默认直接读取。闹钟用 `readSettings(SettingKind.alarms)`；不完整时抛错，需要保留部分记录时使用历史批次。各接口的固件范围和读取选项见 [API 与错误码](API与错误码.md)。

`null`、零和字段缺失分别保存；不要把无效心率的空值改成 0，也不要把有效的零步数丢弃。再次读取及事务保存见[增量同步](数据与时间语义.md#增量同步与-clockepoch)，字段处理见[数值与缺失](数据与时间语义.md#数值单位与缺失)。

## Java

`SomaLoopJava` 包裹同一个客户端，使用宿主提供的 `Executor` 回调，不另建 BLE 连接。

```java
import android.os.Handler;
import android.os.Looper;
import com.somaticai.somaloop.*;

// 放在宿主方法内，client 已连接且空闲。
Handler main = new Handler(Looper.getMainLooper());
SomaLoopJava sdk = new SomaLoopJava(client, command -> main.post(command));
sdk.readHistoryBatch(HistoryKind.temperature, false,
    new SomaLoopJava.Callback<HistoryBatch>() {
        @Override public void onSuccess(HistoryBatch batch) {
            System.out.println(batch.getRecords().size());
            // 保存结果，并检查 getComplete()、getInterruption()、getContinuationAvailable()。
        }
        @Override public void onError(ErrorCode code, String message) {
            System.err.println(code + ": " + message);
        }
    });
```

当前支持固件的普通读取用 `sdk.readHistoryBatch(kind, false, callback)`。带 `allowExperimental` / `allowUntested` 的重载保留兼容，最后的布尔值 `allowUntested` 不绕过最低固件或未支持功能。完整同步使用 `syncHistoryRecords(kind, options, callback)`，同样保留带读取开关的重载。

`observe(listener)` 返回可关闭订阅。包装器的 `close()` 只取消自己的任务，不关闭共享客户端，也不释放它的 `storageRoot`；取消可能不再触发成功/失败回调，宿主还须处理所发起操作的停止与结果查询。整个服务结束使用时，在协程中等待客户端 `shutdown()` 完成。

## 限时原始 ECG

```kotlin
import com.somaticai.somaloop.experimental.SomaLoopResearch
import com.somaticai.somaloop.receptionSummary

suspend fun recordRawECG(client: SomaLoopClient): ECGRecording {
    val recording = SomaLoopResearch(client).recordECG(seconds = 60)
    println("${recording.frames.size} frames; stop=${recording.stopConfirmed}")
    println(recording.receptionSummary)
    return recording
}
```

Java 使用 `sdk.recordECG(60, callback)`，回调为 `Callback<ECGRecording>`。合法时长 30 至 300 秒。直接调用 Kotlin client 的研究方法需 `@OptIn(SomaLoopClient.ResearchAPI::class)`，这属于编译期声明，与固件实验读取开关不同。

`frames` 保存设备原始计数与序号；`recording.receptionSummary` 统计实际接收样本数和相邻序号不连续次数。`sampleCount` 也是扩展属性，使用时导入 `com.somaticai.somaloop.sampleCount`。Java 使用 `ApiViews.ecgReceptionSummary(recording)` 获取接收摘要。

保存完整或部分结果，并分别处理 `interruption` 和 `stopConfirmed`：前者描述录制中断，后者表示停止是否得到确认。请求时长与接收样本数应分别保存。字段定义见 [数据语义](数据与时间语义.md)。

升级时保持主库、可选库和应用使用同一构建，重新编译应用。

## 独立 ACC、电量与接触状态

在连接就绪且客户端空闲时，由宿主管理的协程调用：

```kotlin
val battery = client.readBattery()
val contact = client.readWearState(5.0)
// 短时前台示例；后台采集使用服务的 durationSeconds 重载。
val session = client.startCapture(CaptureMode.accOnly, 60.0)
val stop = client.stopCaptureWithResult() // 用户停止或业务采集完成后调用
println("${stop?.outcome}; pending=${stop?.cleanupPending}")
val exported = client.exportSession(java.io.File(context.cacheDir, "Exports"))
```

Java 对应入口为 `SomaLoopJava.readBattery(callback)`、`readWearState(5.0, callback)`，回调类型分别为 `BatteryReading` 和 `WearState`。独立 ACC 支持持久会话、导出及同身份恢复，Demo 提供相应启动按钮和计数。主动接触检查会短暂启动 PPG；观察时长不含写入与关闭确认时间。采集中上述两个读取入口仍返回 `busy`，未知充电码、电压单位及佩戴事件不会猜测。升级须重新编译应用并补齐新增枚举分支。

0.1.13/build29 的 `SDKEvent.PPG` / `SDKEvent.ACCRecord` 通过 `record.frame` 和 `record.receive` 返回帧与同一条落盘接收记录；Java 用 `getRecord()`。旧 `SDKEvent.ACC` 同时保留，只选择一个 ACC 事件保存或上传，避免重复。字段、去重和 `SDKTestValues` 应用测试示例见[实时帧与接收记录](数据与时间语义.md#实时帧与接收记录)。

## PPI RMSSD（0.1.11 正式算法）

Kotlin / Java 使用 `PPIHRV.fromBatch(ppiBatch)` 从一次完整的 PPI 历史读取返回数值或 null／原因。有效 `rmssdMilliseconds` 可映射到 `hrv_rmssd`；缺失时跳过评分和提醒更新。默认策略、分组边界与质量存储见[数据与时间语义](数据与时间语义.md)。使用本版本完整二进制包，并重新编译应用。

`readWearState` 仅支持 `00000808-260604`，观察时长 1–10 秒；`rawACC` 持久采集仅在该固件为默认可用，其他固件的实验能力状态不等于 `startCapture` 已放行。`durationSeconds` 必须有限、>0 且 ≤604800，省略为 86400。

`stopCaptureWithResult` 的 `acknowledged`、`quiescent` 均释放本地会话；`unconfirmed` 保留待清理，最多两次停止尝试。只在 `acknowledged` 时 `stopConfirmed=true`。需要人工结束本地待处理时，按[采集与马达节拍](采集与马达节拍.md)调用 `abandonPendingCapture`；不要删除会话目录。

## 读取与修改设备名称

```kotlin
val reading = client.readDeviceName()
println(reading.name ?: "编码未确认") // 设备字段；不保证是广播名
val receipt = client.setDeviceName("TBSoma")
println(receipt.advertisementVerified) // false：尚未重扫验证
client.disconnect()
client.scan() // 从 Discovery 事件取得实际名称，再连接核对身份
```

Java 使用 `SomaLoopJava.readDeviceName(Callback<DeviceNameReading>)` 和 `setDeviceName("TBSoma", Callback<DeviceNameChangeReceipt>)`；通过 `getName()`、`getRequestedName()`、`getResponseRawHex()`、`getAdvertisementVerified()` 读取结果。

名称限定为 1–12 个可打印 ASCII 字符（不能全为空格）。固件可能自动添加 `V5 `；`readDeviceName` 可能继续读到旧字段。发生超时或断连后先重扫，不自动重发。字段和应答语义见[API 与错误码](API与错误码.md#设备名称读取与改名)。
