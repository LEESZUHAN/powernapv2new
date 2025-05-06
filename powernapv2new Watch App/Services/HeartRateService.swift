import Foundation
import HealthKit
import Combine
import os

// 泛型版滑動窗口，用於心率數據分析
class HeartRateWindow {
    private var values: [Double] = []
    private let capacity: Int
    
    var items: [Double] { return values }
    var isEmpty: Bool { return values.isEmpty }
    
    init(capacity: Int) {
        self.capacity = capacity
    }
    
    func add(_ value: Double) {
        values.append(value)
        if values.count > capacity {
            values.removeFirst()
        }
    }
    
    func average() -> Double {
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Double(values.count)
    }
}

/// 確保HeartRateService使用正確的共享類型
/// 注意：所有共享類型定義在 SharedTypes.swift 中
class HeartRateService: HeartRateServiceProtocol {
    // MARK: - 公開屬性
    @Published private(set) var currentHeartRate: Double = 0
    @Published private(set) var restingHeartRate: Double = 60
    @Published private(set) var heartRateThreshold: Double = 54
    @Published private(set) var isProbablySleeping: Bool = false
    @Published private(set) var heartRateTrend: Double = 0.0 // 心率趨勢指標：正值=上升，負值=下降，0=穩定
    
    var heartRatePublisher: Published<Double>.Publisher { $currentHeartRate }
    var restingHeartRatePublisher: Published<Double>.Publisher { $restingHeartRate }
    var isProbablySleepingPublisher: Published<Bool>.Publisher { $isProbablySleeping }
    var heartRateTrendPublisher: Published<Double>.Publisher { $heartRateTrend } // 新增趨勢發布者
    
    // MARK: - 私有屬性
    private let healthStore = HKHealthStore()
    private var heartRateQuery: HKAnchoredObjectQuery?
    private var restingHeartRateQuery: HKQuery?
    private var heartRateObserver: AnyCancellable?
    private var sleepDetectionTimer: Timer?
    private var trendAnalysisTimer: Timer? // 新增趨勢分析計時器
    private var heartRateWindow = HeartRateWindow(capacity: 10)
    private var samplingFrequency: TimeInterval = 5
    private var heartRateHistory: [HeartRateAnalysisData] = []
    private var ageGroup: AgeGroup = .adult
    private var isMonitoring = false
    private let logger = Logger(subsystem: "com.yourdomain.powernapv2new", category: "HeartRateService")
    
    // 睡眠會話相關
    private var currentSleepSession: SleepSession?
    private var userId: String = UUID().uuidString // 為每個用戶創建一個唯一ID
    private var userProfile: UserSleepProfile?
    
    // MARK: - 初始化
    init() {
        setupHealthKit()
        fetchRestingHeartRate()
        detectUserAge { [weak self] age in
            guard let self = self else { return }
            let group = AgeGroup.forAge(age)
            self.ageGroup = group
            
            // 設置或更新用戶檔案
            self.initializeUserProfile(ageGroup: group)
            
            self.calculateHeartRateThreshold(for: group)
            print("獲取到用戶年齡: \(age)")
        }
    }
    
    // 初始化或更新用戶睡眠檔案
    private func initializeUserProfile(ageGroup: AgeGroup) {
        // 檢查是否有現有檔案
        if let profile = UserSleepProfileManager.shared.getUserProfile(forUserId: userId) {
            userProfile = profile
            
            // 使用用戶檔案中的閾值
            heartRateThreshold = restingHeartRate * profile.adjustedThresholdPercentage
            logger.info("加載用戶檔案：閾值百分比 \(profile.adjustedThresholdPercentage)")
        } else {
            // 創建新檔案
            userProfile = UserSleepProfile.createDefault(forUserId: userId, ageGroup: ageGroup)
            if let profile = userProfile {
                UserSleepProfileManager.shared.saveUserProfile(profile)
                logger.info("創建新用戶檔案：閾值百分比 \(profile.adjustedThresholdPercentage)")
            }
        }
        
        // 更新用戶檔案（會檢查是否需要優化）
        DispatchQueue.global(qos: .background).async {
            UserSleepProfileManager.shared.updateUserProfile(forUserId: self.userId, restingHR: self.restingHeartRate)
        }
    }
    
    // MARK: - 公開方法
    func startMonitoring() {
        guard !isMonitoring else { return }
        isMonitoring = true
        
        // 開始心率查詢
        startHeartRateQuery()
        
        // 創建新的睡眠會話
        currentSleepSession = SleepSession.create(userId: userId)
        
        // 設置定時檢測
        sleepDetectionTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            self?.analyzeHeartRateForSleep()
        }
        
        // 啟動趨勢分析計時器 - 每30秒分析一次
        trendAnalysisTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.calculateHeartRateTrend()
        }
    }
    
    func stopMonitoring() {
        guard isMonitoring else { return }
        isMonitoring = false
        
        // 停止心率查詢
        if let query = heartRateQuery {
            healthStore.stop(query)
            heartRateQuery = nil
        }
        
        // 停止定時器
        sleepDetectionTimer?.invalidate()
        sleepDetectionTimer = nil
        
        // 停止趨勢分析計時器
        trendAnalysisTimer?.invalidate()
        trendAnalysisTimer = nil
        
        // 完成當前睡眠會話並保存
        if let session = currentSleepSession {
            let completedSession = session.completing()
            UserSleepProfileManager.shared.saveSleepSession(completedSession)
            currentSleepSession = nil
            logger.info("睡眠會話已完成並保存")
        }
    }
    
    func calculateHeartRateThreshold(for ageGroup: AgeGroup) {
        // 使用基於年齡組的默認閾值
        self.heartRateThreshold = self.restingHeartRate * ageGroup.heartRateThresholdPercentage
        logger.info("使用基於年齡組的默認閾值：\(self.heartRateThreshold) (RHR \(self.restingHeartRate) × \(ageGroup.heartRateThresholdPercentage))")
    }
    
    /// 設置自定義心率閾值
    /// - Parameter threshold: 新的心率閾值
    func setCustomHeartRateThreshold(_ threshold: Double) {
        // 確保閾值在合理範圍內
        let minSafeThreshold = self.restingHeartRate * 0.7 // 不低於RHR的70%
        let maxSafeThreshold = self.restingHeartRate * 0.95 // 不高於RHR的95%
        
        let safeThreshold = min(max(threshold, minSafeThreshold), maxSafeThreshold)
        
        self.heartRateThreshold = safeThreshold
        logger.info("設置自定義心率閾值：\(safeThreshold) BPM")
    }
    
    func getHeartRateHistory(from: Date, to: Date) -> [HeartRateAnalysisData] {
        return heartRateHistory.filter { 
            $0.timestamp >= from && $0.timestamp <= to 
        }
    }
    
    /// 使用當前心率數據和動作狀態檢查是否符合睡眠條件
    /// - Parameter motionState: 從動作服務獲取的靜止狀態
    /// - Returns: 是否可能處於睡眠狀態
    public func checkSleepCondition(motionState: Bool) -> Bool {
        // 如果動作不符合靜止條件，直接返回否
        if !motionState {
            return false
        }
        
        // 檢查心率是否低於閾值
        let isBelowThreshold = currentHeartRate < heartRateThreshold
        
        // 檢查是否有顯著心率下降
        let hasHeartRateDecrease = checkSignificantHeartRateDecrease()
        
        // 心率趨勢分析
        let trendDirection = heartRateTrend
        let isDownwardTrend = trendDirection < -0.5 // 下降趨勢
        
        // 增強型睡眠檢測邏輯：
        // 1. 心率低於閾值 -- 基本條件
        // 2. 明顯心率下降 -- ΔHR機制
        // 3. 心率呈下降趨勢 -- 趨勢分析
        
        // 滿足以下條件之一即可能是睡眠狀態：
        // - 心率顯著低於閾值（強睡眠信號）
        // - 心率輕微低於閾值且有顯著下降或下降趨勢（組合信號）
        let strongSignal = currentHeartRate < (heartRateThreshold - 5) 
        let combinedSignal = isBelowThreshold && (hasHeartRateDecrease || isDownwardTrend)
        
        self.isProbablySleeping = strongSignal || combinedSignal
        
        // 記錄決策過程
        if self.isProbablySleeping {
            logger.info("可能處於睡眠狀態: HR=\(self.currentHeartRate), 閾值=\(self.heartRateThreshold), 下降=\(hasHeartRateDecrease), 趨勢=\(trendDirection)")
        }
        
        return self.isProbablySleeping
    }
    
    // 計算心率趨勢指標並返回 - 新增的公開方法
    func calculateAndGetHeartRateTrend() -> Double {
        calculateHeartRateTrend()
        return heartRateTrend
    }
    
    // MARK: - 私有方法
    
    // 計算中位數心率 - 新增函數
    private func calculateMedianHeartRate(_ samples: [Double]) -> Double {
        guard !samples.isEmpty else { return 0 }
        
        let sortedSamples = samples.sorted()
        let mid = sortedSamples.count / 2
        
        if sortedSamples.count % 2 == 0 {
            // 偶數個樣本：取中間兩個值的平均
            return (sortedSamples[mid-1] + sortedSamples[mid]) / 2
        } else {
            // 奇數個樣本：取中間值
            return sortedSamples[mid]
        }
    }
    
    private func setupHealthKit() {
        // 定義需要訪問的類型
        let typesToRead: Set<HKObjectType> = [
            HKObjectType.quantityType(forIdentifier: .heartRate)!,
            HKObjectType.quantityType(forIdentifier: .restingHeartRate)!
        ]
        
        // 請求授權
        healthStore.requestAuthorization(toShare: nil, read: typesToRead) { success, error in
            if let error = error {
                print("HealthKit授權錯誤: \(error.localizedDescription)")
                return
            }
            
            if success {
                print("HealthKit授權成功")
                DispatchQueue.main.async {
                    self.fetchRestingHeartRate()
                }
            } else {
                print("HealthKit授權被拒絕")
            }
        }
    }
    
    private func startHeartRateQuery() {
        // 確保我們可以訪問心率數據
        guard let heartRateType = HKObjectType.quantityType(forIdentifier: .heartRate) else {
            print("無法訪問心率數據類型")
            return
        }
        
        // 設置心率查詢
        let predicate = HKQuery.predicateForSamples(withStart: Date(), end: nil, options: .strictStartDate)
        
        // 創建anchoredObjectQuery以接收心率更新
        let heartRateQuery = HKAnchoredObjectQuery(
            type: heartRateType,
            predicate: predicate,
            anchor: nil,
            limit: HKObjectQueryNoLimit
        ) { [weak self] (_, samples, _, _, error) in
            guard let self = self else { return }
            
            if let error = error {
                print("心率查詢錯誤: \(error.localizedDescription)")
                return
            }
            
            self.processHeartRateSamples(samples)
        }
        
        // 使用observer query來獲取實時更新
        let observerQuery = HKObserverQuery(sampleType: heartRateType, predicate: predicate) { [weak self] (_, completionHandler, error) in
            guard let self = self else {
                completionHandler()
                return
            }
            
            if let error = error {
                print("心率觀察者錯誤: \(error.localizedDescription)")
                completionHandler()
                return
            }
            
            // 執行查詢來獲取最新數據
            let query = HKSampleQuery(
                sampleType: heartRateType,
                predicate: predicate,
                limit: 10,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)]
            ) { (_, samples, error) in
                if let error = error {
                    print("心率樣本查詢錯誤: \(error.localizedDescription)")
                } else {
                    self.processHeartRateSamples(samples)
                }
                completionHandler()
            }
            
            self.healthStore.execute(query)
        }
        
        // 啟動查詢
        healthStore.execute(heartRateQuery)
        healthStore.execute(observerQuery)
        
        // 保存查詢引用以便後續停止
        self.heartRateQuery = heartRateQuery
    }
    
    private func processHeartRateSamples(_ samples: [HKSample]?) {
        guard let heartRateSamples = samples as? [HKQuantitySample] else {
            return
        }
        
        // 添加過濾邏輯，減少樣本處理次數
        let filteredSamples: [HKQuantitySample]
        if heartRateSamples.count > 3 {
            // 如果樣本超過3個，只取最新的3個
            filteredSamples = Array(heartRateSamples.suffix(3))
        } else {
            filteredSamples = heartRateSamples
        }
        
        // 收集心率值用於計算中位數
        var heartRateValues: [Double] = []
        for sample in filteredSamples {
            let hr = sample.quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
            heartRateValues.append(hr)
            
            // 記錄原始心率值到日誌
            logger.info("檢測到心率: \(hr)")
        }
        
        // 如果有足夠的樣本，計算中位數並更新
        if !heartRateValues.isEmpty {
            DispatchQueue.main.async {
                // 計算中位數心率
                let medianHR = self.calculateMedianHeartRate(heartRateValues)
                
                // 更新當前心率為中位數值
                self.currentHeartRate = medianHR
                self.heartRateWindow.add(medianHR)
                
                // 將中位數心率數據添加到歷史記錄
                let data = HeartRateAnalysisData(
                    timestamp: Date(),
                    value: medianHR,
                    isResting: medianHR <= self.restingHeartRate * 1.2 // 簡單判斷是否為靜息
                )
                
                self.heartRateHistory.append(data)
                
                // 限制歷史記錄大小以節省內存
                if self.heartRateHistory.count > 1000 {
                    self.heartRateHistory.removeFirst(100)
                }
                
                // 如果有多個樣本且值不同，輸出中位數計算結果
                if heartRateValues.count > 1 && Set(heartRateValues).count > 1 {
                    self.logger.info("中位數心率計算: \(heartRateValues) -> \(medianHR)")
                }
                
                // 更新當前睡眠會話的心率數據
                if let session = self.currentSleepSession {
                    self.currentSleepSession = session.addingHeartRate(medianHR)
                }
            }
        }
    }
    
    private func fetchRestingHeartRate() {
        guard let restingHRType = HKObjectType.quantityType(forIdentifier: .restingHeartRate) else {
            return
        }
        
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        let query = HKSampleQuery(sampleType: restingHRType, predicate: nil, limit: 5, sortDescriptors: [sortDescriptor]) { [weak self] _, samples, error in
            guard let self = self, let samples = samples as? [HKQuantitySample], !samples.isEmpty else {
                if let error = error {
                    print("獲取靜息心率錯誤: \(error.localizedDescription)")
                }
                return
            }
            
            // 計算最近5個測量值的平均值
            let total = samples.reduce(0.0) { sum, sample in
                return sum + sample.quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
            }
            
            let average = total / Double(samples.count)
            
            DispatchQueue.main.async {
                self.restingHeartRate = average
                self.calculateHeartRateThreshold(for: self.ageGroup)
                print("獲取到用戶平均靜息心率: \(average)")
            }
        }
        
        healthStore.execute(query)
    }
    
    private func detectUserAge(completion: @escaping (Int) -> Void) {
        do {
            let birthdayComponents = try healthStore.dateOfBirthComponents()
            let now = Date()
            let calendar = Calendar.current
            let nowComponents = calendar.dateComponents([.year], from: now)
            
            if let birthYear = birthdayComponents.year, let currentYear = nowComponents.year {
                let age = currentYear - birthYear
                completion(age)
            } else {
                // 默認年齡
                completion(35)
            }
        } catch {
            print("無法獲取用戶年齡: \(error.localizedDescription)")
            // 使用默認年齡
            completion(35)
        }
    }
    
    // 心率趨勢分析 - 優化方法
    private func calculateHeartRateTrend() {
        // 獲取過去5分鐘的心率歷史
        let fiveMinutesAgo = Date().addingTimeInterval(-300) // 5分鐘 = 300秒
        let recentHistory = heartRateHistory.filter { 
            $0.timestamp >= fiveMinutesAgo 
        }.sorted { $0.timestamp < $1.timestamp }
        
        // 確保有足夠的樣本進行分析
        guard recentHistory.count >= 3 else {
            heartRateTrend = 0.0 // 沒有足夠數據，設為中性值
            return
        }
        
        // 使用加權線性回歸分析心率趨勢
        var sumX = 0.0
        var sumY = 0.0
        var sumXY = 0.0
        var sumX2 = 0.0
        var weights = 0.0
        
        // 獲取基準時間點
        let startTimestamp = recentHistory[0].timestamp.timeIntervalSince1970
        
        for (i, sample) in recentHistory.enumerated() {
            // 使用時間作為x軸，心率作為y軸
            let x = sample.timestamp.timeIntervalSince1970 - startTimestamp // 相對時間(秒)
            let y = sample.value // 心率值
            
            // 使用越新的樣本權重越高
            let weight = 1.0 + Double(i) * 0.2 // 權重從1開始，每個後續樣本增加0.2
            
            // 加權累加
            sumX += x * weight
            sumY += y * weight
            sumXY += x * y * weight
            sumX2 += x * x * weight
            weights += weight
        }
        
        // 計算加權平均
        let meanX = sumX / weights
        let meanY = sumY / weights
        
        // 計算斜率(趨勢)
        let slope = (sumXY - sumX * meanY) / (sumX2 - sumX * meanX)
        
        // 標準化斜率為[-1,1]範圍的趨勢指標
        // 心率每分鐘變化2bpm作為一個基準單位
        let normalizedSlope = slope * 30.0 / 2.0 // 30秒內變化，換算成每分鐘
        let boundedSlope = max(min(normalizedSlope, 1.0), -1.0) // 限制在[-1,1]範圍內
        
        // 更新趨勢值
        DispatchQueue.main.async {
            self.heartRateTrend = boundedSlope
            
            // 記錄趨勢變化的日誌
            let trendDescription: String
            if boundedSlope > 0.2 {
                trendDescription = "明顯上升"
            } else if boundedSlope < -0.2 {
                trendDescription = "明顯下降"
            } else if boundedSlope > 0 {
                trendDescription = "輕微上升"
            } else if boundedSlope < 0 {
                trendDescription = "輕微下降"
            } else {
                trendDescription = "穩定"
            }
            
            self.logger.info("心率趨勢分析: \(boundedSlope) (\(trendDescription))")
        }
    }
    
    // 心率分析 - 優化方法
    private func analyzeHeartRateForSleep() {
        guard !heartRateWindow.isEmpty else { return }
        
        // 獲取最新心率
        let currentHR = heartRateWindow.items.last!
        
        // 判斷初始條件
        let wasAlreadySleeping = isProbablySleeping
        let now = Date()
        
        // 1. 基本閾值檢查 - 心率低於計算的閾值
        let belowThreshold = currentHR <= self.heartRateThreshold
        
        // 2. ΔHR輔助判定 - 即使未低於標準閾值，但有顯著心率下降
        let hrDecreasing = checkSignificantHeartRateDecrease()
        
        // 3. 趨勢分析 - 心率有持續下降趨勢
        let hasDecliningTrend = self.heartRateTrend < -0.15
        
        // 4. 靜息相對性 - 當前心率接近用戶靜息心率
        let nearRestingHR = currentHR <= restingHeartRate * 1.05
        
        // 判斷睡眠條件 - 滿足下列條件之一:
        // a) 心率低於閾值
        // b) 有顯著心率下降
        // c) 心率趨勢持續下降且接近靜息值
        if belowThreshold {
            isProbablySleeping = true
            logger.info("通過心率閾值檢測到睡眠狀態：當前 \(currentHR), 閾值 \(self.heartRateThreshold)")
        } else if hrDecreasing {
            isProbablySleeping = true
            logger.info("通過ΔHR檢測到睡眠狀態：顯著心率下降但未低於標準閾值")
        } else if hasDecliningTrend && nearRestingHR {
            // 心率有持續下降趨勢且接近靜息值
            logger.info("透過心率趨勢分析檢測到可能的睡眠狀態：趨勢 \(self.heartRateTrend)，當前心率 \(currentHR)")
            isProbablySleeping = true
        } else {
            // 如果沒有滿足任何睡眠條件，設置為未睡眠狀態
            if isProbablySleeping {
                isProbablySleeping = false
                logger.info("心率檢測 - 當前: \(currentHR), 閾值: \(self.heartRateThreshold), 趨勢: \(self.heartRateTrend)")
            }
        }
        
        // 如果檢測狀態發生變化且現在是睡眠狀態，記錄睡眠開始時間
        if isProbablySleeping && !wasAlreadySleeping {
            updateSleepSessionWithDetectedTime(now)
        }
    }
    
    // 更新睡眠會話的檢測時間
    private func updateSleepSessionWithDetectedTime(_ time: Date) {
        if let session = currentSleepSession, session.detectedSleepTime == nil {
            currentSleepSession = session.withDetectedSleepTime(time)
            logger.info("記錄睡眠檢測時間: \(time)")
            
            // 立即保存當前會話（即使未結束）
            if let currentSession = currentSleepSession {
                UserSleepProfileManager.shared.saveSleepSession(currentSession)
            }
        }
    }
    
    // 檢查是否有顯著心率下降，即ΔHR輔助判定
    private func checkSignificantHeartRateDecrease() -> Bool {
        // 需要至少6個樣本才能進行分析
        if heartRateWindow.items.count < 6 {
            return false
        }
        
        let items = heartRateWindow.items
        
        // 將心率窗口分為前半部分和後半部分
        let halfIndex = items.count / 2
        let firstHalf = Array(items[0..<halfIndex])
        let secondHalf = Array(items[halfIndex..<items.count])
        
        // 計算前半部分和後半部分的平均心率
        let firstHalfAvg = firstHalf.reduce(0, +) / Double(firstHalf.count)
        let secondHalfAvg = secondHalf.reduce(0, +) / Double(secondHalf.count)
        
        // 計算心率下降量和下降百分比
        let decrease = firstHalfAvg - secondHalfAvg
        let decreasePercentage = decrease / firstHalfAvg
        
        // ΔHR輔助判定機制：下降 ≥ 5 bpm 且 < 個人 RHR
        // 1. 檢查下降幅度是否達到5bpm
        let hasSignificantDecrease = decrease >= 5.0 && decreasePercentage >= 0.05
        
        // 2. 確認是否可能是睡眠相關的心率下降
        let isBelowRestingHR = secondHalfAvg < restingHeartRate
        
        if hasSignificantDecrease && isBelowRestingHR {
            logger.info("檢測到顯著心率下降: \(decrease) bpm (\(decreasePercentage*100)%), 當前心率低於靜息心率")
        }
        
        return hasSignificantDecrease && isBelowRestingHR
    }
} 