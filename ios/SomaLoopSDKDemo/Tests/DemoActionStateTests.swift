import Foundation
import XCTest
import SomaLoopSDK
@testable import SomaLoopSDKDemo

final class DemoActionStateTests:XCTestCase {
    private func snapshot(admitted:Bool=true,historyAvailable:Bool=true,hapticsAvailable:Bool=true,deviceInfoAvailable:Bool=true,measurementAvailable:Bool=false)throws->CapabilitySnapshot {
        func entry(_ available:Bool,_ reason:String,_ experimental:Bool=false)->[String:Any] {
            ["state":experimental ? "experimental":(available ? "compatibleCandidate":"untested"),
             "available":available,"requiresExperimentalOptIn":experimental,"reason":reason]
        }
        let json:[String:Any] = ["schemaVersion":1,"protocolAdmitted":admitted,
            "capabilities":["ppgOnly":entry(true,"capture candidate"),"ppgAccPaired":entry(true,"paired candidate"),
                "deviceInfo":entry(deviceInfoAvailable,"read candidate"),"measurements":entry(measurementAvailable,"measurement evidence missing"),
                "clockWrite":entry(false,"clock write evidence missing"),
                "hapticRhythm":entry(hapticsAvailable,"motor vibration unavailable")],
            "history":[String(HistoryKind.temperature.rawValue):entry(historyAvailable,"temperature history evidence missing")]]
        return try JSONCoding.decoder().decode(CapabilitySnapshot.self,from:JSONSerialization.data(withJSONObject:json))
    }
    private func readyState()throws->DemoActionState {
        var state=DemoActionState()
        state.device.transition(to:.ready)
        state.device.receive(try snapshot())
        return state
    }
    private let deviceActions:[DemoAction] = [.capture("ppgOnly"),.capture("ppgAccPaired"),.deviceInfo,.readClock,
        .history(.temperature),.feature("clockWrite"),.feature("measurements"),.playHaptics]

    func testDisconnectRevokesCachedCapabilitiesAndRejectsLateSnapshot()throws {
        var state=try readyState()
        XCTAssertNil(state.disabledReason(for:.capture("ppgOnly")))
        XCTAssertNil(state.disabledReason(for:.history(.temperature)))
        let oldSnapshot=try snapshot()
        state.device.transition(to:.disconnected)
        state.device.receive(oldSnapshot)
        XCTAssertNil(state.device.capabilities)
        for action in deviceActions {XCTAssertNotNil(state.disabledReason(for:action))}
        XCTAssertNil(state.disabledReason(for:.preview))
        XCTAssertNil(state.disabledReason(for:.diagnostics))
    }
    func testReconnectNeedsFreshSnapshotAndDoesNotReusePreviousFirmwareSupport()throws {
        var state=try readyState()
        state.device.transition(to:.reconnecting)
        XCTAssertNotNil(state.disabledReason(for:.history(.temperature)))
        state.device.transition(to:.ready)
        XCTAssertNotNil(state.disabledReason(for:.history(.temperature)))
        state.device.receive(try snapshot(historyAvailable:false))
        XCTAssertEqual(state.disabledReason(for:.history(.temperature)),"temperature history evidence missing")
        state.device.receive(try snapshot())
        XCTAssertNil(state.disabledReason(for:.history(.temperature)))
    }
    func testStopRemainsAvailableOfflineAndDuringOtherWork()throws {
        var runtime=DemoRuntimeState()
        var idle=SessionManifest(device:DeviceProfile(deviceID:"test",mac:"000000000001",firmwareHex:"00000808",dateHex:"260604"),mode:.ppgOnly,duration:1)
        idle.requested=false;idle.cleanupPending=false
        runtime.receiveSession(idle)
        let oldPoll=runtime.requestRefresh()
        var active=idle;active.requested=true
        runtime.receiveSession(active)
        XCTAssertTrue(!runtime.applyRefresh(oldPoll,manifest:idle,haptics:nil))
        XCTAssertTrue(runtime.manifest?.requested == true)
        let beforeOperation=runtime.requestRefresh()
        runtime.invalidate()
        XCTAssertTrue(!runtime.applyRefresh(beforeOperation,manifest:idle,haptics:nil))
        let newest=runtime.requestRefresh()
        XCTAssertTrue(runtime.applyRefresh(newest,manifest:idle,haptics:nil))
        XCTAssertTrue(runtime.manifest?.requested == false)
        var state=try readyState()
        state.hasSession=true;state.hasHaptics=true;state.capturePending=true;state.hapticPending=true;state.busy=true
        state.device.transition(to:.disconnected)
        XCTAssertNil(state.disabledReason(for:.stopCapture))
        XCTAssertNil(state.disabledReason(for:.stopHaptics))
        for action in deviceActions {XCTAssertNotNil(state.disabledReason(for:action))}
        state.busy=false
        XCTAssertNil(state.disabledReason(for:.confirmHaptics))
        XCTAssertNil(state.disabledReason(for:.exportCapture))
        XCTAssertNil(state.disabledReason(for:.exportHaptics))
    }
    func testBusyAndCaptureCleanupBlockNewWorkWithVisibleReasons()throws {
        var state=try readyState()
        state.busy=true
        for action in deviceActions + [.scan,.connect] {
            XCTAssertEqual(state.disabledReason(for:action),"正在处理操作，请稍候")
        }
        state.busy=false;state.hasSession=true;state.capturePending=true
        for action in deviceActions + [.scan,.connect] {
            XCTAssertTrue(state.disabledReason(for:action)?.contains("停止待确认") == true)
        }
        state.capturePending=false
        XCTAssertNil(state.disabledReason(for:.capture("ppgOnly")))
    }
    func testHapticRecoveryCanReconnectButCannotStartMoreDeviceWork()throws {
        var state=try readyState()
        state.hapticPending=true;state.hasHaptics=true
        state.device.transition(to:.disconnected)
        XCTAssertNil(state.disabledReason(for:.scan))
        XCTAssertNil(state.disabledReason(for:.connect))
        XCTAssertNil(state.disabledReason(for:.stopHaptics))
        XCTAssertNil(state.disabledReason(for:.confirmHaptics))
        for action in deviceActions {XCTAssertTrue(state.disabledReason(for:action)?.contains("节拍停止待确认") == true)}
    }
    func testMeasurementUsesAvailabilityWithoutFirmwareAdmission()throws {
        var state=try readyState()
        state.device.receive(try snapshot(admitted:false,measurementAvailable:true))
        XCTAssertNil(state.disabledReason(for:.feature("measurements")))
        for action:DemoAction in [.capture("ppgOnly"),.feature("clockWrite"),.history(.temperature),.deviceInfo,.readClock,.playHaptics] {
            XCTAssertEqual(state.disabledReason(for:action),"当前固件未获协议策略准入")
        }
        state.busy=true
        XCTAssertNotNil(state.disabledReason(for:.feature("measurements")))
        state.busy=false;state.capturePending=true
        XCTAssertNotNil(state.disabledReason(for:.feature("measurements")))
        state.capturePending=false;state.hapticPending=true
        XCTAssertNotNil(state.disabledReason(for:.feature("measurements")))
        state.hapticPending=false
        state.device.receive(try snapshot(admitted:false,measurementAvailable:false))
        XCTAssertEqual(state.disabledReason(for:.feature("measurements")),"measurement evidence missing")
        state.device.transition(to:.disconnected)
        XCTAssertNotNil(state.disabledReason(for:.feature("measurements")))
    }
    func testMotorVibrationFollowsAvailabilityConnectionAndAdmission()throws {
        var state=try readyState()
        XCTAssertNil(state.disabledReason(for:.playHaptics))
        state.device.receive(try snapshot(admitted:false))
        XCTAssertNotNil(state.disabledReason(for:.playHaptics))
        state.device.receive(try snapshot(hapticsAvailable:false))
        XCTAssertEqual(state.disabledReason(for:.playHaptics),"motor vibration unavailable")
        XCTAssertEqual(state.disabledReason(for:.feature("measurements")),"measurement evidence missing")
        XCTAssertEqual(state.disabledReason(for:.feature("clockWrite")),"clock write evidence missing")
        XCTAssertNotNil(state.disabledReason(for:.history(.sleep)))
        // Explicit extra-firmware admission still permits the SDK's safe identity/clock reads.
        state.device.receive(try snapshot(hapticsAvailable:false,deviceInfoAvailable:false))
        XCTAssertNil(state.disabledReason(for:.deviceInfo))
        XCTAssertNil(state.disabledReason(for:.readClock))
    }
}

