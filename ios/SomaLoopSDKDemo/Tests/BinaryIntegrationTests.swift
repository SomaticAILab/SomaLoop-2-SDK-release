import XCTest
import SomaLoopSDK
final class BinaryIntegrationTests:XCTestCase {
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
    private func sleepRecord()throws->HistoryRecord {
        var bytes=[UInt8]([0x53,1,0,0x26,9,0x28,0,1,0,3,1,0,9]);bytes += [UInt8](repeating:0,count:130-bytes.count)
        return try HistoryRecord(packet:SomaLoopPacketDecoder.decode(Data(bytes)))
    }
}
