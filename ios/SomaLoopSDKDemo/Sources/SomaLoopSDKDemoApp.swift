import SwiftUI
import SomaLoopSDK
import SomaLoopExperimental

@MainActor final class DemoModel:ObservableObject {
    @Published var devices=[DiscoveredDevice]()
    @Published var deviceState=DemoConnectionState()
    @Published var status="选择手环后连接"
    @Published var busy=false
    @Published var runtime=DemoRuntimeState()
    @Published var exportURL:URL?
    @Published var profile:DeviceProfile?
    @Published var health:CaptureHealth?
    let client:SomaLoopClient
    private var observer:Task<Void,Never>?,refresh:Task<Void,Never>?
    private var operationCount=0
    var manifest:SessionManifest? {get{runtime.manifest} set{runtime.receiveSession(newValue)}}
    var haptics:HapticReport? {get{runtime.haptics} set{runtime.receiveHaptics(newValue)}}
    init(){
        let root=FileManager.default.urls(for:.documentDirectory,in:.userDomainMask)[0].appendingPathComponent("SomaLoopSessions")
        client=SomaLoopClient(storageRoot:root)
        observer=Task{do{for try await event in await client.events(){switch event {
        case .discovery(let d):if let i=devices.firstIndex(where:{$0.id==d.id}){devices[i]=d}else{devices.append(d)}
        case .connection(let s):
            deviceState.transition(to:s);runtime.invalidate()
            if s != .ready {profile=nil;health=nil}
            if s == .ready {deviceState.receive(await client.capabilitySnapshot());await refreshRuntime()}
        case .device(let p):
            if deviceState.connection == .ready {profile=p;deviceState.receive(await client.capabilitySnapshot())}
        case .captureHealth(let value):health=value
        case .capture(let s):manifest=s
        case .haptics(let r):haptics=r
        case .error(let e,let message):status="\(e.rawValue)：\(message)"
        default:break
        }}}catch{deviceState.transition(to:.disconnected);runtime.invalidate();profile=nil;health=nil;status="事件流已中断：\(error)"}}
        refresh=Task{while !Task.isCancelled{try? await Task.sleep(nanoseconds:2_000_000_000);guard !Task.isCancelled else{return};await refreshRuntime()}}
        run(.diagnostics){_ = try await self.client.resumePendingSession();await self.refreshRuntime()}
    }
    private func refreshRuntime()async {
        let token=runtime.requestRefresh()
        let session=await client.currentSession(),hapticReport=await client.currentHaptics()
        runtime.applyRefresh(token,manifest:session,haptics:hapticReport)
    }
    var actionState:DemoActionState {
        DemoActionState(device:deviceState,busy:busy,hasSession:manifest != nil,
            capturePending:manifest.map{$0.requested || $0.cleanupPending} ?? false,
            hasHaptics:haptics != nil,hapticPending:haptics?.pendingStop==true)
    }
    func disabledReason(_ action:DemoAction)->String? {actionState.disabledReason(for:action)}
    func run(_ action:DemoAction,_ work:@escaping()async throws->Void){
        if let reason=disabledReason(action){status=reason;return}
        // Increment before launching the task so two taps cannot start overlapping work.
        runtime.invalidate();operationCount += 1;busy=true
        Task{defer{runtime.invalidate();operationCount -= 1;busy=operationCount>0};do{try await work()}catch{status="\(error)"}}
    }
    func scan(){run(.scan){self.devices=[];try await self.client.scan();self.status="扫描中，选择设备编号连接"}}
    func connect(_ d:DiscoveredDevice){run(.connect){await self.client.stopScan();try await self.client.connect(d);self.status="已读取设备身份与固件"}}
    func start(_ mode:CaptureMode){run(.capture(mode == .accOnly ? "rawACC" : mode == .ppgOnly ? "ppgOnly":"ppgAccPaired")){self.manifest=try await self.client.startCapture(mode:mode);self.status="计划采集 24 小时，实际连续性以日志为准"}}
    func stop(){run(.stopCapture){try await self.client.stopCapture();self.manifest=await self.client.currentSession();self.status=self.manifest?.stopConfirmed==true ? "手环已确认停止":"停止意图已保存，等待设备关闭确认"}}
    func export(){run(.exportCapture){let root=FileManager.default.temporaryDirectory.appendingPathComponent("SomaLoopExports");self.exportURL=try await self.client.exportSession(to:root);self.status="已生成带 SHA-256 校验值的快照"}}

}
@main struct SomaLoopSDKDemoApp:App {
    @StateObject private var model=DemoModel()
    @Environment(\.scenePhase) private var phase
    var body:some Scene{WindowGroup{DemoView(model:model).onChange(of:phase){p in Task{try? await model.client.setHostBackground(p == .background)}}}}
}
struct DemoView:View {
    @ObservedObject var model:DemoModel
    var body:some View{NavigationView{Form{
        Section{Text("SomaLoop 2 SDK").font(.headline);Text("版本 \(SomaLoop.version)").foregroundColor(.secondary);Text("本机保存 · iOS 24 小时长测待验收").font(.caption)}
        Section("设备 · \(model.deviceState.connection.rawValue)"){
            Button("扫描附近的手环",action:model.scan).demoAvailability(model.disabledReason(.scan))
            ForEach(model.devices,id:\.id){d in Button(action:{model.connect(d)}){VStack(alignment:.leading){Text("手环 · \(d.id.suffix(6).uppercased())");Text((d.rssi == 127 ? "信号未知":"\(d.rssi) dBm") + " · \(d.id)").font(.caption).foregroundColor(.secondary)}}.demoAvailability(model.disabledReason(.connect))}
            if let p=model.profile{Text("固件：\(p.firmwareVersion ?? "未知") · \(p.firmwareDate ?? "日期未提供")");Text("能力状态：\(p.state.rawValue)").font(.caption)}
        }
        Section("原始采集"){
            Button("开始 PPG-only · 24 小时",action:{model.start(.ppgOnly)}).demoAvailability(model.disabledReason(.capture("ppgOnly")))
            Button("开始 PPG + ACC · 24 小时",action:{model.start(.paired)}).demoAvailability(model.disabledReason(.capture("ppgAccPaired")))
            Button("开始独立 ACC · 24 小时",action:{model.start(.accOnly)}).demoAvailability(model.disabledReason(.capture("rawACC")))
            if let health=model.health{Text("\(health.state.rawValue) · \(health.reason)").font(.caption)}
            Button("停止采集",role:.destructive,action:model.stop).demoAvailability(model.disabledReason(.stopCapture))
            if let s=model.manifest{Text("\(s.mode.title) · \(s.status)");Text("ACC 包：\(s.stats.accPackets ?? 0) · 样本：\(s.stats.accSamples ?? 0)");Text("PPG 包：\(s.stats.ppgPackets) · 样本：\(s.stats.ppgSamples)");Text("联合帧：\(s.stats.pairedFrames) · PPG：\(s.stats.pairedPPG) · MEMS：\(s.stats.memsTriples)");Text("两路数组独立保存，没有逐点时间戳或一一配对。").font(.caption)}
            Button("导出会话快照",action:model.export).demoAvailability(model.disabledReason(.exportCapture))
        }
        Section("马达振动 · 振动节拍") {
            Text("默认片段：120 BPM，短、短、长、休止；总长 2 秒。开启窗口 100 / 300 ms。").font(.caption)
            Button("本地编译预览 · 不触发设备"){model.run(.preview){let p=try HapticPattern.firstPulse.compile(preview:true);model.status="预览：\(p.durationMs) ms / \(p.events.count / 2) 个脉冲"}}.demoAvailability(model.disabledReason(.preview))
            Button("播放振动 · 短短长休止"){model.run(.playHaptics){model.haptics=try await model.client.playHaptics(.firstPulse);model.status="片段：\(model.haptics!.status)；\(model.haptics!.error ?? "请确认振动已停止")"}}.demoAvailability(model.disabledReason(.playHaptics))
            Button("立即停止节拍",role:.destructive){model.run(.stopHaptics){await model.client.stopHaptics();model.haptics=await model.client.currentHaptics()}}
            if let h=model.haptics {
                Text("\(h.status) · \(h.error ?? "无软件错误") · 待确认停止 \(h.pendingStop ? "是":"否")").font(.caption)
                Button("确认手环已完全停止"){model.run(.confirmHaptics){try await model.client.confirmHapticsStopped(sessionID:h.id);model.haptics=await model.client.currentHaptics()}}.demoAvailability(model.disabledReason(.confirmHaptics))
                Button("导出节拍日志 JSON"){model.run(.exportHaptics){model.exportURL=try await model.client.exportHaptics(to:FileManager.default.temporaryDirectory.appendingPathComponent("SomaLoopExports"))}}.demoAvailability(model.disabledReason(.exportHaptics))
            }
        }
        Section("常规接口"){
            Button("读取设备信息"){model.run(.deviceInfo){let d=try await model.client.readDeviceInfo();model.status=d.filter{$0.opcode != 0x3e}.map{"0x\(String($0.opcode,radix:16)) \($0.fields)"}.joined(separator:"\n")}}.demoAvailability(model.disabledReason(.deviceInfo))
            Button("读取温度历史一批"){model.run(.history(.temperature)){let b=try await model.client.readHistoryBatch(.temperature);model.status="记录 \(b.records.count) / 通知 \(b.notificationCount) / 结束标记 \(b.complete) / 中断 \(String(describing:b.interruption))"}}.demoAvailability(model.disabledReason(.history(.temperature)))
            Button("心率测量 · 40 秒"){model.run(.feature("measurements")){let d=try await model.client.measure(.heartRate);model.status="收到 \(d.count) 个实时结果"}}.demoAvailability(model.disabledReason(.feature("measurements")))
            Button("读取设备时间与偏移"){model.run(.readClock){let offset=TimeZone.current.secondsFromGMT()/60;let clock=try await model.client.readDeviceClock(utcOffsetMinutes:offset);model.status="设备领先主机 \(clock.offsetSeconds ?? 0) 秒；不确定度 ±\(clock.uncertaintySeconds) 秒。时区假设：UTC \(offset) 分钟"}}.demoAvailability(model.disabledReason(.readClock))
            Button("校准设备时间并回读"){model.run(.feature("clockWrite")){let result=try await model.client.synchronizeClock(utcOffsetMinutes:TimeZone.current.secondsFromGMT()/60);model.status="回读验证：\(result.verified)；历史时钟区间标识：\(result.clockEpoch)"}}.demoAvailability(model.disabledReason(.feature("clockWrite")))
            Button("导出脱敏诊断"){model.run(.diagnostics){model.exportURL=try await model.client.exportDiagnostics(to:FileManager.default.temporaryDirectory.appendingPathComponent("SomaLoopDiagnostics"))}}.demoAvailability(model.disabledReason(.diagnostics))

            Text("设备操作按连接、忙碌与能力状态开放；时间写入按精确设备证据开放，其他设置仍等待验证。").font(.caption)
        }
        Section("状态"){Text(model.status).font(.footnote).textSelection(.enabled)}
    }.navigationTitle("SomaLoop 2 SDK Demo")}.sheet(isPresented:Binding(get:{model.exportURL != nil},set:{if !$0{model.exportURL=nil}})){if let url=model.exportURL{ExportPicker(url:url)}}}
}
struct ExportPicker:UIViewControllerRepresentable {
    let url:URL
    func makeUIViewController(context:Context)->UIDocumentPickerViewController{UIDocumentPickerViewController(forExporting:[url],asCopy:true)}
    func updateUIViewController(_ controller:UIDocumentPickerViewController,context:Context){}
}

private extension View {
    func demoAvailability(_ reason:String?)->some View {
        VStack(alignment:.leading,spacing:4){
            self.disabled(reason != nil)
            if let reason {Text(reason).font(.caption).foregroundColor(.secondary)}
        }
    }
}
