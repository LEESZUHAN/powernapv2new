import Foundation
import Combine
import os

/// HeartRateThresholdOptimizer - 心率閾值自動優化器
/// Watch App 版本，與 UserSleepProfileManager 直接互動
class HeartRateThresholdOptimizer {
    // MARK: - 公開屬性
    private(set) var lastOptimizationResult: OptimizationResult?
    @Published private(set) var optimizationStatus: OptimizationStatus = .idle
    var optimizationStatusPublisher: Published<OptimizationStatus>.Publisher { $optimizationStatus }

    // MARK: - 私有屬性
    private let userProfileManager = UserSleepProfileManager.shared
    private let logger = Logger(subsystem: "com.yourdomain.powernapv2new", category: "HeartRateThresholdOptimizer")
    private var isOptimizing = false

    // MARK: - 公開類型
    enum OptimizationStatus {
        case idle, optimizing
        case optimized(OptimizationResult)
        case failed(String)
    }

    struct OptimizationResult {
        let previousThreshold: Double
        let newThreshold: Double
        let confidenceLevel: Double
        let dataPointsAnalyzed: Int
        let timestamp: Date
        let adjustmentType: AdjustmentType
        enum AdjustmentType: String { case increase = "增加", decrease = "減少", noChange = "不變" }
    }

    // MARK: - API
    @discardableResult
    func checkAndOptimizeThreshold(userId: String, restingHR: Double, force: Bool = false) -> Bool {
        guard !isOptimizing else { return false }
        guard let profile = userProfileManager.getUserProfile(forUserId: userId) else { return false }
        guard shouldOptimizeThreshold(profile: profile, force: force) else { return false }
        isOptimizing = true; optimizationStatus = .optimizing
        let sessions = userProfileManager.getSleepSessions(forUserId: userId)
        guard sessions.count >= 3 else { isOptimizing = false; optimizationStatus = .failed("睡眠數據不足"); return false }
        performOptimization(userId: userId, profile: profile, restingHR: restingHR, sleepSessions: sessions)
        return true
    }

    func resetOptimizationStatus() { optimizationStatus = .idle }

    // MARK: - 私有
    private func shouldOptimizeThreshold(profile: UserSleepProfile, force: Bool) -> Bool {
        if force { return true }
        if profile.firstUseDate == nil || profile.sleepSessionsCount < 3 { return false }
        let now = Date()
        if let last = profile.lastModelUpdateDate {
            let days = now.timeIntervalSince(last) / 86_400
            let hasNew = profile.sleepSessionsCount >= 3
            return days >= 14 || (hasNew && days >= 7)
        } else if let first = profile.firstUseDate {
            return now.timeIntervalSince(first) >= 7 * 86_400 && profile.sleepSessionsCount >= 5
        }
        return false
    }

    private func performOptimization(userId: String, profile: UserSleepProfile, restingHR: Double, sleepSessions: [SleepSession]) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            if let resultTuple = self.userProfileManager.analyzeAndOptimize(profile: profile, restingHR: restingHR, recentSessions: sleepSessions) {
                let result = self.createResult(before: profile.hrThresholdPercentage, after: resultTuple.thresholdPercentage, count: sleepSessions.count)
                let ok = self.updateUserProfile(userId: userId, newThresholdPercentage: resultTuple.thresholdPercentage, newDurationSeconds: Int(resultTuple.confirmationDuration))
                DispatchQueue.main.async {
                    self.isOptimizing = false
                    self.optimizationStatus = ok ? .optimized(result) : .failed("更新用戶配置失敗")
                }
            } else {
                DispatchQueue.main.async { self.isOptimizing = false; self.optimizationStatus = .failed("無法優化閾值") }
            }
        }
    }

    private func createResult(before: Double, after: Double, count: Int) -> OptimizationResult {
        let diff = after - before
        let type: OptimizationResult.AdjustmentType = abs(diff) < 0.005 ? .noChange : (diff > 0 ? .increase : .decrease)
        let conf = min(0.5 + Double(count) * 0.05, 0.95)
        return OptimizationResult(previousThreshold: before, newThreshold: after, confidenceLevel: conf, dataPointsAnalyzed: count, timestamp: Date(), adjustmentType: type)
    }

    private func updateUserProfile(userId: String, newThresholdPercentage: Double, newDurationSeconds: Int) -> Bool {
        guard var profile = userProfileManager.getUserProfile(forUserId: userId) else { return false }
        profile.hrThresholdPercentage = newThresholdPercentage
        profile.minDurationSeconds = newDurationSeconds
        profile.lastModelUpdateDate = Date()
        userProfileManager.saveUserProfile(profile)
        return true
    }
} 