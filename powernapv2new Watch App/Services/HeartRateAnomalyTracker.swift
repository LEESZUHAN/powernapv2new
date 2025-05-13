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
        
        // 新增：心率偏離閾值
        static let upwardDeviationThreshold: Double = 0.05  // 心率向上偏離5%開始記錄異常
        static let downwardDeviationThreshold: Double = 0.08  // 心率向下偏離8%開始記錄異常
        static let downwardAdjustmentFactor: Double = 0.5   // 向下偏離異常分數減半
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
    
    // 新增：追蹤向上和向下的異常
    private(set) var upwardAnomalies: Int = 0        // 向上異常計數
    private(set) var downwardAnomalies: Int = 0      // 向下異常計數
    
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
    
    /// 評估心率偏離並計算異常分數 (不對稱異常檢測)
    /// - Parameters:
    ///   - heartRate: 當前心率
    ///   - expectedHR: 預期心率
    /// - Returns: 異常狀態分類
    @discardableResult
    func evaluateHeartRateDeviation(heartRate: Double, expectedHR: Double, date: Date = Date()) -> AnomalyStatus {
        // 計算偏離百分比
        let deviation = (heartRate - expectedHR) / expectedHR
        
        // 判斷偏離方向
        if deviation > 0 {
            // 向上偏離 (心率高於預期) - 維持嚴格檢測
            return evaluateUpwardDeviation(deviation: deviation, date: date)
        } else {
            // 向下偏離 (心率低於預期) - 使用寬鬆標準
            return evaluateDownwardDeviation(deviation: deviation, date: date)
        }
    }
    
    /// 評估心率向上偏離 (更嚴格檢測)
    private func evaluateUpwardDeviation(deviation: Double, date: Date) -> AnomalyStatus {
        // 超過閾值才記錄異常
        if deviation < Thresholds.upwardDeviationThreshold {
            return .none // 在容忍範圍內
        }
        
        // 計算異常嚴重度 (0-10)
        var anomalySeverity: Double = 0
        
        // 非線性映射偏差到異常嚴重度
        if deviation <= 0.1 {              // 5-10%，輕微異常
            anomalySeverity = (deviation - Thresholds.upwardDeviationThreshold) * 100  // 0-5
        } else if deviation <= 0.2 {       // 10-20%，中度異常
            anomalySeverity = 5.0 + (deviation - 0.1) * 50  // 5-10
        } else {                           // >20%，嚴重異常
            anomalySeverity = 10.0  // 最大異常值
        }
        
        // 記錄向上異常
        upwardAnomalies += 1
        
        // 記錄異常並返回異常狀態
        logger.info("心率向上偏離: +\(String(format: "%.1f", deviation * 100))%, 評分: \(String(format: "%.1f", anomalySeverity))")
        return recordAnomaly(severity: anomalySeverity, date: date)
    }
    
    /// 評估心率向下偏離 (使用寬鬆標準)
    private func evaluateDownwardDeviation(deviation: Double, date: Date) -> AnomalyStatus {
        // 將負偏差轉為正值 (便於比較)
        let absDeviation = abs(deviation)
        
        // 使用寬鬆閾值，超過閾值才記錄異常
        if absDeviation < Thresholds.downwardDeviationThreshold {
            return .none // 在容忍範圍內
        }
        
        // 計算異常嚴重度 (0-10)，採用與向上偏離相同的邏輯，但會減半
        var anomalySeverity: Double = 0
        
        // 非線性映射偏差到異常嚴重度
        if absDeviation <= 0.15 {              // 8-15%，輕微異常
            anomalySeverity = (absDeviation - Thresholds.downwardDeviationThreshold) * 70  // 0-4.9
        } else if absDeviation <= 0.25 {       // 15-25%，中度異常
            anomalySeverity = 4.9 + (absDeviation - 0.15) * 40  // 4.9-8.9
        } else {                               // >25%，嚴重異常
            anomalySeverity = 8.9 + (min(absDeviation - 0.25, 0.05) * 22)  // 8.9-10
        }
        
        // 向下偏離異常分數減半
        anomalySeverity *= Thresholds.downwardAdjustmentFactor
        
        // 記錄向下異常
        downwardAnomalies += 1
        
        // 記錄異常並返回異常狀態
        logger.info("心率向下偏離: -\(String(format: "%.1f", absDeviation * 100))%, 評分: \(String(format: "%.1f", anomalySeverity)) (已減半)")
        return recordAnomaly(severity: anomalySeverity, date: date)
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
        return "異常狀態: \(status.rawValue), 累計分數: \(String(format: "%.1f", cumulativeScore)), 暫時異常: \(temporaryAnomalies), 持久異常: \(persistentAnomalies), 向上異常: \(upwardAnomalies), 向下異常: \(downwardAnomalies), 重置次數: \(baselineResets)"
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
        // 計算30天前的日期
        let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        
        // 移除所有30天前的記錄
        let oldKeys = anomalyScores.keys.filter { date in
            return date < thirtyDaysAgo
        }
        
        // 如果有舊記錄，刪除並記錄
        if !oldKeys.isEmpty {
            for key in oldKeys {
                anomalyScores.removeValue(forKey: key)
            }
            logger.info("已清理\(oldKeys.count)條超過30天的異常記錄")
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
        defaults.set(upwardAnomalies, forKey: "HeartRateAnomalyUpwardCount")
        defaults.set(downwardAnomalies, forKey: "HeartRateAnomalyDownwardCount")
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
        upwardAnomalies = defaults.integer(forKey: "HeartRateAnomalyUpwardCount")
        downwardAnomalies = defaults.integer(forKey: "HeartRateAnomalyDownwardCount")
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