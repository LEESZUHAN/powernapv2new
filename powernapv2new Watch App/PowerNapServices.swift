import Foundation
import HealthKit
import CoreMotion
import os
import UserNotifications
#if os(watchOS)
import WatchKit
#endif
import Combine

// MARK: - WorkoutSessionManager
class WorkoutSessionManager: NSObject, HKWorkoutSessionDelegate {
    
    private let logger = Logger(subsystem: "com.yourdomain.powernapv2new", category: "WorkoutSessionManager")
    private let healthStore = HKHealthStore()
    
    private var workoutSession: HKWorkoutSession?
    private var workoutBuilder: HKLiveWorkoutBuilder?
    
    // 添加心率公開屬性
    private(set) var latestHeartRate: Double?
    
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
        
        // 先檢查HealthKit授權狀態
        let typesToRead: Set<HKObjectType> = [
            HKObjectType.quantityType(forIdentifier: .heartRate)!,
            HKObjectType.quantityType(forIdentifier: .restingHeartRate)!
        ]
        
        healthStore.requestAuthorization(toShare: nil, read: typesToRead) { [weak self] success, error in
            guard let self = self, success else {
                if let error = error {
                    self?.logger.error("HealthKit授權失敗: \(error.localizedDescription)")
                } else {
                    self?.logger.error("HealthKit授權被拒絕")
                }
                return
            }
            
            // 授權成功後創建並啟動會話
            DispatchQueue.main.async {
                self.createAndStartWorkoutSession(with: workoutConfiguration)
            }
        }
    }
    
    // 將會話創建邏輯分離為獨立方法
    private func createAndStartWorkoutSession(with workoutConfiguration: HKWorkoutConfiguration) {
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
            workoutBuilder?.beginCollection(withStart: Date()) { [weak self] success, error in
                guard let self = self else { return }
                
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
        
        // 在結束workoutSession前先結束數據收集
        // 使用同步方法確保順序正確
        let group = DispatchGroup()
        var endCollectionError: Error?
        
        group.enter()
        workoutBuilder?.endCollection(withEnd: Date()) { [weak self] success, error in
            defer { group.leave() }
            
            if let error = error {
                self?.logger.error("無法結束數據收集: \(error.localizedDescription)")
                endCollectionError = error
                return
            }
            
            if success {
                self?.logger.info("成功結束數據收集")
            }
        }
        
        // 等待數據收集結束，然後再結束會話
        // 設置超時防止無限等待
        let result = group.wait(timeout: .now() + 2.0)
        
        if result == .timedOut {
            logger.warning("等待結束數據收集超時，繼續結束會話")
        } else if endCollectionError != nil {
            logger.warning("結束數據收集出錯，嘗試忽略錯誤並繼續結束會話")
        }
        
        // 結束會話
        workoutSession.end()
                
                // 棄用workout數據，因為這只是一個休息會話
        workoutBuilder?.discardWorkout()
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
                // 更新最新心率
                latestHeartRate = heartRate
                
                // 發送通知
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: NSNotification.Name("HeartRateUpdated"), object: nil, userInfo: ["heartRate": heartRate])
                }
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
    
    // 心率閾值設定 - 將userRHR改為公開
    private let minRestingHeartRate: Double = 40.0 // 最低安全閾值
    private(set) var userRHR: Double = 60.0 // 默認靜息心率，改為公開訪問
    private var userAge: Int = 30 // 默認年齡
    
    // 根據用戶年齡和靜息心率計算的閾值 - 改為公開計算屬性
    var sleepingHeartRateThreshold: Double {
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
    
    // 添加公開屬性來存儲當前加速度值
    private(set) var currentAcceleration: Double = 0.0
    
    // 委派處理運動事件
    var onMotionDetected: ((Double) -> Void)?
    
    // 上次通知時間 - 用於限制通知頻率
    private var lastNotificationTime: Date = Date(timeIntervalSince1970: 0)
    private let minNotificationInterval: TimeInterval = 0.5 // 最小通知間隔0.5秒
    
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
        motionQueue.qualityOfService = .utility // 降低優先級以節省電量
        
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
            
            // 更新當前加速度值 - 使用主線程
            DispatchQueue.main.async {
                self.currentAcceleration = absAcceleration
                
                // 檢查是否超過通知間隔限制 - 避免過於頻繁的通知
                let now = Date()
                if now.timeIntervalSince(self.lastNotificationTime) >= self.minNotificationInterval {
                // 發送通知以便UI更新
                    NotificationCenter.default.post(
                        name: NSNotification.Name("AccelerationUpdated"), 
                        object: nil, 
                        userInfo: ["acceleration": absAcceleration]
                    )
                    self.lastNotificationTime = now
            }
            
            // 檢測是否超過閾值
            if absAcceleration > self.significantAccelerationThreshold {
                self.logger.info("檢測到顯著運動，強度: \(absAcceleration)")
                
                // 寫入日誌檔案
                self.logMotionData(detected: true, intensity: absAcceleration)
                
                    // 通知監聽者 - 也應用通知間隔限制
                    if now.timeIntervalSince(self.lastNotificationTime) >= self.minNotificationInterval {
                    self.onMotionDetected?(absAcceleration)
                }
            } else {
                // 記錄低於閾值的運動
                self.logMotionData(detected: false, intensity: absAcceleration)
                }
            }
        }
        #endif
        
        logger.info("動作監測已啟動")
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
    
    // 記錄動作數據到文件 - 改為使用批量寫入
    private var pendingLogData: [String] = []
    private var lastLogWriteTime: Date = Date()
    private let logFlushInterval: TimeInterval = 5.0 // 每5秒寫入一次
    
    private func logMotionData(detected: Bool, intensity: Double) {
        let timestamp = Date()
        let logString = "時間: \(timestamp), 檢測到運動: \(detected), 強度: \(intensity)\n"
        
        // 添加到待寫入數據
        pendingLogData.append(logString)
        
        // 如果達到指定間隔或數據量較大，執行寫入
        if timestamp.timeIntervalSince(lastLogWriteTime) >= logFlushInterval || pendingLogData.count > 20 {
            flushLogData()
        }
    }
    
    // 批量寫入日誌數據
    private func flushLogData() {
        guard !pendingLogData.isEmpty, let fileURL = fileURL else { return }
        
        let dataToWrite = pendingLogData.joined()
        pendingLogData.removeAll()
        lastLogWriteTime = Date()
        
        // 使用後台線程寫入
        DispatchQueue.global(qos: .background).async {
            if let fileHandle = try? FileHandle(forWritingTo: fileURL) {
                fileHandle.seekToEndOfFile()
                if let data = dataToWrite.data(using: .utf8) {
                    fileHandle.write(data)
                }
                try? fileHandle.close()
            }
        }
    }
}

// MARK: - NotificationManager
class NotificationManager: NSObject {
    
    private let logger = Logger(subsystem: "com.yourdomain.powernapv2new", category: "NotificationManager")
    
    // 鬧鈴相關屬性
    private var alarmTimer: Timer?
    private let alarmDuration: TimeInterval = 180 // 3分鐘持續響鈴
    private var alarmStartTime: Date?
    private var notificationCount = 0
    
    // 發布鬧鈴狀態
    @Published var isAlarmActive: Bool = false
    var alarmStatePublisher: Published<Bool>.Publisher { $isAlarmActive }
    
    static let shared = NotificationManager()
    
    private override init() {
        super.init()
        
        // 設置通知代理
        UNUserNotificationCenter.current().delegate = self
    }
    
    // 發送喚醒通知 - 持續模式
    func sendWakeupNotification() {
        #if os(watchOS)
        // 標記鬧鈴開始
        DispatchQueue.main.async {
            self.isAlarmActive = true
        }
        alarmStartTime = Date()
        notificationCount = 0
        
        // 播放系統聲音和震動
        WKInterfaceDevice.current().play(.notification)
        
        // 發送首次通知
        sendNotificationWithDelay(0.1, identifier: "initial")
        
        // 設置鬧鈴持續時間計時器
        alarmTimer = Timer.scheduledTimer(withTimeInterval: alarmDuration, repeats: false) { [weak self] _ in
            DispatchQueue.main.async {
                self?.stopContinuousAlarm()
            }
        }
        
        // 安排多個通知，作為鬧鈴序列
        scheduleNotificationSequence()
        #endif
    }
    
    // 發送帶延遲的通知
    private func sendNotificationWithDelay(_ delay: TimeInterval, identifier: String) {
        let content = UNMutableNotificationContent()
        content.title = "小睡結束"
        content.body = "是時候起來了！"
        content.sound = UNNotificationSound.defaultCritical
        content.categoryIdentifier = "WAKEUP"
        content.interruptionLevel = .timeSensitive
        content.relevanceScore = 1.0
        
        // 設置延遲
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false)
        
        // 創建請求，使用遞增計數確保標識符唯一
        notificationCount += 1
        let request = UNNotificationRequest(
            identifier: "wakeup-\(identifier)-\(notificationCount)-\(Date().timeIntervalSince1970)",
            content: content,
            trigger: trigger
        )
        
        // 添加請求到通知中心
        UNUserNotificationCenter.current().add(request) { [weak self] error in
            if let error = error {
                self?.logger.error("通知發送失敗: \(error.localizedDescription)")
            }
        }
    }
    
    // 安排通知序列
    private func scheduleNotificationSequence() {
        // 設計一個節奏感強的通知序列，前一分鐘頻率更高
        
        // 初始喚醒（0-3秒）- 急促三連發
        sendNotificationWithDelay(0.1, identifier: "initial-1")
        sendNotificationWithDelay(1.5, identifier: "initial-2")
        sendNotificationWithDelay(3, identifier: "initial-3")
        
        // 第一節拍（5-10秒）- 緊密節奏
        sendNotificationWithDelay(5, identifier: "beat1-1")
        sendNotificationWithDelay(7, identifier: "beat1-2")
        sendNotificationWithDelay(10, identifier: "beat1-3")
                
        // 第二節拍（15-20秒）- 緊密節奏
        sendNotificationWithDelay(15, identifier: "beat2-1")
        sendNotificationWithDelay(17, identifier: "beat2-2")
        sendNotificationWithDelay(20, identifier: "beat2-3")
        
        // 第三節拍（25-30秒）
        sendNotificationWithDelay(25, identifier: "beat3-1")
        sendNotificationWithDelay(27, identifier: "beat3-2")
        sendNotificationWithDelay(30, identifier: "beat3-3")
        
        // 第四節拍（35-40秒）
        sendNotificationWithDelay(35, identifier: "beat4-1")
        sendNotificationWithDelay(37, identifier: "beat4-2")
        sendNotificationWithDelay(40, identifier: "beat4-3")
        
        // 第五節拍（45-50秒）
        sendNotificationWithDelay(45, identifier: "beat5-1")
        sendNotificationWithDelay(47, identifier: "beat5-2")
        sendNotificationWithDelay(50, identifier: "beat5-3")
        
        // 第六節拍（55-60秒）- 一分鐘標記（強化）
        sendNotificationWithDelay(55, identifier: "beat6-1")
        sendNotificationWithDelay(58, identifier: "beat6-2")
        sendNotificationWithDelay(60, identifier: "minute1-1")
        sendNotificationWithDelay(61, identifier: "minute1-2")
        sendNotificationWithDelay(63, identifier: "minute1-3")
        
        // 90秒提醒
        sendNotificationWithDelay(90, identifier: "second90-1")
        sendNotificationWithDelay(92, identifier: "second90-2")
        sendNotificationWithDelay(95, identifier: "second90-3")
        
        // 二分鐘提醒（更強烈）
        sendNotificationWithDelay(120, identifier: "minute2-1")
        sendNotificationWithDelay(121, identifier: "minute2-2")
        sendNotificationWithDelay(123, identifier: "minute2-3")
        
        // 150秒提醒
        sendNotificationWithDelay(150, identifier: "second150-1")
        sendNotificationWithDelay(152, identifier: "second150-2")
        sendNotificationWithDelay(155, identifier: "second150-3")
        
        // 三分鐘提醒（最後一輪）
        sendNotificationWithDelay(175, identifier: "final-1")
        sendNotificationWithDelay(177, identifier: "final-2")
        sendNotificationWithDelay(179, identifier: "final-3")
    }
    
    // 停止持續鬧鈴
    func stopContinuousAlarm() {
        alarmTimer?.invalidate()
        alarmTimer = nil
        
        // 取消所有待處理的通知
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        
        // 標記鬧鈴已停止 - 確保在主線程上執行
        DispatchQueue.main.async {
            self.isAlarmActive = false
        }
        
        logger.info("鬧鈴已停止")
    }
    
    // 檢查鬧鈴是否已響過一段時間
    func getAlarmElapsedTime() -> TimeInterval? {
        guard let startTime = alarmStartTime, isAlarmActive else {
            return nil
        }
        return Date().timeIntervalSince(startTime)
    }
    
    // 添加deinit方法確保資源被清理
    deinit {
        alarmTimer?.invalidate()
        alarmTimer = nil
        
        // 如果鬧鈴還在活動狀態，強制停止
        if isAlarmActive {
            stopContinuousAlarm()
        }
        
        logger.info("NotificationManager被釋放")
    }
}

// MARK: - UNUserNotificationCenterDelegate
extension NotificationManager: UNUserNotificationCenterDelegate {
    // 在前台時接收通知
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        // 允許在前台顯示通知，包括聲音和提醒
        completionHandler([.banner, .sound, .list])
        
        // 在前台模式下，增強通知效果
        #if os(watchOS)
        if isAlarmActive {
            // 播放震動效果
            DispatchQueue.main.async {
                WKInterfaceDevice.current().play(.notification)
            }
        }
        #endif
    }
    
    // 處理用戶與通知的交互
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        // 用戶點擊了通知，可以添加特定行為
        completionHandler()
    }
}

// MARK: - SleepDataLogger
class SleepDataLogger {
    
    private let fileManager = FileManager.default
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return formatter
    }()
    
    // 紀錄檔案標識符
    private var sessionId: String?
    private var logFilePath: URL?
    
    // 新增屬性
    private var pendingLogEntries: [String] = []        // 待寫入的日誌條目
    private var lastLogWriteTime: Date = Date()         // 上次寫入時間
    private let logFlushInterval: TimeInterval = 10.0   // 日誌寫入間隔（10秒）
    private let maxEntriesBeforeFlush: Int = 20         // 在寫入前允許的最大條目數
    private let logRetentionDays: Int = 14              // 日誌保留天數（14天）
    private var loggingTimer: Timer?                    // 定時寫入計時器
    private var lastLogEntryTime: Date?                 // 上次記錄時間
    private let minLogInterval: TimeInterval = 10.0     // 最小記錄間隔（10秒）
    
    static let shared = SleepDataLogger()
    
    private init() {}
    
    // 開始新的記錄會話
    func startNewSession() {
        // 生成唯一會話ID
        sessionId = UUID().uuidString
        
        // 創建日期字符串作為文件名的一部分
        let dateString = dateFormatter.string(from: Date())
        let fileName = "powernap_session_\(dateString).csv"
        
        // 獲取文檔目錄
        if let docsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first {
            // 檢查或創建LogFiles目錄
            let logDirectory = docsDirectory.appendingPathComponent("LogFiles")
            
            do {
                if !fileManager.fileExists(atPath: logDirectory.path) {
                    try fileManager.createDirectory(at: logDirectory, withIntermediateDirectories: true)
                }
                
                // 設置日誌文件路徑
                logFilePath = logDirectory.appendingPathComponent(fileName)
                
                // 寫入標題行
                let headerLine = "Timestamp,HeartRate,RestingHR,HRThreshold,HRTrend,AccelerationLevel,IsResting,IsSleeping,SleepPhase,RemainingTime,Notes\n"
                try headerLine.write(to: logFilePath!, atomically: true, encoding: .utf8)
                
                print("開始睡眠數據記錄: \(fileName)")
                
                // 啟動定時刷新計時器
                startLoggingTimer()
                
                // 清理過期日誌
                cleanupOldLogFiles()
                
            } catch {
                print("創建日誌文件失敗: \(error.localizedDescription)")
            }
        }
    }
    
    // 記錄心率和睡眠數據
    func logSleepData(
        heartRate: Double,
        restingHR: Double,
        hrThreshold: Double,
        hrTrend: Double,
        acceleration: Double,
        isResting: Bool,
        isSleeping: Bool,
        sleepPhase: String,
        remainingTime: TimeInterval,
        notes: String = ""
    ) {
        guard logFilePath != nil else { return }
        
        let now = Date()
        
        // 檢查是否應該跳過本次記錄（時間間隔控制）
        if let lastTime = lastLogEntryTime, now.timeIntervalSince(lastTime) < minLogInterval {
            return // 距離上次記錄還不到10秒，跳過
        }
        
        // 更新最後記錄時間
        lastLogEntryTime = now
        
        // 格式化數據行
        let dateString = dateFormatter.string(from: now)
        let dataLine = "\(dateString),\(heartRate),\(restingHR),\(hrThreshold),\(hrTrend),\(acceleration),\(isResting),\(isSleeping),\(sleepPhase),\(remainingTime),\"\(notes)\"\n"
        
        // 添加到待寫入隊列
        pendingLogEntries.append(dataLine)
        
        // 如果達到閾值或時間間隔足夠長，執行寫入
        if pendingLogEntries.count >= maxEntriesBeforeFlush || 
           now.timeIntervalSince(lastLogWriteTime) >= logFlushInterval {
            flushLogEntries()
        }
    }
    
    // 結束記錄會話
    func endSession(summary: String) {
        // 確保所有待寫入數據都被寫入
        flushLogEntries()
        
        guard logFilePath != nil else { return }
        
        // 添加會話總結
        let summaryLine = "\n--- 會話結束 ---\n\(summary)\n"
        
        if let fileHandle = try? FileHandle(forWritingTo: self.logFilePath!) {
            fileHandle.seekToEndOfFile()
            if let data = summaryLine.data(using: .utf8) {
                fileHandle.write(data)
            }
            fileHandle.closeFile()
            
            print("睡眠數據記錄已完成，保存至: \(self.logFilePath!.lastPathComponent)")
        }
        
        // 重置會話變量
        sessionId = nil
        self.logFilePath = nil
        
        // 停止日誌計時器
        loggingTimer?.invalidate()
        loggingTimer = nil
    }
    
    // 新增方法: 啟動日誌定時器
    private func startLoggingTimer() {
        loggingTimer?.invalidate()
        loggingTimer = Timer.scheduledTimer(withTimeInterval: logFlushInterval, repeats: true) { [weak self] _ in
            self?.flushLogEntries()
        }
    }
    
    // 新增方法: 批量寫入日誌
    private func flushLogEntries() {
        guard !pendingLogEntries.isEmpty, logFilePath != nil else { return }
        
        let dataToWrite = pendingLogEntries.joined()
        pendingLogEntries.removeAll()
        lastLogWriteTime = Date()
        
        // 使用後台線程寫入
        DispatchQueue.global(qos: .utility).async {
            if let fileHandle = try? FileHandle(forWritingTo: self.logFilePath!) {
                fileHandle.seekToEndOfFile()
                if let data = dataToWrite.data(using: .utf8) {
                    fileHandle.write(data)
                }
                try? fileHandle.close()
            }
        }
    }
    
    // 新增方法: 清理過期日誌文件
    private func cleanupOldLogFiles() {
        // 獲取日誌目錄
        guard let docsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let logDirectory = docsDirectory.appendingPathComponent("LogFiles")
        
        // 確保目錄存在
        guard fileManager.fileExists(atPath: logDirectory.path) else { return }
        
        // 計算14天前的日期
        let calendar = Calendar.current
        guard let cutoffDate = calendar.date(byAdding: .day, value: -logRetentionDays, to: Date()) else { return }
        
        // 在後台執行清理
        DispatchQueue.global(qos: .utility).async {
            do {
                // 獲取所有日誌文件
                let fileURLs = try self.fileManager.contentsOfDirectory(at: logDirectory, includingPropertiesForKeys: [.creationDateKey], options: [])
                
                // 檢查每個文件
                for fileURL in fileURLs {
                    if let attributes = try? self.fileManager.attributesOfItem(atPath: fileURL.path),
                       let creationDate = attributes[.creationDate] as? Date {
                        
                        // 如果文件創建於14天前，刪除
                        if creationDate < cutoffDate {
                            try? self.fileManager.removeItem(at: fileURL)
                            print("已刪除過期日誌文件: \(fileURL.lastPathComponent)")
                        }
                    }
                }
            } catch {
                print("清理日誌文件時出錯: \(error.localizedDescription)")
            }
        }
    }
    
    /// 停止並清理日誌計時器
    func stopLoggingTimer() {
        loggingTimer?.invalidate()
        loggingTimer = nil
    }
}

// MARK: - PowerNapViewModel
class PowerNapViewModel: ObservableObject {
    
    private let logger = Logger(subsystem: "com.yourdomain.powernapv2new", category: "PowerNapViewModel")
    
    // 狀態管理
    @Published var isNapping = false
    @Published var napDuration: TimeInterval = 20 * 60  // 默認20分鐘
    @Published var napMinutes: Int = 20  // 默認20分鐘 - 用於Picker
    @Published var remainingTime: TimeInterval = 0
    @Published var sleepPhase: SleepPhase = .awake
    
    // 測試頁面顯示的數據
    @Published var currentHeartRate: Double = 0
    @Published var restingHeartRate: Double = 60
    @Published var heartRateThreshold: Double = 54
    @Published var isResting: Bool = false
    @Published var isProbablySleeping: Bool = false
    @Published var currentAcceleration: Double = 0.0
    @Published var motionThreshold: Double = 0.1  // 運動閾值，與MotionManager中的對應
    
    // 新增：用戶閾值調整
    @Published var userHRThresholdOffset: Double = 0.0 // 用戶心率閾值調整值
    @Published var userSelectedAgeGroup: AgeGroup? // 用戶選擇的年齡組
    @Published var sleepSensitivity: Double = 0.5 // 睡眠敏感度（0-低靈敏度，1-高靈敏度）
    @Published var showingThresholdConfirmation: Bool = false // 判定寬鬆確認狀態
    @Published var pendingThresholdOffset: Double? = nil // 待確認的閾值調整值
    
    // 計時器
    private var napTimer: Timer?
    private var startTime: Date?
    private var statsUpdateTimer: Timer?
    
    // 服務管理
    private let workoutManager = WorkoutSessionManager.shared
    private let runtimeManager = ExtendedRuntimeManager.shared
    private let sleepDetection = SleepDetectionService.shared
    private let motionManager = MotionManager.shared
    private let notificationManager = NotificationManager.shared
    private let heartRateService = HeartRateService()
    
    // 新增：整合睡眠服務和睡眠檢測協調器
    private let sleepServices = SleepServices.shared
    private var sleepDetectionCoordinator: SleepDetectionCoordinator {
        return sleepServices.sleepDetectionCoordinator
    }
    
    // 新增：用戶配置文件管理
    private let userProfileManager = UserSleepProfileManager.shared
    @Published private(set) var currentUserProfile: UserSleepProfile?
    
    // 睡眠數據記錄器
    private let sleepLogger = SleepDataLogger.shared
    
    // 睡眠階段枚舉
    enum SleepPhase {
        case awake
        case falling
        case light
        case deep
        case rem
    }
    
    // 休息階段
    enum NapPhase {
        case awaitingSleep    // 等待入睡
        case sleeping         // 正在休息倒計時
        case waking           // 正在喚醒
    }
    
    // 添加休息階段狀態
    @Published private(set) var napPhase: NapPhase = .awaitingSleep
    
    // 檢測到睡眠的起始時間
    private var sleepStartTime: Date?
    
    // 訂閱管理
    private var cancellables = Set<AnyCancellable>()
    
    // 添加與閾值優化相關的屬性
    @Published var thresholdOptimizationStatus: String = ""
    @Published private(set) var isOptimizingThreshold: Bool = false
    
    // MARK: - 用戶反饋相關
    enum FeedbackType {
        case falsePositive  // 系統誤判為睡眠（過於寬鬆）
        case falseNegative  // 系統未檢測到睡眠（過於嚴謹）
        case accurate       // 判斷準確
        case unknown        // 未知
    }
    
    @Published var showingFeedbackPrompt: Bool = false // 控制是否顯示反饋提示
    @Published var lastFeedbackDate: Date? // 最近一次提供反饋的日期
    @Published var lastFeedbackType: FeedbackType = .unknown // 最近一次反饋的類型
    private var hasSubmittedFeedback: Bool = false // 是否已寫入任何 feedback
    
    // MARK: - 喚醒UI控制相關
    @Published var showingAlarmStopUI: Bool = false // 控制是否顯示鬧鈴停止界面
    @Published var alarmStopped: Bool = false // 鬧鈴是否已停止
    
    // MARK: - 新增：心率異常追蹤器
    private let heartRateAnomalyTracker = HeartRateAnomalyTracker()
    
    /// 當前心率異常狀態
    @Published private(set) var heartRateAnomalyStatus: HeartRateAnomalyTracker.AnomalyStatus = .none
    
    /// 異常摘要信息（用於調試和高級用戶）
    var anomalySummary: String {
        return heartRateAnomalyTracker.getAnomalySummary()
    }
    
    // 新增: 碎片化睡眠模式
    @Published var fragmentedSleepMode: Bool = false
    
    // MARK: - 追蹤本次 Session 起始參數 (新增)
    private var sessionStartThresholdPercent: Double? = nil
    private var sessionStartMinDuration: Int? = nil
    
    // 1. 在 PowerNapViewModel class 層級新增 detectSource
    private var detectSource: String = ""
    
    init() {
        // 確保napDuration和napMinutes保持同步
        $napDuration
            .map { Int($0 / 60) }
            .assign(to: &$napMinutes)
        
        // 初始化時可執行的設置，例如設置運動檢測回調
        setupMotionDetection()
        setupHeartRateSubscriptions()
        startStatsUpdateTimer()
        
        // 添加觀察者接收加速度更新
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("AccelerationUpdated"),
            object: nil,
            queue: .main) { [weak self] notification in
                guard let self = self,
                      let acceleration = notification.userInfo?["acceleration"] as? Double else { return }
                self.currentAcceleration = acceleration
            }
        
        // 新增：訂閱SleepDetectionCoordinator的睡眠狀態更新
        setupSleepDetectionSubscription()
        
        // 新增：載入用戶配置文件
        loadUserProfile()
        
        // 確保睡眠時間選擇不小於確認時間
        DispatchQueue.main.async {
            self.ensureValidNapDuration()
        }
    }
    
    deinit {
        statsUpdateTimer?.invalidate()
        NotificationCenter.default.removeObserver(self)
        cancellables.forEach { $0.cancel() }
        invalidateTimer() // 確保napTimer被清理
        
        // 確保所有服務都已停止
        if isNapping {
            workoutManager.stopWorkoutSession()
            sleepServices.stopMonitoring()
            sleepDetection.stopMonitoring()
            heartRateService.stopMonitoring()
            motionManager.stopMonitoring()
            runtimeManager.stopSession()
        }
        
        logger.info("PowerNapViewModel被釋放")
    }
    
    // 新增：設置睡眠檢測協調器訂閱
    private func setupSleepDetectionSubscription() {
        sleepDetectionCoordinator.sleepStatePublisher
            .receive(on: RunLoop.main)
            .sink { [weak self] sleepState in
                guard let self = self else { return }
                
                // 根據協調器報告的睡眠狀態更新我們的UI狀態
                switch sleepState {
                case .awake:
                    self.sleepPhase = .awake
                case .resting:
                    self.sleepPhase = .falling
                case .lightSleep:
                    self.sleepPhase = .light
                    
                    // 如果是第一次進入輕度睡眠狀態，且我們在等待入睡階段
                    if self.napPhase == .awaitingSleep && self.sleepStartTime == nil {
                        // 標記可能進入睡眠階段，但尚未完全確認
                        self.logger.info("檢測到可能進入輕度睡眠")
                    }
                    
                case .deepSleep:
                    self.sleepPhase = .deep
                    
                    // 如果是第一次進入深度睡眠狀態，且我們在等待入睡階段
                    if self.napPhase == .awaitingSleep && self.sleepStartTime == nil {
                        self.sleepStartTime = Date()
                        self.logger.info("檢測到深度睡眠開始，開始倒計時 \(self.napDuration) 秒")
                        
                        // 更新階段
                        self.napPhase = .sleeping
                    }
                }
                
                // 高級日誌：睡眠階段變化
                AdvancedLogger.shared.log(.phaseChange, payload: [
                    "newPhase": .string(String(describing: sleepState))
                ])
            }
            .store(in: &cancellables)
    }
    
    // 設置心率服務訂閱
    private func setupHeartRateSubscriptions() {
        // 訂閱心率更新
        heartRateService.heartRatePublisher
            .receive(on: RunLoop.main)
            .sink { [weak self] heartRate in
                self?.currentHeartRate = heartRate
            }
            .store(in: &cancellables)
        
        // 訂閱靜息心率更新
        heartRateService.restingHeartRatePublisher
            .receive(on: RunLoop.main)
            .sink { [weak self] restingHeartRate in
                self?.restingHeartRate = restingHeartRate
                // 更新閾值
                self?.heartRateThreshold = self?.heartRateService.heartRateThreshold ?? 54
            }
            .store(in: &cancellables)
        
        // 訂閱睡眠狀態更新
        heartRateService.isProbablySleepingPublisher
            .receive(on: RunLoop.main)
            .sink { [weak self] isProbablySleeping in
                self?.isProbablySleeping = isProbablySleeping
            }
            .store(in: &cancellables)
    }
    
    // 啟動統計數據更新計時器
    private func startStatsUpdateTimer() {
        statsUpdateTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.updateStats()
        }
    }
    
    // 更新統計數據
    private func updateStats() {
        // 從SleepDetectionService獲取數據
        self.isResting = sleepDetection.isResting
        
        // 從WorkoutManager獲取心率數據 (我們現在優先使用HeartRateService，這裡作為備用)
        if self.currentHeartRate == 0, let hr = workoutManager.latestHeartRate {
            self.currentHeartRate = hr
        }
        
        // 從SleepDetectionService獲取靜止心率和閾值 (備用)
        if self.restingHeartRate == 60 {  // 如果尚未從HeartRateService獲取
        self.restingHeartRate = sleepDetection.userRHR
        self.heartRateThreshold = sleepDetection.sleepingHeartRateThreshold
        }
        
        // 從MotionManager獲取當前加速度
        self.currentAcceleration = motionManager.currentAcceleration
    }
    
    // 設置運動檢測回調
    private func setupMotionDetection() {
        motionManager.onMotionDetected = { [weak self] intensity in
            guard let self = self else { return }
            
            // 將運動數據傳遞給睡眠檢測服務
            self.sleepDetection.handleMotionDetected(intensity: intensity)
        }
    }
    
    // 新增：載入用戶配置文件
    private func loadUserProfile() {
        let userId = getUserId()
        
        // 從UserSleepProfileManager獲取用戶配置文件
        if let profile = userProfileManager.getUserProfile(forUserId: userId) {
            currentUserProfile = profile
            
            // 使用配置文件中的設置更新UI
            userHRThresholdOffset = profile.manualAdjustmentOffset
            userSelectedAgeGroup = profile.ageGroup
            
            // 計算實際使用的心率閾值
            updateHeartRateThreshold()
            
            logger.info("已載入用戶配置文件: ID=\(userId)")
            
            // 新增：嘗試自動優化閾值（不強制，僅在滿足條件時執行）
            checkForAutomaticThresholdOptimization(userId: userId)
        } else {
            // 如果沒有現有配置文件，創建一個默認的
            let userAge = 35 // 默認假設用戶35歲
            let ageGroup = AgeGroup.forAge(userAge)
            
            let newProfile = UserSleepProfile.createDefault(forUserId: userId, ageGroup: ageGroup)
            currentUserProfile = newProfile
            userProfileManager.saveUserProfile(newProfile)
            
            userSelectedAgeGroup = ageGroup
            
            logger.info("創建並保存了新的用戶配置文件: ID=\(userId)")
        }
    }
    
    // 新增：獲取用戶ID
    private func getUserId() -> String {
        let defaults = UserDefaults.standard
        let userIdKey = "com.yourdomain.powernapv2new.userId"
        
        if let savedId = defaults.string(forKey: userIdKey) {
            return savedId
        }
        
        // 創建新的用戶ID
        let newId = UUID().uuidString
        defaults.set(newId, forKey: userIdKey)
        return newId
    }
    
    // 新增：更新心率閾值
    func updateHeartRateThreshold() {
        guard let profile = currentUserProfile else { return }
        
        // 修正：直接使用設定的百分比計算閾值
        // 不再使用基礎閾值和用戶調整的間接計算
        
        // 獲取目標百分比（成人默認0.9，加上用戶調整）
        let targetPercentage = profile.hrThresholdPercentage + userHRThresholdOffset
        
        // 應用敏感度調整
        let sensitivityAdjustment = sleepSensitivity * 0.1 // 0-10% 變化
        
        // 應用異常調整（如果有）
        var anomalyAdjustment: Double = 0.0
        
        // 獲取當前異常狀態
        let anomalyStatus = heartRateAnomalyTracker.getCurrentAnomalyStatus()
        heartRateAnomalyStatus = anomalyStatus
        
        switch anomalyStatus {
        case .temporary:
            // 暫時異常：稍微寬鬆閾值(+2%)
            anomalyAdjustment = 0.02
            logger.info("檢測到暫時性心率異常，適當寬鬆閾值(+2%)")
        case .persistent:
            // 持久異常：更寬鬆閾值(+4%)
            anomalyAdjustment = 0.04
            logger.info("檢測到持久性心率異常，顯著寬鬆閾值(+4%)")
        case .requiresReset:
            // 需要重校準：大幅調整(+7%)並觸發重校準流程
            anomalyAdjustment = 0.07
            // 僅提示，實際重校準在特定時機進行
            logger.info("心率異常程度嚴重，需要重置基線，暫時大幅放寬閾值(+7%)")
        default:
            // 正常狀態：不額外調整
            break
        }
        
        // 直接計算最終閾值
        let finalThreshold = restingHeartRate * targetPercentage * (1 + sensitivityAdjustment) * (1 + anomalyAdjustment)
        
        // 更新UI顯示的閾值
        heartRateThreshold = finalThreshold
        
        // 更新心率服務中的閾值
        heartRateService.setCustomHeartRateThreshold(finalThreshold)
        
        // 計算並記錄實際的閾值百分比(相對於RHR)
        let actualPercentage = (finalThreshold / restingHeartRate) * 100
        let basePercentage = targetPercentage * 100
        
        logger.info("更新心率閾值: \(finalThreshold) BPM (目標百分比: \(String(format: "%.1f", basePercentage))%, 敏感度調整: \(sensitivityAdjustment), 異常調整: \(anomalyAdjustment), 實際百分比: \(String(format: "%.1f", actualPercentage))%)")
    }
    
    // 新增：設置用戶心率閾值偏移
    func setUserHeartRateThresholdOffset(_ offset: Double) {
        // 計算新的累計偏移值
        let newOffset = offset  // 直接使用提供的偏移值
        
        // 獲取基礎百分比（成人為0.9或90%）
        let basePercentage = AgeGroup.adult.heartRateThresholdPercentage
        
        // 計算目標百分比
        let targetPercentage = basePercentage + newOffset
        
        // 檢查目標百分比是否在合理範圍內
        // 開發階段使用更寬的範圍：70%-110%
        if targetPercentage < 0.70 {
            // 下限：RHR的70%
            userHRThresholdOffset = 0.70 - basePercentage
            logger.info("閾值調整已達下限(RHR的70%)")
        } else if targetPercentage > 1.10 {
            // 上限：RHR的110%
            userHRThresholdOffset = 1.10 - basePercentage
            logger.info("閾值調整已達上限(RHR的110%)")
        } else {
            // 在合理範圍內，接受新的累計偏移值
            userHRThresholdOffset = newOffset
        }
        
        // 四捨五入到最接近的0.01，確保顯示與實際值完全匹配
        let roundedOffset = (userHRThresholdOffset * 100).rounded() / 100
        userHRThresholdOffset = roundedOffset
        
        // 更新用戶配置文件
        if var profile = currentUserProfile {
            profile.manualAdjustmentOffset = roundedOffset
            userProfileManager.saveUserProfile(profile)
            currentUserProfile = profile
        }
        
        // 更新心率閾值
        updateHeartRateThreshold()
        
        // 顯示百分比（直接從偏移值計算）
        let displayPercentage = (basePercentage + roundedOffset) * 100
        
        // 考慮敏感度調整後的實際百分比
        let sensitivityAdjustment = sleepSensitivity * 0.1
        let effectivePercentage = (basePercentage + roundedOffset) * (1 + sensitivityAdjustment)
        let effectiveDisplayPercentage = effectivePercentage * 100
        
        logger.info("用戶調整了心率閾值：設定為RHR的\(String(format: "%.1f", displayPercentage))%，含敏感度調整後為\(String(format: "%.1f", effectiveDisplayPercentage))% (偏移值：\(roundedOffset))")
    }
    
    // 新增：設置睡眠敏感度
    func setSleepSensitivity(_ sensitivity: Double) {
        // 限制敏感度在 0 到 1 之間
        let limitedSensitivity = min(max(sensitivity, 0), 1)
        sleepSensitivity = limitedSensitivity
        
        // 更新心率閾值
        updateHeartRateThreshold()
        
        // 修正：調整靜止比例要求，使與心率閾值邏輯一致
        // 靈敏度1.0(極寬鬆)時對應-5%靜止要求（放寬標準）
        // 靈敏度0.5(中性)時對應0%調整
        // 靈敏度0.0(極嚴謹)時對應+5%靜止要求（提高標準）
        let restingRatioAdjustment = -(limitedSensitivity * 0.1) + 0.05
        
        // 更新用戶檔案中的靜止比例調整值
        if var profile = currentUserProfile {
            profile.restingRatioAdjustment = restingRatioAdjustment
            userProfileManager.saveUserProfile(profile)
            currentUserProfile = profile
            
            // 記錄實際生效的靜止比例
            let effectiveRatio = profile.effectiveRestingRatioThreshold
            logger.info("靜止比例調整: \(String(format: "%.1f", restingRatioAdjustment * 100))% (有效比例: \(String(format: "%.1f", effectiveRatio * 100))%)")
        }
        
        logger.info("用戶調整了睡眠敏感度: \(limitedSensitivity)")
    }
    
    // 新增：設置用戶年齡組
    func setUserAgeGroup(_ ageGroup: AgeGroup) {
        userSelectedAgeGroup = ageGroup
        
        // 更新用戶配置文件
        let userId = getUserId()
        
        if var profile = currentUserProfile {
            // 更新現有配置文件
            profile = UserSleepProfile.createDefault(forUserId: userId, ageGroup: ageGroup)
            profile.manualAdjustmentOffset = userHRThresholdOffset // 保留用戶調整值
            userProfileManager.saveUserProfile(profile)
            currentUserProfile = profile
        } else {
            // 創建新配置文件
            let newProfile = UserSleepProfile.createDefault(forUserId: userId, ageGroup: ageGroup)
            userProfileManager.saveUserProfile(newProfile)
            currentUserProfile = newProfile
        }
        
        // 更新心率閾值
        updateHeartRateThreshold()
        
        logger.info("用戶設置了年齡組: \(String(describing: ageGroup))")
    }
    
    // 開始小睡
    func startNap() {
        guard !isNapping else { return }
        
        logger.info("開始小睡會話，設定時間: \(self.napDuration) 秒")
        
        // 開始記錄睡眠數據
        sleepLogger.startNewSession()
        
        // 高級日誌：啟動新會話並寫入sessionStart
        AdvancedLogger.shared.startNewSession()
        let thresholdPercent = (restingHeartRate > 0) ? (heartRateThreshold / restingHeartRate * 100) : 0
        AdvancedLogger.shared.log(.sessionStart, payload: [
            "rhr": .int(Int(restingHeartRate)),
            "thresholdPercent": .double(thresholdPercent),
            "thresholdBPM": .int(Int(heartRateThreshold)),
            "minDurationSeconds": .int(currentUserProfile?.minDurationSeconds ?? 180)
        ])
        
        // 追蹤本次 Session 的起始百分比與確認時間 (新增)
        sessionStartThresholdPercent = thresholdPercent
        sessionStartMinDuration = currentUserProfile?.minDurationSeconds
        
        // 更新狀態
        isNapping = true
        sleepPhase = .awake
        napPhase = .awaitingSleep
        startTime = Date()  // 這裡startTime暫時記錄為會話開始時間
        sleepStartTime = nil
        remainingTime = napDuration
        
        // 在啟動服務前更新心率閾值
        updateHeartRateThreshold()
        
        // 啟動計時器
        setupNapTimer()
        
        // 按順序啟動服務，確保依賴關係正確
        // 1. 首先啟動運行時服務
        runtimeManager.startSession()
        
        // 2. 然後啟動運動和姿勢監測
        motionManager.startMonitoring()
        
        // 3. 接著啟動心率服務
        heartRateService.startMonitoring()
        
        // 4. 啟動睡眠檢測服務
        sleepDetection.startMonitoring()
        
        // 5. 整合的睡眠服務
        sleepServices.startMonitoring()
        
        // 6. 最後啟動HealthKit會話
        workoutManager.startWorkoutSession()
    }
    
    // 停止小睡
    func stopNap() {
        guard isNapping else { return }
        
        logger.info("停止小睡會話")
        
        // 保存當前狀態，用於確定反饋類型
        let currentSleepPhase = sleepPhase
        let currentNapPhase = napPhase
        let hadStartedSleep = sleepStartTime != nil
        
        // 記錄最終的睡眠數據，無論是否檢測到睡眠
        recordFinalSleepData(
            detectedSleep: hadStartedSleep,
            sleepPhase: currentSleepPhase,
            napPhase: currentNapPhase
        )
        
        // 按相反順序停止服務
        // 1. 首先停止HealthKit會話
        workoutManager.stopWorkoutSession()
        
        // 2. 停止睡眠監測服務
        sleepServices.stopMonitoring()
        sleepDetection.stopMonitoring()
        
        // 3. 停止心率和運動監測
        heartRateService.stopMonitoring()
        motionManager.stopMonitoring()
        
        // 4. 最後停止運行時服務
        runtimeManager.stopSession()
        
        // 更新用戶配置文件
        updateUserProfileAfterSession()
        
        // 新增：更新收斂算法的會話計數
        let userId = getUserId()
        userProfileManager.incrementSessionsCount(forUserId: userId)
        
        // 停止計時器
        invalidateTimer()
        statsUpdateTimer?.invalidate()
        statsUpdateTimer = nil
        
        // 不在這裡結束 session，等用戶反饋後再結束
        
        // 新增：會話結束後嘗試優化閾值（由SleepServices內部決定是否執行）
        // 在SleepServices中已經實現在停止監測時嘗試優化閾值
        
        // 修改後的反饋提示顯示邏輯：只要啟動過小睡就顯示反饋
        // 延遲一秒顯示反饋提示，讓用戶有時間看到結果
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            if !self.showingFeedbackPrompt {
                self.showingFeedbackPrompt = true
                // 移除預設反饋類型，讓用戶根據實際情況自由選擇
                self.lastFeedbackType = .unknown
            }
        }
        
        // 更新狀態
        isNapping = false
        napPhase = .awaitingSleep
        
        logger.info("小睡會話已停止")
        stopAllTimers()
    }
    
    // 新增：記錄最終的睡眠數據，無論是否檢測到睡眠
    private func recordFinalSleepData(detectedSleep: Bool, sleepPhase: SleepPhase, napPhase: NapPhase) {
        // 從心率服務獲取趨勢數據
        let hrHistoryWindow = heartRateService.getHeartRateHistory(
            from: Date().addingTimeInterval(-300), // 過去5分鐘
            to: Date()
        )
        
        // 計算心率趨勢
        var hrTrendIndicator = 0.0
        if hrHistoryWindow.count >= 3 {
            // 分析最近的心率變化
            var downwardTrend = 0
            var upwardTrend = 0
            
            for i in 1..<hrHistoryWindow.count {
                let current = hrHistoryWindow[i].value
                let previous = hrHistoryWindow[i-1].value
                
                if current < previous - 1 { // 下降超過1 BPM
                    downwardTrend += 1
                    upwardTrend = 0
                } else if current > previous + 1 { // 上升超過1 BPM
                    upwardTrend += 1
                    downwardTrend = 0
                }
            }
            
            // 計算趨勢指標
            hrTrendIndicator = Double(upwardTrend - downwardTrend) / Double(hrHistoryWindow.count)
        }
        
        // 決定記錄的筆記內容，基於檢測到的情況
        var notes = ""
        
        if detectedSleep {
            // 情境1：系統正確檢測到睡眠 (真陽性)
            if napPhase == .sleeping || napPhase == .waking {
                notes = "情境1：系統成功檢測到睡眠 (真陽性)"
            }
        } else {
            // 根據睡眠階段來確定是哪種情境
            if sleepPhase == .awake || sleepPhase == .falling || sleepPhase == .light {
                // 情境4：用戶未入睡或只是輕度睡眠但未確認，系統正確未檢測 (真陰性)
                // 修正：將輕度睡眠(sleepPhase == .light)但未確認為睡眠(detectedSleep == false)的情況視為情境4
                notes = "情境4：系統正確未檢測到睡眠 (真陰性)"
            } else {
                // 情境2：用戶已達到深度睡眠，系統未檢測到 (假陰性)
                // 只有在深度或REM睡眠但系統未確認的情況下才視為漏報
                notes = "情境2：系統未成功檢測到睡眠 (假陰性)"
            }
        }
        
        // 計算會話持續時間 (目前未使用)
        _ = startTime != nil ? Date().timeIntervalSince(startTime!) : 0
        
        // 計算本次 session 的平均睡眠心率（入睡後）
        var avgSleepHR: Double? = nil
        if let sleepStart = sleepStartTime {
            let sleepHRs = hrHistoryWindow.filter { $0.timestamp >= sleepStart }.map { $0.value }
            if !sleepHRs.isEmpty {
                avgSleepHR = sleepHRs.reduce(0, +) / Double(sleepHRs.count)
            }
        }
        
        // 先計算 thresholdPercent，之後才能計算其他差值
        let thresholdPercent = (restingHeartRate > 0) ? (heartRateThreshold / restingHeartRate * 100) : 0
        
        // 新增：計算偏離百分比（deviationPercent）
        var deviationPercent: Double? = nil
        if let avg = avgSleepHR, restingHeartRate > 0 {
            deviationPercent = (avg - restingHeartRate) / restingHeartRate * 100
        }
        
        // 計算 delta（與 Session 開始值差）
        var deltaPercentShort: Double? = nil
        var deltaDurationShort: Int? = nil
        if let startPerc = sessionStartThresholdPercent {
            deltaPercentShort = thresholdPercent - startPerc
        }
        let currentMinDur = currentUserProfile?.minDurationSeconds ?? 0
        if let startDur = sessionStartMinDuration {
            deltaDurationShort = currentMinDur - startDur
        }
        
        // 記錄睡眠分析總結數據
        logger.info("記錄最終睡眠分析數據: 檢測到睡眠: \(detectedSleep), 分類: \(notes)")
        
        // === 新增：決定判定來源 detectSource ===
        let ratioValue = (avgSleepHR != nil && heartRateThreshold > 0) ? (avgSleepHR! / heartRateThreshold) : 1.0
        var detectSourceLocal = ""
        if ratioValue < 0.75 {
            detectSourceLocal = "滑動視窗"
        } else if hrTrendIndicator <= -0.20 && (avgSleepHR ?? 0) < restingHeartRate * 1.10 {
            detectSourceLocal = "trend"
        } else {
            detectSourceLocal = "ΔHR"
        }
        // 更新屬性，供其他流程使用
        self.detectSource = detectSourceLocal

        // 高級日誌：會話結束
        AdvancedLogger.shared.log(.sessionEnd, payload: [
            "detectedSleep": .bool(detectedSleep),
            "notes": .string(notes),
            "avgSleepHR": avgSleepHR != nil ? .double(avgSleepHR!) : .string("-"),
            "rhr": .double(restingHeartRate),
            "thresholdBPM": .double(heartRateThreshold),
            "thresholdPercent": .double(thresholdPercent),
            "deviationPercent": deviationPercent != nil ? .double(deviationPercent!) : .string("-"),
            "ratio": (avgSleepHR != nil && heartRateThreshold > 0) ? .double(avgSleepHR! / heartRateThreshold) : .string("-"),
            "deltaPercentShort": deltaPercentShort != nil ? .double(deltaPercentShort!) : .string("-"),
            "deltaDurationShort": deltaDurationShort != nil ? .int(deltaDurationShort!) : .string("-"),
            "trend": .double(hrTrendIndicator),
            "detectSource": .string(detectSourceLocal),
            "adjustmentSourceShort": .string("feedback"),
            "schemaVersion": .int(2)
        ])
        
        // 記錄到日誌文件
        sleepLogger.logSleepData(
            heartRate: currentHeartRate,
            restingHR: restingHeartRate,
            hrThreshold: heartRateThreshold,
            hrTrend: hrTrendIndicator,
            acceleration: currentAcceleration,
            isResting: isResting,
            isSleeping: isProbablySleeping,
            sleepPhase: sleepPhaseText,
            remainingTime: remainingTime,
            notes: "整合協調器檢測"
        )
        
        // 高級日誌：心率取樣
        AdvancedLogger.shared.log(.hr, payload: [
            "bpm": .double(currentHeartRate),
            "phase": .string(sleepPhaseText),
            "acc": .double(currentAcceleration)
        ])
    }
    
    // 設置小睡計時器
    private func setupNapTimer() {
        invalidateTimer()
        
        napTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self, self.isNapping else { return }
            
            // 根據休息階段執行不同的更新
            switch self.napPhase {
            case .awaitingSleep:
                // 等待入睡階段（現在主要依賴於SleepDetectionCoordinator來檢測）
                // 不需要額外調用checkSleepState，因為我們訂閱了協調器的狀態更新
                
                // 檢查是否超時，使用新的超時機制
                checkSleepWaitTimeout()
            
            case .sleeping:
                // 睡眠階段，更新倒計時
                if let sleepStartTime = self.sleepStartTime {
                    // 計算已經睡眠的時間
                    let elapsedSleepTime = Date().timeIntervalSince(sleepStartTime)
                    
                    // 獲取當前用戶的確認時間設定（秒）
                    let confirmationTime = Double(self.currentUserProfile?.minDurationSeconds ?? 180)
                    
                    // 計算實際的倒計時時間（總休息時間 - 確認時間，確保用戶獲得完整的設定休息時間）
                    // 新邏輯：從設定的napDuration中減去確認時間，這樣確認時間就算入了總休息時間
                    self.remainingTime = max(0, self.napDuration - elapsedSleepTime - confirmationTime)
                    
                    // 記錄睡眠數據
                    self.logSleepData()
                    
                    // 檢查是否時間到或符合智能喚醒條件
                    if self.remainingTime <= 0 || self.shouldWakeUpEarly() {
                        self.wakeUp()
                    }
                }
                
            case .waking:
                // 喚醒階段，不做特別處理
                break
            }
        }
    }
    
    // 記錄睡眠數據
    private func logSleepData() {
        // 從心率服務獲取趨勢數據
        let hrHistoryWindow = heartRateService.getHeartRateHistory(
            from: Date().addingTimeInterval(-300), // 過去5分鐘
            to: Date()
        )
        
        // 計算心率趨勢
        var hrTrendIndicator = 0.0
        if hrHistoryWindow.count >= 3 {
            // 分析最近的心率變化
            var downwardTrend = 0
            var upwardTrend = 0
            
            for i in 1..<hrHistoryWindow.count {
                let current = hrHistoryWindow[i].value
                let previous = hrHistoryWindow[i-1].value
                
                if current < previous - 1 { // 下降超過1 BPM
                    downwardTrend += 1
                    upwardTrend = 0
                } else if current > previous + 1 { // 上升超過1 BPM
                    upwardTrend += 1
                    downwardTrend = 0
                }
            }
            
            // 計算趨勢指標
            hrTrendIndicator = Double(upwardTrend - downwardTrend) / Double(hrHistoryWindow.count)
        }
        
        // 記錄到日誌文件
        sleepLogger.logSleepData(
            heartRate: currentHeartRate,
            restingHR: restingHeartRate,
            hrThreshold: heartRateThreshold,
            hrTrend: hrTrendIndicator,
            acceleration: currentAcceleration,
            isResting: isResting,
            isSleeping: isProbablySleeping,
            sleepPhase: sleepPhaseText,
            remainingTime: remainingTime,
            notes: "整合協調器檢測"
        )
    }
    
    // 喚醒功能
    private func wakeUp() {
        if napPhase == .waking { return }  // 避免重複喚醒
        
        logger.info("喚醒流程觸發")
        
        // 使用新的喚醒流程
        startWakeUpSequence()
        stopAllTimers()
    }
    
    // 取消計時器
    private func invalidateTimer() {
        napTimer?.invalidate()
        napTimer = nil
    }
    
    // 智能喚醒邏輯 - 根據睡眠階段決定最佳喚醒時間
    func shouldWakeUpEarly() -> Bool {
        // 暫時禁用智能喚醒功能
        return false
        
        /* 以下為原功能代碼，暫時註釋
        // 檢查是否達到最小睡眠時間
        guard let startTime = startTime else { return false }
        
        let elapsedTime = Date().timeIntervalSince(startTime)
        let minimumNapTime = napDuration * 0.8  // 至少完成80%設定時間
        
        if elapsedTime < minimumNapTime {
            return false  // 未達到最小休息時間，不應醒來
        }
        
        // 智能喚醒條件
        // 1. 處於輕度睡眠或REM階段 - 這些階段醒來感覺最好
        // 2. 心率開始自然上升 - 表示身體開始準備醒來
        // 3. 檢測到輕微運動 - 可能表示自然醒來過程開始
        
        let isLightOrREM = (sleepPhase == .light || sleepPhase == .rem)
        let isHRRising = heartRateService.currentHeartRate > heartRateThreshold * 1.05
        let hasSlightMovement = currentAcceleration > motionThreshold * 0.7 && currentAcceleration < motionThreshold * 1.2
        
        // 滿足以下條件之一時觸發智能喚醒
        let shouldWake = (isLightOrREM && isHRRising) || 
                         (isLightOrREM && hasSlightMovement) ||
                         (isHRRising && hasSlightMovement)
        
        if shouldWake {
            logger.info("智能喚醒條件滿足 - 睡眠階段: \(String(describing: self.sleepPhase)), 心率上升: \(isHRRising), 輕微運動: \(hasSlightMovement)")
        }
        
        return shouldWake
        */
    }
    
    // 新屬性 - 獲取當前睡眠階段的描述文本
    var sleepPhaseText: String {
        switch sleepPhase {
        case .awake:
            return "清醒"
        case .falling:
            return "即將入睡"
        case .light:
            return "輕度睡眠"
        case .deep:
            return "深度睡眠"
        case .rem:
            return "REM睡眠"
        }
    }
    
    // 會話結束後更新用戶配置文件
    private func updateUserProfileAfterSession() {
        let userId = getUserId()
        
        // 更新用戶配置文件中的統計數據
        userProfileManager.updateUserProfile(forUserId: userId, restingHR: restingHeartRate)
        
        // 重新加載用戶配置文件以獲取最新的設置
        loadUserProfile()
    }
    
    // 添加一個新方法來處理自動閾值優化
    private func checkForAutomaticThresholdOptimization(userId: String) {
        // 使用SleepServices的心率閾值優化器
        let optimizing = sleepServices.checkAndOptimizeThreshold()
        if optimizing {
            logger.info("已啟動自動心率閾值優化")
        }
        
        // 訂閱優化結果
        sleepServices.optimizationStatusPublisher
            .sink { [weak self] status in
                guard let self = self else { return }
                
                switch status {
                case .optimized(let result):
                    // 優化成功，通知用戶
                    self.logger.info("心率閾值已自動優化：\(String(format: "%.1f", result.previousThreshold * 100))% → \(String(format: "%.1f", result.newThreshold * 100))%")
                    // 高級日誌：參數優化
                    AdvancedLogger.shared.log(.optimization, payload: [
                        "oldThreshold": AdvancedLogger.CodableValue.double(result.previousThreshold),
                        "newThreshold": AdvancedLogger.CodableValue.double(result.newThreshold),
                        "adjustmentSourceLong": .string("optimization")
                    ])
                    // 當閾值發生變化時，我們接收到了變化值，但也需要更新自己的閾值記錄
                    self.refreshThresholdAfterOptimization(userId: userId)
                    
                case .failed(let error):
                    self.logger.warning("心率閾值優化失敗：\(error)")
                    
                default:
                    break
                }
            }
            .store(in: &cancellables)
    }
    
    // 添加一個刷新閾值的方法
    private func refreshThresholdAfterOptimization(userId: String) {
        // 重新獲取用戶配置，以取得最新的閾值設定
        if let profile = userProfileManager.getUserProfile(forUserId: userId) {
            // 更新 ViewModel 中的數據
            userHRThresholdOffset = profile.manualAdjustmentOffset
            
            // 更新當前閾值
            updateHeartRateThreshold()
            
            // 用戶配置可能也更新了
            currentUserProfile = profile
        }
    }
    
    // 處理用戶反饋
    func processFeedback(wasAccurate: Bool) {
        // 記錄用戶反饋
        lastFeedbackDate = Date()
        
        // 獲取用戶ID
        let userId = getUserId()
        
        if wasAccurate {
            // 用戶表示檢測準確
            lastFeedbackType = .accurate
            
            if var profile = userProfileManager.getUserProfile(forUserId: userId) {
                profile.accurateDetectionCount += 1
                userProfileManager.saveUserProfile(profile)
                logger.info("用戶反饋：檢測準確，累計次數：\(profile.accurateDetectionCount)")
                
                // 準確反饋不再調整確認時間，因為系統已經表現良好
            }
        } else {
            // 用戶表示檢測不準確
            
            // 根據當前睡眠狀態確定是哪種不準確類型
            if sleepPhase == .light || sleepPhase == .deep {
                // 誤報：系統認為用戶在睡眠狀態，但實際未入睡(過於寬鬆)
                lastFeedbackType = .falsePositive
                logger.info("用戶反饋：系統誤判為睡眠（過於寬鬆）")
                
                if !isSimulatingFeedback() {
                    // 應用不對稱用戶反饋機制 - 調整心率閾值
                    userProfileManager.adjustHeartRateThreshold(
                        forUserId: userId,
                        feedbackType: .falsePositive
                    )
                    
                    // 同時也調整確認時間
                    userProfileManager.adjustConfirmationTime(
                        forUserId: userId, 
                        direction: 1,  // 增加確認時間
                        fromFeedback: true
                    )
                }
            } else {
                // 漏報：系統認為用戶未睡眠，但實際已入睡(過於嚴謹)
                lastFeedbackType = .falseNegative
                logger.info("用戶反饋：系統未檢測到睡眠（過於嚴謹）")
                
                if !isSimulatingFeedback() {
                    // 應用不對稱用戶反饋機制 - 調整心率閾值
                    userProfileManager.adjustHeartRateThreshold(
                        forUserId: userId,
                        feedbackType: .falseNegative
                    )
                    
                    // 同時也調整確認時間
                    userProfileManager.adjustConfirmationTime(
                        forUserId: userId, 
                        direction: -1,  // 減少確認時間
                        fromFeedback: true
                    )
                }
            }
            
            // 將此反饋保存到用戶配置文件
            if var profile = userProfileManager.getUserProfile(forUserId: userId) {
                profile.inaccurateDetectionCount += 1
                userProfileManager.saveUserProfile(profile)
                logger.info("用戶反饋：檢測不準確，累計次數：\(profile.inaccurateDetectionCount)")
            }
            
            // 用戶反饋後刷新當前閾值
            refreshThresholdAfterOptimization(userId: userId)
        }
        
        // 不在這裡關閉反饋提示，由UI層控制關閉時機

        // 高級日誌：用戶反饋
        AdvancedLogger.shared.log(.feedback, payload: [
            "accurate": AdvancedLogger.CodableValue.bool(wasAccurate),
            "type": AdvancedLogger.CodableValue.string(String(describing: lastFeedbackType))
        ])

        // 高級日誌：會話結束（根據本次 session 狀態正確寫入 detectedSleep 與所有欄位）
        let detectedSleep = (sleepStartTime != nil)
        let hrHistoryWindow = heartRateService.getHeartRateHistory(
            from: Date().addingTimeInterval(-300),
            to: Date()
        )
        var avgSleepHR: Double? = nil
        if let sleepStart = sleepStartTime {
            let sleepHRs = hrHistoryWindow.filter { $0.timestamp >= sleepStart }.map { $0.value }
            if !sleepHRs.isEmpty {
                avgSleepHR = sleepHRs.reduce(0, +) / Double(sleepHRs.count)
            }
        }
        let thresholdPercentFB = (restingHeartRate > 0) ? (heartRateThreshold / restingHeartRate * 100) : 0
        
        // 計算偏離百分比、delta 變化量 (針對回饋時點)
        var deviationPercentFB: Double? = nil
        if let avg = avgSleepHR, restingHeartRate > 0 {
            deviationPercentFB = (avg - restingHeartRate) / restingHeartRate * 100
        }
        var deltaPercentShortFB: Double? = nil
        var deltaDurationShortFB: Int? = nil
        if let startPerc = sessionStartThresholdPercent {
            deltaPercentShortFB = thresholdPercentFB - startPerc
        }
        let currentMinDurFB = currentUserProfile?.minDurationSeconds ?? 0
        if let startDur = sessionStartMinDuration {
            deltaDurationShortFB = currentMinDurFB - startDur
        }
        
        // === 新增：計算心率趨勢與判定來源 detectSource ===
        var hrTrendIndicatorFB = 0.0
        if hrHistoryWindow.count >= 3 {
            var down = 0
            var up = 0
            for i in 1..<hrHistoryWindow.count {
                let cur = hrHistoryWindow[i].value
                let prev = hrHistoryWindow[i-1].value
                if cur < prev - 1 { down += 1; up = 0 }
                else if cur > prev + 1 { up += 1; down = 0 }
            }
            hrTrendIndicatorFB = Double(up - down) / Double(hrHistoryWindow.count)
        }
        let ratioFB = (avgSleepHR != nil && heartRateThreshold > 0) ? (avgSleepHR! / heartRateThreshold) : 1.0
        var detectSourceFB = ""
        if ratioFB < 0.75 {
            detectSourceFB = "滑動視窗"
        } else if hrTrendIndicatorFB <= -0.20 && (avgSleepHR ?? 0) < restingHeartRate * 1.10 {
            detectSourceFB = "trend"
        } else {
            detectSourceFB = "ΔHR"
        }
        self.detectSource = detectSourceFB

        AdvancedLogger.shared.log(.sessionEnd, payload: [
            "detectedSleep": AdvancedLogger.CodableValue.bool(detectedSleep),
            "notes": AdvancedLogger.CodableValue.string("用戶反饋後結束"),
            "avgSleepHR": avgSleepHR != nil ? .double(avgSleepHR!) : .string("-"),
            "rhr": .double(restingHeartRate),
            "thresholdBPM": .double(heartRateThreshold),
            "thresholdPercent": .double(thresholdPercentFB),
            "deviationPercent": deviationPercentFB != nil ? .double(deviationPercentFB!) : .string("-"),
            "ratio": .double(ratioFB),
            "deltaPercentShort": deltaPercentShortFB != nil ? .double(deltaPercentShortFB!) : .string("-"),
            "deltaDurationShort": deltaDurationShortFB != nil ? .int(deltaDurationShortFB!) : .string("-"),
            "trend": .double(hrTrendIndicatorFB),
            "detectSource": .string(detectSourceFB),
            "adjustmentSourceShort": .string("feedback"),
            "schemaVersion": .int(2)
        ])
        // 結束 session，寫入 csv
        sleepLogger.endSession(summary: "小睡會話已完成（用戶反饋後結束）")
        
        hasSubmittedFeedback = true
        stopAllTimers() // feedback 寫入後才關閉所有 timer
    }
    
    // 判斷是否正在模擬反饋(測試模式)
    private func isSimulatingFeedback() -> Bool {
        // 檢查是否是通過測試按鈕模擬的反饋
        return lastFeedbackType == .accurate && !isNapping ||
               lastFeedbackType == .falseNegative && !isNapping ||
               lastFeedbackType == .falsePositive && !isNapping
    }
    
    // MARK: - 測試反饋功能
    
    // 測試情境1：用戶入睡，系統正確檢測到
    func simulateScenario1Feedback() {
        // 模擬正確檢測到睡眠的情況
        sleepPhase = .deep
        napPhase = .sleeping
        isProbablySleeping = true
        
        // 顯示反饋提示
        showingFeedbackPrompt = true
        lastFeedbackType = .accurate
        
        logger.info("測試情境1：模擬系統正確檢測到睡眠")
        stopAllTimers()
    }
    
    // 測試情境2：用戶入睡，系統未檢測到
    func simulateScenario2Feedback() {
        // 模擬未檢測到睡眠的情況
        sleepPhase = .awake
        napPhase = .awaitingSleep
        isProbablySleeping = false
        
        // 顯示反饋提示，並設置反饋類型為未檢測到(過於嚴謹)
        showingFeedbackPrompt = true
        lastFeedbackType = .falseNegative
        
        logger.info("測試情境2：模擬系統未檢測到睡眠")
    }
    
    // 測試情境3：用戶未入睡，系統誤判為睡眠
    func simulateScenario3Feedback() {
        // 模擬誤判為睡眠的情況
        sleepPhase = .light
        napPhase = .sleeping
        isProbablySleeping = true
        
        // 顯示反饋提示，並設置反饋類型為誤判(過於寬鬆)
        showingFeedbackPrompt = true
        lastFeedbackType = .falsePositive
        
        logger.info("測試情境3：模擬系統誤判為睡眠")
        stopAllTimers()
    }
    
    // 測試情境4：用戶未入睡，系統正確未檢測
    func simulateScenario4Feedback() {
        // 模擬正確未檢測到睡眠的情況
        sleepPhase = .awake
        napPhase = .awaitingSleep
        isProbablySleeping = false
        
        // 顯示反饋提示
        showingFeedbackPrompt = true
        lastFeedbackType = .accurate
        
        logger.info("測試情境4：模擬系統正確未檢測到睡眠")
    }
    
    // 修改等待入睡超時時間為40分鐘
    private func checkSleepWaitTimeout() {
        if let startTime = self.startTime, Date().timeIntervalSince(startTime) > 40 * 60 {
            self.logger.info("等待入睡超時(40分鐘)，停止小睡")
            self.stopNap()
        }
    }
    
    // 鬧鈴停止後的處理
    private func handleAlarmStopped() {
        // 確保只執行一次
        guard !alarmStopped else { return }
        alarmStopped = true
        
        // 顯示反饋提示（如果適用）
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            // 只有在尚未顯示反饋提示時才顯示，避免重複
            if !self.showingFeedbackPrompt {
                // 顯示反饋提示，讓用戶評價睡眠檢測
                self.showingFeedbackPrompt = true
                
                // 移除預設反饋類型，讓用戶根據實際情況自由選擇
                // 不應自動預設為準確，因為可能是系統誤判
                self.lastFeedbackType = .unknown
                
                // 10秒後自動隱藏反饋提示
                DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
                    if self.showingFeedbackPrompt {
                        self.showingFeedbackPrompt = false
                    }
                }
            }
        }
        
        // 完全重置狀態，返回準備狀態
        isNapping = false
        sleepPhase = .awake
        napPhase = .awaitingSleep
        logger.info("喚醒流程完成，返回準備狀態")
        stopAllTimers()
    }
    
    // 啟動喚醒流程
    func startWakeUpSequence() {
        // 更新狀態
        napPhase = .waking
        showingAlarmStopUI = true
        alarmStopped = false
        
        // 發送喚醒通知（持續模式）
        notificationManager.sendWakeupNotification()
        
        // 訂閱鬧鈴狀態變化
        notificationManager.alarmStatePublisher
            .sink { [weak self] isActive in
                if !isActive {
                    // 鬧鈴已停止（可能是超時或用戶手動停止）
                    self?.handleAlarmStopped()
                }
            }
            .store(in: &cancellables)
        
        logger.info("喚醒流程已啟動，顯示關閉鬧鈴界面")
    }
    
    // 停止鬧鈴
    func stopAlarm() {
        notificationManager.stopContinuousAlarm()
        alarmStopped = true
        
        // 隱藏鬧鈴停止UI
        showingAlarmStopUI = false
        
        logger.info("用戶手動停止鬧鈴")
        
        // 後續流程處理
        handleAlarmStopped()
        stopAllTimers()
    }
    
    // 模擬計時結束
    func simulateTimerEnd() {
        logger.info("模擬計時結束")
        startWakeUpSequence()
        stopAllTimers()
    }
    
    // MARK: - 更新睡眠確認時間
    func updateSleepConfirmationTime(_ seconds: Int, disableLearning: Bool = true) {
        logger.info("更新睡眠確認時間: \(seconds) 秒")
        
        let userId = getUserId()
        
        if var profile = userProfileManager.getUserProfile(forUserId: userId) {
            // 更新確認時間
            profile.minDurationSeconds = seconds
            
            // 手動調整時，根據參數決定是否暫停自動收斂
            if disableLearning {
                profile.durationAdjustmentStopped = true
                logger.info("手動調整時已暫停自動收斂")
            }
            
            // 保存到用戶配置管理器
            userProfileManager.saveUserProfile(profile)
            
            // 更新當前用戶配置引用
            currentUserProfile = profile
            
            // 若當前正在進行監測，則需要更新閾值
            if isNapping {
                updateHeartRateThreshold()
            }
        }
    }
    
    // MARK: - 重置睡眠確認時間
    func resetSleepConfirmationTime() {
        logger.info("重置睡眠確認時間")
        
        let userId = getUserId()
        
        if var profile = userProfileManager.getUserProfile(forUserId: userId) {
            // 獲取該年齡組的默認值
            let defaultProfile = UserSleepProfile.createDefault(forUserId: userId, ageGroup: profile.ageGroup)
            
            // 重置確認時間到預設值
            profile.minDurationSeconds = defaultProfile.minDurationSeconds
            
            // 重新啟用自動收斂
            profile.durationAdjustmentStopped = false
            profile.consecutiveDurationAdjustments = 0
            profile.lastDurationAdjustmentDirection = 0
            profile.sessionsSinceLastDurationAdjustment = 0
            
            // 保存到用戶配置管理器
            userProfileManager.saveUserProfile(profile)
            
            // 更新當前用戶配置引用
            currentUserProfile = profile
            
            // 若當前正在進行監測，則需要更新閾值
            if isNapping {
                updateHeartRateThreshold()
            }
            
            logger.info("睡眠確認時間已重置為 \(profile.minDurationSeconds) 秒，並重新啟用智慧學習")
        }
    }
    
    // MARK: - 繼續智慧學習
    func continueSleepLearning() {
        logger.info("繼續智慧學習")
        
        let userId = getUserId()
        
        if var profile = userProfileManager.getUserProfile(forUserId: userId) {
            // 重新啟用自動收斂，但保留當前的確認時間值
            profile.durationAdjustmentStopped = false
            
            // 重置收斂狀態，但保留當前時間
            profile.consecutiveDurationAdjustments = 0
            profile.lastDurationAdjustmentDirection = 0
            profile.sessionsSinceLastDurationAdjustment = 0
            
            // 保存到用戶配置管理器
            userProfileManager.saveUserProfile(profile)
            
            // 更新當前用戶配置引用
            currentUserProfile = profile
            
            logger.info("基於當前設定值 \(profile.minDurationSeconds) 秒繼續智慧學習")
        }
    }
    
    // MARK: - 關閉智慧學習
    func disableSleepLearning() {
        logger.info("關閉智慧學習")
        
        let userId = getUserId()
        
        if var profile = userProfileManager.getUserProfile(forUserId: userId) {
            // 停止自動收斂，但保留當前的確認時間值
            profile.durationAdjustmentStopped = true
            
            // 保存到用戶配置管理器
            userProfileManager.saveUserProfile(profile)
            
            // 更新當前用戶配置引用
            currentUserProfile = profile
            
            logger.info("智慧學習已關閉，使用者設定保持在 \(profile.minDurationSeconds) 秒")
        }
    }
    
    // MARK: - 心率異常處理方法
    
    /// 評估並記錄心率異常
    /// - Parameters:
    ///   - heartRate: 當前心率
    ///   - expectedRange: 預期範圍
    private func evaluateHeartRateAnomaly(heartRate: Double, expectedRange: ClosedRange<Double>) {
        // 使用新的不對稱異常檢測邏輯
        
        // 如果心率在預期範圍內，不需要記錄異常
        if expectedRange.contains(heartRate) {
            return
        }
        
        // 計算預期心率（使用範圍的中間值作為參考點）
        let expectedHR = (expectedRange.lowerBound + expectedRange.upperBound) / 2.0
        
        // 使用不對稱異常檢測功能評估心率偏離
        let anomalyStatus = heartRateAnomalyTracker.evaluateHeartRateDeviation(
            heartRate: heartRate,
            expectedHR: expectedHR
        )
        
        // 更新UI中顯示的異常狀態
        heartRateAnomalyStatus = anomalyStatus
        
        // 處理異常狀態
        if anomalyStatus == .requiresReset {
            // 檢查是否需要重校準基線
            considerResetHeartRateBaseline()
        }
        
        // 記錄到日誌
        logger.info("心率異常評估 - 心率: \(heartRate), 預期範圍: \(expectedRange.lowerBound)-\(expectedRange.upperBound), 狀態: \(anomalyStatus.rawValue)")
    }
    
    /// 考慮重置心率基線
    private func considerResetHeartRateBaseline() {
        // 檢查是否需要重校準基線
        guard heartRateAnomalyStatus == .requiresReset else { return }
        
        // 檢查上次重置時間，避免頻繁重置
        if let lastReset = UserDefaults.standard.object(forKey: "LastHeartRateBaselineReset") as? Date {
            let daysSinceLastReset = Date().timeIntervalSince(lastReset) / (24 * 3600)
            if daysSinceLastReset < 3 {
                logger.info("距離上次心率基線重置未超過3天，暫不重置")
                return
            }
        }
        
        // 執行重置流程
        resetHeartRateBaseline()
    }
    
    /// 重置心率基線
    func resetHeartRateBaseline() {
        let userId = getUserId()
        guard var profile = userProfileManager.getUserProfile(forUserId: userId) else {
            return
        }
        
        // 1. 重置異常追蹤器
        heartRateAnomalyTracker.resetBaseline()
        
        // 2. 更新用戶配置
        // 將心率閾值設回適合當前年齡組的默認值
        let defaultThreshold = profile.ageGroup.heartRateThresholdPercentage
        profile.hrThresholdPercentage = defaultThreshold
        
        // 重置用戶手動調整
        profile.manualAdjustmentOffset = 0.0
        
        // 3. 更新本地狀態
        userHRThresholdOffset = 0.0
        
        // 4. 保存更新後的配置
        userProfileManager.saveUserProfile(profile)
        currentUserProfile = profile
        
        // 5. 重新計算心率閾值
        updateHeartRateThreshold()
        
        // 6. 記錄重置時間
        UserDefaults.standard.set(Date(), forKey: "LastHeartRateBaselineReset")
        
        logger.info("已重置心率基線，閾值恢復至年齡組默認值: \(defaultThreshold)")
    }
    
    // ... existing code ...
    
    // MARK: - 睡眠檢測相關
    
    /// 處理實時心率
    /// - Parameter heartRate: 當前心率
    func processHeartRate(_ heartRate: Double) {
        // ... existing code ...
        
        // 評估心率異常
        // 計算預期的心率範圍 (靜息心率的80%-120%)
        let expectedLower = restingHeartRate * 0.80
        let expectedUpper = restingHeartRate * 1.20
        
        evaluateHeartRateAnomaly(heartRate: heartRate, expectedRange: expectedLower...expectedUpper)
        
        // ... existing code ...
    }
    
    // ... existing code ...
    
    // 碎片化睡眠模式的函數
    func setFragmentedSleepMode(_ enabled: Bool) {
        fragmentedSleepMode = enabled
        
        // 更新用戶配置
        if var profile = userProfileManager.getUserProfile(forUserId: getUserId()) {
            profile.fragmentedSleepMode = enabled
            userProfileManager.saveUserProfile(profile)
            
            // 如果啟用了碎片化睡眠模式，調整確認時間
            if enabled {
                // 碎片化睡眠模式下縮短確認時間
                let reducedTime = min(profile.minDurationSeconds, 120) // 不低於120秒
                profile.minDurationSeconds = reducedTime
                userProfileManager.saveUserProfile(profile)
                logger.info("啟用碎片化睡眠模式，調整確認時間為\(reducedTime)秒")
            } else {
                // 恢復原始確認時間
                let ageGroup = profile.ageGroup
                let defaultTime: Int
                switch ageGroup {
                case .teen: defaultTime = 120
                case .adult: defaultTime = 180
                case .senior: defaultTime = 240
                }
                
                profile.minDurationSeconds = defaultTime
                userProfileManager.saveUserProfile(profile)
                logger.info("關閉碎片化睡眠模式，恢復確認時間為\(defaultTime)秒")
            }
        }
        
        logger.info("碎片化睡眠模式: \(enabled ? "開啟" : "關閉")")
    }
    
    func loadUserPreferences() {
        // 獲取用戶ID
        let userId = getUserId()
        
        // 獲取用戶配置
        if let profile = userProfileManager.getUserProfile(forUserId: userId) {
            // 更新本地狀態
            currentUserProfile = profile
            
            // 載入用戶手動心率閾值調整
            userHRThresholdOffset = profile.manualAdjustmentOffset
            
            // 載入碎片化睡眠模式
            fragmentedSleepMode = profile.fragmentedSleepMode
            
            // 更新心率閾值
            updateHeartRateThreshold()
            
            logger.info("已載入用戶設定：心率閾值調整 \(String(format: "%.1f", profile.manualAdjustmentOffset * 100))%, 碎片化睡眠模式 \(profile.fragmentedSleepMode ? "開啟" : "關閉")")
        } else {
            logger.info("未找到用戶設定，使用默認配置")
        }
    }
    
    // 強制觸發閾值優化（測試用）
    func forceOptimizeThreshold() {
        let userId = getUserId()
        checkForAutomaticThresholdOptimization(userId: userId)
    }
    
    // 真正強制優化（不經條件判斷）
    func forceReallyOptimizeThreshold() {
        SleepServices.shared.forceOptimizeThreshold()
    }
    
    /// 使用者完全未評價時寫入 noFeedback
    func recordNoFeedbackIfNeeded() {
        guard !hasSubmittedFeedback && showingFeedbackPrompt == false else { return }
        AdvancedLogger.shared.log(.feedback, payload: [
            "accurate": AdvancedLogger.CodableValue.string("null"),
            "type": AdvancedLogger.CodableValue.string("noFeedback")
        ])
    }
    
    /// 統一停止所有計時器，確保不殘留任何背景 timer
    private func stopAllTimers() {
        napTimer?.invalidate(); napTimer = nil
        statsUpdateTimer?.invalidate(); statsUpdateTimer = nil
        NotificationManager.shared.stopContinuousAlarm() // alarmTimer
        SleepDataLogger.shared.stopLoggingTimer()
        heartRateService.stopMonitoring() // 內部會停 sleepDetectionTimer、trendAnalysisTimer
        motionManager.stopMonitoring()    // 內部會停 updateTimer
        sleepDetectionCoordinator.stopMonitoring() // 內部會停 stateTransitionTimer
    }
}

// MARK: - PowerNapViewModel Extension for Nap Duration Validation
extension PowerNapViewModel {
    
    /// 獲取當前用戶的確認時間
    var currentConfirmationTimeSeconds: Int {
        return currentUserProfile?.minDurationSeconds ?? 180
    }
    
    /// 獲取最小可選睡眠時間（分鐘）
    var minimumNapDuration: Int {
        return MinimumNapDurationCalculator.calculateMinimumNapDuration(
            confirmationTimeSeconds: currentConfirmationTimeSeconds
        )
    }
    
    /// 獲取有效的睡眠時間選項範圍
    var validNapDurationRange: ClosedRange<Int> {
        return MinimumNapDurationCalculator.getValidNapDurationRange(
            confirmationTimeSeconds: currentConfirmationTimeSeconds
        )
    }
    
    /// 確保當前選擇的睡眠時間有效
    func ensureValidNapDuration() {
        let minDuration = minimumNapDuration
        
        // 如果當前選擇的時間小於最小允許時間，則自動調整
        if napMinutes < minDuration {
            napMinutes = minDuration
            napDuration = Double(minDuration) * 60
            
            // 記錄日誌
            logger.info("自動調整睡眠時間: 從 \(self.napMinutes) 分鐘調整為 \(minDuration) 分鐘，確保大於確認時間")
        }
    }
}

// MARK: - PowerNapViewModel Extension for Resetting All Parameters
extension PowerNapViewModel {
    
    /// 重置所有異常評分指標和累計數據
    /// 包括異常評分、累計分數、基線重置記錄等所有相關數據
    func resetAllAnomalyScores() {
        // 首先調用心率基線重置（已有的功能）
        resetHeartRateBaseline()
        
        // 直接清除UserDefaults中儲存的所有異常追蹤數據
        let defaults = UserDefaults.standard
        
        // 清除異常評分相關的所有數據
        let keysToRemove = [
            "HeartRateAnomalyScores",
            "HeartRateAnomalyCumulativeScore",
            "HeartRateAnomalyTemporaryCount",
            "HeartRateAnomalyPersistentCount",
            "HeartRateAnomalyUpwardCount",
            "HeartRateAnomalyDownwardCount",
            "HeartRateAnomalyBaselineResets",
            "HeartRateAnomalyLastResetDate"
        ]
        
        for key in keysToRemove {
            defaults.removeObject(forKey: key)
        }
        
        // 直接使用自身的heartRateAnomalyTracker而不是通過heartRateService
        heartRateAnomalyTracker.resetBaseline()
        
        // 確保異常狀態也被重置
        heartRateAnomalyStatus = .none
        
        logger.info("已重置所有異常評分指標和累計數據")
    }
} 