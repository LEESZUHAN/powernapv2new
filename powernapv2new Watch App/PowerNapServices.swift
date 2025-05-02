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
            
            // 更新當前加速度值
            DispatchQueue.main.async {
                self.currentAcceleration = absAcceleration
                // 發送通知以便UI更新
                NotificationCenter.default.post(name: NSNotification.Name("AccelerationUpdated"), object: nil, userInfo: ["acceleration": absAcceleration])
            }
            
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
        // 首先播放系統聲音（增強提示效果）
        WKInterfaceDevice.current().play(.notification)
        
        // 創建通知內容
        let content = UNMutableNotificationContent()
        content.title = "小睡結束"
        content.body = "是時候起來了！"
        // 使用預設聲音（確保有聲音）
        content.sound = UNNotificationSound.defaultCritical
        content.categoryIdentifier = "WAKEUP"
        
        // 設置通知為高優先級
        content.interruptionLevel = .critical
        content.relevanceScore = 1.0
        
        // 立即觸發通知（不延遲）
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)
        
        // 創建請求
        let request = UNNotificationRequest(
            identifier: "wakeupNotification-\(Date().timeIntervalSince1970)",
            content: content,
            trigger: trigger
        )
        
        // 添加請求到通知中心
        UNUserNotificationCenter.current().add(request) { [weak self] error in
            guard let self = self else { return }
            
            if let error = error {
                self.logger.error("無法發送喚醒通知: \(error.localizedDescription)")
            } else {
                self.logger.info("成功安排喚醒通知")
                
                // 連續震動3次，模擬3-2-1倒數效果
                self.playSeriesOfVibrations()
            }
        }
        #endif
    }
    
    // 連續震動3次，模擬3-2-1倒數
    private func playSeriesOfVibrations() {
        #if os(watchOS)
        // 第一次震動
        WKInterfaceDevice.current().play(.success)
        
        // 延遲1秒後第二次震動
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            WKInterfaceDevice.current().play(.success)
            
            // 再延遲1秒播放第三次震動
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                WKInterfaceDevice.current().play(.start)
            }
        }
        #endif
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
    
    init() {
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
        
        // 啟動計時器
        setupNapTimer()
        
        // 啟動服務
        workoutManager.startWorkoutSession()
        runtimeManager.startSession()
        
        // 使用新的SleepServices代替直接啟動舊的服務
        sleepServices.startMonitoring()
        
        // 保留舊服務以保持兼容性，之後可以移除
        sleepDetection.startMonitoring()
        motionManager.startMonitoring()
        heartRateService.startMonitoring()
    }
    
    // 停止小睡
    func stopNap() {
        guard isNapping else { return }
        
        logger.info("停止小睡會話")
        
        // 生成會話摘要
        let sessionDuration = startTime != nil ? Date().timeIntervalSince(startTime!) : 0
        let summary = """
        會話持續時間: \(Int(sessionDuration))秒
        最終睡眠階段: \(sleepPhaseText)
        平均心率: \(Int(currentHeartRate))
        靜息心率: \(Int(restingHeartRate))
        心率閾值: \(Int(heartRateThreshold))
        """
        
        // 結束記錄
        sleepLogger.endSession(summary: summary)
        
        // 更新狀態
        isNapping = false
        sleepPhase = .awake
        invalidateTimer()
        
        // 停止服務
        workoutManager.stopWorkoutSession()
        runtimeManager.stopSession()
        
        // 使用新的SleepServices代替直接停止舊的服務
        sleepServices.stopMonitoring()
        
        // 保留舊服務以保持兼容性，之後可以移除
        sleepDetection.stopMonitoring()
        motionManager.stopMonitoring()
        heartRateService.stopMonitoring()
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
                
                // 如果設定了最大等待時間（例如20分鐘），可以在這裡檢查是否超時
                // 檢查是否已經等待太久（30分鐘）
                if let startTime = self.startTime, Date().timeIntervalSince(startTime) > 30 * 60 {
                    self.logger.info("等待入睡超時，停止小睡")
                    self.stopNap()
                }
                
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
        
        logger.info("智能喚醒觸發")
        napPhase = .waking
        
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
} 