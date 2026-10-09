import XCTest
import SomaLoopSDK
final class BinaryIntegrationTests:XCTestCase {
    func testDeviceNameBinaryReadAndWrite() async throws {
        let device=DiscoveredDevice(id:"synthetic-name",name:"Original",rssi:-40)
        let mac=try ReplayExchange(commandHex:"22000000000000000000000000000022",notificationHex:["22010203040506000000000000000037"])
        let read=try ReplayExchange(commandHex:"3e00000000000000000000000000003e",notificationHex:["3e4f524947494e414c000000000000000000000000000093"])
        let exchanges=try [mac,
            ReplayExchange(commandHex:"27000000000000000000000000000027",notificationHex:["27000008082606040000000000000067"]),
            ReplayExchange(commandHex:"41000000000000000000000000000041",notificationHex:["41260929123045000000000000000020"]),
            read,mac,
            ReplayExchange(commandHex:"3d5442536f6d61000000000000000063",notificationHex:["3d5442536f6d6100000000000000006300000000000000c6"]),read]
        let replay=try ReplayBLETransport(device:device,exchanges:exchanges)
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let client=SomaLoopClient(replay:replay,storageRoot:root)
        defer{try? FileManager.default.removeItem(at:root)}
        do {
            try await client.connect(device)
            let before=try await client.readDeviceName(),receipt=try await client.setDeviceName("TBSoma"),after=try await client.readDeviceName()
            XCTAssertEqual(before.name,"ORIGINAL");XCTAssertEqual(after,before)
            XCTAssertEqual(receipt.requestedName,"TBSoma");XCTAssertFalse(receipt.advertisementVerified)
            XCTAssertEqual(DeviceNameReading(name:nil,rawHex:"ff").rawHex,"ff")
            await client.shutdown()
        } catch { await client.shutdown();throw error }
    }

    func testBinaryFactoryAdvertisingWithoutServiceUUID() {
        let device = DiscoveredDevice(id: "factory", name: "JCV8B 8D1816", rssi: -48)
        XCTAssertNil(device.advertisedServiceUUIDs)
        XCTAssertEqual(device.discoveryKind, .candidate)
        XCTAssertEqual(device.discoveryEvidence, ["advertisedName"])
        XCTAssertEqual(device.name, "JCV8B 8D1816")
    }

    func testBinaryTypedDataViewsAndHostConstructors() throws {
        let packet = try DecodedPacket(kind: .realtime, fields: ["temperatureRaw": .integer(365), "distanceRaw": .integer(125)])
        XCTAssertEqual(packet.kind, .realtime)
        XCTAssertEqual(packet.measurements.skinTemperature?.value ?? 0, 36.5, accuracy: 1e-10)
        XCTAssertEqual(packet.measurements.distance?.value, 1.25)
        XCTAssertEqual(packet.measurements.distance?.unit, "km")
        let history = try DecodedPacket(kind: .history, historyKind: .temperature)
        XCTAssertEqual(history.historyKind, .temperature)
        XCTAssertThrowsError(try HistoryRecord(packet: history))
        let device = DiscoveredDevice(id: "test", name: nil, rssi: -50, advertisedServiceUUIDs: ["FFF0"])
        XCTAssertEqual(device.discoveryKind, .candidate)
        XCTAssertEqual(device.discoveryEvidence, ["advertisedService"])
        let received = JournalRecord(kind: "test", time: Date(timeIntervalSince1970: 1_700_000_000.125), uptime: 10)
        let ppg = try PPGFrame(sequence: 42, values: Array(repeating: 1, count: 25))
        let acc = try ACCFrame(sequence: 42, samples: Array(repeating: MEMSSample(x: -1, y: 0, z: 1), count: 6))
        let ecg = try ECGFrame(sequence: 42, values: Array(repeating: 1, count: 59))
        let events: [SDKEvent] = [.ppg(PPGRecord(frame: ppg, receive: received)), .accRecord(ACCRecord(frame: acc, receive: received)), .acc(acc)]
        XCTAssertEqual(events.count, 3)
        XCTAssertEqual(ecg.rawHex, "")
        XCTAssertNil(ECGReceptionSummary(frames: [ecg]).sampleRateHz)
        let sport = try DecodedPacket(kind: .history, historyKind: .sport, fields: ["distance": .text("0000c03f")])
        XCTAssertEqual(sport.measurements.distance?.value, 1.5)
        XCTAssertNil(sport.measurements.distance?.unit)
        let alarm = try DecodedPacket(kind: .history, historyKind: .alarms, fields: ["textBytes": .text("4142")])
        XCTAssertEqual(alarm.alarmLabel?.text, "AB")
    }

    func testStopResultClockAndFixedDateBinarySurface()async throws {
        XCTAssertEqual(SomaLoop.version,Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String)
        let result=try JSONDecoder().decode(CaptureStopResult.self,from:Data(#"{"sessionID":"test","outcome":"quiescent","attempts":1,"reason":"acc_quiet_3_seconds","observedAt":1700000000}"#.utf8))
        XCTAssertFalse(result.stopConfirmed);XCTAssertFalse(result.cleanupPending)
        let record=JournalRecord(kind:"example",time:Date(timeIntervalSince1970:1700000000))
        let data=try JSONEncoder().encode(record)
        let json=try XCTUnwrap(JSONSerialization.jsonObject(with:data) as? [String:Any])
        XCTAssertEqual(json["time"] as? Double,1700000000000)
        XCTAssertEqual(try JSONDecoder().decode(JournalRecord.self,from:data).time,record.time)
        let device=DiscoveredDevice(id:"synthetic-issue45",name:nil,rssi:-45)
        let exchanges=try [
            ReplayExchange(commandHex:"22000000000000000000000000000022",notificationHex:["22010203040506000000000000000037"]),
            ReplayExchange(commandHex:"27000000000000000000000000000027",notificationHex:["27000008082606040000000000000067"]),
            ReplayExchange(commandHex:"41000000000000000000000000000041",notificationHex:["41260929123045000000000000000020"]),
            ReplayExchange(commandHex:"13000000000000000000000000000013",notificationHex:["134b02341200000000000000000000a6"])
        ]
        let replay=try ReplayBLETransport(device:device,exchanges:exchanges)
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let client=SomaLoopClient(replay:replay,storageRoot:root)
        defer{try? FileManager.default.removeItem(at:root)}
        do {
            try await client.connect(device)
            let epoch=await client.currentClockEpoch;XCTAssertEqual(epoch,"unspecified")
            let battery=try await client.readBattery();XCTAssertNotNil(battery.readAt)
            let stop=try await client.stopCaptureWithResult();XCTAssertNil(stop)
            do{_ = try await client.abandonPendingCapture(sessionID:"absent",reason:"example",confirm:true);XCTFail()}catch{XCTAssertEqual(error as? SDKError,.invalidArgument)}
        }catch{await client.shutdown();throw error}
        await client.shutdown()
    }
    func testBinaryPPIRMSSDAndUnavailableJSON() throws {
        let result = try PPIHRV.calculate(intervalsMilliseconds: (0..<50).map { $0 % 2 == 0 ? 800 : 840 })
        XCTAssertEqual(try XCTUnwrap(result.rmssdMilliseconds), 40, accuracy: 1e-10)
        XCTAssertEqual(result.quality, "screenedPPI")
        XCTAssertEqual(result.unit, "ms")
        XCTAssertEqual(result.algorithm, "ppi-rmssd")
        let filtered = try PPIHRV.calculate(intervalsMilliseconds: Array(repeating: 800, count: 18) + [1400] + Array(repeating: 840, count: 18))
        XCTAssertEqual(filtered.rmssdMilliseconds, 0)
        XCTAssertEqual(filtered.retainedIntervalCount, 36)
        XCTAssertEqual(filtered.rejectedIntervalCount, 1)
        XCTAssertEqual(filtered.successiveDifferenceCount, 34)
        XCTAssertEqual(try PPIHRV.calculate(intervalsMilliseconds: Array(repeating: 800, count: 35)).rmssdMilliseconds, 0)
        XCTAssertEqual(try PPIHRV.calculate(intervalsMilliseconds: Array(repeating: 800, count: 34)).unavailableReason, .insufficientRetainedIntervals)
        let missing = try PPIHRV.calculate(intervalsMilliseconds: [800, nil])
        XCTAssertNil(missing.rmssdMilliseconds)
        XCTAssertEqual(missing.unavailableReason, .invalidInterval)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(missing)) as? [String: Any])
        XCTAssertTrue(json["rmssdMilliseconds"] is NSNull)
    }
    func testBinaryACCAndBatteryContactAPIs()throws {
        XCTAssertEqual(CaptureMode.accOnly.rawValue,"acc_only")
        XCTAssertEqual(CaptureMode.accOnly.serverMode,"accOnly")
        var bytes=[UInt8](repeating:0,count:44);bytes[0]=0x33;bytes[1]=0xff;bytes[2]=0xff;bytes[43]=255
        let frame=try XCTUnwrap(ACCFrame(Data(bytes)))
        XCTAssertEqual(frame.samples.count,6);XCTAssertEqual(frame.samples[0].x,-1);XCTAssertEqual(frame.sequence,255)
        let battery=try JSONDecoder().decode(BatteryReading.self,from:Data(#"{"percentage":{"rawValue":75,"value":75,"unit":"percent","quality":"raw"},"rawHex":"134b02341200000000000000000000a6"}"#.utf8))
        XCTAssertEqual(battery.chargingStateRaw,2);XCTAssertEqual(battery.chargingState,.unknown)
        XCTAssertEqual(battery.voltage?.rawValue,4660);XCTAssertNil(battery.voltage?.unit)
        let wear=try JSONDecoder().decode(WearState.self,from:Data(#"{"state":"unknown","source":"0x86","rawValue":"1","observedAt":1}"#.utf8))
        XCTAssertEqual(wear.state,.unknown);XCTAssertEqual(wear.rawValue,"1")
    }
    func testBinaryCompatibleHistoryAndCompleteAlarmSettings()async throws {
        let device=DiscoveredDevice(id:"synthetic-read-permissions",name:nil,rssi:-45)
        var sport=[UInt8](repeating:0,count:26);sport[0]=0x5c;sport[1]=1
        sport.replaceSubrange(3..<9,with:[0x26,9,0x30,0x12,0,0])
        var alarm=[UInt8](repeating:0,count:41);alarm[0]=0x57;alarm[1]=1
        alarm.replaceSubrange(3..<13,with:[1,0,1,1,7,0x30,0x7f,2,65,66])
        let clock=try ReplayExchange(commandHex:"41000000000000000000000000000041",notificationHex:["41260929123045000000000000000020"])
        let exchanges=try [
            ReplayExchange(commandHex:"22000000000000000000000000000022",notificationHex:["22010203040506000000000000000037"]),
            ReplayExchange(commandHex:"27000000000000000000000000000027",notificationHex:["27000008082606040000000000000067"]),
            clock,clock,
            ReplayExchange(commandHex:"5c00000000000000000000000000015d",notificationHex:[Data(sport).hex,"5cff"]),
            ReplayExchange(commandHex:"57000000000000000000000000000057",notificationHex:[Data(alarm).hex,"57ff"])
        ]
        let replay=try ReplayBLETransport(device:device,exchanges:exchanges)
        let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let client=SomaLoopClient(replay:replay,storageRoot:directory)
        defer{try? FileManager.default.removeItem(at:directory)}
        do {
            try await client.connect(device)
            let before=await replay.writes
            do{_ = try await client.readSettings(.automaticMeasurement,type:3,allowUntested:true);XCTFail()}catch{XCTAssertEqual(error as? SDKError,.unverifiedCapability)}
            let denied=await replay.writes;XCTAssertEqual(denied,before)
            let batch=try await client.readHistoryBatch(.sport)
            XCTAssertTrue(batch.complete);XCTAssertEqual(batch.records.map(\.rawHex),[Data(sport).hex])
            let settings=try await client.readSettings(.alarms)
            XCTAssertEqual(settings.rawHex,Data(alarm).hex);XCTAssertEqual(settings.fields["complete"],.boolean(true))
            XCTAssertEqual(settings.fields["recordCount"],.integer(1));XCTAssertEqual(settings.fields["notificationCount"],.integer(2))
            guard case .array(let records)=settings.fields["records"],case .object(let record)=records.first else{XCTFail();await client.shutdown();return}
            XCTAssertEqual(record["rawHex"],.text(Data(alarm).hex));XCTAssertEqual(record["opcode"],.integer(87))
            try await replay.assertComplete();await client.shutdown()
        }catch{await client.shutdown();throw error}
    }
    func testBinaryHistoryErasurePreparationAndFreshConnectionReport()async throws {
        let device=DiscoveredDevice(id:"synthetic-erasure-replay",name:nil,rssi:-55)
        let identity=try [
            ReplayExchange(commandHex:"22000000000000000000000000000022",notificationHex:["22010203040506000000000000000037"]),
            ReplayExchange(commandHex:"27000000000000000000000000000027",notificationHex:["27000008082606040000000000000067"]),
            ReplayExchange(commandHex:"41000000000000000000000000000041",notificationHex:["41260929123045000000000000000020"])
        ]
        let deletion=try ReplayExchange(commandHex:"629900000000000000000000000000fb",notificationHex:["629900000000000000000000000000fb","62ff"])
        let readback=try ReplayExchange(commandHex:"62000000000000000000000000000163",notificationHex:["62ff"])
        let replay=try ReplayBLETransport(device:device,exchanges:identity+[deletion]+identity+[readback])
        let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let client=SomaLoopClient(replay:replay,storageRoot:directory)
        defer{try? FileManager.default.removeItem(at:directory)}
        do {
            try await client.connect(device)
            let before=await replay.writes
            do{_ = try await client.prepareHistoryErasure(kinds:[.temperature]);XCTFail()}catch{XCTAssertEqual(error as? SDKError,.unverifiedCapability)}
            do{_ = try await client.prepareHistoryErasure(kinds:[.temperature],allowExperimental:false);XCTFail()}catch{XCTAssertEqual(error as? SDKError,.unverifiedCapability)}
            let preparation:HistoryErasurePreparation=try await client.prepareHistoryErasure(kinds:[.temperature],allowExperimental:true)
            XCTAssertEqual(try JSONDecoder().decode(HistoryErasurePreparation.self,from:JSONEncoder().encode(preparation)),preparation)
            do{_ = try await client.eraseHistory(preparation,confirm:true);XCTFail()}catch{XCTAssertEqual(error as? SDKError,.unverifiedCapability)}
            do{_ = try await client.eraseHistory(preparation,confirm:true,allowExperimental:false);XCTFail()}catch{XCTAssertEqual(error as? SDKError,.unverifiedCapability)}
            let denied=await replay.writes;XCTAssertEqual(denied,before)
            let report:HistoryErasureReport=try await client.eraseHistory(preparation,confirm:true,allowExperimental:true)
            let result:HistoryErasureKindResult=try XCTUnwrap(report.results.first)
            let verification:HistoryErasureVerification=result.verification
            XCTAssertTrue(report.readbackEmpty);XCTAssertTrue(report.freshConnectionVerified);XCTAssertTrue(report.checkpointResetRequired)
            XCTAssertEqual(verification,.empty);XCTAssertTrue(result.commandAttempted);XCTAssertTrue(result.transportWriteCompleted)
            XCTAssertTrue(result.readComplete);XCTAssertEqual(result.recordCount,0);XCTAssertNil(result.interruption)
            XCTAssertEqual(report.preparationID,preparation.id);XCTAssertEqual(report.deviceIdentity,preparation.deviceIdentity)
            XCTAssertGreaterThanOrEqual(report.endedAt,report.startedAt)
            let decoded=try JSONDecoder().decode(HistoryErasureReport.self,from:JSONEncoder().encode(report))
            XCTAssertTrue(decoded.readbackEmpty);let latest=await client.lastHistoryErasureReport
            XCTAssertEqual(latest?.preparationID,preparation.id)
            try await replay.assertComplete();await client.shutdown()
        }catch{await client.shutdown();throw error}
    }
    func testBinaryConnectedRetrievalPreservesReplayDiscoveryAndIdentity()async throws {
        let device=DiscoveredDevice(id:"synthetic-binary-replay",name:"Synthetic peripheral",rssi:-55)
        let exchanges=try [
            ReplayExchange(commandHex:"22000000000000000000000000000022",notificationHex:["22010203040506000000000000000037"]),
            ReplayExchange(commandHex:"27000000000000000000000000000027",notificationHex:["27000008082606040000000000000067"]),
            ReplayExchange(commandHex:"41000000000000000000000000000041",notificationHex:["41260929123045000000000000000020"])
        ]
        let replay=try ReplayBLETransport(device:device,exchanges:exchanges)
        let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let client=SomaLoopClient(replay:replay,storageRoot:directory)
        let stream=await client.events(),discovery=expectation(description:"Replay discovery remains available")
        let observer=Task { () throws -> DiscoveredDevice? in
            for try await event in stream {
                if case .discovery(let found)=event{discovery.fulfill();return found}
            }
            return nil
        }
        defer{observer.cancel();try? FileManager.default.removeItem(at:directory)}
        do {
            let connected=try await client.retrieveConnectedDevices()
            let beforeState=await client.connectionState,beforeWrites=await replay.writes,beforeConsumed=await replay.consumedExchanges
            XCTAssertTrue(connected.isEmpty);XCTAssertEqual(beforeState,.disconnected)
            XCTAssertTrue(beforeWrites.isEmpty);XCTAssertEqual(beforeConsumed,0)
            try await client.scan()
            await fulfillment(of:[discovery],timeout:2)
            observer.cancel()
            let found=try await observer.value
            XCTAssertEqual(found,device)
            await client.stopScan()
            try await client.connect(try XCTUnwrap(found))
            let state=await client.connectionState,profile=await client.profile,clock=await client.lastClockSnapshot,writes=await replay.writes
            XCTAssertEqual(state,.ready);XCTAssertEqual(profile?.deviceID,device.id)
            XCTAssertEqual(profile?.mac,"010203040506");XCTAssertEqual(profile?.firmwareHex,"00000808")
            XCTAssertEqual(profile?.advertisedName,device.name);XCTAssertNotNil(clock)
            XCTAssertEqual(writes,exchanges.map(\.commandHex))
            try await replay.assertComplete()
            await client.shutdown()
        } catch {await client.shutdown();throw error}
    }
    func test0088BinaryCapabilitiesAndPreservedMask()throws {
        let p=DeviceProfile(deviceID:"test",mac:"66778899aabb",firmwareHex:"00000808",dateHex:"260604")
        XCTAssertEqual(p.state,.compatibleCandidate);XCTAssertEqual(p.capability("ppgOnly"),.compatibleCandidate)
        XCTAssertEqual(p.capability("measurements"),.compatibleCandidate);XCTAssertEqual(p.capability("hapticRhythm"),.compatibleCandidate)
        XCTAssertEqual(p.capability("rawECG"),.compatibleCandidate);XCTAssertEqual(p.capability("diagnostics"),.untested)
        XCTAssertEqual(p.historyCapability(.sleep),.compatibleCandidate)
        XCTAssertEqual(try SomaLoopPacketDecoder.decode(Data(hex:"2b0200002359ff0500010000000000ae")!).fields["weekMask"],.integer(255))
    }
    func testHapticBinaryContract()throws {
        let p=try HapticPattern.firstPulse.compile()
        XCTAssertEqual(p.durationMs,2000);XCTAssertEqual(p.events.count,6)
        XCTAssertEqual(try JSONCoding.decoder().decode(HapticPattern.self,from:JSONCoding.encoder().encode(p.pattern)),p.pattern)
        XCTAssertThrowsError(try HapticPattern(name:"too fast",bpm:121).compile())
    }
    func testBinaryProfileIdentity() {
        XCTAssertEqual(SomaLoop.product,"SomaLoop 2 SDK")
        let p = DeviceProfile(deviceID:"test",mac:"001122334455",firmwareHex:"00000808",dateHex:"260604",advertisedName:"Original BLE name")
        XCTAssertEqual(p.id,"somaloop-fw-00000808-260604")
        XCTAssertEqual(p.advertisedName,"Original BLE name")
        XCTAssertEqual(p.state,.compatibleCandidate)
    }
    func testBinaryPublicHistoryContract()throws {
        let profile=DeviceProfile(deviceID:"test",mac:"001122334455",firmwareHex:"00000808",dateHex:"260604")
        XCTAssertEqual(profile.firmwareVersion,"0.0.8.8")
        XCTAssertEqual(profile.capability("clockWrite"),.compatibleCandidate)
        let packet=try SomaLoopPacketDecoder.decode(Data([0x54,1,0,0x26,9,0x28,0x12,0x30,0]+Array(60...74)))
        let record=try HistoryRecord(packet:packet),samples=try record.samples(field:"heartRates")
        XCTAssertEqual(samples.count,15);XCTAssertEqual(Set(samples.map(\.id)).count,15)
        XCTAssertTrue(samples.allSatisfy{$0.timestamp==nil})
    }
    func testBinarySleepContractResolvesSupportedFirmware()throws {
        let profile=DeviceProfile(deviceID:"test",mac:"001122334455",firmwareHex:"00000808",dateHex:"260604")
        let record=try sleepRecord()
        let result=SleepTimelineResolver.resolve(record,profile:profile,utcOffsetMinutes:480)
        XCTAssertEqual(result.status,.resolved);XCTAssertNil(result.reason)
        XCTAssertEqual(result.rawSlots.map(\.rawValue),[1,0,9]);XCTAssertEqual(result.intervals.count,3)
        XCTAssertEqual(result.ruleID,"sleep-start-60s-00000808-260604-v1")
        XCTAssertEqual(result.evidenceID,"sleep-time-rule-evidence-20260929")
        let header=Int64(try record.deviceCalendar!.resolvedDate(utcOffsetMinutes:480).timeIntervalSince1970*1000)
        for (index,interval) in result.intervals.enumerated() {
            XCTAssertEqual(interval.slotIndex,index);XCTAssertEqual(interval.rawCode,[1,0,9][index])
            XCTAssertEqual(interval.startUnixMilliseconds,header+Int64(index)*60000)
            XCTAssertEqual(interval.endUnixMilliseconds,header+Int64(index+1)*60000)
        }
        let start=try XCTUnwrap(SleepTimelineResolver.recordStart(record,generationProfile:profile,utcOffsetMinutes:480))
        XCTAssertEqual(start.deviceCalendar,record.deviceCalendar)
        XCTAssertEqual(start.unixMilliseconds,header)
        XCTAssertEqual(start.evidenceSource,"userConfirmed");XCTAssertFalse(start.independentlyValidated)
        XCTAssertNil(SleepTimelineResolver.recordStart(record,generationProfile:profile)?.unixMilliseconds)
        let info=try XCTUnwrap(SleepTimelineResolver.ruleInfo(generationProfile:profile))
        XCTAssertEqual(info.opcodes,[83,107]);XCTAssertEqual(info.codeDurationSeconds,60)
        XCTAssertEqual(info.stageMappingSource,"protocolReference");XCTAssertFalse(info.stageAccuracyIndependentlyValidated)
        XCTAssertEqual(try JSONDecoder().decode(SleepTimingRuleInfo.self,from:JSONEncoder().encode(info)),info)

        let adapted=try SomaContractAdapter.historyWithDeviceTiming(record,deviceID:"01ARZ3NDEKTSV4RRFFQ69G5FAV",generationProfile:profile,utcOffsetMinutes:480)
        XCTAssertTrue(adapted.rejections.isEmpty);XCTAssertEqual(adapted.retainedRawRecords,[record])
        XCTAssertEqual(adapted.objects.count,4)
        XCTAssertEqual(adapted.objects[0]["schema"],.text("soma.history-record/v1"))
        XCTAssertEqual(adapted.objects[0]["raw_hex"],.text(record.rawHex))
        let intervals=Array(adapted.objects.dropFirst())
        for (index,interval) in intervals.enumerated() {
            XCTAssertEqual(interval["schema"],.text("soma.interval/v1"))
            XCTAssertEqual(interval["attrs"],.object(["stage":.text(["deep","awake","awake"][index]),"code":.integer([1,0,9][index])]))
            XCTAssertEqual(interval["start_ts"],.text("2026-09-27T16:0\(index+1):00Z"))
            XCTAssertEqual(interval["end_ts"],.text("2026-09-27T16:0\(index+2):00Z"))
            XCTAssertEqual(interval["quality"],.array([.text("reconstructed")]))
        }
        guard case .object(let rule)=adapted.provenance[0]["sleep_time_rule"],case .object(let timeline)=adapted.provenance[0]["sleep_timeline"] else{return XCTFail("Missing public timing provenance")}
        XCTAssertEqual(rule["ruleID"],.text(info.ruleID))
        XCTAssertEqual(rule["independentlyValidated"],.boolean(false))
        XCTAssertEqual(rule["stageAccuracyIndependentlyValidated"],.boolean(false))
        XCTAssertEqual(timeline["status"],.text("resolved"))
        let encoded=try JSONEncoder().encode(adapted)
        let decoded=try JSONDecoder().decode(SomaAdaptationResult.self,from:encoded)
        XCTAssertEqual(decoded.objects,adapted.objects);XCTAssertEqual(decoded.provenance,adapted.provenance)
        let booleans=try JSONDecoder().decode(ProtocolValue.self,from:Data("[false,true,0,1]".utf8))
        XCTAssertEqual(booleans,.array([.boolean(false),.boolean(true),.integer(0),.integer(1)]))
    }
    func testBinarySleepContractPreservesRawWithoutGenerationRule()throws {
        let record=try sleepRecord()
        for (firmware,date) in [("00000808","260603"),("00000809","260519")] {
            let profile=DeviceProfile(deviceID:"test",mac:"001122334455",firmwareHex:firmware,dateHex:date)
            let result=SleepTimelineResolver.resolve(record,profile:profile,utcOffsetMinutes:480)
            XCTAssertEqual(result.status,.unresolved);XCTAssertEqual(result.reason,"unverified_rule")
            XCTAssertEqual(result.rawSlots.map(\.rawValue),[1,0,9]);XCTAssertTrue(result.intervals.isEmpty)
            XCTAssertNil(result.ruleID);XCTAssertNil(result.evidenceID)
            XCTAssertNil(SleepTimelineResolver.recordStart(record,generationProfile:profile,utcOffsetMinutes:480))
            XCTAssertNil(SleepTimelineResolver.ruleInfo(generationProfile:profile))
            let adapted=try SomaContractAdapter.historyWithDeviceTiming(record,deviceID:"01ARZ3NDEKTSV4RRFFQ69G5FAV",generationProfile:profile,utcOffsetMinutes:480)
            XCTAssertEqual(adapted.objects.count,1);XCTAssertEqual(adapted.objects[0]["raw_hex"],.text(record.rawHex))
            XCTAssertEqual(adapted.retainedRawRecords,[record]);XCTAssertEqual(adapted.rejections.map(\.reason),["unverified_rule"])
            XCTAssertNil(adapted.provenance[0]["sleep_time_rule"])
        }
    }
    func testBinaryDeviceTimingHeartRateAndBatch()throws {
        let profile=DeviceProfile(deviceID:"test",mac:"001122334455",firmwareHex:"00000808",dateHex:"260604")
        let heart=try HistoryRecord(packet:SomaLoopPacketDecoder.decode(Data([0x54,1,0,0x26,9,0x28,0,1,0]+[60,0]+Array(62...74))))
        let sleep=try sleepRecord(),deviceID="01ARZ3NDEKTSV4RRFFQ69G5FAV"
        let adapted=try SomaContractAdapter.historyWithDeviceTiming([sleep,heart,sleep,heart],deviceID:deviceID,generationProfile:profile,utcOffsetMinutes:480)
        XCTAssertEqual(adapted.objects.count,6);XCTAssertEqual(adapted.retainedRawRecords.count,4)
        XCTAssertEqual(adapted.rejections.map(\.reason),["serverZeroBecomesNull"])
        let series=try XCTUnwrap(adapted.objects.first{$0["schema"] == .text("soma.series/v1")})
        XCTAssertEqual(series["ts"],.text("2026-09-27T16:01:00Z"));XCTAssertEqual(series["step_ms"],.integer(5000))
        guard case .array(let values)=series["values"],case .object(let rule)=adapted.provenance[1]["device_time_rule"] else{return XCTFail("Missing public heart-rate series or timing provenance")}
        XCTAssertEqual(values.count,15);XCTAssertEqual(values[0],.number(60));XCTAssertEqual(values[1],.null);XCTAssertEqual(values[14],.number(74))
        XCTAssertEqual(rule["ruleID"],.text("heart-rate-start-5s-00000808-260604-v1"))
        XCTAssertEqual(rule["evidenceSource"],.text("protocolReferenceAndUserConfirmation"))
        XCTAssertEqual(rule["independentlyValidated"],.boolean(false))
    }
    func testBinaryPartialCalendarRevisionPreservesPowerDebugWithoutInventedTime()throws {
        var bytes=[UInt8](repeating:0,count:HistoryKind.powerDebug.recordLength)
        bytes.replaceSubrange(0...7,with:[0x67,1,0,0x10,1,0x14,0x59,7])
        let original=try HistoryRecord(packet:SomaLoopPacketDecoder.decode(Data(bytes)))
        let restored=try JSONCoding.decoder().decode(HistoryRecord.self,from:JSONCoding.encoder().encode(original))
        let result=try SomaContractAdapter.historyForContract(restored,deviceID:"01ARZ3NDEKTSV4RRFFQ69G5FAV",contractRevision:.partialCalendarHistoryV1)
        let object=try XCTUnwrap(result.objects.first)
        XCTAssertEqual(result.objects.count,1);XCTAssertTrue(result.rejections.isEmpty)
        XCTAssertEqual(Set(object.keys),Set(["schema","kind","device_date","precision","raw_hex","device_id"]))
        XCTAssertEqual(object["schema"],.text("soma.history-record/v1"));XCTAssertEqual(object["kind"],.text("powerDebug"))
        XCTAssertEqual(object["device_date"],.text("10011459"));XCTAssertEqual(object["precision"],.text("minute_no_year"))
        XCTAssertEqual(object["raw_hex"],.text(Data(bytes).hex));XCTAssertEqual(result.retainedRawRecords,[restored])
        XCTAssertNil(restored.deviceCalendar);XCTAssertTrue(restored.series.isEmpty)
        guard case .object(let parts)=restored.fields["deviceDateParts"] else{return XCTFail("Missing raw partial calendar")}
        XCTAssertEqual(Set(parts.keys),Set(["month","day","hour","minute"]))
        XCTAssertEqual(result.provenance[0]["record_id"],.null)
        XCTAssertEqual(result.provenance[0]["server_contract_revision"],.text(SomaContractRevision.partialCalendarHistoryV1.rawValue))
        XCTAssertNil(result.provenance[0]["time_evidence"])
        let previous=try SomaContractAdapter.historyForContract(restored,deviceID:"01ARZ3NDEKTSV4RRFFQ69G5FAV",contractRevision:.diagnosticHistoryV1)
        XCTAssertTrue(previous.objects.isEmpty);XCTAssertEqual(previous.rejections.map(\.reason),["calendarPrecisionInsufficient"])
    }
    func testBinaryECGDecodesOldRecordingAndExposesReceiptTimingWithoutCoverageClaim()throws {
        var bytes=[UInt8](repeating:0,count:181);bytes[0]=7;bytes[1]=0
        bytes.replaceSubrange(2...4,with:[0xff,0xff,0xff]);bytes.replaceSubrange(179...180,with:[0xab,0xcd])
        let packet=try SomaLoopPacketDecoder.decode(Data(bytes))
        let original=ECGRecording(startedAt:1,endedAt:61,requestedSeconds:60,packets:[packet],stopConfirmed:true,interruption:nil)
        var json=try XCTUnwrap(JSONSerialization.jsonObject(with:JSONEncoder().encode(original)) as? [String:Any])
        json.removeValue(forKey:"receptionTiming")
        let old=try JSONDecoder().decode(ECGRecording.self,from:JSONSerialization.data(withJSONObject:json))
        XCTAssertNil(old.receptionTiming);XCTAssertNil(old.receptionSummary.receptionTiming)
        XCTAssertEqual(old.frames.count,1);XCTAssertEqual(old.frames[0].values.count,59)
        XCTAssertEqual(old.frames[0].values.first,0xffffff);XCTAssertEqual(old.frames[0].unknownTail,"abcd")
        XCTAssertEqual(old.packets.map(\.rawHex),[Data(bytes).hex]);XCTAssertEqual(old.receptionSummary.completeness,"unknown")
        json["receptionTiming"]=["observationDurationSeconds":60,"receivedFrameCount":1,"firstFrameOffsetSeconds":30,
                                 "lastFrameOffsetSeconds":30,"leadingSilenceSeconds":30,"trailingSilenceSeconds":30]
        let current=try JSONDecoder().decode(ECGRecording.self,from:JSONSerialization.data(withJSONObject:json))
        let timing=try XCTUnwrap(current.receptionTiming)
        XCTAssertEqual(timing.observationDurationSeconds,60);XCTAssertEqual(timing.receivedFrameCount,1)
        XCTAssertEqual(timing.firstFrameOffsetSeconds,30);XCTAssertEqual(timing.lastFrameOffsetSeconds,30)
        XCTAssertNil(timing.maximumInterFrameGapSeconds);XCTAssertEqual(timing.leadingSilenceSeconds,30);XCTAssertEqual(timing.trailingSilenceSeconds,30)
        XCTAssertEqual(current.receptionSummary.receptionTiming,timing);XCTAssertEqual(current.sampleCount,59)
        XCTAssertEqual(current.receptionSummary.completeness,"unknown")
        XCTAssertNil(current.receptionSummary.sampleRateHz);XCTAssertNil(current.receptionSummary.expectedSampleCount)
        XCTAssertEqual(try JSONDecoder().decode(ECGRecording.self,from:JSONEncoder().encode(current)).receptionTiming,timing)
    }
    private func sleepRecord()throws->HistoryRecord {
        var bytes=[UInt8]([0x53,1,0,0x26,9,0x28,0,1,0,3,1,0,9]);bytes += [UInt8](repeating:0,count:130-bytes.count)
        return try HistoryRecord(packet:SomaLoopPacketDecoder.decode(Data(bytes)))
    }
}
