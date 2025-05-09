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
        // 設計一個節奏感強的通知序列，每個節拍包含2-3個通知
        
        // 第一節拍（15秒）
        sendNotificationWithDelay(4, identifier: "beat1-1")
        sendNotificationWithDelay(7, identifier: "beat1-2")
        sendNotificationWithDelay(10, identifier: "beat1-3")
        sendNotificationWithDelay(15, identifier: "beat1-4")
        
        // 第二節拍（30秒）
        sendNotificationWithDelay(30, identifier: "beat2-1")
        sendNotificationWithDelay(32, identifier: "beat2-2")
        sendNotificationWithDelay(35, identifier: "beat2-3")
        
        // 第三節拍（45秒）
        sendNotificationWithDelay(45, identifier: "beat3-1")
        sendNotificationWithDelay(47, identifier: "beat3-2")
        sendNotificationWithDelay(50, identifier: "beat3-3")
        
        // 一分鐘提醒（更強烈）
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
        guard let logFilePath = logFilePath else { return }
        
        // 格式化數據行
        let timestamp = Date()
        let dateString = dateFormatter.string(from: timestamp)
        
        let dataLine = "\(dateString),\(heartRate),\(restingHR),\(hrThreshold),\(hrTrend),\(acceleration),\(isResting),\(isSleeping),\(sleepPhase),\(remainingTime),\"\(notes)\"\n"
        
        // 追加到文件
        if let fileHandle = try? FileHandle(forWritingTo: logFilePath) {
            fileHandle.seekToEndOfFile()
            if let data = dataLine.data(using: .utf8) {
                fileHandle.write(data)
            }
            fileHandle.closeFile()
        } else {
            // 如果無法打開文件，嘗試創建新文件
            try? dataLine.write(to: logFilePath, atomically: true, encoding: .utf8)
        }
    }
    
    // 結束記錄會話
    func endSession(summary: String) {
        guard let logFilePath = logFilePath else { return }
        
        // 添加會話總結
        let summaryLine = "\n--- 會話結束 ---\n\(summary)\n"
        
        if let fileHandle = try? FileHandle(forWritingTo: logFilePath) {
            fileHandle.seekToEndOfFile()
            if let data = summaryLine.data(using: .utf8) {
                fileHandle.write(data)
            }
            fileHandle.closeFile()
            
            print("睡眠數據記錄已完成，保存至: \(logFilePath.lastPathComponent)")
        }
        
        // 重置會話變量
        sessionId = nil
        self.logFilePath = nil
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
    
    // MARK: - 喚醒UI控制相關
    @Published var showingAlarmStopUI: Bool = false // 控制是否顯示鬧鈴停止界面
    @Published var alarmStopped: Bool = false // 鬧鈴是否已停止
    
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
    }
    
    deinit {
        statsUpdateTimer?.invalidate()
        NotificationCenter.default.removeObserver(self)
        cancellables.forEach { $0.cancel() }
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
        
        // 直接計算最終閾值
        let finalThreshold = restingHeartRate * targetPercentage * (1 + sensitivityAdjustment)
        
        // 更新UI顯示的閾值
        heartRateThreshold = finalThreshold
        
        // 更新心率服務中的閾值
        heartRateService.setCustomHeartRateThreshold(finalThreshold)
        
        // 計算並記錄實際的閾值百分比(相對於RHR)
        let actualPercentage = (finalThreshold / restingHeartRate) * 100
        let basePercentage = targetPercentage * 100
        
        logger.info("更新心率閾值: \(finalThreshold) BPM (目標百分比: \(String(format: "%.1f", basePercentage))%, 敏感度調整: \(sensitivityAdjustment), 實際百分比: \(String(format: "%.1f", actualPercentage))%)")
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
        
        // 更新狀態
        isNapping = false
        napPhase = .awaitingSleep
        sleepPhase = .awake
        
        // 保存會話數據
        sleepLogger.endSession(summary: "小睡會話已完成")
        
        // 新增：會話結束後嘗試優化閾值（由SleepServices內部決定是否執行）
        // 在SleepServices中已經實現在停止監測時嘗試優化閾值
        
        // 檢查是否應該顯示反饋提示
        // 只有當用戶實際開始了睡眠監測，且時間超過一定閾值才顯示
        if sleepStartTime != nil || napPhase != .awaitingSleep {
            // 延遲一秒顯示反饋提示，讓用戶有時間看到結果
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                self.showingFeedbackPrompt = true
                
                // 10秒後自動隱藏反饋提示
                DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
                    if self.showingFeedbackPrompt {
                        self.showingFeedbackPrompt = false
                    }
                }
            }
        }
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
                
                /* 舊的超時檢查邏輯，替換為新方法
                // 檢查是否已經等待太久（30分鐘）
                if let startTime = self.startTime, Date().timeIntervalSince(startTime) > 30 * 60 {
                    self.logger.info("等待入睡超時，停止小睡")
                    self.stopNap()
                }
                */
                
            case .sleeping:
                // 睡眠階段，更新倒計時
                if let sleepStartTime = self.sleepStartTime {
                    // 計算已經睡眠的時間
                    let elapsedSleepTime = Date().timeIntervalSince(sleepStartTime)
    
    // 更新剩餘時間
                    self.remainingTime = max(0, self.napDuration - elapsedSleepTime)
                    
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
                
                // 應用收斂算法 - 增加確認時間(除非是測試情境)
                if !isSimulatingFeedback() {
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
                
                // 應用收斂算法 - 減少確認時間(除非是測試情境)
                if !isSimulatingFeedback() {
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
        }
        
        // 不在這裡關閉反饋提示，由UI層控制關閉時機
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
            // 顯示反饋提示，讓用戶評價睡眠檢測
            self.showingFeedbackPrompt = true
            
            // 10秒後自動隱藏反饋提示
            DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
                if self.showingFeedbackPrompt {
                    self.showingFeedbackPrompt = false
                }
            }
        }
        
        // 完全重置狀態，返回準備狀態
        isNapping = false
        sleepPhase = .awake
        napPhase = .awaitingSleep
        logger.info("喚醒流程完成，返回準備狀態")
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
    }
    
    // 模擬計時結束
    func simulateTimerEnd() {
        logger.info("模擬計時結束")
        startWakeUpSequence()
    }
    
    // MARK: - 更新睡眠確認時間
    func updateSleepConfirmationTime(_ seconds: Int) {
        logger.info("更新睡眠確認時間: \(seconds) 秒")
        
        let userId = getUserId()
        
        if var profile = userProfileManager.getUserProfile(forUserId: userId) {
            // 更新確認時間
            profile.minDurationSeconds = seconds
            
            // 手動調整時，暫停自動收斂
            profile.durationAdjustmentStopped = true
            
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
} 