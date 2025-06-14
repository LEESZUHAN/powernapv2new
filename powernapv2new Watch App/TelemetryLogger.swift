import Foundation

/// 統一封裝 TelemetryDeck 事件上傳
/// 預設「緩衝」所有事件，待 `flush()` 時一次送出，
/// 減少網路連線次數並確保 Session 完整性。
final class TelemetryLogger {
    static let shared = TelemetryLogger()
    private init() {}
    
    private var buffer: [(String, [String: String])] = []
    
    /// 將事件暫存到快取
    func log(_ name: String, _ parameters: [String: String] = [:]) {
        buffer.append((name, parameters))
    }
    
    /// 將快取中的事件全部送出
    func flush() {
        guard !buffer.isEmpty else { return }

        // 於 Xcode Console 提示即將送出多少事件
        print("[TelemetryLogger] Flushing \(buffer.count) events")

        for (name, params) in buffer {
            CloudKitLogger.shared.save(name: name, params: params)
        }

        buffer.removeAll()
        print("[TelemetryLogger] Flush completed")
    }
    
    /// 測試 CloudKit 連接和記錄讀取
    func testCloudKitConnection() {
        print("[TelemetryLogger] Testing CloudKit connection...")
        
        // 測試寫入
        CloudKitLogger.shared.save(name: "test_connection", params: ["test": "true", "timestamp_str": "\(Date())"])
        
        // 測試讀取（使用不需要索引的方法）
        CloudKitLogger.shared.fetchAllRecords { records, error in
            DispatchQueue.main.async {
                if let error = error {
                    print("[TelemetryLogger] CloudKit test failed: \(error.localizedDescription)")
                } else if let records = records {
                    print("[TelemetryLogger] CloudKit test success: Found \(records.count) records")
                    
                    // 顯示最近的幾筆記錄
                    let recentRecords = records.prefix(5)
                    for record in recentRecords {
                        let recordType = record.recordType
                        let timestamp = record["timestamp"] as? Date ?? Date()
                        print("  - \(recordType): \(timestamp)")
                    }
                } else {
                    print("[TelemetryLogger] CloudKit test: No records found")
                }
            }
        }
    }
    
    /// 測試 CloudKit 匯出功能
    func testExportAllRecords() {
        print("[TelemetryLogger] 開始匯出所有 CloudKit 記錄...")
        CloudKitLogger.shared.exportToJSON()
    }
} 