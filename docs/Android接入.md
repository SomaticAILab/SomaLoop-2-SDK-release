# Android / Java 接入

Somatic AI SDK 支持 Android API 26 及以上，包名保持 `com.somaticai.somaloop`。

以下接入步骤仅用于获授权的内部评估与开发测试。当前交付为私有候选，使用范围见 [SDK 评估许可](../LICENSE)。

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
    implementation("com.somaticai.somaloop:sdk:0.1.6-beta")
    implementation("com.somaticai.somaloop:experimental:0.1.6-beta") // 研究入口，可选
}
```

当前分发方式是本地 Maven 仓库，没有远程 Maven 发布地址。主库、研究库与依赖清单须来自同一完整包。版本号相同时也可能有不同 build；替换旧包后核对 `SomaLoop.buildRevision`，不要只依赖 Gradle 坐标判断新旧。

Demo 工具链为 JDK 17、Gradle 8.11.1、AGP 8.10.1、Kotlin 2.1.10，compile/target SDK 36。包内运行依赖见 `android/dependencies.json`；宿主统一已有 Kotlin/协程依赖版本，避免重复引入 JAR。Android Studio、平台 SDK 和构建插件需要自行准备。

在 `android/SomaLoopSDKDemo` 执行 `./gradlew :app:testDebugUnitTest :app:assembleDebug`。缓存齐全时可选 `--offline`。构建成功与手机 BLE 验收分别记录。

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

连接就绪并取得权限后，可从可见 Activity 调用 `SomaLoopCaptureService.startCapture(activity, CaptureMode.paired)`；停止入口调用 `client.stopCapture()`。Activity 销毁只解除绑定，不在旋转屏幕时关闭服务持有的采集客户端。服务重建可能恢复本地未结束会话；用户强制停止应用后不承诺自动恢复。

自建服务可用 `SomaLoopClient(context, storageRoot)`，但须承担相同权限、通知和生命周期责任。用 `setHostBackground(true/false)` 上报实际前后台，整个服务结束使用时才 `shutdown()`。

## Kotlin 读取

```kotlin
suspend fun readTemperature(client: SomaLoopClient): HistoryBatch {
    val batch = client.readHistoryBatch(HistoryKind.temperature)
    val records = batch.records.map { HistoryDecoder.decode(it) }
    println("${records.size} records; complete=${batch.complete}")
    // 保存部分 records，再检查 interruption 和 continuationAvailable。
    return batch
}

suspend fun readExperimentalSport(client: SomaLoopClient): HistoryBatch =
    client.readHistoryBatch(HistoryKind.sport, allowExperimental = true)
```

未验证的只读尝试需宿主先准入固件，再显式 `allowUntested = true`。闹钟可用 `readSettings(SettingKind.alarms, allowExperimental = true)`；不完整时抛错，部分记录改用历史批次。参数不放行 `unsupported`，不授予设置写入、校时、删除或研究流权限。

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

实验读取用 `sdk.readHistoryBatch(kind, false, true, callback)`。未验证读取用 `sdk.readHistoryBatch(kind, false, false, true, callback)`，最后的布尔值为 `allowUntested`。完整同步使用 `syncHistoryRecords(kind, options, callback)`，或带 `allowUntested` 的重载。

`observe(listener)` 返回可关闭订阅。包装器的 `close()` 只取消自己的任务，不关闭共享客户端；取消可能不再触发成功/失败回调，宿主还须处理所发起操作的停止与结果查询。

## 限时原始 ECG

```kotlin
import com.somaticai.somaloop.experimental.SomaLoopResearch

suspend fun recordRawECG(client: SomaLoopClient): ECGRecording {
    val recording = SomaLoopResearch(client).recordECG(seconds = 60)
    println("${recording.frames.size} frames; stop=${recording.stopConfirmed}")
    return recording
}
```

Java 使用 `sdk.recordECG(60, callback)`，回调为 `Callback<ECGRecording>`。合法时长 30 至 300 秒。直接调用 Kotlin client 的研究方法需 `@OptIn(SomaLoopClient.ResearchAPI::class)`，这属于编译期声明，与固件实验读取开关不同。

保留 `frames`、`interruption`、`stopConfirmed`；空集合或部分集合均不能写成完整录制。原始计数没有已验证的采样率、增益或医学准确性。完整字段和平台差异见[数据语义](数据与时间语义.md)。
