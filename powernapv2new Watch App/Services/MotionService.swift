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

// MARK: - 動作檢測服務
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
        longWindow = SlidingWindow(windowDuration: MotionAnalysisWindow.medium.timeInterval)
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
            logger.info("更新動作閾值: \(self.motionThreshold)")
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
            
            // 添加硬性大小限制，避免歷史記錄無限增長
            if self.motionHistory.count > 500 { // 限制最多保留500條記錄
                // 按時間排序並只保留最近的500條
                let sortedKeys = self.motionHistory.keys.sorted()
                for key in sortedKeys.prefix(sortedKeys.count - 500) {
                    self.motionHistory.removeValue(forKey: key)
                }
                self.logger.info("動作歷史記錄已清理至500條")
            }
            
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
