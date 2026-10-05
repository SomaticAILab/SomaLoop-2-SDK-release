# SomaLoop 2 SDK 版权与第三方告知

SomaLoop 2 SDK 由 Somatic AI 维护和提供。本交付包包含 SDK 二进制、接口文档与集成示例，不包含 SDK 实现源码。SDK 及随附材料仅供内部评估与开发测试；商业使用及任何对外分发须另行签署书面协议，具体范围见 [SDK 评估许可](../LICENSE)。本告知不替代该许可，也不将第三方软件或设备的权利转移给 Somatic AI。

## Android 第三方依赖

下列第三方软件分别受其自身许可约束。Android SDK 的第三方运行时依赖由 Gradle 解析；随包提供的本地 Maven 仓库包含 SomaLoop 2 SDK 的 AAR 与依赖元数据。

| 软件 | 版本 | 许可与项目来源 |
| --- | --- | --- |
| Kotlin stdlib | 2.1.10 | Apache-2.0，JetBrains，[项目](https://github.com/JetBrains/kotlin) |
| kotlinx-coroutines core-jvm / android | 1.9.0 | Apache-2.0，JetBrains，[项目](https://github.com/Kotlin/kotlinx.coroutines) |
| kotlinx-serialization json-jvm / core-jvm | 1.7.3 | Apache-2.0，JetBrains，[项目](https://github.com/Kotlin/kotlinx.serialization) |
| JetBrains annotations | 23.0.0 | Apache-2.0，JetBrains，[项目](https://github.com/JetBrains/java-annotations) |

[Apache License 2.0 全文](Apache-2.0.txt)随包提供。使用或再分发第三方组件时，应保留其版权、许可及适用的 NOTICE 告知；组件中的原有 META-INF 告知不得因本 SDK 的集成而删除。本目录的 Apache-2.0 文本用于上述第三方组件，不表示 SomaLoop 2 SDK 整体以 Apache-2.0 开源。

## 构建工具与示例

示例包含 Gradle Wrapper 脚本和 JAR，应保留其原有版权与 Apache-2.0 许可告知。Gradle、Android Gradle Plugin、JDK 与 Android SDK 各自受其许可约束；这些构建工具不作为 SomaLoop 2 SDK 运行时重新封装。

第三方许可授予的权利不受本 SDK 许可缩减。如第三方组件的具体版权或告知与本说明存在差异，以该组件随附的许可和告知为准。
