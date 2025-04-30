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

// 直接從Supporting Files導入所需類型
// 標準方法無法成功導入的情况下，直接在.swift文件中包含類型定義

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
    private let significantAccelerationThreshold: Double = 0.1  // 顯著運動的加速度閾值
    
    // 動作歷史記錄 - 用於分析時間窗口內的動作模式
    private var motionHistory: [Date: MotionIntensity] = [:]
    private var lastSignificantMotionDate: Date?
    private var lastUpdateTime: Date = Date()
    
    // 用於計時的計時器
    private var updateTimer: Timer?
    
    // MARK: - 初始化
    
    public init() {
        motionQueue.name = "com.yourdomain.powernapv2new.motionQueue"
        motionQueue.qualityOfService = .utility
        
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
        logger.info("更新動作分析窗口: 時間間隔=\(window.timeInterval)秒, 樣本間隔=\(window.sampleInterval)秒")
    }
    
    /// 獲取指定時間範圍內的動作強度歷史
    public func getMotionIntensityHistory(from: Date, to: Date) -> [Date: MotionIntensity] {
        return motionHistory.filter { $0.key >= from && $0.key <= to }
    }
    
    /// 檢查是否在指定的時間窗口內達到靜止條件
    public func checkStationaryCondition(for timeWindow: TimeInterval) -> Bool {
        let now = Date()
        let windowStart = now.addingTimeInterval(-timeWindow)
        
        // 獲取窗口內的動作歷史
        let historyInWindow = getMotionIntensityHistory(from: windowStart, to: now)
        
        // 計算靜止樣本的百分比
        let totalSamples = historyInWindow.count
        if totalSamples == 0 {
            // 沒有樣本數據時，預設為靜止
            return true
        }
        
        let stationarySamples = historyInWindow.values.filter { $0.isStationary }.count
        let stationaryPercentage = Double(stationarySamples) / Double(totalSamples)
        
        // 檢查是否達到分析窗口要求的靜止百分比
        return stationaryPercentage >= analysisWindow.requiredStationaryPercentage
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
        
        // 更新當前動作強度
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
        
        if let lastMotion = lastSignificantMotionDate {
            let timeElapsed = now.timeIntervalSince(lastMotion)
            
            // 如果超過分析窗口的時間間隔未檢測到顯著運動，則處於靜止狀態
            let newIsStationary = timeElapsed >= analysisWindow.timeInterval
            
            // 如果狀態變化，記錄日誌
            if newIsStationary != isStationary {
                if newIsStationary {
                    logger.info("進入靜止狀態，靜止時間: \(timeElapsed)秒")
                } else {
                    logger.info("離開靜止狀態")
                }
            }
            
            // 更新靜止狀態
            isStationary = newIsStationary
            
            // 更新持續靜止時間
            if isStationary {
                stationaryDuration += timeSinceLastUpdate
            } else {
                stationaryDuration = 0
            }
        } else {
            // 如果從未檢測到運動，默認為靜止狀態
            if !isStationary {
                logger.info("進入靜止狀態（無運動歷史）")
                isStationary = true
            }
            
            // 更新持續靜止時間
            stationaryDuration += timeSinceLastUpdate
        }
    }
} 