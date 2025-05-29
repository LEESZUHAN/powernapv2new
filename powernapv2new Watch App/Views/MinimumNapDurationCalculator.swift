import Foundation
import SwiftUI

/// 睡眠時間計算工具，用於確保睡眠時間不小於確認時間
struct MinimumNapDurationCalculator {
    
    /// 根據確認時間計算最小睡眠時間（分鐘）
    /// - Parameter confirmationTimeSeconds: 確認時間（秒）
    /// - Returns: 最小允許的睡眠時間（分鐘）
    static func calculateMinimumNapDuration(confirmationTimeSeconds: Int) -> Int {
        // 將確認時間（秒）轉換為分鐘並向上取整
        let confirmationTimeMinutes = Int(ceil(Double(confirmationTimeSeconds) / 60.0))
        
        // 確保最小睡眠時間至少比確認時間大1分鐘，並且不小於3分鐘
        return max(confirmationTimeMinutes + 1, 3)
    }
    
    /// 生成可用的睡眠時間選項範圍
    /// - Parameter confirmationTimeSeconds: 確認時間（秒）
    /// - Returns: 可選的睡眠時間範圍（分鐘）
    static func getValidNapDurationRange(confirmationTimeSeconds: Int) -> ClosedRange<Int> {
        let minimum = calculateMinimumNapDuration(confirmationTimeSeconds: confirmationTimeSeconds)
        return minimum...30 // 最大值固定為30分鐘
    }
} 