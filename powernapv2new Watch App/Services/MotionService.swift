import Foundation
import CoreMotion
import Combine
import os

// 導入必要的框架
#if os(watchOS)
import WatchKit
#endif

// 導入所需的UI框架
import SwiftUI

// MARK: - 從SharedTypes.swift引入的類型

/// 動作強度等級
public enum MotionIntensity: String, Codable {
    case none        // 無動作
    case minimal     // 最小動作（可能是環境干擾）
    case light       // 輕微動作（如小幅度移動手腕）
    case moderate    // 中等動作（如伸懶腰）
    case intense     // 強烈動作（如走動）
    
    // 閾值設定，單位：G (1G = 9.8 m/s²)
    public static func fromAcceleration(_ acceleration: Double) -> MotionIntensity {
        switch acceleration {
        case 0..<0.02:
            return .none
        case 0.02..<0.05:
            return .minimal
        case 0.05..<0.15:
            return .light
        case 0.15..<0.5:
            return .moderate
        default:
            return .intense
        }
    }
    
    // 判斷是否為靜止狀態
    public var isStationary: Bool {
        switch self {
        case .none, .minimal:
            return true
        case .light, .moderate, .intense:
            return false
        }
    }
}

/// 動作分析窗口
public struct MotionAnalysisWindow {
    public let timeInterval: TimeInterval // 窗口時間長度（秒）
    public let sampleInterval: TimeInterval // 採樣間隔（秒）
    public let requiredStationaryPercentage: Double // 靜止時間佔比要求
    
    // 預設窗口設置
    public static let short = MotionAnalysisWindow(
        timeInterval: 60, // 1分鐘
        sampleInterval: 1, // 每秒採樣
        requiredStationaryPercentage: 0.9 // 90%時間靜止
    )
    
    public static let medium = MotionAnalysisWindow(
        timeInterval: 180, // 3分鐘
        sampleInterval: 2, // 每2秒採樣
        requiredStationaryPercentage: 0.85 // 85%時間靜止
    )
    
    public static let long = MotionAnalysisWindow(
        timeInterval: 300, // 5分鐘
        sampleInterval: 5, // 每5秒採樣
        requiredStationaryPercentage: 0.8 // 80%時間靜止
    )
    
    public init(timeInterval: TimeInterval, sampleInterval: TimeInterval, requiredStationaryPercentage: Double) {
        self.timeInterval = timeInterval
        self.sampleInterval = sampleInterval
        self.requiredStationaryPercentage = requiredStationaryPercentage
    }
}

/// 動作服務協議
public protocol MotionServiceProtocol {
    var currentMotionIntensity: MotionIntensity { get }
    var motionIntensityPublisher: Published<MotionIntensity>.Publisher { get }
    var isStationaryPublisher: Published<Bool>.Publisher { get }
    var isStationary: Bool { get }
    var stationaryDuration: TimeInterval { get }
    var analysisWindow: MotionAnalysisWindow { get }
    
    func startMonitoring()
    func stopMonitoring()
    func updateAnalysisWindow(window: MotionAnalysisWindow)
    func getMotionIntensityHistory(from: Date, to: Date) -> [Date: MotionIntensity]
    func checkStationaryCondition(for timeWindow: TimeInterval) -> Bool
}

/// 滑動窗口：用於存儲和分析一段時間內的動作數據
private class SlidingWindow {
    // MARK: - 公開屬性
    
    /// 窗口大小（秒）
    let windowDuration: TimeInterval
    
    /// 窗口內的樣本數量
    var sampleCount: Int {
        return dataPoints.count
    }
    
    // MARK: - 私有屬性
    
    /// 存儲數據點的陣列 (timestamp, intensity)
    private var dataPoints: [(timestamp: Date, intensity: Double)]
    
    /// 用於優化計算的緩存
    private var _cachedStationarySampleCount: Int = 0
    private var _cachedThreshold: Double = -1
    private var _cacheNeedsUpdate: Bool = true
    
    // MARK: - 初始化
    
    /// 初始化滑動窗口
    /// - Parameters:
    ///   - windowDuration: 窗口持續時間（秒）
    ///   - initialCapacity: 初始容量大小（預設為每秒一個樣本）
    init(windowDuration: TimeInterval, initialCapacity: Int? = nil) {
        self.windowDuration = windowDuration
        let capacity = initialCapacity ?? Int(windowDuration)
        self.dataPoints = []
        self.dataPoints.reserveCapacity(capacity)
    }
    
    // MARK: - 公開方法
    
    /// 添加新的數據點到窗口，並移除過期數據
    /// - Parameters:
    ///   - intensity: 動作強度值
    ///   - timestamp: 時間戳（預設為當前時間）
    func addDataPoint(_ intensity: Double, timestamp: Date = Date()) {
        // 標記緩存需要更新
        _cacheNeedsUpdate = true
        
        // 添加新數據點
        dataPoints.append((timestamp, intensity))
        
        // 移除過期數據
        let cutoffTime = timestamp.addingTimeInterval(-windowDuration)
        dataPoints = dataPoints.filter { $0.timestamp > cutoffTime }
    }
    
    /// 計算窗口內靜止樣本的比例
    /// - Parameter threshold: 判定靜止的閾值
    /// - Returns: 靜止樣本佔總樣本的比例 (0.0 - 1.0)
    func calculateStationaryPercentage(threshold: Double) -> Double {
        if dataPoints.isEmpty {
            return 1.0 // 無數據時預設為靜止
        }
        
        // 計算靜止樣本數量
        let stationarySampleCount = getStationarySampleCount(threshold: threshold)
        
        // 計算比例
        return Double(stationarySampleCount) / Double(dataPoints.count)
    }
    
    /// 獲取窗口內靜止的樣本數
    /// - Parameter threshold: 判定靜止的閾值
    /// - Returns: 靜止樣本數量
    func getStationarySampleCount(threshold: Double) -> Int {
        // 如果使用相同閾值且緩存有效，直接返回緩存結果
        if _cachedThreshold == threshold && !_cacheNeedsUpdate {
            return _cachedStationarySampleCount
        }
        
        // 計算靜止樣本數
        _cachedStationarySampleCount = dataPoints.filter { $0.intensity < threshold }.count
        _cachedThreshold = threshold
        _cacheNeedsUpdate = false
        
        return _cachedStationarySampleCount
    }
    
    /// 獲取窗口內的平均動作強度
    /// - Returns: 平均強度值
    func getAverageIntensity() -> Double {
        if dataPoints.isEmpty {
            return 0.0
        }
        
        let sum = dataPoints.reduce(0.0) { $0 + $1.intensity }
        return sum / Double(dataPoints.count)
    }
    
    /// 獲取窗口內的標準差
    /// - Returns: 標準差值
    func getStandardDeviation() -> Double {
        if dataPoints.isEmpty {
            return 0.0
        }
        
        let mean = getAverageIntensity()
        let variance = dataPoints.reduce(0.0) { $0 + pow($1.intensity - mean, 2) } / Double(dataPoints.count)
        
        return sqrt(variance)
    }
    
    /// 清空窗口數據
    func clear() {
        dataPoints.removeAll(keepingCapacity: true)
        _cacheNeedsUpdate = true
    }
    
    /// 獲取窗口內的所有數據點
    /// - Returns: 數據點陣列的副本
    func getAllDataPoints() -> [(timestamp: Date, intensity: Double)] {
        return dataPoints
    }
    
    /// 獲取窗口內的數據點數量
    /// - Returns: 數據點數量
    func getDataPointCount() -> Int {
        return dataPoints.count
    }
}

/// 自適應閾值系統：根據動作數據自動調整判定閾值
private class AdaptiveThresholdSystem {
    // MARK: - 公開屬性
    
    /// 當前使用的閾值
    private(set) var currentThreshold: Double
    
    /// 最小允許閾值
    let minThreshold: Double
    
    /// 最大允許閾值
    let maxThreshold: Double
    
    /// 平滑係數 (0.0-1.0)，值越大，新閾值影響越大
    let smoothingFactor: Double
    
    // MARK: - 私有屬性
    
    /// 上次更新時間
    private var lastUpdateTime: Date = Date()
    
    /// 更新間隔（秒）
    private let updateInterval: TimeInterval
    
    // MARK: - 初始化
    
    /// 初始化自適應閾值系統
    /// - Parameters:
    ///   - initialThreshold: 初始閾值
    ///   - minThreshold: 最小允許閾值
    ///   - maxThreshold: 最大允許閾值
    ///   - smoothingFactor: 平滑係數 (0.0-1.0)
    ///   - updateInterval: 更新間隔（秒）
    init(
        initialThreshold: Double = 0.02,
        minThreshold: Double = 0.015,
        maxThreshold: Double = 0.05,
        smoothingFactor: Double = 0.3,
        updateInterval: TimeInterval = 60.0
    ) {
        self.currentThreshold = initialThreshold
        self.minThreshold = minThreshold
        self.maxThreshold = maxThreshold
        self.smoothingFactor = max(0.0, min(1.0, smoothingFactor))
        self.updateInterval = updateInterval
    }
    
    // MARK: - 公開方法
    
    /// 根據最新的動作數據更新閾值
    /// - Parameter recentMotionData: 最近的動作數據樣本
    /// - Returns: 是否更新了閾值
    func updateThreshold(recentMotionData: [Double]) -> Bool {
        let now = Date()
        
        // 檢查是否需要更新閾值
        if now.timeIntervalSince(lastUpdateTime) < updateInterval {
            return false
        }
        
        // 只有當有足夠的數據時才更新閾值
        if recentMotionData.count < 10 {
            return false
        }
        
        // 計算新閾值
        let newThreshold = calculateAdaptiveThreshold(recentMotionData: recentMotionData)
        
        // 應用平滑過渡
        let smoothedThreshold = (1.0 - smoothingFactor) * currentThreshold + smoothingFactor * newThreshold
        
        // 應用限制範圍
        currentThreshold = max(minThreshold, min(maxThreshold, smoothedThreshold))
        
        // 更新時間
        lastUpdateTime = now
        
        return true
    }
    
    /// 強制立即更新閾值
    /// - Parameter recentMotionData: 最近的動作數據樣本
    /// - Returns: 新計算的閾值
    func forceUpdateThreshold(recentMotionData: [Double]) -> Double {
        if recentMotionData.isEmpty {
            return currentThreshold
        }
        
        // 計算新閾值
        let newThreshold = calculateAdaptiveThreshold(recentMotionData: recentMotionData)
        
        // 應用平滑過渡
        let smoothedThreshold = (1.0 - smoothingFactor) * currentThreshold + smoothingFactor * newThreshold
        
        // 應用限制範圍
        currentThreshold = max(minThreshold, min(maxThreshold, smoothedThreshold))
        
        // 更新時間
        lastUpdateTime = Date()
        
        return currentThreshold
    }
    
    // MARK: - 私有方法
    
    /// 計算自適應閾值
    /// - Parameter recentMotionData: 最近的動作數據樣本
    /// - Returns: 建議的新閾值
    private func calculateAdaptiveThreshold(recentMotionData: [Double]) -> Double {
        // 預設值
        guard !recentMotionData.isEmpty else {
            return currentThreshold
        }
        
        // 計算平均值
        let mean = recentMotionData.reduce(0.0, +) / Double(recentMotionData.count)
        
        // 計算標準差
        let sumOfSquaredDifferences = recentMotionData.reduce(0.0) { $0 + pow($1 - mean, 2) }
        let variance = sumOfSquaredDifferences / Double(recentMotionData.count)
        let standardDeviation = sqrt(variance)
        
        // 計算新閾值：平均值 + 標準差
        return mean + standardDeviation
    }
}

/// 動作檢測服務：負責監測和分析設備的動作狀態
public class MotionService: MotionServiceProtocol, ObservableObject {
    
    // MARK: - 公開屬性
    
    @Published public private(set) var currentMotionIntensity: MotionIntensity = .none
    @Published public private(set) var isStationary: Bool = true
    
    public var motionIntensityPublisher: Published<MotionIntensity>.Publisher { $currentMotionIntensity }
    public var isStationaryPublisher: Published<Bool>.Publisher { $isStationary }
    
    private(set) public var stationaryDuration: TimeInterval = 0
    private(set) public var analysisWindow: MotionAnalysisWindow = .medium
    
    // MARK: - 私有屬性
    
    private let logger = Logger(subsystem: "com.yourdomain.powernapv2new", category: "MotionService")
    #if os(watchOS)
    private let motionManager = CMMotionManager()
    #else
    // 在非watchOS平台上使用模擬
    private class MockMotionManager {
        var isAccelerometerAvailable = true
        var isAccelerometerActive = false
        var accelerometerUpdateInterval: TimeInterval = 0.5
        
        func startAccelerometerUpdates(to queue: OperationQueue, withHandler handler: @escaping CMAccelerometerHandler) {
            isAccelerometerActive = true
        }
        
        func stopAccelerometerUpdates() {
            isAccelerometerActive = false
        }
    }
    private let motionManager = MockMotionManager()
    #endif
    
    private let motionQueue = OperationQueue()
    
    // 加速度數據相關閾值
    private var motionThreshold: Double = 0.02  // 靜止判定閾值
    
    // 動作歷史記錄 - 用於分析時間窗口內的動作模式
    private var motionHistory: [Date: MotionIntensity] = [:]
    
    // 滑動窗口實例
    private var longWindow: SlidingWindow
    private var shortWindow: SlidingWindow
    
    // 自適應閾值系統
    private var adaptiveThreshold: AdaptiveThresholdSystem
    
    // 狀態追蹤
    private var lastSignificantMotionDate: Date?
    private var lastUpdateTime: Date = Date()
    private var rawAccelerationData: [Double] = []
    
    // 用於計時的計時器
    private var updateTimer: Timer?
    
    // 設定參數
    private let rawDataBufferSize = 300 // 保存5分鐘的原始數據
    private let shortWindowSize: TimeInterval = 20 // 短窗口20秒
    
    // MARK: - 初始化
    
    public init() {
        motionQueue.name = "com.yourdomain.powernapv2new.motionQueue"
        motionQueue.qualityOfService = .utility
        
        // 初始化滑動窗口
        longWindow = SlidingWindow(windowDuration: analysisWindow.timeInterval)
        shortWindow = SlidingWindow(windowDuration: shortWindowSize)
        
        // 初始化自適應閾值系統
        adaptiveThreshold = AdaptiveThresholdSystem(
            initialThreshold: 0.02,
            minThreshold: 0.015,
            maxThreshold: 0.05,
            smoothingFactor: 0.3,
            updateInterval: 60.0
        )
        
        // 初始狀態設為靜止
        self.isStationary = true
        self.currentMotionIntensity = .none
        self.lastSignificantMotionDate = nil
    }
    
    deinit {
        stopMonitoring()
    }
    
    // MARK: - 公開方法
    
    /// 啟動動作監測
    public func startMonitoring() {
        #if os(watchOS)
        guard motionManager.isAccelerometerAvailable else {
            logger.error("加速度計不可用")
            return
        }
        
        // 避免重複啟動
        if motionManager.isAccelerometerActive {
            logger.info("加速度計已經處於活動狀態")
            return
        }
        
        // 設置更新間隔和隊列
        motionManager.accelerometerUpdateInterval = 0.5  // 每0.5秒更新一次
        
        // 啟動加速度計更新
        motionManager.startAccelerometerUpdates(to: motionQueue) { [weak self] accelerometerData, error in
            guard let self = self else { return }
            
            if let error = error {
                self.logger.error("加速度計錯誤: \(error.localizedDescription)")
                return
            }
            
            if let accelerometerData = accelerometerData {
                self.processAccelerometerData(accelerometerData)
            }
        }
        #else
        // 非watchOS平台上的模擬行為
        logger.info("在非watchOS平台上模擬動作監測")
        motionManager.startAccelerometerUpdates(to: motionQueue) { _, _ in }
        #endif
        
        // 啟動定時器進行狀態更新
        DispatchQueue.main.async {
            self.updateTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                self?.updateStationaryState()
            }
        }
        
        logger.info("動作監測已啟動")
    }
    
    /// 停止動作監測
    public func stopMonitoring() {
        #if os(watchOS)
        if motionManager.isAccelerometerActive {
            motionManager.stopAccelerometerUpdates()
        }
        #else
        motionManager.stopAccelerometerUpdates()
        #endif
        
        // 停止更新計時器
        updateTimer?.invalidate()
        updateTimer = nil
        
        logger.info("動作監測已停止")
    }
    
    /// 更新動作分析窗口設置
    public func updateAnalysisWindow(window: MotionAnalysisWindow) {
        self.analysisWindow = window
        
        // 更新長窗口大小
        longWindow = SlidingWindow(windowDuration: window.timeInterval)
        
        logger.info("更新動作分析窗口: 時間間隔=\(window.timeInterval)秒, 樣本間隔=\(window.sampleInterval)秒")
    }
    
    /// 獲取指定時間範圍內的動作強度歷史
    public func getMotionIntensityHistory(from: Date, to: Date) -> [Date: MotionIntensity] {
        return motionHistory.filter { $0.key >= from && $0.key <= to }
    }
    
    /// 檢查是否在指定的時間窗口內達到靜止條件
    public func checkStationaryCondition(for timeWindow: TimeInterval) -> Bool {
        // 從當前配置獲取所需的靜止百分比
        let requiredStationaryPercentage = analysisWindow.requiredStationaryPercentage
        
        // 計算窗口內靜止樣本的占比
        let stationaryPercentage = longWindow.calculateStationaryPercentage(threshold: motionThreshold)
        
        // 檢查是否達到所需百分比
        return stationaryPercentage >= requiredStationaryPercentage
    }
    
    // MARK: - 私有方法
    
    /// 處理加速度計數據
    private func processAccelerometerData(_ accelerometerData: CMAccelerometerData) {
        // 計算合成加速度的絕對值（去除方向，只關注強度）
        let x = accelerometerData.acceleration.x
        let y = accelerometerData.acceleration.y
        let z = accelerometerData.acceleration.z
        
        // 移除重力加速度（1G）後的淨加速度強度
        let netAcceleration = sqrt(x*x + y*y + z*z) - 1.0
        let absAcceleration = abs(netAcceleration)
        
        // 確保非負值
        let adjustedAcceleration = max(0, absAcceleration)
        
        // 將加速度值轉換為動作強度等級
        let intensity = MotionIntensity.fromAcceleration(adjustedAcceleration)
        
        // 更新滑動窗口
        longWindow.addDataPoint(adjustedAcceleration)
        shortWindow.addDataPoint(adjustedAcceleration)
        
        // 保存原始加速度數據用於自適應閾值
        rawAccelerationData.append(adjustedAcceleration)
        if rawAccelerationData.count > rawDataBufferSize {
            rawAccelerationData.removeFirst(rawAccelerationData.count - rawDataBufferSize)
        }
        
        // 根據累積的數據更新自適應閾值
        if adaptiveThreshold.updateThreshold(recentMotionData: rawAccelerationData) {
            motionThreshold = adaptiveThreshold.currentThreshold
            logger.info("更新動作閾值: \(motionThreshold)")
        }
        
        DispatchQueue.main.async {
            // 更新當前動作強度
            self.currentMotionIntensity = intensity
            
            // 記錄到歷史中
            let now = Date()
            self.motionHistory[now] = intensity
            
            // 清理過時的歷史記錄（保留最近2小時的數據）
            let twoHoursAgo = now.addingTimeInterval(-7200)
            self.motionHistory = self.motionHistory.filter { $0.key >= twoHoursAgo }
            
            // 如果檢測到顯著運動，更新最後運動時間
            if !intensity.isStationary {
                self.lastSignificantMotionDate = now
                // 立即更新靜止狀態
                self.isStationary = false
                self.stationaryDuration = 0
            }
        }
    }
    
    /// 更新靜止狀態
    private func updateStationaryState() {
        let now = Date()
        
        // 計算自上次更新以來的時間差
        let timeSinceLastUpdate = now.timeIntervalSince(lastUpdateTime)
        lastUpdateTime = now
        
        // 計算窗口內靜止樣本的占比
        let longWindowStationaryPercentage = longWindow.calculateStationaryPercentage(threshold: motionThreshold)
        let shortWindowStationaryPercentage = shortWindow.calculateStationaryPercentage(threshold: motionThreshold)
        
        // 根據窗口數據判斷當前是否靜止
        let requiredPercentage = analysisWindow.requiredStationaryPercentage
        let newIsStationary = longWindowStationaryPercentage >= requiredPercentage
        
        // 短窗口檢測突發運動
        let suddenMovement = shortWindowStationaryPercentage < requiredPercentage * 0.7
        
        // 如果有突發運動，優先判斷為非靜止
        let finalIsStationary = suddenMovement ? false : newIsStationary
        
        // 如果狀態變化，記錄日誌
        if finalIsStationary != isStationary {
            if finalIsStationary {
                self.logger.info("進入靜止狀態，長窗口靜止比例: \(longWindowStationaryPercentage)")
            } else {
                self.logger.info("離開靜止狀態，短窗口靜止比例: \(shortWindowStationaryPercentage)")
            }
        }
        
        // 更新靜止狀態
        self.isStationary = finalIsStationary
        
        // 更新持續靜止時間
        if self.isStationary {
            self.stationaryDuration += timeSinceLastUpdate
        } else {
            self.stationaryDuration = 0
        }
    }
} 