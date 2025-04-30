import Foundation
import Combine

// 這個文件提供了一個臨時的解決方案來統一類型定義
// 在Swift項目中正確設置Target Membership和類型可見性後，
// 可以移除此文件，直接引用SharedTypes.swift中的類型

// MARK: - 睡眠狀態枚舉
public enum SleepState: String, Codable {
    case awake           // 清醒狀態
    case resting         // 靜止休息狀態
    case lightSleep      // 輕度睡眠
    case deepSleep       // 深度睡眠
    
    public var description: String {
        switch self {
        case .awake:
            return "清醒"
        case .resting:
            return "靜止休息"
        case .lightSleep:
            return "輕度睡眠"
        case .deepSleep:
            return "深度睡眠"
        }
    }
}

// MARK: - 年齡組別
public enum AgeGroup: String, CaseIterable, Codable, Identifiable {
    case teen = "青少年 (10-17歲)"
    case adult = "成人 (18-59歲)"
    case senior = "銀髮族 (60歲以上)"
    
    public var id: String { self.rawValue }
    
    // 心率閾值百分比（相對於靜息心率）
    public var heartRateThresholdPercentage: Double {
        switch self {
        case .teen:
            return 0.875 // 87.5% of RHR for teens
        case .adult:
            return 0.9 // 90% of RHR for adults
        case .senior:
            return 0.935 // 93.5% of RHR for seniors
        }
    }
    
    // 最小時間窗口設置（秒）
    public var minDurationForSleepDetection: TimeInterval {
        switch self {
        case .teen:
            return 60 * 2 // 2分鐘
        case .adult:
            return 60 * 3 // 3分鐘
        case .senior:
            return 60 * 4 // 4分鐘
        }
    }
    
    // 檢測該年齡段的閾值
    public static func forAge(_ age: Int) -> AgeGroup {
        if age < 18 {
            return .teen
        } else if age < 60 {
            return .adult
        } else {
            return .senior
        }
    }
}

// MARK: - 動作強度等級
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

// MARK: - 動作分析窗口
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
    
    // 根據年齡組別獲取適當的窗口設置
    public static func forAgeGroup(_ ageGroup: AgeGroup) -> MotionAnalysisWindow {
        switch ageGroup {
        case .teen:
            return .short
        case .adult:
            return .medium
        case .senior:
            return .long
        }
    }
}

// MARK: - 心率分析數據
public struct HeartRateAnalysisData {
    public let timestamp: Date
    public let value: Double // BPM
    public let isResting: Bool // 是否是靜息狀態下測量的
    
    public init(timestamp: Date, value: Double, isResting: Bool) {
        self.timestamp = timestamp
        self.value = value
        self.isResting = isResting
    }
}

// MARK: - 心率變化類型
public enum HeartRateVariation: String {
    case increasing // 上升
    case decreasing // 下降
    case stable     // 穩定
    
    // 判斷心率變化類型
    public static func analyze(current: Double, previous: Double, threshold: Double = 3.0) -> HeartRateVariation {
        let difference = current - previous
        if abs(difference) < threshold {
            return .stable
        }
        return difference > 0 ? .increasing : .decreasing
    }
}

// MARK: - 睡眠檢測狀態
public struct SleepDetectionState {
    public var sleepState: SleepState
    public var motionIntensity: MotionIntensity
    public var currentHeartRate: Double?
    public var isStationaryDuration: TimeInterval // 持續靜止時間
    public var timestamp: Date
    
    public init(
        sleepState: SleepState = .awake,
        motionIntensity: MotionIntensity = .none,
        currentHeartRate: Double? = nil,
        isStationaryDuration: TimeInterval = 0,
        timestamp: Date = Date()
    ) {
        self.sleepState = sleepState
        self.motionIntensity = motionIntensity
        self.currentHeartRate = currentHeartRate
        self.isStationaryDuration = isStationaryDuration
        self.timestamp = timestamp
    }
}

// MARK: - 服務協議

// 動作服務協議
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