import Foundation
import CloudKit

/// 負責將 Telemetry 事件寫入 CloudKit Public Database，免後端伺服器。
/// 每個事件對應一筆 CKRecord：Record Type = signal name
/// 欄位規則：
///   • userId   : String  (installationId)
///   • timestamp: Date   (ISO8601)
///   • 其餘 key   : String (或 Double 轉字串)
final class CloudKitLogger {
    static let shared = CloudKitLogger()
    private init() {}

    // 使用明確的 Umbrella Container，避免 watchkitapp 後綴造成錯誤
    private let db = CKContainer(identifier: "iCloud.com.powernap").publicCloudDatabase

    /// 將事件寫入 CloudKit；失敗時僅列印錯誤，不影響主流程。
    func save(name: String, params: [String: String]) {
        // 使用者若未同意分享使用資料，直接略過
        if !UserDefaults.standard.bool(forKey: "shareUsage") {
            return
        }
        let record = CKRecord(recordType: name)

        // userId 同 powernapv2newApp.swift 生成的 installationId
        if let installId = UserDefaults.standard.string(forKey: "installationId") {
            record["userId"] = installId as CKRecordValue
        }
        record["timestamp"] = Date() as CKRecordValue

        for (k, v) in params {
            record[k] = v as CKRecordValue
        }

        db.save(record) { _, error in
            if let error = error {
                print("[CloudKitLogger] save error: \(error.localizedDescription)")
            } else {
                print("[CloudKitLogger] save success: \(name)")
            }
        }
    }
    
    /// 查詢記錄（用於測試和驗證）
    /// 使用 timestamp 欄位查詢，避免依賴 recordName 索引
    func queryRecords(recordType: String, completion: @escaping ([CKRecord]?, Error?) -> Void) {
        // 使用 timestamp 欄位查詢最近的記錄，而不是使用 NSPredicate(value: true)
        let oneDayAgo = Date().addingTimeInterval(-24 * 60 * 60)
        let predicate = NSPredicate(format: "timestamp >= %@", oneDayAgo as NSDate)
        let query = CKQuery(recordType: recordType, predicate: predicate)
        
        // 按時間戳排序
        query.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: false)]
        
        // 使用 CKQueryOperation 來避免 API 歧義
        let operation = CKQueryOperation(query: query)
        operation.resultsLimit = CKQueryOperation.maximumResults
        operation.zoneID = nil // 使用 default zone
        
        var fetchedRecords: [CKRecord] = []
        
        // 使用新 API (watchOS 8+)：recordMatchedBlock 取代 recordFetchedBlock
        operation.recordMatchedBlock = { recordID, result in
            switch result {
            case .success(let record):
                fetchedRecords.append(record)
            case .failure(let error):
                print("[CloudKitLogger] Record fetch error: \(error)")
            }
        }
        
        // 使用新 API (watchOS 8+)：queryResultBlock 取代 queryCompletionBlock
        operation.queryResultBlock = { result in
            switch result {
            case .success(_):
                completion(fetchedRecords, nil)
            case .failure(let error):
                completion(nil, error)
            }
        }
        
        db.add(operation)
    }

    /// 使用 CKFetchRecordZoneChangesOperation 獲取所有記錄（不需要索引）
    func fetchAllRecords(recordType: String? = nil, completion: @escaping ([CKRecord]?, Error?) -> Void) {
        let zoneID = CKRecordZone.default().zoneID
        let operation = CKFetchRecordZoneChangesOperation(recordZoneIDs: [zoneID], configurationsByRecordZoneID: nil)
        
        var allRecords: [CKRecord] = []
        
        operation.recordWasChangedBlock = { _, result in
            switch result {
            case .success(let record):
                // 如果指定了 recordType，只收集該類型的記錄
                if let targetType = recordType {
                    if record.recordType == targetType {
                        allRecords.append(record)
                    }
                } else {
                    // 收集所有記錄
                    allRecords.append(record)
                }
            case .failure(let error):
                print("[CloudKitLogger] Record fetch error: \(error)")
            }
        }
        
        // 新 API：recordZoneFetchResultBlock (watchOS 8+) 取代 recordZoneFetchCompletionBlock
        operation.recordZoneFetchResultBlock = { _, result in
            switch result {
            case .success:
                print("[CloudKitLogger] 成功獲取 \(allRecords.count) 筆記錄")
                completion(allRecords, nil)
            case .failure(let error):
                print("[CloudKitLogger] Zone 獲取失敗: \(error)")
                completion(nil, error)
            }
        }
        
        db.add(operation)
    }
    
    /// 匯出記錄到 JSON 檔案（用於資料分析）
    func exportToJSON(recordType: String? = nil, filename: String? = nil) {
        fetchAllRecords(recordType: recordType) { records, error in
            if let error = error {
                print("[CloudKitLogger] 匯出失敗: \(error)")
                return
            }
            
            guard let records = records, !records.isEmpty else {
                print("[CloudKitLogger] 沒有找到記錄")
                return
            }
            
            // 轉換為 JSON 格式
            let jsonData = records.map { record -> [String: Any] in
                var json: [String: Any] = [:]
                
                // 系統欄位
                json["recordType"] = record.recordType
                json["recordName"] = record.recordID.recordName
                json["creationDate"] = ISO8601DateFormatter().string(from: record.creationDate ?? Date())
                json["modificationDate"] = ISO8601DateFormatter().string(from: record.modificationDate ?? Date())
                
                // 自定義欄位
                for key in record.allKeys() {
                    if let value = record[key] {
                        json[key] = self.convertToJSONValue(value)
                    }
                }
                
                return json
            }
            
            // 寫入檔案
            do {
                let data = try JSONSerialization.data(withJSONObject: jsonData, options: .prettyPrinted)
                let outputFilename = filename ?? "\(recordType ?? "all_records")_export.json"
                
                // 寫到 Documents 目錄
                let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                let fileURL = documentsPath.appendingPathComponent(outputFilename)
                
                try data.write(to: fileURL)
                print("[CloudKitLogger] 成功匯出到: \(fileURL.path)")
                print("[CloudKitLogger] 記錄數量: \(records.count)")
                
                // 顯示記錄類型統計
                let typeCount = Dictionary(grouping: records, by: { $0.recordType })
                    .mapValues { $0.count }
                print("[CloudKitLogger] 記錄類型統計:")
                for (type, count) in typeCount.sorted(by: { $0.key < $1.key }) {
                    print("  \(type): \(count) 筆")
                }
                
            } catch {
                print("[CloudKitLogger] 寫入檔案失敗: \(error)")
            }
        }
    }
    
    /// 轉換 CKRecordValue 為 JSON 可序列化的值
    private func convertToJSONValue(_ value: CKRecordValue) -> Any {
        switch value {
        case let stringValue as String:
            return stringValue
        case let numberValue as NSNumber:
            return numberValue
        case let dateValue as Date:
            return ISO8601DateFormatter().string(from: dateValue)
        case let dataValue as Data:
            return dataValue.base64EncodedString()
        default:
            return String(describing: value)
        }
    }
} 