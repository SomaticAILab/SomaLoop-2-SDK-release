import Foundation
import CryptoKit
import SomaLoopSDK

/// App-owned example: serial reads on one connection/type, raw page saved before continuation.
/// Each invocation uses a new directory; a persisted page number is never an SDK continuation token.
enum HistoryPageExport {
    struct Report: Codable {
        struct Page: Codable {
            let file: String, sha256: String, records: Int
            var typedFile: String?, typedError: String?
        }
        let schemaVersion: Int, id: String, sdkVersion: String, buildRevision: String
        let device: DeviceProfile, kind: HistoryKind, startedAt: Date
        var pages: [Page] = []
        var complete = false
        var interruption: String?
        var finishedAt: Date?
    }

    static func read(client: SomaLoopClient, kind: HistoryKind, root: URL, maximumPages: Int = 1000) async throws -> URL {
        guard let device=await client.profile else { throw SDKError.disconnected }
        return try await read(kind:kind,device:device,root:root,maximumPages:maximumPages) { continuation in
            try await client.readHistoryBatch(kind,continuation:continuation)
        }
    }

    static func read(kind: HistoryKind, device: DeviceProfile, root: URL, maximumPages: Int = 1000,
                     fetch: (Bool) async throws -> HistoryBatch) async throws -> URL {
        guard maximumPages > 0 else { throw SDKError.invalidArgument }
        let id=UUID().uuidString,directory=root.appendingPathComponent("history-\(kind.rawValue)-\(id)",isDirectory:true)
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        var report=Report(schemaVersion:1,id:id,sdkVersion:SomaLoop.version,buildRevision:SomaLoop.buildRevision,
                          device:device,kind:kind,startedAt:Date())
        func saveReport() throws {
            try JSONCoding.encoder().encode(report).write(to:directory.appendingPathComponent("report.json"),options:.atomic)
        }
        try saveReport() // Incomplete until the terminal batch is durably saved.
        var continuation=false
        for index in 1...maximumPages {
            let batch:HistoryBatch
            do { try Task.checkCancellation();batch=try await fetch(continuation) }
            catch { report.interruption=error is CancellationError ? SDKError.cancelled.rawValue:String(describing:error);break }
            let file=String(format:"page-%04d.json",index)
            let raw=try JSONCoding.encoder().encode(batch)
            try raw.write(to:directory.appendingPathComponent(file),options:.atomic)
            var page=Report.Page(file:file,sha256:SHA256.hash(data:raw).map{String(format:"%02x",$0)}.joined(),records:batch.records.count)
            report.pages.append(page)
            try saveReport() // A typed conversion failure cannot remove the saved batch.
            var typed:[HistoryRecord]?
            do { typed=try batch.typedRecords }
            catch { page.typedError=String(describing:error) }
            if let typed {
                let typedFile=String(format:"typed-%04d.json",index)
                // A storage error aborts; it is not disguised as a decoder failure.
                try JSONCoding.encoder().encode(typed).write(to:directory.appendingPathComponent(typedFile),options:.atomic)
                page.typedFile=typedFile
            }
            report.pages[report.pages.count-1]=page
            try saveReport()
            if batch.kind != kind { report.interruption=SDKError.protocolMismatch.rawValue;break }
            if let error=batch.interruption { report.interruption=error.rawValue;break }
            if batch.complete && !batch.continuationAvailable { report.complete=true;break }
            guard !batch.complete && batch.continuationAvailable else { report.interruption=SDKError.protocolMismatch.rawValue;break }
            if index==maximumPages { report.interruption="pageLimit";break }
            continuation=true // Only after both raw file and its report entry were saved.
        }
        report.finishedAt=Date();try saveReport()
        return directory
    }
}
