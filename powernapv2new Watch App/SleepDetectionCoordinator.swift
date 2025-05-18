import Foundation
import Combine
import os

/// 睡眠檢測協調器
/// 負責整合動作服務和心率服務，綜合判定睡眠狀態
public class SleepDetectionCoordinator {
    // MARK: - 公開屬性
    
    /// 睡眠狀態
    @Published private(set) var sleepState: SleepState = SleepState.awake
    
    /// 睡眠狀態發布者
    public var sleepStatePublisher: Published<SleepState>.Publisher { $sleepState }
    
    /// 檢測到的睡眠開始時間
    private(set) var detectedSleepTime: Date?
    
    /// 睡眠檢測是否正在運行
    private(set) var isMonitoring: Bool = false
    
    // MARK: - 私有屬性
    private let motionService: MotionServiceProtocol
    private let heartRateService: HeartRateServiceProtocol
    private var cancellables = Set<AnyCancellable>()
    private var stateTransitionTimer: Timer?
    private var currentStateDuration: TimeInterval = 0
    private let logger = Logger(subsystem: "com.yourdomain.powernapv2new", category: "SleepDetectionCoordinator")
    
    // 新增：最後數據記錄時間
    private var lastDataRecordTime: Date?
    
    // 狀態轉換條件
    private var isStationary: Bool = false
    private var isHeartRateLow: Bool = false
    private var heartRateTrend: Double = 0
    
    // 滑動窗口數據結構
    private struct WindowData {
        let timestamp: Date
        let isHeartRateBelowThreshold: Bool
        let isResting: Bool
    }
    
    // 滑動窗口和相關屬性
    private var sleepDetectionWindow: [WindowData] = []
    private let maxWindowSize = 360 // 最大窗口大小(秒)
    
    // 狀態轉換穩定性變量
    private var motionDisruptionCount: Int = 0  // 動作干擾計數
    private var heartRateIncreaseCount: Int = 0  // 心率上升計數
    
    // 靜止比例閾值常數
    private func getRestingRatioThreshold(for ageGroup: AgeGroup) -> Double {
        switch ageGroup {
        case .teen: return 0.80  // 青少年需要80%的靜止時間
        case .adult: return 0.75 // 成人需要75%的靜止時間
        case .senior: return 0.70 // 銀髮族需要70%的靜止時間
        }
    }
    
    // MARK: - 初始化
    public init(motionService: MotionServiceProtocol, heartRateService: HeartRateServiceProtocol) {
        self.motionService = motionService
        self.heartRateService = heartRateService
        
        // 設置數據監聽
        setupSubscriptions()
    }
    
    deinit {
        stateTransitionTimer?.invalidate()
        cancellables.forEach { $0.cancel() }
    }
    
    // MARK: - 公開方法
    
    /// 開始監測睡眠
    public func startMonitoring() {
        guard !isMonitoring else { return }
        
        // 重置狀態
        sleepState = SleepState.awake
        detectedSleepTime = nil
        currentStateDuration = 0
        
        // 啟動服務
        motionService.startMonitoring()
        heartRateService.startMonitoring()
        
        // 設置並啟動狀態評估計時器（每秒執行一次）
        stateTransitionTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.evaluateSleepState()
        }
        
        isMonitoring = true
        logger.info("睡眠檢測已開始監測")
    }
    
    /// 停止監測睡眠
    public func stopMonitoring() {
        guard isMonitoring else { return }
        
        // 停止服務
        motionService.stopMonitoring()
        heartRateService.stopMonitoring()
        
        // 停止計時器
        stateTransitionTimer?.invalidate()
        stateTransitionTimer = nil
        
        isMonitoring = false
        logger.info("睡眠檢測已停止監測")
    }
    
    // MARK: - 私有方法
    
    /// 設置數據訂閱
    private func setupSubscriptions() {
        // 訂閱動作靜止狀態
        motionService.isStationaryPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isStationary in
                self?.isStationary = isStationary
            }
            .store(in: &cancellables)
        
        // 訂閱心率數據
        heartRateService.isProbablySleepingPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isProbablySleeping in
                self?.isHeartRateLow = isProbablySleeping
            }
            .store(in: &cancellables)
        
        // 訂閱心率趨勢數據
        heartRateService.heartRateTrendPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] trend in
                self?.heartRateTrend = trend
            }
            .store(in: &cancellables)
    }
    
    // 新增: 更新數據窗口方法
    private func updateDataWindow(heartRateBelowThreshold: Bool, isResting: Bool) {
        let now = Date()
        
        // 添加新數據點
        let newData = WindowData(
            timestamp: now,
            isHeartRateBelowThreshold: heartRateBelowThreshold,
            isResting: isResting
        )
        sleepDetectionWindow.append(newData)
        
        // 移除超過窗口大小的數據
        let cutoffTime = now.addingTimeInterval(-Double(maxWindowSize))
        sleepDetectionWindow.removeAll { $0.timestamp < cutoffTime }
    }
    
    // 新增: 計算窗口內靜止比例的方法
    private func calculateRestingRatio(for duration: TimeInterval) -> Double {
        let now = Date()
        let cutoffTime = now.addingTimeInterval(-duration)
        
        // 獲取時間窗口內的數據
        let windowData = sleepDetectionWindow.filter { $0.timestamp >= cutoffTime }
        
        if windowData.isEmpty {
            return 0.0
        }
        
        // 計算靜止記錄占比
        let restingCount = windowData.filter { $0.isResting }.count
        return Double(restingCount) / Double(windowData.count)
    }
    
    // 新增: 計算心率低於閾值的比例
    private func calculateHeartRateBelowThresholdRatio(for duration: TimeInterval) -> Double {
        let now = Date()
        let cutoffTime = now.addingTimeInterval(-duration)
        
        let windowData = sleepDetectionWindow.filter { $0.timestamp >= cutoffTime }
        
        if windowData.isEmpty {
            return 0.0
        }
        
        let belowThresholdCount = windowData.filter { $0.isHeartRateBelowThreshold }.count
        return Double(belowThresholdCount) / Double(windowData.count)
    }
    
    // 新增: 獲取窗口持續時間
    private func getWindowDuration() -> TimeInterval {
        guard let oldestData = sleepDetectionWindow.min(by: { $0.timestamp < $1.timestamp }),
              let newestData = sleepDetectionWindow.max(by: { $0.timestamp < $1.timestamp }) else {
            return 0
        }
        
        return newestData.timestamp.timeIntervalSince(oldestData.timestamp)
    }
    
    // 新增: 獲取進入深度睡眠所需的持續時間（秒），同時考慮靜止比例
    private func getCurrentRequiredDuration() -> TimeInterval {
        // 從UserSleepProfileManager獲取用戶檔案，使用其優化後的參數
        guard let userProfileManager = getUserProfileManager(),
              let userId = getUserId(),
              let profile = userProfileManager.getUserProfile(forUserId: userId) else {
            // 無法獲取用戶檔案時使用預設值
            return getDefaultDurationForAgeGroup(getUserAgeGroup())
        }
        
        // 使用用戶檔案中已優化的持續時間
        // 確保持續時間在合理範圍內
        let duration = TimeInterval(profile.minDurationSeconds)
        return min(max(duration, 60), 360) // 限制在1-6分鐘範圍內
    }
    
    /// 評估並更新睡眠狀態
    private func evaluateSleepState() {
        // 確保監測中
        guard isMonitoring else { return }
        
        // 獲取當前條件
        let isCurrentlyStationary = isStationary
        let isCurrentHeartRateLow = isHeartRateLow
        let currentHeartRateTrend = heartRateTrend
        
        // 更新數據窗口 - 加入當前狀態數據
        updateDataWindow(heartRateBelowThreshold: isCurrentHeartRateLow, isResting: isCurrentlyStationary)
        
        // 記錄周期性數據，無論是否檢測到睡眠
        recordPeriodicSleepData()
        
        // 使用傳統方法評估基本睡眠狀態轉換
        evaluateBasicSleepStateTransitions(
            isCurrentlyStationary: isCurrentlyStationary,
            isCurrentHeartRateLow: isCurrentHeartRateLow,
            currentHeartRateTrend: currentHeartRateTrend
        )
        
        // 使用增強的滑動窗口方法評估深度睡眠確認
        evaluateDeepSleepWithRatioCheck()
    }
    
    /// 記錄周期性睡眠數據，無論是否檢測到睡眠
    private func recordPeriodicSleepData() {
        // 每30秒記錄一次數據
        let now = Date()
        guard lastDataRecordTime == nil || now.timeIntervalSince(lastDataRecordTime!) >= 30.0 else {
            return
        }
        
        // 更新最後記錄時間
        lastDataRecordTime = now
        
        // 記錄當前窗口統計數據 - 心率低於閾值比例
        let hrBelowThresholdRatio = calculateHeartRateBelowThresholdRatio(for: 60) // 過去60秒
        
        // 記錄靜止比例
        let restingRatio = calculateRestingRatio(for: 60) // 過去60秒
        
        // 日誌記錄
        logger.info("周期性數據記錄 - 心率低於閾值比例: \(String(format: "%.2f", hrBelowThresholdRatio)), 靜止比例: \(String(format: "%.2f", restingRatio)), 當前狀態: \(self.sleepState.description)")
    }
    
    /// 使用傳統方法評估基本睡眠狀態轉換
    private func evaluateBasicSleepStateTransitions(
        isCurrentlyStationary: Bool,
        isCurrentHeartRateLow: Bool,
        currentHeartRateTrend: Double
    ) {
        // 根據當前狀態應用不同的轉換邏輯
        switch sleepState {
        case .awake:
            // 清醒→靜止休息：檢測到靜止
            if isCurrentlyStationary {
                currentStateDuration += 1
                
                // 根據年齡組調整必要靜止時間
                let requiredStationaryTime: TimeInterval
                switch getUserAgeGroup() {
                case .teen:
                    requiredStationaryTime = 25  // 青少年動作頻繁，稍微縮短時間
                case .adult:
                    requiredStationaryTime = 30  // 標準時間
                case .senior:
                    requiredStationaryTime = 40  // 老年人可能本身活動較少，需要更長時間確認
                }
                
                // 需要連續靜止指定秒數
                if currentStateDuration >= requiredStationaryTime {
                    transitionToState(SleepState.resting)
                }
            } else {
                // 重置計時，但使用漸進式重置而非完全重置
                // 這樣可以處理偶爾的輕微動作幹擾
                if currentStateDuration > 5 {
                    currentStateDuration -= 5  // 減少而非重置為0
                } else {
                    currentStateDuration = 0
                }
            }
            
        case .resting:
            // 靜止休息→清醒：檢測到明顯動作或長時間無睡眠跡象
            if !isCurrentlyStationary {
                // 如果有明顯動作，先累計動作計數
                motionDisruptionCount += 1
                
                // 只有連續3次動作幹擾才回到清醒狀態，提高穩定性
                if motionDisruptionCount >= 3 {
                    transitionToState(SleepState.awake)
                    motionDisruptionCount = 0
                    return
                }
            } else {
                // 靜止時重置動作幹擾計數
                motionDisruptionCount = 0
            }
            
            // 靜止休息→輕度睡眠：心率下降且持續靜止
            if isCurrentHeartRateLow {
                currentStateDuration += 1
                
                // 根據年齡組判斷所需的持續時間
                let requiredLowHeartRateTime: TimeInterval
                switch getUserAgeGroup() {
                case .teen:
                    requiredLowHeartRateTime = 45  // 青少年
                case .adult:
                    requiredLowHeartRateTime = 60  // 成人
                case .senior:
                    requiredLowHeartRateTime = 75  // 老年人
                }
                
                // 需要連續指定秒數心率低+靜止
                if currentStateDuration >= requiredLowHeartRateTime {
                    transitionToState(SleepState.lightSleep)
                }
            } else if isCurrentlyStationary {
                // 持續靜止但心率未達標準，緩慢增加計時
                // 這樣即使心率波動，持續靜止也能漸進地增加可能性
                currentStateDuration += 0.5
            } else {
                // 既有動作又沒有心率下降，減少計時
                if currentStateDuration > 5 {
                    currentStateDuration -= 5
                } else {
                    currentStateDuration = 0
                }
            }
            
            // 避免靜止休息狀態持續過長（超過10分鐘）但未進入睡眠
            if currentStateDuration > 600 {
                // 回到清醒狀態，可能用戶只是放鬆而非睡眠
                logger.info("靜止休息持續過長（10分鐘）但未轉入睡眠，重置狀態")
                transitionToState(SleepState.awake)
            }
            
        case .lightSleep, .deepSleep:
            // 使用滑動窗口方法評估，簡化此處邏輯
            break
        }
    }
    
    /// 使用增強的滑動窗口方法評估深度睡眠確認
    private func evaluateDeepSleepWithRatioCheck() {
        // 只在輕度睡眠狀態評估進階確認
        if sleepState != .lightSleep {
            return
        }
        
        // 獲取當前配置
        let requiredDuration = getCurrentRequiredDuration() // 基於年齡組或用戶設定的確認時間
        let currentAgeGroup = getUserAgeGroup()
        let restingRatioThreshold = getRestingRatioThreshold(for: currentAgeGroup)
        
        // 檢查窗口是否足夠長
        let windowDuration = getWindowDuration()
        guard windowDuration >= requiredDuration else {
            // 數據收集不足，繼續等待
            return
        }
        
        // 計算指標
        let hrBelowThresholdRatio = calculateHeartRateBelowThresholdRatio(for: requiredDuration)
        let restingRatio = calculateRestingRatio(for: requiredDuration)
        
        // 綜合判斷 - 需要90%的心率低於閾值且達到年齡組要求的靜止比例
        let hrConditionMet = hrBelowThresholdRatio >= 0.9 // 90%的時間心率低於閾值
        let restingConditionMet = restingRatio >= restingRatioThreshold
        
        // 記錄判斷結果
        logger.info("睡眠評估: 心率條件\(hrConditionMet ? "滿足" : "不滿足")(\(hrBelowThresholdRatio*100)%), 靜止條件\(restingConditionMet ? "滿足" : "不滿足")(\(restingRatio*100)%)")
        
        // 只有同時滿足心率和靜止比例條件才轉換到深度睡眠
        if hrConditionMet && restingConditionMet {
            transitionToState(SleepState.deepSleep)
            
            // 記錄睡眠檢測時間
            if detectedSleepTime == nil {
                detectedSleepTime = Date()
                logger.info("檢測到睡眠，時間：\(self.detectedSleepTime!)")
            }
        }
    }
    
    /// 轉換到新狀態
    private func transitionToState(_ newState: SleepState) {
        // 只有狀態變化時才記錄
        if sleepState != newState {
            logger.info("睡眠狀態從 \(self.sleepState.description) 轉換為 \(newState.description)")
            
            // 更新狀態
            sleepState = newState
            
            // 重置狀態持續時間計數
            currentStateDuration = 0
        }
    }
    
    /// 獲取進入深度睡眠所需的持續時間（秒）
    private func getRequiredDurationForDeepSleep() -> TimeInterval {
        // 從UserSleepProfileManager獲取用戶檔案，使用其優化後的參數
        guard let userProfileManager = getUserProfileManager(),
              let userId = getUserId(),
              let profile = userProfileManager.getUserProfile(forUserId: userId) else {
            // 無法獲取用戶檔案時使用預設值
            return getDefaultDurationForAgeGroup(getUserAgeGroup())
        }
        
        // 使用用戶檔案中已優化的持續時間
        // 確保持續時間在合理範圍內
        let duration = TimeInterval(profile.minDurationSeconds)
        return min(max(duration, 60), 360) // 限制在1-6分鐘範圍內
    }
    
    /// 獲取默認的持續時間（基於年齡組）
    private func getDefaultDurationForAgeGroup(_ ageGroup: AgeGroup) -> TimeInterval {
        switch ageGroup {
        case .teen:
            return 120 // 青少年：2分鐘
        case .adult:
            return 180 // 成人：3分鐘
        case .senior:
            return 240 // 銀髮族：4分鐘
        }
    }
    
    /// 獲取用戶年齡組
    private func getUserAgeGroup() -> AgeGroup {
        // 嘗試從UserSleepProfileManager獲取
        if let userProfileManager = getUserProfileManager(),
           let userId = getUserId(),
           let profile = userProfileManager.getUserProfile(forUserId: userId) {
            return profile.ageGroup
        }
        
        // 默認返回成人
        return AgeGroup.adult
    }
    
    /// 獲取用戶ID
    private func getUserId() -> String? {
        // 使用UserDefaults存儲和檢索用戶ID
        let defaults = UserDefaults.standard
        let userIdKey = "com.yourdomain.powernapv2new.userId"
        
        // 檢查是否已有用戶ID
        if let savedId = defaults.string(forKey: userIdKey) {
            return savedId
        }
        
        // 創建新的用戶ID
        let newId = UUID().uuidString
        defaults.set(newId, forKey: userIdKey)
        return newId
    }
    
    /// 獲取UserSleepProfileManager實例
    private func getUserProfileManager() -> UserSleepProfileManager? {
        return UserSleepProfileManager.shared
    }
    
    /// 根據心率數據和動作數據更新睡眠狀態
    private func updateSleepState() {
        // 檢查心率是否在睡眠範圍內
        let isHeartRateInSleepRange = heartRateService.isProbablySleeping
        
        // 檢查動作是否在靜止範圍內
        let isMotionInRestRange = motionService.isStationary
        
        // 根據當前狀態和條件更新
        switch sleepState {
        case .awake:
            if isMotionInRestRange {
                // 從清醒到靜息
                transitionToState(SleepState.resting)
            }
            
        case .resting:
            if !isMotionInRestRange {
                // 回到清醒
                transitionToState(SleepState.awake)
            } else if isHeartRateInSleepRange && isMotionInRestRange {
                // 從靜息進入淺度睡眠
                transitionToState(SleepState.lightSleep)
            }
            
        case .lightSleep:
            if !isMotionInRestRange || !isHeartRateInSleepRange {
                // 返回靜息或清醒
                transitionToState(isMotionInRestRange ? SleepState.resting : SleepState.awake)
            } else {
                // 在淺度睡眠中，檢查是否持續足夠長的時間進入深度睡眠
                let requiredDuration = getCurrentRequiredDuration()
                
                if currentStateDuration >= requiredDuration {
                    transitionToState(SleepState.deepSleep)
                    // 記錄睡眠檢測時間
                    if detectedSleepTime == nil {
                        detectedSleepTime = Date()
                        logger.info("檢測到睡眠，時間：\(self.detectedSleepTime!)")
                    }
                }
            }
            
        case .deepSleep:
            // 深度睡眠狀態維護
            if !isHeartRateInSleepRange && !isMotionInRestRange {
                // 如果心率和動作都超出範圍，回到清醒
                transitionToState(SleepState.awake)
                // 重置睡眠檢測時間
                detectedSleepTime = nil
            } else if !isHeartRateInSleepRange || !isMotionInRestRange {
                // 如果只有一個條件不滿足，回到淺度睡眠
                transitionToState(SleepState.lightSleep)
            }
        }
    }
} 