import Foundation
import XCTest
import SomaLoopSDK
@testable import SomaLoopSDKDemo

final class HistoryPageExportTests:XCTestCase {
    private let device=DeviceProfile(deviceID:"synthetic",mac:"001122334455",firmwareHex:"00000808",dateHex:"260604")
    private func batch(_ kind:HistoryKind = .ppi,complete:Bool=false,continuation:Bool=true,interruption:String?=nil,invalidRecord:Bool=false)throws->HistoryBatch {
        var json:[String:Any] = ["kind":kind.rawValue,"records":invalidRecord ? [["opcode":kind.rawValue,"layout":"synthetic-invalid","fields":[:],"rawHex":"ff"]]:[],"notificationCount":0,"complete":complete,"continuationAvailable":continuation]
        if let interruption{json["interruption"]=interruption}
        return try JSONCoding.decoder().decode(HistoryBatch.self,from:JSONSerialization.data(withJSONObject:json))
    }
    private func report(_ directory:URL)throws->HistoryPageExport.Report {
        try JSONCoding.decoder().decode(HistoryPageExport.Report.self,from:Data(contentsOf:directory.appendingPathComponent("report.json")))
    }
    private func directory(_ root:URL)throws->URL {
        try XCTUnwrap(FileManager.default.contentsOfDirectory(at:root,includingPropertiesForKeys:nil).first)
    }
    func testNormalContinuationPersistsEachBatchBeforeFetchingNext()async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);defer{try? FileManager.default.removeItem(at:root)}
        var flags=[Bool]()
        let result=try await HistoryPageExport.read(kind:.ppi,device:device,root:root){continuation in
            if !flags.isEmpty {
                let folder=try self.directory(root),saved=try self.report(folder)
                XCTAssertFalse(saved.complete);XCTAssertEqual(saved.pages.count,flags.count)
                let data=try Data(contentsOf:folder.appendingPathComponent(saved.pages.last!.file))
                let raw=try JSONCoding.decoder().decode(HistoryBatch.self,from:data)
                XCTAssertTrue(raw.continuationAvailable);XCTAssertNil(raw.interruption)
                XCTAssertEqual(saved.pages.last!.sha256.count,64)
            }
            flags.append(continuation)
            return try self.batch(complete:flags.count==3,continuation:flags.count != 3)
        }
        XCTAssertEqual(flags,[false,true,true]);let final=try report(result)
        XCTAssertTrue(final.complete);XCTAssertNil(final.interruption);XCTAssertEqual(final.pages.count,3)
    }
    func testInterruptionSavedWithoutRequestingAnotherPageEvenWithEndFlag()async throws {
        for complete in [false,true] {
            let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);defer{try? FileManager.default.removeItem(at:root)}
            var calls=0
            let result=try await HistoryPageExport.read(kind:.ppi,device:device,root:root){_ in calls+=1;return try self.batch(complete:complete,interruption:"timeout")}
            let final=try report(result);XCTAssertEqual(calls,1);XCTAssertFalse(final.complete);XCTAssertEqual(final.interruption,"timeout")
            let raw=try JSONCoding.decoder().decode(HistoryBatch.self,from:Data(contentsOf:result.appendingPathComponent(final.pages[0].file)))
            XCTAssertEqual(raw.interruption,.timeout);XCTAssertEqual(raw.complete,complete)
        }
    }
    func testTypedFailureRetainsRawRecordAndDoesNotWriteEmptySuccess()async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);defer{try? FileManager.default.removeItem(at:root)}
        let result=try await HistoryPageExport.read(kind:.ppi,device:device,root:root){_ in try self.batch(complete:true,continuation:false,invalidRecord:true)}
        let final=try report(result);XCTAssertTrue(final.complete);XCTAssertNotNil(final.pages[0].typedError);XCTAssertNil(final.pages[0].typedFile)
        let raw=try JSONCoding.decoder().decode(HistoryBatch.self,from:Data(contentsOf:result.appendingPathComponent(final.pages[0].file)))
        XCTAssertEqual(raw.records.count,1);XCTAssertEqual(raw.records[0].rawHex,"ff")
        XCTAssertFalse(FileManager.default.fileExists(atPath:result.appendingPathComponent("typed-0001.json").path))
    }
    func testRawStorageFailurePreventsContinuation()async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);defer{try? FileManager.default.removeItem(at:root)}
        var calls=0
        do {
            _ = try await HistoryPageExport.read(kind:.ppi,device:device,root:root){_ in
                calls+=1;let blocked=try self.directory(root).appendingPathComponent("page-0001.json")
                try FileManager.default.createDirectory(at:blocked,withIntermediateDirectories:true)
                try Data([1]).write(to:blocked.appendingPathComponent("keep"))
                return try self.batch()
            };XCTFail()
        }catch{}
        XCTAssertEqual(calls,1);let saved=try report(directory(root));XCTAssertFalse(saved.complete);XCTAssertTrue(saved.pages.isEmpty)
    }
    func testInvalidCompletionStatesAndPageLimitDoNotClaimComplete()async throws {
        for (complete,continuation) in [(false,false),(true,true),(false,true)] {
            let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);defer{try? FileManager.default.removeItem(at:root)}
            var calls=0
            let result=try await HistoryPageExport.read(kind:.ppi,device:device,root:root,maximumPages:1){_ in calls+=1;return try self.batch(complete:complete,continuation:continuation)}
            XCTAssertEqual(calls,1);let final=try report(result);XCTAssertFalse(final.complete)
            XCTAssertEqual(final.interruption,!complete && continuation ? "pageLimit":"protocolMismatch")
        }
    }
    func testReadFailurePreservesPriorPageAndNewRunStartsWithoutContinuation()async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);defer{try? FileManager.default.removeItem(at:root)}
        var calls=0
        let first=try await HistoryPageExport.read(kind:.ppi,device:device,root:root){_ in
            calls+=1;if calls==2{throw SDKError.disconnected};return try self.batch()
        }
        let saved=try report(first);XCTAssertEqual(saved.pages.count,1);XCTAssertFalse(saved.complete);XCTAssertEqual(saved.interruption,"disconnected")
        let second=try await HistoryPageExport.read(kind:.ppi,device:device,root:root){continuation in
            XCTAssertFalse(continuation);return try self.batch(complete:true,continuation:false)
        }
        XCTAssertNotEqual(first,second);XCTAssertEqual(try report(first).pages.count,1)
    }
    func testAllFifteenKindsRoundTripEmptyTerminalBatch()async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);defer{try? FileManager.default.removeItem(at:root)}
        for kind in HistoryKind.allCases {
            let result=try await HistoryPageExport.read(kind:kind,device:device,root:root){continuation in
                XCTAssertFalse(continuation);return try self.batch(kind,complete:true,continuation:false)
            }
            let final=try report(result);XCTAssertTrue(final.complete);XCTAssertEqual(final.kind,kind);XCTAssertEqual(final.pages[0].records,0)
            let decoded=try JSONCoding.decoder().decode(HistoryBatch.self,from:Data(contentsOf:result.appendingPathComponent(final.pages[0].file)))
            XCTAssertEqual(decoded.kind,kind);XCTAssertTrue(decoded.complete);XCTAssertFalse(decoded.continuationAvailable)
        }
    }
}
