import Foundation
import os
import Combine

/// HeartRateThresholdOptimizer - 心率閾值自動優化器
/// 負責分析用戶睡眠數據並自動調整心率閾值，以提高睡眠檢測的準確性
class HeartRateThresholdOptimizer {
    // MARK: - 公開屬性
    /// 最後一次優化的結果
    private(set) var lastOptimizationResult: OptimizationResult?
    
    /// 優化結果發布者
    @Published private(set) var optimizationStatus: OptimizationStatus = .idle
    var optimizationStatusPublisher: Published<OptimizationStatus>.Publisher { $optimizationStatus }
    
    // MARK: - 私有屬性
    private let userProfileManager = UserSleepProfileManager.shared
    private let logger = Logger(subsystem: "com.yourdomain.powernapv2new", category: "HeartRateThresholdOptimizer")
    private var isOptimizing = false
    
    // MARK: - 公開類型
    /// 優化狀態
    enum OptimizationStatus {
        case idle                      // 閒置中，未優化
        case optimizing                // 正在優化
        case optimized(OptimizationResult) // 已優化，包含結果
        case failed(String)            // 優化失敗，包含錯誤信息
    }
    
    /// 優化結果
    struct OptimizationResult {
        let previousThreshold: Double  // 優化前的閾值百分比
        let newThreshold: Double       // 優化後的閾值百分比
        let confidenceLevel: Double    // 置信度 (0.0-1.0)
        let dataPointsAnalyzed: Int    // 分析的數據點數量
        let timestamp: Date            // 優化時間
        let adjustmentType: AdjustmentType // 調整類型
        
        enum AdjustmentType: String {
            case increase = "增加"     // 增加閾值（變寬鬆）
            case decrease = "減少"     // 減少閾值（變嚴格）
            case noChange = "不變"     // 維持不變
        }
    }
    
    // MARK: - 初始化
    init() {
        // 初始化代碼如果需要
    }
    
    // MARK: - 公開方法
    
    /// 檢查並優化用戶的心率閾值
    /// - Parameters:
    ///   - userId: 用戶ID
    ///   - restingHR: 靜息心率
    ///   - force: 是否強制優化，忽略時間間隔等限制
    /// - Returns: 是否會執行優化（異步過程，結果通過optimizationStatusPublisher獲取）
    @discardableResult
    func checkAndOptimizeThreshold(userId: String, restingHR: Double, force: Bool = false) -> Bool {
        guard !isOptimizing else {
            logger.info("已經在優化中，忽略新的優化請求")
            return false
        }
        
        // 獲取用戶配置
        guard let profile = userProfileManager.getUserProfile(forUserId: userId) else {
            logger.warning("找不到用戶配置，無法優化閾值")
            optimizationStatus = .failed("找不到用戶配置")
            return false
        }
        
        // 檢查是否需要優化
        let needsOptimization = shouldOptimizeThreshold(profile: profile, force: force)
        if !needsOptimization {
            logger.info("當前不需要優化閾值")
            return false
        }
        
        // 開始優化過程
        isOptimizing = true
        optimizationStatus = .optimizing
        
        // 獲取用戶的睡眠會話數據
        let sleepSessions = userProfileManager.getSleepSessions(forUserId: userId)
        
        // 確保有足夠的數據
        guard sleepSessions.count >= 3 else {
            logger.info("睡眠數據不足，需要至少3次睡眠記錄才能優化")
            isOptimizing = false
            optimizationStatus = .failed("睡眠數據不足")
            return false
        }
        
        // 執行優化
        performOptimization(userId: userId, profile: profile, restingHR: restingHR, sleepSessions: sleepSessions)
        return true
    }
    
    /// 重置優化狀態
    func resetOptimizationStatus() {
        optimizationStatus = .idle
    }
    
    // MARK: - 私有方法
    
    /// 判斷是否應該執行閾值優化
    private func shouldOptimizeThreshold(profile: UserSleepProfile, force: Bool) -> Bool {
        // 強制優化
        if force {
            return true
        }
        
        // 第一次使用不優化
        if profile.firstUseDate == nil || profile.sleepSessionsCount < 3 {
            return false
        }
        
        let now = Date()
        
        // 未曾更新過的情況
        if profile.lastModelUpdateDate == nil {
            // 如果使用超過7天且有足夠數據，進行首次優化
            if let firstUse = profile.firstUseDate, 
               now.timeIntervalSince(firstUse) >= 7 * 24 * 3600 && // 7天
               profile.sleepSessionsCount >= 5 { // 至少5次睡眠
                return true
            }
            return false
        }
        
        // 已有更新記錄的情況
        if let lastUpdate = profile.lastModelUpdateDate {
            // 計算距離上次更新的天數
            let daysSinceLastUpdate = now.timeIntervalSince(lastUpdate) / (24 * 3600)
            
            // 優化間隔策略：
            // 1. 超過14天強制更新
            // 2. 有新數據且超過7天
            let hasNewDataSinceLastUpdate = profile.sleepSessionsCount >= 3
            
            return daysSinceLastUpdate >= 14 || (hasNewDataSinceLastUpdate && daysSinceLastUpdate >= 7)
        }
        
        return false
    }
    
    /// 執行閾值優化
    private func performOptimization(userId: String, profile: UserSleepProfile, restingHR: Double, sleepSessions: [SleepSession]) {
        // 記錄開始優化
        logger.info("開始閾值優化 - 用戶ID: \(userId), 當前閾值: \(profile.hrThresholdPercentage)")
        
        // 在後台線程執行優化計算
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            // 調用優化算法
            if let optimizedThresholds = self.userProfileManager.analyzeAndOptimize(
                profile: profile,
                restingHR: restingHR,
                recentSessions: sleepSessions
            ) {
                // 建立優化結果
                let result = self.createOptimizationResult(
                    previousThreshold: profile.hrThresholdPercentage,
                    newThreshold: optimizedThresholds.thresholdPercentage,
                    dataPoints: sleepSessions.count
                )
                
                // 更新用戶配置
                let updated = self.updateUserProfile(
                    userId: userId,
                    newThresholdPercentage: optimizedThresholds.thresholdPercentage,
                    newDurationSeconds: Int(optimizedThresholds.confirmationDuration)
                )
                
                // 回到主線程更新狀態
                DispatchQueue.main.async {
                    self.isOptimizing = false
                    
                    if updated {
                        self.lastOptimizationResult = result
                        self.optimizationStatus = .optimized(result)
                        self.logger.info("閾值優化成功 - 新閾值: \(optimizedThresholds.thresholdPercentage), 調整類型: \(result.adjustmentType.rawValue)")
                    } else {
                        self.optimizationStatus = .failed("更新用戶配置失敗")
                        self.logger.error("更新用戶配置失敗")
                    }
                }
            } else {
                // 優化失敗
                DispatchQueue.main.async {
                    self.isOptimizing = false
                    self.optimizationStatus = .failed("無法優化閾值")
                    self.logger.error("無法優化閾值，可能是數據不足或算法問題")
                }
            }
        }
    }
    
    /// 建立優化結果
    private func createOptimizationResult(previousThreshold: Double, newThreshold: Double, dataPoints: Int) -> OptimizationResult {
        // 計算調整類型
        let adjustmentType: OptimizationResult.AdjustmentType
        let diff = newThreshold - previousThreshold
        
        if abs(diff) < 0.005 { // 閾值變化小於0.5%視為不變
            adjustmentType = .noChange
        } else if diff > 0 {
            adjustmentType = .increase  // 增加閾值，判定更寬鬆
        } else {
            adjustmentType = .decrease  // 減少閾值，判定更嚴格
        }
        
        // 計算置信度 - 簡單模型
        // 數據點越多，置信度越高，但有上限
        let confidence = min(0.5 + Double(dataPoints) * 0.05, 0.95)
        
        return OptimizationResult(
            previousThreshold: previousThreshold,
            newThreshold: newThreshold,
            confidenceLevel: confidence,
            dataPointsAnalyzed: dataPoints,
            timestamp: Date(),
            adjustmentType: adjustmentType
        )
    }
    
    /// 更新用戶配置
    private func updateUserProfile(userId: String, newThresholdPercentage: Double, newDurationSeconds: Int) -> Bool {
        // 獲取當前配置
        guard var profile = userProfileManager.getUserProfile(forUserId: userId) else {
            return false
        }
        
        // 更新參數
        profile.hrThresholdPercentage = newThresholdPercentage
        profile.minDurationSeconds = newDurationSeconds
        profile.lastModelUpdateDate = Date()
        
        // 保存更新後的配置
        userProfileManager.saveUserProfile(profile)
        return true
    }
} 