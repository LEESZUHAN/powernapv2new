import Foundation

/// 自適應閾值系統：根據動作數據自動調整判定閾值
public class AdaptiveThresholdSystem {
    // MARK: - 公開屬性
    
    /// 當前使用的閾值
    public private(set) var currentThreshold: Double
    
    /// 最小允許閾值
    public let minThreshold: Double
    
    /// 最大允許閾值
    public let maxThreshold: Double
    
    /// 平滑係數 (0.0-1.0)，值越大，新閾值影響越大
    public let smoothingFactor: Double
    
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
    public init(
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
    public func updateThreshold(recentMotionData: [Double]) -> Bool {
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
    public func forceUpdateThreshold(recentMotionData: [Double]) -> Double {
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