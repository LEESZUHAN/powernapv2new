import Foundation
import HealthKit
import CoreMotion
import os
import UserNotifications
#if os(watchOS)
import WatchKit
#endif

// MARK: - WorkoutSessionManager
class WorkoutSessionManager: NSObject, HKWorkoutSessionDelegate {
    
    private let logger = Logger(subsystem: "com.yourdomain.powernapv2new", category: "WorkoutSessionManager")
    private let healthStore = HKHealthStore()
    
    private var workoutSession: HKWorkoutSession?
    private var workoutBuilder: HKLiveWorkoutBuilder?
    
    // 優化參數
    private let optimizedUpdateFrequency: HKUpdateFrequency = .immediate // 可調整為.immediate, .normal, 或 .reduced 以節省電力
    
    static let shared = WorkoutSessionManager()
    
    private override init() {
        super.init()
    }
    
    func startWorkoutSession() {
        guard HKHealthStore.isHealthDataAvailable() else {
            logger.error("HealthKit 不可用")
            return
        }
        
        // 確保先停止任何當前的session
        stopWorkoutSession()
        
        // 設定workout configuration
        let workoutConfiguration = HKWorkoutConfiguration()
        workoutConfiguration.activityType = .mindAndBody // 最省電的活動類型
        workoutConfiguration.locationType = .indoor
        
        do {
            // 創建workoutSession
            #if os(watchOS)
            workoutSession = try HKWorkoutSession(healthStore: healthStore, configuration: workoutConfiguration)
            workoutBuilder = workoutSession?.associatedWorkoutBuilder()
            
            workoutSession?.delegate = self
            workoutBuilder?.delegate = self
            
            // 設置優化的更新頻率
            workoutBuilder?.dataSource = HKLiveWorkoutDataSource(
                healthStore: healthStore,
                workoutConfiguration: workoutConfiguration
            )
            
            // 啟動session
            workoutSession?.startActivity(with: Date())
            workoutBuilder?.beginCollection(withStart: Date()) { success, error in
                if let error = error {
                    self.logger.error("無法開始數據收集: \(error.localizedDescription)")
                    return
                }
                
                if success {
                    self.logger.info("開始數據收集")
                }
            }
            #endif
            
            logger.info("成功啟動HKWorkoutSession")
        } catch {
            logger.error("啟動HKWorkoutSession失敗: \(error.localizedDescription)")
        }
    }
    
    func stopWorkoutSession() {
        #if os(watchOS)
        guard let workoutSession = workoutSession, 
              workoutSession.state != .ended else {
            return
        }
        
        workoutSession.end()
        
        workoutBuilder?.endCollection(withEnd: Date()) { success, error in
            if let error = error {
                self.logger.error("無法結束數據收集: \(error.localizedDescription)")
                return
            }
            
            if success {
                self.logger.info("成功結束數據收集")
                
                // 棄用workout數據，因為這只是一個休息會話
                self.workoutBuilder?.discardWorkout()
            }
        }
        #endif
        
        logger.info("停止HKWorkoutSession")
    }
    
    // MARK: - HKWorkoutSessionDelegate
    
    func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState, from fromState: HKWorkoutSessionState, date: Date) {
        logger.info("HKWorkoutSession狀態變更: 從 \(fromState.rawValue) 到 \(toState.rawValue)")
        
        if toState == .running {
            logger.info("HKWorkoutSession正在運行")
        } else if toState == .ended {
            logger.info("HKWorkoutSession已結束")
        }
    }
    
    func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        logger.error("HKWorkoutSession失敗: \(error.localizedDescription)")
    }
}

// MARK: - HKLiveWorkoutBuilderDelegate
extension WorkoutSessionManager: HKLiveWorkoutBuilderDelegate {
    func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        // 可以在這裡處理收集到的數據，但為了節省資源，我們可以保持最小處理
        if let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate),
           collectedTypes.contains(heartRateType) {
            // 只關心心率數據
            let statistics = workoutBuilder.statistics(for: heartRateType)
            if let heartRate = statistics?.mostRecentQuantity()?.doubleValue(for: HKUnit(from: "count/min")) {
                logger.info("最新心率數據: \(heartRate) BPM")
            }
        }
    }
    
    func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {
        // 通常不需要處理，可以留空以節省資源
    }
}

// MARK: - ExtendedRuntimeManager
class ExtendedRuntimeManager: NSObject {
    
    private let logger = Logger(subsystem: "com.yourdomain.powernapv2new", category: "ExtendedRuntimeManager")
    #if os(watchOS)
    private var session: WKExtendedRuntimeSession?
    #endif
    
    static let shared = ExtendedRuntimeManager()
    
    private override init() {
        super.init()
    }
    
    func startSession() {
        // 每次創建新的session實例
        stopSession()
        
        #if os(watchOS)
        session = WKExtendedRuntimeSession()
        session?.delegate = self
        session?.start()
        #endif
        
        logger.info("嘗試啟動Extended Runtime Session")
    }
    
    func stopSession() {
        #if os(watchOS)
        if let session = session, session.state != .invalid {
            session.invalidate()
            logger.info("停止Extended Runtime Session")
        }
        session = nil
        #endif
    }
}

#if os(watchOS)
// MARK: - WKExtendedRuntimeSessionDelegate
extension ExtendedRuntimeManager: WKExtendedRuntimeSessionDelegate {
    func extendedRuntimeSession(_ extendedRuntimeSession: WKExtendedRuntimeSession, didInvalidateWith reason: WKExtendedRuntimeSessionInvalidationReason, error: Error?) {
        // 直接使用原始值來記錄原因，避免直接使用API特定的枚舉名稱
        let reasonString = "原因代碼: \(reason.rawValue)"
        logger.error("Extended Runtime Session 失效: \(reasonString), 錯誤: \(String(describing: error))")
    }
    
    func extendedRuntimeSessionDidStart(_ extendedRuntimeSession: WKExtendedRuntimeSession) {
        logger.info("Extended Runtime Session 已啟動")
    }
    
    func extendedRuntimeSessionWillExpire(_ extendedRuntimeSession: WKExtendedRuntimeSession) {
        logger.info("Extended Runtime Session 即將過期")
    }
}
#endif

// MARK: - SleepDetectionService
class SleepDetectionService {
    
    private let logger = Logger(subsystem: "com.yourdomain.powernapv2new", category: "SleepDetectionService")
    private let healthStore = HKHealthStore()
    
    // 運動緩衝時間（秒）
    private let motionBufferTimeInterval: TimeInterval = 5.0
    private var lastSignificantMotionDate: Date?
    
    // 心率閾值設定
    private let minRestingHeartRate: Double = 40.0 // 最低安全閾值
    private var userRHR: Double = 60.0 // 默認靜息心率
    private var userAge: Int = 30 // 默認年齡
    
    // 根據用戶年齡和靜息心率計算的閾值
    private var sleepingHeartRateThreshold: Double {
        // 基於年齡的閾值百分比
        let thresholdPercentage: Double
        if userAge < 18 {
            thresholdPercentage = 0.875 // 87.5% for teens
        } else if userAge < 60 {
            thresholdPercentage = 0.9 // 90% for adults
        } else {
            thresholdPercentage = 0.935 // 93.5% for seniors
        }
        
        // 應用閾值，確保不低於最低安全閾值
        return max(userRHR * thresholdPercentage, minRestingHeartRate)
    }
    
    // 當前狀態
    private(set) var isResting = false
    private(set) var isProbablySleeping = false
    
    static let shared = SleepDetectionService()
    
    private init() {}
    
    // 開始監測
    func startMonitoring() {
        // 確保有必要的許可權
        requestAuthorization { success in
            guard success else {
                self.logger.error("無法獲取HealthKit許可權")
                return
            }
            
            // 獲取用戶靜息心率和年齡
            self.fetchUserRestingHeartRate()
            self.fetchUserDateOfBirth()
            
            // 開始監測心率
            self.startHeartRateMonitoring()
        }
    }
    
    // 停止監測
    func stopMonitoring() {
        // 取消任何進行中的心率查詢或訂閱
    }
    
    // 請求HealthKit許可權
    private func requestAuthorization(completion: @escaping (Bool) -> Void) {
        // 需要讀取的數據類型
        let typesToRead: Set<HKObjectType> = [
            HKObjectType.quantityType(forIdentifier: .heartRate)!,
            HKObjectType.quantityType(forIdentifier: .restingHeartRate)!,
            HKObjectType.characteristicType(forIdentifier: .dateOfBirth)!,
            HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!
        ]
        
        // 需要共享的數據類型
        let typesToShare: Set<HKSampleType> = [
            HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!
        ]
        
        healthStore.requestAuthorization(toShare: typesToShare, read: typesToRead) { success, error in
            if let error = error {
                self.logger.error("HealthKit授權失敗: \(error.localizedDescription)")
            }
            completion(success)
        }
    }
    
    // 獲取用戶靜息心率
    private func fetchUserRestingHeartRate() {
        guard let restingHeartRateType = HKQuantityType.quantityType(forIdentifier: .restingHeartRate) else {
            return
        }
        
        let calendar = Calendar.current
        let now = Date()
        let startDate = calendar.date(byAdding: .day, value: -7, to: now)!
        
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: now, options: .strictStartDate)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        
        let query = HKSampleQuery(sampleType: restingHeartRateType, predicate: predicate, limit: 7, sortDescriptors: [sortDescriptor]) { [weak self] (_, samples, error) in
            guard let self = self else { return }
            
            if let error = error {
                self.logger.error("獲取靜息心率錯誤: \(error.localizedDescription)")
                return
            }
            
            guard let samples = samples as? [HKQuantitySample], !samples.isEmpty else {
                self.logger.warning("未找到靜息心率數據，使用默認值")
                return
            }
            
            // 計算平均靜息心率
            let totalRHR = samples.reduce(0.0) { sum, sample in
                return sum + sample.quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
            }
            
            let averageRHR = totalRHR / Double(samples.count)
            self.userRHR = averageRHR
            
            self.logger.info("獲取到用戶平均靜息心率: \(averageRHR)")
        }
        
        healthStore.execute(query)
    }
    
    // 獲取用戶生日計算年齡
    private func fetchUserDateOfBirth() {
        do {
            let birthdayComponents = try healthStore.dateOfBirthComponents()
            let now = Date()
            let calendar = Calendar.current
            let nowComponents = calendar.dateComponents([.year], from: now)
            
            if let birthYear = birthdayComponents.year, let currentYear = nowComponents.year {
                self.userAge = currentYear - birthYear
                logger.info("獲取到用戶年齡: \(self.userAge)")
            }
        } catch {
            logger.error("獲取生日信息失敗: \(error.localizedDescription)")
        }
    }
    
    // 開始心率監測
    private func startHeartRateMonitoring() {
        guard let heartRateType = HKObjectType.quantityType(forIdentifier: .heartRate) else {
            return
        }
        
        // 設置心率數據查詢
        let predicate = HKQuery.predicateForSamples(withStart: Date(), end: nil, options: .strictStartDate)
        
        let heartRateQuery = HKAnchoredObjectQuery(type: heartRateType, predicate: predicate, anchor: nil, limit: HKObjectQueryNoLimit) { query, samples, deletedObjects, anchor, error in
            
            if let error = error {
                self.logger.error("心率查詢錯誤: \(error.localizedDescription)")
                return
            }
            
            // 處理新的心率樣本
            self.processHeartRateSamples(samples)
        }
        
        // 添加更新處理器
        heartRateQuery.updateHandler = { query, samples, deletedObjects, anchor, error in
            if let error = error {
                self.logger.error("心率更新錯誤: \(error.localizedDescription)")
                return
            }
            
            // 處理新的心率樣本
            self.processHeartRateSamples(samples)
        }
        
        // 執行查詢
        healthStore.execute(heartRateQuery)
    }
    
    // 處理心率樣本
    private func processHeartRateSamples(_ samples: [HKSample]?) {
        guard let heartRateSamples = samples as? [HKQuantitySample], !heartRateSamples.isEmpty else { return }
        
        for sample in heartRateSamples {
            let heartRateUnit = HKUnit(from: "count/min")
            let heartRate = sample.quantity.doubleValue(for: heartRateUnit)
            
            logger.info("檢測到心率: \(heartRate)")
            
            // 更新睡眠狀態
            updateSleepState(heartRate: heartRate)
        }
    }
    
    // 更新睡眠狀態
    private func updateSleepState(heartRate: Double) {
        // 基於個人化心率閾值判斷睡眠狀態
        let threshold = sleepingHeartRateThreshold
        
        if heartRate <= threshold {
            if !isProbablySleeping {
                logger.info("進入輕度睡眠狀態，心率: \(heartRate)，閾值: \(threshold)")
                isProbablySleeping = true
            }
        } else {
            if isProbablySleeping {
                logger.info("離開睡眠狀態，心率: \(heartRate)，閾值: \(threshold)")
                isProbablySleeping = false
            }
        }
    }
    
    // 處理檢測到的運動
    func handleMotionDetected(intensity: Double) {
        let now = Date()
        lastSignificantMotionDate = now
        
        logger.info("檢測到運動，強度: \(intensity)")
        
        // 立即更新靜止狀態
        updateRestingState()
        
        // 安排一個延遲調用來檢查緩衝期後的狀態
        DispatchQueue.main.asyncAfter(deadline: .now() + motionBufferTimeInterval) {
            self.updateRestingState()
        }
    }
    
    // 更新靜止狀態
    private func updateRestingState() {
        if let lastMotion = lastSignificantMotionDate {
            let timeElapsed = Date().timeIntervalSince(lastMotion)
            
            // 如果自上次顯著運動以來經過的時間超過緩衝期
            if timeElapsed > motionBufferTimeInterval {
                if !isResting {
                    logger.info("進入靜止狀態")
                    isResting = true
                }
            } else {
                if isResting {
                    logger.info("離開靜止狀態")
                    isResting = false
                }
            }
        } else {
            // 如果從未檢測到運動，則處於靜止狀態
            if !isResting {
                logger.info("進入靜止狀態（無運動歷史）")
                isResting = true
            }
        }
    }
}

// MARK: - MotionManager
class MotionManager {
    
    private let logger = Logger(subsystem: "com.yourdomain.powernapv2new", category: "MotionManager")
    #if os(watchOS)
    private let motionManager = CMMotionManager()
    #endif
    private let motionQueue = OperationQueue()
    
    // 加速度閾值，用於檢測顯著運動
    private let significantAccelerationThreshold: Double = 0.1
    
    // 委派處理運動事件
    var onMotionDetected: ((Double) -> Void)?
    
    // 檔案記錄
    private let fileURL: URL? = {
        if let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            return documentsDirectory.appendingPathComponent("motion_log.txt")
        }
        return nil
    }()
    
    static let shared = MotionManager()
    
    private init() {
        motionQueue.name = "com.yourdomain.powernapv2new.motionQueue"
        // 創建日誌檔案
        if let fileURL = fileURL {
            let initialText = "--- 動作日誌開始於 \(Date()) ---\n"
            try? initialText.data(using: .utf8)?.write(to: fileURL)
        }
    }
    
    // 開始監測運動
    func startMonitoring() {
        #if os(watchOS)
        guard motionManager.isAccelerometerAvailable else {
            logger.error("加速度計不可用")
            return
        }
        
        // 停止任何當前的監測
        stopMonitoring()
        
        // 設置更新間隔為1秒
        motionManager.accelerometerUpdateInterval = 1.0
        
        // 開始監測加速度數據
        motionManager.startAccelerometerUpdates(to: motionQueue) { [weak self] data, error in
            guard let self = self, let data = data else {
                if let error = error {
                    self?.logger.error("加速度計更新錯誤: \(error.localizedDescription)")
                }
                return
            }
            
            // 計算總加速度
            let totalAcceleration = sqrt(
                pow(data.acceleration.x, 2) +
                pow(data.acceleration.y, 2) +
                pow(data.acceleration.z, 2)
            ) - 1.0 // 減去重力加速度
            
            let absAcceleration = abs(totalAcceleration)
            
            // 檢測是否超過閾值
            if absAcceleration > self.significantAccelerationThreshold {
                self.logger.info("檢測到顯著運動，強度: \(absAcceleration)")
                
                // 寫入日誌檔案
                self.logMotionData(detected: true, intensity: absAcceleration)
                
                // 通知監聽者
                DispatchQueue.main.async {
                    self.onMotionDetected?(absAcceleration)
                }
            } else {
                // 記錄低於閾值的運動
                self.logMotionData(detected: false, intensity: absAcceleration)
            }
        }
        #endif
        
        logger.info("開始運動監測")
    }
    
    // 停止監測運動
    func stopMonitoring() {
        #if os(watchOS)
        if motionManager.isAccelerometerActive {
            motionManager.stopAccelerometerUpdates()
            logger.info("停止運動監測")
        }
        #endif
    }
    
    // 記錄動作數據到文件
    private func logMotionData(detected: Bool, intensity: Double) {
        let timestamp = Date()
        let logString = "時間: \(timestamp), 檢測到運動: \(detected), 強度: \(intensity)\n"
        
        // 寫入到文件，方便稍後查看
        if let fileURL = fileURL {
            if let fileHandle = try? FileHandle(forWritingTo: fileURL) {
                fileHandle.seekToEndOfFile()
                if let data = logString.data(using: .utf8) {
                    fileHandle.write(data)
                }
                fileHandle.closeFile()
            }
        }
    }
}

// MARK: - NotificationManager
class NotificationManager {
    
    private let logger = Logger(subsystem: "com.yourdomain.powernapv2new", category: "NotificationManager")
    
    static let shared = NotificationManager()
    
    private init() {}
    
    // 發送喚醒通知
    func sendWakeupNotification() {
        #if os(watchOS)
        // 創建通知內容
        let content = UNMutableNotificationContent()
        content.title = "小睡結束"
        content.body = "是時候起來了！"
        content.sound = UNNotificationSound.default
        content.categoryIdentifier = "WAKEUP"
        
        // 立即觸發通知
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        
        // 創建請求
        let request = UNNotificationRequest(
            identifier: "wakeupNotification-\(Date().timeIntervalSince1970)",
            content: content,
            trigger: trigger
        )
        
        // 添加請求到通知中心
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                self.logger.error("無法發送喚醒通知: \(error.localizedDescription)")
            } else {
                self.logger.info("成功安排喚醒通知")
            }
        }
        #endif
    }
}

// MARK: - PowerNapViewModel
class PowerNapViewModel: ObservableObject {
    
    private let logger = Logger(subsystem: "com.yourdomain.powernapv2new", category: "PowerNapViewModel")
    
    // 狀態管理
    @Published var isNapping = false
    @Published var napDuration: TimeInterval = 20 * 60  // 默認20分鐘
    @Published var remainingTime: TimeInterval = 0
    @Published var sleepPhase: SleepPhase = .awake
    
    // 計時器
    private var napTimer: Timer?
    private var startTime: Date?
    
    // 服務管理 - 恢復WorkoutManager
    private let workoutManager = WorkoutSessionManager.shared
    private let runtimeManager = ExtendedRuntimeManager.shared
    private let sleepDetection = SleepDetectionService.shared
    private let motionManager = MotionManager.shared
    private let notificationManager = NotificationManager.shared
    
    // 睡眠階段枚舉
    enum SleepPhase {
        case awake
        case falling
        case light
        case deep
        case rem
    }
    
    init() {
        // 初始化時可執行的設置，例如設置運動檢測回調
        setupMotionDetection()
    }
    
    // 設置運動檢測回調
    private func setupMotionDetection() {
        motionManager.onMotionDetected = { [weak self] intensity in
            guard let self = self else { return }
            
            // 將運動數據傳遞給睡眠檢測服務
            self.sleepDetection.handleMotionDetected(intensity: intensity)
            
            // 如果運動強度非常高，可以考慮直接中斷小睡
            if intensity > 0.5 && self.isNapping {
                self.logger.info("檢測到強烈運動（強度: \(intensity)），考慮中斷小睡")
                // 這裡可以選擇中斷小睡或只是記錄
            }
        }
    }
    
    // 開始小睡
    func startNap() {
        guard !isNapping else { return }
        
        logger.info("開始小睡會話，設定時間: \(self.napDuration) 秒")
        
        // 更新狀態
        isNapping = true
        sleepPhase = .awake
        startTime = Date()
        remainingTime = napDuration
        
        // 啟動計時器
        setupNapTimer()
        
        // 啟動服務 - 恢復啟動WorkoutSession
        workoutManager.startWorkoutSession()
        runtimeManager.startSession()
        sleepDetection.startMonitoring()
        motionManager.startMonitoring()
    }
    
    // 停止小睡
    func stopNap() {
        guard isNapping else { return }
        
        logger.info("停止小睡會話")
        
        // 更新狀態
        isNapping = false
        sleepPhase = .awake
        invalidateTimer()
        
        // 停止服務 - 恢復停止WorkoutSession
        workoutManager.stopWorkoutSession()
        runtimeManager.stopSession()
        sleepDetection.stopMonitoring()
        motionManager.stopMonitoring()
    }
    
    // 設置小睡計時器
    private func setupNapTimer() {
        invalidateTimer()
        
        napTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self, self.isNapping else { return }
            
            self.updateRemainingTime()
            self.checkSleepState()
            
            // 時間到了自動結束
            if self.remainingTime <= 0 {
                self.wakeUp()
            }
        }
    }
    
    // 更新剩餘時間
    private func updateRemainingTime() {
        guard let startTime = startTime else { return }
        
        let elapsedTime = Date().timeIntervalSince(startTime)
        remainingTime = max(0, napDuration - elapsedTime)
    }
    
    // 檢查睡眠狀態
    private func checkSleepState() {
        // 根據SleepDetectionService的狀態來更新睡眠階段
        if sleepDetection.isProbablySleeping {
            if sleepDetection.isResting {
                // 靜止且可能睡眠 -> 深度睡眠
                if sleepPhase != .deep {
                    logger.info("進入深度睡眠狀態")
                    sleepPhase = .deep
                }
            } else {
                // 不靜止但可能睡眠 -> REM睡眠（可能是做夢階段）
                if sleepPhase != .rem {
                    logger.info("進入REM睡眠狀態")
                    sleepPhase = .rem
                }
            }
        } else if sleepDetection.isResting {
            // 靜止但不確定是否睡眠 -> 輕度睡眠
            if sleepPhase == .awake {
                logger.info("進入輕度睡眠狀態")
                sleepPhase = .light
            }
        } else {
            // 既不靜止也不確定是否睡眠 -> 清醒或即將入睡
            if sleepPhase != .awake && sleepPhase != .falling {
                logger.info("回到清醒狀態")
                sleepPhase = .awake
            }
        }
    }
    
    // 喚醒功能
    private func wakeUp() {
        logger.info("智能喚醒觸發")
        
        // 發送喚醒通知
        notificationManager.sendWakeupNotification()
        
        // 停止小睡
        stopNap()
    }
    
    // 取消計時器
    private func invalidateTimer() {
        napTimer?.invalidate()
        napTimer = nil
    }
    
    // 智能喚醒邏輯 - 根據睡眠階段決定最佳喚醒時間
    func shouldWakeUpEarly() -> Bool {
        // 示例：如果處於輕度睡眠且至少已經睡了napDuration的80%，則建議喚醒
        guard let startTime = startTime else { return false }
        
        let elapsedTime = Date().timeIntervalSince(startTime)
        let minimumNapTime = napDuration * 0.8
        
        return elapsedTime >= minimumNapTime && (sleepPhase == .light || sleepPhase == .rem)
    }
} 