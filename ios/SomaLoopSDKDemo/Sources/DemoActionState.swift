import SomaLoopSDK

/// Demo decisions are local UI guidance; the SDK still enforces every operation.
struct DemoConnectionState {
    private(set) var connection: ConnectionState = .disconnected
    private(set) var capabilities: CapabilitySnapshot?

    mutating func transition(to state: ConnectionState) {
        connection = state
        // A new ready event must obtain a fresh snapshot, including after reconnect.
        capabilities = nil
    }

    mutating func receive(_ snapshot: CapabilitySnapshot) {
        guard connection == .ready else { return }
        capabilities = snapshot
    }
}


/// An async poll cannot overwrite a newer capture event or operation result.
struct DemoRuntimeState {
    private(set) var manifest:SessionManifest?
    private(set) var haptics:HapticReport?
    private var revision=0

    mutating func invalidate(){revision += 1}
    mutating func receiveSession(_ value:SessionManifest?){invalidate();manifest=value}
    mutating func receiveHaptics(_ value:HapticReport?){invalidate();haptics=value}
    mutating func requestRefresh()->Int {invalidate();return revision}
    @discardableResult mutating func applyRefresh(_ token:Int,manifest:SessionManifest?,haptics:HapticReport?)->Bool {
        guard token == revision else {return false}
        self.manifest=manifest;self.haptics=haptics
        return true
    }
}

enum DemoAction {
    case scan, connect, capture(String), feature(String), history(HistoryKind)
    case deviceInfo, readClock, playHaptics, preview, diagnostics
    case exportCapture, exportHaptics, stopCapture, stopHaptics, confirmHaptics
}

struct DemoActionState {
    var device = DemoConnectionState()
    var busy = false
    var hasSession = false
    var capturePending = false
    var hasHaptics = false
    var hapticPending = false

    /// nil means enabled; every disabled decision has text visible beside its button.
    func disabledReason(for action: DemoAction) -> String? {
        // Stop/recovery must remain available while another operation is running or offline.
        switch action {
        case .stopCapture: return hasSession ? nil : "暂无采集会话"
        case .stopHaptics: return nil
        default: break
        }
        if busy { return "正在处理操作，请稍候" }
        switch action {
        case .preview, .diagnostics: return nil
        case .exportCapture: return hasSession ? nil : "暂无可导出的采集会话"
        case .exportHaptics: return hasHaptics ? nil : "暂无可导出的节拍日志"
        case .confirmHaptics: return hapticPending ? nil : "没有待确认的停止；仅在体感确认已停止后使用"
        default: break
        }
        if capturePending { return "采集正在运行或停止待确认，请先停止采集并完成设备关闭确认" }
        switch action {
        // Scanning/reconnecting is needed to finish an unconfirmed haptic stop.
        case .scan, .connect: return nil
        default: break
        }
        if hapticPending { return "节拍停止待确认，请先停止节拍并确认手环已完全停止" }
        guard device.connection == .ready else { return "设备未就绪（\(device.connection.rawValue)），请先连接设备" }
        guard let snapshot = device.capabilities else { return "正在读取当前设备能力，请稍候" }
        // Active measurement follows its connection-aware entry, independently of firmware admission.
        if case .feature("measurements") = action {
            guard let entry = snapshot.capabilities["measurements"] else { return "当前设备没有提供此项能力，不能启用" }
            return entry.available ? nil : entry.reason
        }
        guard snapshot.protocolAdmitted else { return "当前固件未获协议策略准入" }
        let entry: CapabilityEntry?
        switch action {
        case .capture(let feature), .feature(let feature): entry = snapshot.capabilities[feature]
        case .history(let kind): entry = snapshot.history[String(kind.rawValue)]
        // Safe identity/clock reads follow the configured admission policy, including extra firmware.
        case .deviceInfo, .readClock: return nil
        case .playHaptics:
            entry = snapshot.capabilities["hapticRhythm"]
        default: return nil
        }
        guard let entry else { return "当前设备没有提供此项能力，不能启用" }
        return entry.available ? nil : entry.reason
    }
}
