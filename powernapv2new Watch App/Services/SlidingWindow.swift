import Foundation

/// 滑動窗口：用於存儲和分析一段時間內的動作數據
public class SlidingWindow {
    // MARK: - 公開屬性
    
    /// 窗口大小（秒）
    public let windowDuration: TimeInterval
    
    /// 窗口內的樣本數量
    public var sampleCount: Int {
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
    public init(windowDuration: TimeInterval, initialCapacity: Int? = nil) {
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
    public func addDataPoint(_ intensity: Double, timestamp: Date = Date()) {
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
    public func calculateStationaryPercentage(threshold: Double) -> Double {
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
    public func getStationarySampleCount(threshold: Double) -> Int {
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
    public func getAverageIntensity() -> Double {
        if dataPoints.isEmpty {
            return 0.0
        }
        
        let sum = dataPoints.reduce(0.0) { $0 + $1.intensity }
        return sum / Double(dataPoints.count)
    }
    
    /// 獲取窗口內的標準差
    /// - Returns: 標準差值
    public func getStandardDeviation() -> Double {
        if dataPoints.isEmpty {
            return 0.0
        }
        
        let mean = getAverageIntensity()
        let variance = dataPoints.reduce(0.0) { $0 + pow($1.intensity - mean, 2) } / Double(dataPoints.count)
        
        return sqrt(variance)
    }
    
    /// 清空窗口數據
    public func clear() {
        dataPoints.removeAll(keepingCapacity: true)
        _cacheNeedsUpdate = true
    }
    
    /// 獲取窗口內的所有數據點
    /// - Returns: 數據點陣列的副本
    public func getAllDataPoints() -> [(timestamp: Date, intensity: Double)] {
        return dataPoints
    }
    
    /// 獲取窗口內的數據點數量
    /// - Returns: 數據點數量
    public func getDataPointCount() -> Int {
        return dataPoints.count
    }
} 