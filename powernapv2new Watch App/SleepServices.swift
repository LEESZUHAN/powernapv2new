import Foundation
import Combine
import os

/// SleepServices - 睡眠服務管理器
/// 作為應用中各睡眠相關服務的中央協調點
class SleepServices {
    // MARK: - 服務單例
    static let shared = SleepServices()
    
    // MARK: - 服務組件
    private let motionService = MotionService()
    private let heartRateService = HeartRateService()
    private var cancellables = Set<AnyCancellable>()
    private let logger = Logger(subsystem: "com.yourdomain.powernapv2new", category: "SleepServices")
    
    /// 睡眠檢測協調器 - 負責整合心率和動作數據進行睡眠狀態判定
    private(set) lazy var sleepDetectionCoordinator: SleepDetectionCoordinator = {
        let coordinator = SleepDetectionCoordinator(
            motionService: motionService,
            heartRateService: heartRateService
        )
        return coordinator
    }()
    
    /// 心率閾值優化器 - 負責自動分析睡眠數據並優化心率閾值
    private(set) lazy var heartRateThresholdOptimizer = HeartRateThresholdOptimizer()
    
    // 使用者睡眠檔案管理器
    var userProfileManager: UserSleepProfileManager {
        return UserSleepProfileManager.shared
    }
    
    // 發布者
    @Published private(set) var isMonitoring: Bool = false
    var isMonitoringPublisher: Published<Bool>.Publisher { $isMonitoring }
    
    // 優化狀態發布者
    var optimizationStatusPublisher: Published<HeartRateThresholdOptimizer.OptimizationStatus>.Publisher {
        return heartRateThresholdOptimizer.optimizationStatusPublisher
    }
    
    // MARK: - 初始化
    private init() {
        setupObservers()
    }
    
    // MARK: - 私有方法
    private func setupObservers() {
        // 訂閱睡眠狀態變化
        sleepDetectionCoordinator.sleepStatePublisher
            .sink { [weak self] state in
                guard let self = self else { return }
                
                // 記錄狀態變化
                self.logger.info("睡眠狀態變化: \(state.description)")
                
                // 更新當前會話的睡眠狀態
                if self.isMonitoring {
                    self.updateCurrentSessionState(state)
                }
                
                // 當檢測到深度睡眠時，記錄睡眠開始時間
                if state == .deepSleep {
                    if let detectedTime = self.sleepDetectionCoordinator.detectedSleepTime {
                        self.recordSleepDetectionTime(detectedTime)
                        self.logger.info("記錄睡眠檢測時間: \(detectedTime)")
                    }
                }
            }
            .store(in: &cancellables)
        
        // 訂閱心率數據
        heartRateService.heartRatePublisher
            .sink { [weak self] heartRate in
                guard let self = self, self.isMonitoring else { return }
                
                // 將心率數據添加到當前睡眠會話
                self.addHeartRateSample(
                    heartRate,
                    isResting: self.motionService.isStationary,
                    timestamp: Date()
                )
            }
            .store(in: &cancellables)
            
        // 訂閱閾值優化器狀態
        heartRateThresholdOptimizer.optimizationStatusPublisher
            .sink { [weak self] status in
                guard let self = self else { return }
                
                switch status {
                case .optimized(let result):
                    // 優化成功，更新心率服務的閾值
                    self.logger.info("閾值優化完成: 從 \(result.previousThreshold) 到 \(result.newThreshold) (\(result.adjustmentType.rawValue))")
                    
                    // 獲取用戶ID和靜息心率
                    if let userId = self.getUserId() {
                        if let profile = userProfileManager.getUserProfile(forUserId: userId) {
                            // 重新計算並設置心率閾值
                            let newThreshold = self.heartRateService.restingHeartRate * profile.adjustedThresholdPercentage
                            self.heartRateService.setCustomHeartRateThreshold(newThreshold)
                            
                            self.logger.info("已更新心率閾值: \(newThreshold) BPM (RHR \(self.heartRateService.restingHeartRate) × \(profile.adjustedThresholdPercentage))")
                        }
                    }
                    
                case .failed(let error):
                    self.logger.error("閾值優化失敗: \(error)")
                    
                default:
                    break
                }
            }
            .store(in: &cancellables)
    }
    
    // MARK: - 公開方法
    
    /// 開始監測睡眠
    func startMonitoring() {
        guard !isMonitoring else { return }
        
        // 啟動睡眠檢測協調器
        sleepDetectionCoordinator.startMonitoring()
        
        isMonitoring = true
    }
    
    /// 停止監測睡眠
    func stopMonitoring() {
        guard isMonitoring else { return }
        
        // 停止睡眠檢測協調器
        sleepDetectionCoordinator.stopMonitoring()
        
        isMonitoring = false
        
        // 睡眠會話結束時，嘗試優化閾值
        checkAndOptimizeThreshold()
    }
    
    /// 檢查並優化心率閾值
    /// - Parameter force: 是否強制優化
    /// - Returns: 是否會執行優化（異步結果）
    @discardableResult
    func checkAndOptimizeThreshold(force: Bool = false) -> Bool {
        guard let userId = getUserId() else {
            logger.warning("無法獲取用戶ID，無法優化閾值")
            return false
        }
        
        let restingHR = heartRateService.restingHeartRate
        
        logger.info("嘗試優化心率閾值 - 用戶ID: \(userId), 靜息心率: \(restingHR)")
        return heartRateThresholdOptimizer.checkAndOptimizeThreshold(userId: userId, restingHR: restingHR, force: force)
    }
    
    /// 更新當前睡眠會話的狀態
    func updateCurrentSessionState(_ state: SleepState) {
        // 此方法會在將來用於記錄睡眠狀態變化
        logger.info("更新睡眠狀態: \(state.description)")
    }
    
    /// 記錄檢測到睡眠的時間
    func recordSleepDetectionTime(_ time: Date) {
        // 此方法會在將來用於記錄睡眠開始時間
        logger.info("記錄睡眠開始時間: \(time)")
    }
    
    /// 添加心率樣本到當前會話
    func addHeartRateSample(_ heartRate: Double, isResting: Bool, timestamp: Date) {
        // 此方法會將心率樣本添加到當前會話
        logger.info("添加心率樣本: \(heartRate), 靜息狀態: \(isResting)")
    }
    
    /// 獲取當前睡眠狀態
    var currentSleepState: SleepState {
        return sleepDetectionCoordinator.sleepState
    }
    
    /// 睡眠狀態發布者
    var sleepStatePublisher: Published<SleepState>.Publisher {
        return sleepDetectionCoordinator.sleepStatePublisher
    }
    
    /// 檢測到的睡眠開始時間
    var detectedSleepTime: Date? {
        return sleepDetectionCoordinator.detectedSleepTime
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
}
