import Foundation
import os

/// JSON Lines Logger（高級日誌系統）
/// 每行寫入一個 `LogEntry` JSON，方便串流與後續分析。
/// 使用非同步背景佇列寫檔，並定期 flush buffer。
final class AdvancedLogger {
    // MARK: - Types
    static let shared = AdvancedLogger()
    private init() { createLogDirectoryIfNeeded() }

    // 日誌事件種類
    enum LogType: String, Codable {
        case sessionStart
        case hr               // 心率取樣
        case phaseChange      // 睡眠階段轉換
        case sleepDetected
        case anomaly          // 心率異常
        case optimization     // 參數優化
        case feedback         // 使用者反饋
        case sessionEnd
    }

    /// 雜湊型 payload 的 value 型別，支援常見基本型別
    enum CodableValue: Codable {
        case int(Int)
        case double(Double)
        case string(String)
        case bool(Bool)

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let v = try? container.decode(Int.self) { self = .int(v) }
            else if let v = try? container.decode(Double.self) { self = .double(v) }
            else if let v = try? container.decode(Bool.self) { self = .bool(v) }
            else { self = .string(try container.decode(String.self)) }
        }
        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .int(let v): try container.encode(v)
            case .double(let v): try container.encode(v)
            case .string(let v): try container.encode(v)
            case .bool(let v): try container.encode(v)
            }
        }
    }

    struct LogEntry: Codable {
        let ts: String            // ISO8601 字串
        let type: LogType
        let payload: [String: CodableValue]
    }

    // MARK: - Public API
    private let queue = DispatchQueue(label: "AdvancedLoggerQueue", qos: .utility)
    private var buffer: [String] = []
    private var lastFlush: Date = Date()
    private let flushInterval: TimeInterval = 10
    private let maxBuffer: Int = 20

    /// 當前 session 檔案 URL
    private var currentLogURL: URL? {
        didSet { lastFlush = Date() }
    }

    /// 啟動新會話（在 ViewModel.startNap 呼叫）
    func startNewSession() {
        queue.async { [self] in
            let name = "powernap_session_" + Self.fileDateFormatter.string(from: Date()) + ".log"
            let url = Self.logDirectory.appendingPathComponent(name)
            FileManager.default.createFile(atPath: url.path, contents: nil)
            currentLogURL = url
            buffer.removeAll()
        }
    }

    /// 寫入一筆日誌
    func log(_ type: LogType, payload: [String: CodableValue] = [:]) {
        queue.async { [self] in
            guard let url = currentLogURL else { return }
            let entry = LogEntry(ts: Self.iso8601.string(from: Date()), type: type, payload: payload)
            if let jsonData = try? Self.encoder.encode(entry),
               let jsonString = String(data: jsonData, encoding: .utf8) {
                buffer.append(jsonString + "\n")
            }
            flushIfNeeded(to: url)
            if type == .feedback || type == .sessionEnd {
                flushBufferImmediately(to: url)
            }
        }
    }

    // MARK: - Private
    private func flushIfNeeded(to url: URL) {
        let now = Date()
        if buffer.count >= maxBuffer || now.timeIntervalSince(lastFlush) > flushInterval {
            let data = buffer.joined().data(using: .utf8)!
            buffer.removeAll()
            lastFlush = now
            if let handle = try? FileHandle(forWritingTo: url) {
                handle.seekToEndOfFile()
                handle.write(data)
                try? handle.close()
            }
        }
    }

    private func flushBufferImmediately(to url: URL) {
        if !buffer.isEmpty {
            let data = buffer.joined().data(using: .utf8)!
            buffer.removeAll()
            lastFlush = Date()
            if let handle = try? FileHandle(forWritingTo: url) {
                handle.seekToEndOfFile()
                handle.write(data)
                try? handle.close()
            }
        }
    }

    private func createLogDirectoryIfNeeded() {
        let fm = FileManager.default
        if !fm.fileExists(atPath: Self.logDirectory.path) {
            try? fm.createDirectory(at: Self.logDirectory, withIntermediateDirectories: true)
        }
    }

    // MARK: - Helpers
    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.withoutEscapingSlashes]
        return e
    }()
    private static let iso8601: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let fileDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return f
    }()
    private static var logDirectory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("AdvancedLogFiles")
    }
} 