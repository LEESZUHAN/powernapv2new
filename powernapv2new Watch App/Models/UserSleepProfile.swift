import Foundation
import HealthKit
import Combine

/// 用戶睡眠檔案，用於保存個人化睡眠檢測參數
public struct UserSleepProfile: Codable {
    // 基本信息
    public let userId: String
    public let ageGroup: AgeGroup
    
    // 心率閾值設定
    public var hrThresholdPercentage: Double  // 例如 0.9 表示 RHR 的 90%
    public var minDurationSeconds: Int        // 維持低心率需要的時間（秒）
    
    // 模型狀態追蹤
    public var firstUseDate: Date?            // 首次使用日期
    public var lastModelUpdateDate: Date?     // 最後一次模型更新日期
    public var sleepSessionsCount: Int        // 記錄的睡眠次數
    
    // 統計數據
    public var averageSleepHR: Double?        // 平均睡眠心率
    public var minSleepHR: Double?            // 最低睡眠心率
    public var sleepHRVariance: Double?       // 睡眠心率變異
    public var truePositiveRate: Double?      // 準確檢測率（如果有反饋）
    
    // 用戶手動調整值，範圍通常是 -0.05 到 +0.05
    public var manualAdjustmentOffset: Double = 0.0
    
    // 用戶反饋統計
    public var accurateDetectionCount: Int = 0   // 用戶反饋檢測準確的次數
    public var inaccurateDetectionCount: Int = 0 // 用戶反饋檢測不準確的次數
    
    // 新增: 靜止比例相關參數
    public var baseRestingRatioThreshold: Double // 基於年齡組的基礎靜止比例
    public var restingRatioAdjustment: Double = 0.0 // 用戶調整值，範圍-0.1到0.1之間
    
    // 獲取有效的靜止比例閾值
    public var effectiveRestingRatioThreshold: Double {
        // 應用用戶調整，但確保結果在0.5到0.95之間
        let adjusted = baseRestingRatioThreshold + restingRatioAdjustment
        return min(max(adjusted, 0.5), 0.95)
    }
    
    // 創建默認配置文件
    public static func createDefault(forUserId userId: String, ageGroup: AgeGroup) -> UserSleepProfile {
        let baseThreshold: Double
        let minDuration: Int
        let baseRestingRatio: Double
        
        switch ageGroup {
        case .teen:
            baseThreshold = 0.875 // 87.5% for teens
            minDuration = 120     // 2分鐘
            baseRestingRatio = 0.80 // 80% 靜止比例
        case .adult:
            baseThreshold = 0.9   // 90% for adults
            minDuration = 180     // 3分鐘
            baseRestingRatio = 0.75 // 75% 靜止比例
        case .senior:
            baseThreshold = 0.935 // 93.5% for seniors
            minDuration = 240     // 4分鐘
            baseRestingRatio = 0.70 // 70% 靜止比例
        }
        
        return UserSleepProfile(
            userId: userId,
            ageGroup: ageGroup,
            hrThresholdPercentage: baseThreshold,
            minDurationSeconds: minDuration,
            firstUseDate: Date(),
            lastModelUpdateDate: nil as Date?,
            sleepSessionsCount: 0,
            averageSleepHR: nil as Double?,
            minSleepHR: nil as Double?,
            sleepHRVariance: nil as Double?,
            truePositiveRate: nil as Double?,
            accurateDetectionCount: 0,
            inaccurateDetectionCount: 0,
            baseRestingRatioThreshold: baseRestingRatio,
            restingRatioAdjustment: 0.0
        )
    }
    
    // 計算實際使用的閾值百分比（包含手動調整）
    public var adjustedThresholdPercentage: Double {
        return hrThresholdPercentage + manualAdjustmentOffset
    }
}

/// 睡眠會話數據結構，用於記錄單次睡眠過程中的心率數據
public struct SleepSession: Codable {
    let id: String
    let userId: String
    let startTime: Date
    let endTime: Date?
    let heartRates: [Double]
    let detectedSleepTime: Date?
    let averageHeartRate: Double?
    let minimumHeartRate: Double?
    let userFeedback: SleepFeedback?
    
    public enum SleepFeedback: String, Codable {
        case accurate     // 用戶反饋檢測準確
        case falsePositive // 用戶未睡著但被檢測為睡眠
        case falseNegative // 用戶已睡著但未被檢測到
        case none         // 未提供反饋
    }
    
    /// 創建新睡眠會話
    public static func create(userId: String) -> SleepSession {
        return SleepSession(
            id: UUID().uuidString,
            userId: userId,
            startTime: Date(),
            endTime: nil,
            heartRates: [],
            detectedSleepTime: nil,
            averageHeartRate: nil,
            minimumHeartRate: nil,
            userFeedback: SleepFeedback.none
        )
    }
    
    /// 添加一個心率樣本
    public func addingHeartRate(_ heartRate: Double) -> SleepSession {
        var newHeartRates = self.heartRates
        newHeartRates.append(heartRate)
        
        return SleepSession(
            id: self.id,
            userId: self.userId,
            startTime: self.startTime,
            endTime: self.endTime,
            heartRates: newHeartRates,
            detectedSleepTime: self.detectedSleepTime,
            averageHeartRate: self.averageHeartRate,
            minimumHeartRate: self.minimumHeartRate,
            userFeedback: self.userFeedback
        )
    }
    
    /// 完成會話（添加結束時間和計算統計數據）
    public func completing() -> SleepSession {
        let avgHR = heartRates.isEmpty ? nil : heartRates.reduce(0, +) / Double(heartRates.count)
        let minHR = heartRates.isEmpty ? nil : heartRates.min()
        
        return SleepSession(
            id: self.id,
            userId: self.userId,
            startTime: self.startTime,
            endTime: Date(),
            heartRates: self.heartRates,
            detectedSleepTime: self.detectedSleepTime,
            averageHeartRate: avgHR,
            minimumHeartRate: minHR,
            userFeedback: self.userFeedback
        )
    }
    
    /// 設置檢測到睡眠的時間
    public func withDetectedSleepTime(_ time: Date) -> SleepSession {
        return SleepSession(
            id: self.id,
            userId: self.userId,
            startTime: self.startTime,
            endTime: self.endTime,
            heartRates: self.heartRates,
            detectedSleepTime: time,
            averageHeartRate: self.averageHeartRate,
            minimumHeartRate: self.minimumHeartRate,
            userFeedback: self.userFeedback
        )
    }
    
    /// 添加用戶反饋
    public func withFeedback(_ feedback: SleepFeedback) -> SleepSession {
        return SleepSession(
            id: self.id,
            userId: self.userId,
            startTime: self.startTime,
            endTime: self.endTime,
            heartRates: self.heartRates,
            detectedSleepTime: self.detectedSleepTime,
            averageHeartRate: self.averageHeartRate,
            minimumHeartRate: self.minimumHeartRate,
            userFeedback: feedback
        )
    }
}

/// OptimizedThresholds - 優化後的睡眠檢測閾值
public struct OptimizedThresholds {
    // 心率閾值百分比（相對於靜息心率）
    var thresholdPercentage: Double = 0.9
    
    // 確認持續時間（秒）
    var confirmationDuration: TimeInterval = 180
    
    // 靜止比例閾值 - 新增
    var restingRatioThreshold: Double = 0.75
    
    // 確認時間的上下限（秒）
    static let minConfirmationTime: TimeInterval = 60  // 最短1分鐘
    static let maxConfirmationTime: TimeInterval = 360 // 最長6分鐘
    
    // 心率閾值百分比的上下限
    static let minThresholdPercentage: Double = 0.80  // 最低降至RHR的80%
    static let maxThresholdPercentage: Double = 0.95  // 最高不超過RHR的95%
    
    // 靜止比例的上下限 - 新增
    static let minRestingRatio: Double = 0.5  // 最低要求50%靜止
    static let maxRestingRatio: Double = 0.95 // 最高要求95%靜止
}

/// 用戶睡眠配置管理器
public class UserSleepProfileManager {
    private let defaults = UserDefaults.standard
    private let profileKey = "UserSleepProfile"
    private let sleepSessionsKey = "SleepSessions"
    
    public static let shared = UserSleepProfileManager()
    
    private init() {}
    
    /// 獲取用戶睡眠配置文件
    public func getUserProfile(forUserId userId: String) -> UserSleepProfile? {
        guard let data = defaults.data(forKey: "\(profileKey)_\(userId)") else {
            return nil
        }
        
        do {
            return try JSONDecoder().decode(UserSleepProfile.self, from: data)
        } catch {
            print("解碼用戶睡眠配置文件錯誤: \(error.localizedDescription)")
            return nil
        }
    }
    
    /// 保存用戶睡眠配置文件
    public func saveUserProfile(_ profile: UserSleepProfile) {
        do {
            let data = try JSONEncoder().encode(profile)
            defaults.set(data, forKey: "\(profileKey)_\(profile.userId)")
        } catch {
            print("編碼用戶睡眠配置文件錯誤: \(error.localizedDescription)")
        }
    }
    
    /// 保存睡眠會話
    public func saveSleepSession(_ session: SleepSession) {
        var sessions = getSleepSessions(forUserId: session.userId)
        
        // 更新或添加會話
        if let index = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[index] = session
        } else {
            sessions.append(session)
        }
        
        // 只保留最近30次會話
        if sessions.count > 30 {
            sessions.sort { $0.startTime > $1.startTime }
            sessions = Array(sessions.prefix(30))
        }
        
        do {
            let data = try JSONEncoder().encode(sessions)
            defaults.set(data, forKey: "\(sleepSessionsKey)_\(session.userId)")
        } catch {
            print("編碼睡眠會話錯誤: \(error.localizedDescription)")
        }
    }
    
    /// 獲取用戶睡眠會話記錄
    public func getSleepSessions(forUserId userId: String) -> [SleepSession] {
        guard let data = defaults.data(forKey: "\(sleepSessionsKey)_\(userId)") else {
            return []
        }
        
        do {
            return try JSONDecoder().decode([SleepSession].self, from: data)
        } catch {
            print("解碼睡眠會話錯誤: \(error.localizedDescription)")
            return []
        }
    }
    
    /// 分析並優化睡眠檢測參數 - 增強版
    public func analyzeAndOptimize(profile: UserSleepProfile, 
                                   restingHR: Double,
                                   recentSessions: [SleepSession]) -> OptimizedThresholds? {
        // 確保有足夠數據進行分析
        guard !recentSessions.isEmpty else { return nil }
        
        // 過濾出已完成的會話（有結束時間的）
        _ = recentSessions.filter { $0.endTime != nil }
        
        // 1. 收集睡眠心率數據
        let allHeartRates = recentSessions.flatMap { $0.heartRates }
        guard !allHeartRates.isEmpty else { return nil }
        
        // 從近期會話中提取有用的統計數據
        let sessionsWithSleepDetected = recentSessions.filter { $0.detectedSleepTime != nil }
        
        // 創建初始優化閾值
        var optimizedThresholds = OptimizedThresholds()
        
        // 2. 心率分析
        let avgHR = allHeartRates.reduce(0, +) / Double(allHeartRates.count)
        let minHR = allHeartRates.min() ?? (restingHR * 0.9)
        
        // 計算初步的適應性心率閾值百分比
        // 使用最低心率和平均心率的加權平均
        let lowHRPercentage = minHR / restingHR
        let avgHRPercentage = avgHR / restingHR
        
        // 加權計算 (更偏向最低心率)
        var adjustedThreshold = (lowHRPercentage * 0.7) + (avgHRPercentage * 0.3)
        
        // 3. 睡眠確認時間分析
        var adjustedDuration: TimeInterval = 180  // 默認3分鐘
        
        // 4. 靜止比例分析
        var adjustedRestingRatio = profile.effectiveRestingRatioThreshold
        
        // 分析睡眠檢測時間
        if !sessionsWithSleepDetected.isEmpty {
            // 計算平均睡眠檢測時間（從會話開始到睡眠檢測）
            let detectionTimes = sessionsWithSleepDetected.compactMap { session -> TimeInterval? in
                guard let detectedTime = session.detectedSleepTime else { return nil }
                let startTime = session.startTime
                return detectedTime.timeIntervalSince(startTime)
            }
            
            if !detectionTimes.isEmpty {
                let avgDetectionTime = detectionTimes.reduce(0, +) / Double(detectionTimes.count)
                
                // 找出睡眠確認持續時間的理想值
                // 通常我們需要的確認時間是檢測時間的約15-25%
                let idealConfirmationTime = max(avgDetectionTime * 0.2, 60)
                
                // 確保在合理範圍內
                adjustedDuration = min(max(idealConfirmationTime, OptimizedThresholds.minConfirmationTime), 
                                      OptimizedThresholds.maxConfirmationTime)
                
                print("自適應學習：平均檢測時間 \(avgDetectionTime)秒，調整後確認時間 \(adjustedDuration)秒")
            }
        }
        
        // 5. 睡眠狀態穩定性分析
        let stableHeartRates = recentSessions.filter { session in
            // 檢查心率在會話中的穩定性
            let rates = session.heartRates
            guard rates.count >= 5 else { return false }
            
            // 計算標準差
            let mean = rates.reduce(0, +) / Double(rates.count)
            let variance = rates.reduce(0) { sum, rate in
                let diff = rate - mean
                return sum + (diff * diff)
            } / Double(rates.count)
            let stdDev = sqrt(variance)
            
            // 標準差低表示心率穩定
            return stdDev < 5.0
        }
        
        // 如果用戶心率通常很穩定，可以更依賴心率
        if !stableHeartRates.isEmpty && stableHeartRates.count > recentSessions.count / 2 {
            // 移除心率閾值調整，只保留動作相關調整
            // 心率穩定時可以略微降低靜止比例要求
            adjustedRestingRatio -= 0.03
            print("用戶心率穩定，靜止要求適當降低")
        } else {
            // 心率不穩定用戶，增加靜止比例要求
            adjustedRestingRatio += 0.03
            print("用戶心率不穩定，增加靜止比例要求")
        }
        
        // 6. 用戶反饋數據分析
        let sessionsWithFeedback = recentSessions.filter { $0.userFeedback != SleepSession.SleepFeedback.none }
        
        // 初始化變數，放在if條件外面以擴大作用域
        var falsePositives = 0
        var falseNegatives = 0
        var totalWithFeedback = 0
        
        if !sessionsWithFeedback.isEmpty {
            falsePositives = sessionsWithFeedback.filter { $0.userFeedback == .falsePositive }.count
            falseNegatives = sessionsWithFeedback.filter { $0.userFeedback == .falseNegative }.count
            totalWithFeedback = sessionsWithFeedback.count
            
            // 根據錯誤類型調整閾值
            if falsePositives > totalWithFeedback / 3 {
                // 較多假陽性，移除心率閾值調整，只調整靜止比例
                // 同時增加靜止比例要求
                adjustedRestingRatio += 0.05
                print("較多假陽性反饋，增加靜止比例要求")
            }
            
            if falseNegatives > totalWithFeedback / 3 {
                // 較多假陰性，移除心率閾值調整，只調整靜止比例
                // 同時降低靜止比例要求
                adjustedRestingRatio -= 0.05
                print("較多假陰性反饋，降低靜止比例要求")
            }
            
            // 根據用戶反饋調整時間
            if falsePositives > totalWithFeedback / 3 {
                // 假陽性多，增加確認時間
                adjustedDuration += 45
                print("較多假陽性反饋，增加確認時間")
            }
            
            if falseNegatives > totalWithFeedback / 4 {
                // 假陰性多，減少確認時間
                adjustedDuration -= 30
                print("較多假陰性反饋，減少確認時間")
            }
        }
        
        // 確保心率閾值百分比在合理範圍內
        adjustedThreshold = min(max(adjustedThreshold, OptimizedThresholds.minThresholdPercentage), 
                               OptimizedThresholds.maxThresholdPercentage)
        
        // 確保確認時間在合理範圍內
        adjustedDuration = min(max(adjustedDuration, OptimizedThresholds.minConfirmationTime), 
                              OptimizedThresholds.maxConfirmationTime)
        
        // 確保靜止比例在合理範圍內
        adjustedRestingRatio = min(max(adjustedRestingRatio, OptimizedThresholds.minRestingRatio),
                                  OptimizedThresholds.maxRestingRatio)
        
        // 設置優化後的閾值
        optimizedThresholds.thresholdPercentage = adjustedThreshold
        optimizedThresholds.confirmationDuration = adjustedDuration
        optimizedThresholds.restingRatioThreshold = adjustedRestingRatio
        
        print("優化閾值：心率閾值百分比 \(adjustedThreshold)，確認時間 \(adjustedDuration)秒，靜止比例 \(adjustedRestingRatio)")
        
        return optimizedThresholds
    }
    
    /// 更新用戶睡眠檔案 - 增強版
    public func updateUserProfile(forUserId userId: String, restingHR: Double) {
        // 獲取或創建用戶檔案
        var profile = getUserProfile(forUserId: userId)
        
        // 如果沒有現有檔案，創建一個默認檔案
        if profile == nil {
            // 檢測用戶年齡（此處簡化）
            let userAge = 35 // 默認為35歲
            let ageGroup = AgeGroup.forAge(userAge)
            
            profile = UserSleepProfile.createDefault(forUserId: userId, ageGroup: ageGroup)
        }
        
        guard var userProfile = profile else { return }
        
        // 設置首次使用日期
        if userProfile.firstUseDate == nil {
            userProfile.firstUseDate = Date()
            saveUserProfile(userProfile)
            return // 首次運行，僅保存基本檔案
        }
        
        let now = Date()
        // 檢查是否需要更新模型的條件：
        // 1. 從未更新過模型
        // 2. 距離上次更新超過14天
        // 3. 累積了至少3次新的睡眠會話
        // 4. 用戶提供了新的反饋
        
        let needsUpdate: Bool
        if userProfile.lastModelUpdateDate == nil {
            // 從未更新過，需要至少5次睡眠記錄
            needsUpdate = userProfile.sleepSessionsCount >= 5
        } else if let lastUpdate = userProfile.lastModelUpdateDate {
            // 已有更新記錄
            let daysSinceLastUpdate = now.timeIntervalSince(lastUpdate) / (24 * 3600)
            
            // 獲取上次更新後的會話數據
            let recentSessions = getSleepSessions(forUserId: userId)
            let sessionsAfterLastUpdate = recentSessions.filter { 
                guard let sessionStart = $0.startTime as Date? else { return false }
                return sessionStart > lastUpdate
            }
            
            // 檢查是否有新的用戶反饋
            let newFeedback = sessionsAfterLastUpdate.contains { 
                $0.userFeedback != SleepSession.SleepFeedback.none && $0.userFeedback != nil
            }
            
            // 滿足以下任一條件即更新：
            // - 超過14天
            // - 有3次以上新會話且超過7天
            // - 有新的用戶反饋且超過3天
            needsUpdate = daysSinceLastUpdate >= 14 || 
                         (sessionsAfterLastUpdate.count >= 3 && daysSinceLastUpdate >= 7) ||
                         (newFeedback && daysSinceLastUpdate >= 3)
        } else {
            needsUpdate = false
        }
        
        if needsUpdate {
            // 獲取近期睡眠會話數據
            let recentSessions = getSleepSessions(forUserId: userId)
            
            // 分析數據並優化閾值
            if let optimizedThresholds = analyzeAndOptimize(
                profile: userProfile,
                restingHR: restingHR,
                recentSessions: recentSessions
            ) {
                // 更新配置文件
                userProfile.hrThresholdPercentage = optimizedThresholds.thresholdPercentage
                userProfile.minDurationSeconds = Int(optimizedThresholds.confirmationDuration)
                userProfile.lastModelUpdateDate = now
                userProfile.sleepSessionsCount = recentSessions.count
                
                // 計算統計數據
                let sleepHeartRates = recentSessions.compactMap { session -> [Double]? in
                    // 只使用檢測到睡眠後的心率
                    guard let sleepTime = session.detectedSleepTime else { return nil }
                    
                    // 假設心率按時間順序
                    let sessionStart = session.startTime
                    let totalDuration = session.endTime?.timeIntervalSince(sessionStart) ?? 0
                    let sleepTimeOffset = sleepTime.timeIntervalSince(sessionStart)
                    
                    // 計算大約的睡眠心率索引位置
                    if totalDuration > 0 && sleepTimeOffset > 0 {
                        let ratio = sleepTimeOffset / totalDuration
                        let sleepIndex = Int(Double(session.heartRates.count) * ratio)
                        
                        // 返回睡眠後的心率
                        if sleepIndex < session.heartRates.count {
                            return Array(session.heartRates[sleepIndex...])
                        }
                    }
                    
                    return nil
                }.flatMap { $0 }
                
                if !sleepHeartRates.isEmpty {
                    userProfile.averageSleepHR = sleepHeartRates.reduce(0, +) / Double(sleepHeartRates.count)
                    userProfile.minSleepHR = sleepHeartRates.min()
                    
                    // 計算標準差
                    let mean = userProfile.averageSleepHR ?? 0
                    let variance = sleepHeartRates.reduce(0.0) { sum, hr in
                        let diff = hr - mean
                        return sum + diff * diff
                    } / Double(sleepHeartRates.count)
                    userProfile.sleepHRVariance = sqrt(variance)
                    
                    // 記錄優化信息
                    print("用戶睡眠檔案已更新 - 閾值: \(userProfile.hrThresholdPercentage), 持續時間: \(userProfile.minDurationSeconds)秒, 靜止比例: \(userProfile.effectiveRestingRatioThreshold)")
                    print("睡眠統計 - 平均: \(userProfile.averageSleepHR ?? 0), 最低: \(userProfile.minSleepHR ?? 0), 變異: \(userProfile.sleepHRVariance ?? 0)")
                }
                
                // 保存更新後的檔案
                saveUserProfile(userProfile)
            }
        }
    }
} 