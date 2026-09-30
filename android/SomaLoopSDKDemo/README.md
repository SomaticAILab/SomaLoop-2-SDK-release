# Somatic AI SDK · Android 示例

需要 JDK 17 与 Android SDK。在本目录配置自己的 `local.properties` 或 SDK 环境变量，然后执行 `./gradlew :app:assembleDebug`。示例从 `../repository` 使用本轮 SDK AAR，不依赖 SDK 实现源码。

构建产物仅供本地测试，不属于发布包。设备连接、采集和清除由使用者显式发起；构建成功不代表手机 BLE 或长期运行已验收。
