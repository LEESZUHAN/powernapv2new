import Foundation
import os

/// 心率異常追蹤器 - 負責區分暫時和持久性心率異常
/// 用於提高對用戶睡眠狀態的準確判斷，並適應長期變化
class HeartRateAnomalyTracker {
    // MARK: - 常量
    /// 異常類型分類閾值
    private struct Thresholds {
        static let lowAnomalyScore: Double = 3.0     // 低異常分數閾值
        static let highAnomalyScore: Double = 7.0    // 高異常分數閾值
        static let persistentThreshold: Double = 12.0 // 持久異常閾值
        static let decayFactor: Double = 0.8         // 每日衰減因子
        static let baselineResetThreshold: Double = 14.0 // 基線重校準所需的分數
    }
    
    // MARK: - 屬性
    private var anomalyScores: [Date: Double] = [:]  // 異常分數記錄
    private var cumulativeScore: Double = 0          // 累計異常分數
    private let logger = Logger(subsystem: "com.yourdomain.powernapv2new", category: "HeartRateAnomalyTracker")
    
    // 最後重置日期
    private var lastResetDate: Date?
    
    // 分析指標
    private(set) var temporaryAnomalies: Int = 0     // 暫時異常計數
    private(set) var persistentAnomalies: Int = 0    // 持久異常計數
    private(set) var baselineResets: Int = 0         // 基線重置次數
    
    // 公開異常狀態，供外部系統使用
    public enum AnomalyStatus: String {
        case none = "正常"             // 無異常
        case temporary = "暫時異常"     // 暫時性異常
        case persistent = "持久異常"    // 持久性異常
        case requiresReset = "需要重校準" // 異常程度需要重校準
    }
    
    // MARK: - 初始化
    init() {
        // 初始化時讀取保存的異常記錄
        loadAnomalyData()
    }
    
    // MARK: - 公開方法
    
    /// 記錄心率異常並分類
    /// - Parameters:
    ///   - severity: 異常嚴重度 (0.0-10.0)
    ///   - date: 異常發生日期
    /// - Returns: 異常狀態分類
    @discardableResult
    func recordAnomaly(severity: Double, date: Date = Date()) -> AnomalyStatus {
        // 1. 清理過期數據
        cleanupOldData()
        
        // 2. 記錄新異常
        let score = min(max(severity, 0), 10) // 確保分數在0-10範圍內
        anomalyScores[date] = score
        
        // 3. 更新累計分數
        updateCumulativeScore()
        
        // 4. 獲取異常狀態
        let status = getCurrentAnomalyStatus()
        
        // 5. 根據狀態更新計數
        switch status {
        case .temporary:
            temporaryAnomalies += 1
        case .persistent:
            persistentAnomalies += 1
        case .requiresReset:
            // 僅記錄，實際重置在外部調用
            logger.info("心率異常嚴重，建議重置基線")
        default:
            break
        }
        
        // 6. 保存更新後的數據
        saveAnomalyData()
        
        logger.info("記錄心率異常 - 嚴重度: \(severity), 狀態: \(status.rawValue), 累計分數: \(self.cumulativeScore)")
        return status
    }
    
    /// 獲取當前異常狀態
    func getCurrentAnomalyStatus() -> AnomalyStatus {
        if cumulativeScore >= Thresholds.baselineResetThreshold {
            return .requiresReset
        } else if cumulativeScore >= Thresholds.persistentThreshold {
            return .persistent
        } else if cumulativeScore >= Thresholds.lowAnomalyScore {
            return .temporary
        } else {
            return .none
        }
    }
    
    /// 重置基線
    /// 用於當系統檢測到長期異常，需要適應新的基線時
    func resetBaseline() {
        anomalyScores.removeAll()
        cumulativeScore = 0
        lastResetDate = Date()
        baselineResets += 1
        
        logger.info("已重置心率異常基線，總重置次數: \(self.baselineResets)")
        saveAnomalyData()
    }
    
    /// 獲取異常摘要信息
    func getAnomalySummary() -> String {
        let status = getCurrentAnomalyStatus()
        return "異常狀態: \(status.rawValue), 累計分數: \(String(format: "%.1f", cumulativeScore)), 暫時異常: \(temporaryAnomalies), 持久異常: \(persistentAnomalies), 重置次數: \(baselineResets)"
    }
    
    // MARK: - 私有方法
    
    /// 更新累計異常分數
    private func updateCumulativeScore() {
        // 通過時間加權對所有異常進行評分
        let now = Date()
        var totalScore: Double = 0
        
        for (date, score) in anomalyScores {
            // 計算天數差
            let daysSince = now.timeIntervalSince(date) / (24 * 3600)
            
            // 使用指數衰減加權
            let weight = pow(Thresholds.decayFactor, daysSince)
            totalScore += score * weight
        }
        
        cumulativeScore = totalScore
    }
    
    /// 清理舊數據（超過14天的異常記錄）
    private func cleanupOldData() {
        let now = Date()
        let cutoffDate = now.addingTimeInterval(-14 * 24 * 3600) // 14天前
        
        // 移除超過14天的記錄
        anomalyScores = anomalyScores.filter { key, _ in
            return key > cutoffDate
        }
    }
    
    /// 保存異常數據
    private func saveAnomalyData() {
        let defaults = UserDefaults.standard
        
        // 轉換日期-分數字典為可存儲的格式
        let encodableScores: [String: Double] = anomalyScores.mapKeys { date in
            return date.timeIntervalSince1970.description
        }
        
        // 保存數據
        defaults.set(encodableScores, forKey: "HeartRateAnomalyScores")
        defaults.set(cumulativeScore, forKey: "HeartRateAnomalyCumulativeScore")
        defaults.set(temporaryAnomalies, forKey: "HeartRateAnomalyTemporaryCount")
        defaults.set(persistentAnomalies, forKey: "HeartRateAnomalyPersistentCount")
        defaults.set(baselineResets, forKey: "HeartRateAnomalyBaselineResets")
        defaults.set(lastResetDate?.timeIntervalSince1970, forKey: "HeartRateAnomalyLastResetDate")
    }
    
    /// 加載異常數據
    private func loadAnomalyData() {
        let defaults = UserDefaults.standard
        
        // 讀取並轉換回日期-分數字典
        if let encodedScores = defaults.object(forKey: "HeartRateAnomalyScores") as? [String: Double] {
            anomalyScores = encodedScores.mapKeys { timeString in
                let timeInterval = TimeInterval(timeString) ?? 0
                return Date(timeIntervalSince1970: timeInterval)
            }
        }
        
        // 讀取其他數據
        cumulativeScore = defaults.double(forKey: "HeartRateAnomalyCumulativeScore")
        temporaryAnomalies = defaults.integer(forKey: "HeartRateAnomalyTemporaryCount")
        persistentAnomalies = defaults.integer(forKey: "HeartRateAnomalyPersistentCount")
        baselineResets = defaults.integer(forKey: "HeartRateAnomalyBaselineResets")
        
        if let resetTimeInterval = defaults.object(forKey: "HeartRateAnomalyLastResetDate") as? TimeInterval {
            lastResetDate = Date(timeIntervalSince1970: resetTimeInterval)
        }
    }
}

// 擴展Dictionary以支持mapKeys操作
extension Dictionary {
    func mapKeys<T>(_ transform: (Key) -> T) -> [T: Value] where T: Hashable {
        var result: [T: Value] = [:]
        for (key, value) in self {
            result[transform(key)] = value
        }
        return result
    }
} 