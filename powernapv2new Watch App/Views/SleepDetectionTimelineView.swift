import SwiftUI
import Charts

// 時間軸資料點
struct SleepTimelinePoint: Identifiable {
    let id = UUID()
    let offsetSeconds: Double // 相對判睡(秒)，負值表示判睡前
    let percent: Double       // HR / RHR × 100
}

/// 心率% vs 時間，可視化判睡點與閾值
struct SleepDetectionTimelineView: View {
    let data: [SleepTimelinePoint]
    let thresholdPercent: Double
    let minutesRange: Double   // 左右各幾分鐘
    let centerMinute: Double   // 0 分刻度在會話中的絕對分鐘位置
    let useFullRange: Bool     // 若為 true，X 軸使用資料實際範圍，而非對稱區間

    init(data: [SleepTimelinePoint], thresholdPercent: Double, minutesRange: Double, centerMinute: Double, useFullRange: Bool = false) {
        self.data = data
        self.thresholdPercent = thresholdPercent
        self.minutesRange = minutesRange
        self.centerMinute = centerMinute
        self.useFullRange = useFullRange
    }

    var body: some View {
        if #available(watchOS 10.0, *) {
            Chart {
                ForEach(data) { p in
                    LineMark(
                        x: .value("Time", centerMinute + p.offsetSeconds / 60),
                        y: .value("HR%", p.percent)
                    )
                    .foregroundStyle(.white)
                }
                // 閾值水平線
                RuleMark(y: .value("Threshold", thresholdPercent))
                    .foregroundStyle(Color.red)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4]))
                // 判睡垂直線 (x=centerMinute)
                RuleMark(x: .value("Detect", centerMinute))
                    .foregroundStyle(Color.green)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3]))
            }
            .chartXScale(domain: xDomain)
            .chartYScale(domain: [70, 120])
            .frame(height: 120)
        } else {
            Text("watchOS 10 以上才支援圖表")
                .font(.footnote)
                .foregroundColor(.gray)
        }
    }

    /// 根據 useFullRange 計算 X 軸範圍
    private var xDomain: ClosedRange<Double> {
        if useFullRange {
            let xs = data.map { centerMinute + $0.offsetSeconds / 60 }
            guard let minX = xs.min(), let maxX = xs.max(), minX < maxX else {
                return centerMinute - minutesRange ... centerMinute + minutesRange
            }
            return minX ... maxX
        } else {
            return (centerMinute - minutesRange) ... (centerMinute + minutesRange)
        }
    }
} 