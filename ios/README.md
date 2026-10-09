# SomaLoop 2 SDK · iOS

版本 0.1.15 / build 32，最低 iOS 15。本包仅供内部评估与开发测试。使用范围见[接入说明](../README.md)与 [SDK 评估许可](../LICENSE)。

完整保留 `SomaLoopSDK-Package`，在 Xcode 的 Add Package Dependencies 中选择 Add Local。示例在 `SomaLoopSDKDemo`；主库与研究库须来自同一构建。

运行 Demo 需完整 Xcode 和 XcodeGen：安装 Homebrew 后执行 `brew install xcodegen`，在 `SomaLoopSDKDemo` 执行 `xcodegen generate`，再打开生成的工程并选择自己的签名团队。

接入步骤见 [iOS 接入](../docs/iOS接入.md)，实际验证范围见[验收状态](../docs/验收状态.md)。完成构建或测试不构成生产、商业使用或对外分发授权。
