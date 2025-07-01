import Foundation

/// 統一封裝 TelemetryDeck 事件上傳
/// 預設「緩衝」所有事件，待 `flush()` 時一次送出，
/// 減少網路連線次數並確保 Session 完整性。
final class TelemetryLogger {
    static let shared = TelemetryLogger()
    private init() {}
    
    /// 目前小睡 Session 的唯一標識，於 `startNap()` 生成並在用戶反饋結束後清空。
    static var currentSessionId: String?
    
    private var buffer: [(String, [String: String])] = []
    
    /// 將事件暫存到快取
    func log(_ name: String, _ parameters: [String: String] = [:]) {
        var merged = parameters

        // 自動帶入 App 版號與 Build 號，除非呼叫端已手動覆寫
        if merged["appVersion"] == nil {
            let ver = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
            merged["appVersion"] = ver
        }
        if merged["buildNumber"] == nil {
            let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
            merged["buildNumber"] = build
        }

        // 自動帶入 SessionId，除非呼叫端已手動覆寫
        if merged["sessionId"] == nil, let sid = TelemetryLogger.currentSessionId {
            merged["sessionId"] = sid
        }

        buffer.append((name, merged))
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
        
        // 測試讀取：改用 queryRecords 避免對 _defaultZone 執行 fetchZoneChanges 產生噪音錯誤
        CloudKitLogger.shared.queryRecords(recordType: "session_end") { records, error in
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