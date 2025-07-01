import SwiftUI

// 讓 AdvancedLogger.CodableValue 可以安全轉成 Double
extension AdvancedLogger.CodableValue {
    var doubleValue: Double? {
        switch self {
        case .double(let v): return v
        case .int(let v): return Double(v)
        case .string(let s): return Double(s)
        default: return nil
        }
    }
}

extension AdvancedLogger.CodableValue {
    var stringValue: String? {
        switch self {
        case .string(let s): return s
        case .int(let v): return String(v)
        case .double(let v): return String(v)
        case .bool(let b): return b ? "true" : "false"
        }
    }
}

struct AdvancedLogsView: View {
    // MARK: - State
    @State private var logFiles: [URL] = []
    @State private var selectedFile: URL? = nil
    @State private var isPushingDetail: Bool = false
    @State private var logLines: [String] = [] // 先用String，之後再改
    @State private var avgSleepHRDisplay: String = "-"
    @State private var deviationPercentDisplay: String = "-"
    @State private var anomalyScoreDisplay: String = "-"
    @State private var anomalyTotalScoreDisplay: String = "-"
    @State private var detectionErrorDisplay: String = "-"
    @State private var userFeedbackDisplay: String = "-"
    @State private var thresholdChangeDisplay: String = "-"
    @State private var confirmationTimeChangeDisplay: String = "-"
    @State private var systemDetectionDisplay: String = "-"
    @State private var thresholdPercentDisplay: String = "-"
    @State private var thresholdShortDisplay: String = "-"
    @State private var thresholdLongDisplay: String = "-"
    @State private var confirmationShortDisplay: String = "-"
    @State private var confirmationLongDisplay: String = "-"
    @State private var trendDisplay: String = "-"
    @State private var detectSourceDisplay: String = "-"
    @State private var timelinePoints: [SleepTimelinePoint] = []
    @State private var timelineThresholdPercent: Double? = nil
    @State private var timelineMinutesRange: Double = 7.0
    @State private var sessionStartTS: Date? = nil
    @State private var timelineCenterMinute: Double = 0.0
    @State private var tmpThresholdShortStr: String = "-"
    @State private var timelineUseFullRange: Bool = false
    
    // MARK: - Body
    var body: some View {
        NavigationView {
            logFileListView
                .navigationBarTitleDisplayMode(.inline)
                .navigationTitle("")
        }
        .onAppear(perform: loadLogFiles)
    }
    
    // MARK: - Views
    private var logFileListView: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack {
                Text(NSLocalizedString("history_records", comment: "歷史紀錄"))
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding(.vertical, 5)
                if logFiles.isEmpty {
                    Text(NSLocalizedString("no_records", comment: "尚無記錄"))
                        .foregroundColor(.gray)
                        .padding(.top, 20)
                } else {
                    ForEach(logFiles, id: \.lastPathComponent) { url in
                        NavigationLink(
                            destination: logDetailView(for: url)
                                .onAppear {
                                    selectedFile = url
                                    loadLogContent(from: url)
                                },
                            label: {
                                HStack {
                                    Text(fileDisplayName(from: url))
                                        .font(.system(size: 14))
                                        .foregroundColor(.white)
                                        .lineLimit(1)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .foregroundColor(.gray)
                                        .font(.system(size: 12))
                                }
                                .padding(.vertical, 8)
                                .padding(.horizontal, 15)
                                .background(Color.black.opacity(0.3))
                                .cornerRadius(8)
                            }
                        )
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                Button(action: loadLogFiles) {
                    HStack {
                        Image(systemName: "arrow.clockwise")
                        Text(NSLocalizedString("refresh", comment: "重新整理"))
                    }
                    .font(.system(size: 14))
                    .foregroundColor(.blue)
                    .padding(.top, 10)
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.horizontal)
        }
    }
    
    private func logDetailView(for file: URL) -> some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 12) {
                    // 分析標題
                    Text(NSLocalizedString("sleep_status_analysis", comment: "睡眠數據分析"))
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.bottom, 4)
                    // 心率數據
                    HStack {
                        Text(NSLocalizedString("heart_rate_data", comment: "心率數據"))
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white)
                        Spacer()
                        Text(avgSleepHRDisplay)
                            .font(.system(size: 12))
                            .foregroundColor(avgSleepHRDisplay == "-" ? .gray : .white)
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 10)
                    .background(Color(white: 0.15))
                    .cornerRadius(8)
                    // 偏離比例
                    HStack {
                        Text(NSLocalizedString("deviation_ratio", comment: "偏離比例"))
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white)
                        Spacer()
                        Text(deviationPercentDisplay)
                            .font(.system(size: 12))
                            .foregroundColor(deviationPercentDisplay == "-" ? .gray : .white)
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 10)
                    .background(Color(white: 0.15))
                    .cornerRadius(8)
                    // 異常評分
                    HStack {
                        Text(NSLocalizedString("anomaly_score", comment: "異常評分"))
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white)
                        Spacer()
                        Text(anomalyScoreDisplay)
                            .font(.system(size: 12))
                            .foregroundColor(anomalyScoreDisplay == "-" ? .gray : .white)
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 10)
                    .background(Color(white: 0.15))
                    .cornerRadius(8)
                    // 累計分數
                    HStack {
                        Text(NSLocalizedString("cumulative_score", comment: "累計分數"))
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white)
                        Spacer()
                        Text(anomalyTotalScoreDisplay)
                            .font(.system(size: 12))
                            .foregroundColor(anomalyTotalScoreDisplay == "-" ? .gray : .white)
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 10)
                    .background(Color(white: 0.15))
                    .cornerRadius(8)
                    // 閾值百分比
                    HStack {
                        Text(NSLocalizedString("threshold_percentage", comment: "閾值百分比"))
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white)
                        Spacer()
                        Text(thresholdPercentDisplay)
                            .font(.system(size: 12))
                            .foregroundColor(thresholdPercentDisplay == "-" ? .gray : .white)
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 10)
                    .background(Color(white: 0.15))
                    .cornerRadius(8)
                    // 系統判定
                    HStack {
                        Text(NSLocalizedString("system_detection", comment: "系統判定"))
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white)
                        Spacer()
                        Text(systemDetectionDisplay)
                            .font(.system(size: 12))
                            .foregroundColor(systemDetectionDisplay == "-" ? .gray : .white)
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 10)
                    .background(Color(white: 0.15))
                    .cornerRadius(8)
                    // 漏/誤報
                    HStack {
                        Text(NSLocalizedString("false_positive_negative", comment: "漏/誤報"))
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white)
                        Spacer()
                        Text(detectionErrorDisplay)
                            .font(.system(size: 12))
                            .foregroundColor(detectionErrorDisplay == "-" ? .gray : .orange)
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 10)
                    .background(Color(white: 0.15))
                    .cornerRadius(8)
                    // 用戶反饋
                    HStack {
                        Text(NSLocalizedString("user_feedback", comment: "用戶反饋"))
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white)
                        Spacer()
                        Text(userFeedbackDisplay)
                            .font(.system(size: 12))
                            .foregroundColor(userFeedbackDisplay == "-" ? .gray : (userFeedbackDisplay == NSLocalizedString("accurate_feedback_comparison", comment: "準確") ? .green : .orange))
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 10)
                    .background(Color(white: 0.15))
                    .cornerRadius(8)
                    // 閾值調整（合併短/長/來源）
                    HStack {
                        Text(NSLocalizedString("hr_threshold_adjustment", comment: "閾值調整"))
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white)
                        Spacer()
                        Text([thresholdShortDisplay, thresholdLongDisplay].filter { $0 != "-" }.joined(separator: " "))
                            .font(.system(size: 12))
                            .foregroundColor((thresholdShortDisplay == "-" && thresholdLongDisplay == "-") ? .gray : .blue)
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 10)
                    .background(Color(white: 0.15))
                    .cornerRadius(8)
                    // trend
                    HStack {
                        Text(NSLocalizedString("heart_rate_trend", comment: "心率趨勢 (trend)"))
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white)
                        Spacer()
                        Text(trendDisplay)
                            .font(.system(size: 12))
                            .foregroundColor(trendDisplay == "-" ? .gray : .white)
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 10)
                    .background(Color(white: 0.15))
                    .cornerRadius(8)
                    // 判定來源
                    HStack {
                        Text(NSLocalizedString("detection_source", comment: "判定來源"))
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white)
                        Spacer()
                        Text(detectSourceDisplay)
                            .font(.system(size: 12))
                            .foregroundColor(detectSourceDisplay == "-" ? .gray : .white)
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 10)
                    .background(Color(white: 0.15))
                    .cornerRadius(8)
                }
                .padding(.vertical)
                // === 新增：判睡前後心率趨勢圖 ===
                if let threshold = timelineThresholdPercent, !timelinePoints.isEmpty {
                    SleepDetectionTimelineView(data: timelinePoints, thresholdPercent: threshold, minutesRange: timelineMinutesRange, centerMinute: timelineCenterMinute, useFullRange: timelineUseFullRange)
                        .padding(.bottom, 10)
                }
                // 原始日誌區塊
                if !logLines.isEmpty {
                    Divider()
                        .background(Color.gray.opacity(0.3))
                        .padding(.vertical, 8)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(NSLocalizedString("raw_logs", comment: "原始日誌"))
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.gray)
                            .padding(.horizontal)
                        ForEach(Array(logLines.enumerated()), id: \.element) { idx, line in
                            if idx > 0 {
                                Divider()
                                    .background(Color.gray.opacity(0.3))
                                    .padding(.vertical, 2)
                            }
                            Text(line)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundColor(.white)
                                .padding(.horizontal)
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Helpers
    private func loadLogFiles() {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!.appendingPathComponent("AdvancedLogFiles")
        let fm = FileManager.default
        if let urls = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) {
            logFiles = urls.sorted { $0.lastPathComponent > $1.lastPathComponent }
        }
    }
    
    private func loadLogContent(from url: URL) {
        // 先重設顯示值
        DispatchQueue.main.async {
            self.avgSleepHRDisplay = "-"
            self.deviationPercentDisplay = "-"
            self.anomalyScoreDisplay = "-"
            self.anomalyTotalScoreDisplay = "-"
            self.detectionErrorDisplay = "-"
            self.userFeedbackDisplay = "-"
            self.thresholdChangeDisplay = "-"
            self.confirmationTimeChangeDisplay = "-"
            self.systemDetectionDisplay = "-"
            self.thresholdPercentDisplay = "-"
            self.thresholdShortDisplay = "-"
            self.thresholdLongDisplay = "-"
            self.confirmationShortDisplay = "-"
            self.confirmationLongDisplay = "-"
            self.trendDisplay = "-"
            self.detectSourceDisplay = "-"
        }

        DispatchQueue.global(qos: .userInitiated).async(execute: DispatchWorkItem {
            guard let data = try? Data(contentsOf: url),
                  let raw = String(data: data, encoding: .utf8) else { return }
            let lines = raw.split(separator: "\n")
            let decoder = JSONDecoder()
            var entries: [Any] = []
            var tmpAvgSleepHR: String = "-"
            var tmpDeviationPercent: String = "-"
            var tmpAnomalyScore: String = "-"
            var tmpAnomalyTotal: String = "-"
            var tmpDetectionError: String = "-"
            var tmpUserFeedback: String = "-"
            let tmpThresholdChange: String = "-"
            let tmpConfirmationChange: String = "-"
            var tmpThresholdPercent: String = "-"
            var tmpSystemDetection: String = "-"
            var deltaPercentShortVal: Double = 0
            var deltaDurationShortVal: Int = 0
            var deltaPercentLongVal: Double = 0
            var deltaDurationLongVal: Int = 0
            var tmpTrend: String = "-"
            var tmpDetectSource: String = "-"
            var tmpAdjustmentSourceShort: String = "-"
            var tmpAdjustmentSourceLong: String = "-"
            // tmpAdjustmentSourceAnomaly 與 _newThreshold / _newConfirmation 目前未使用，省略以避免編譯警告
            var detectedSleep: Bool? = nil
            var feedbackAccurate: Bool? = nil // nil 代表未評價
            // === 新增：時間軸暫存 ===
            var detectTimestamp: Date? = nil
            var thresholdPercentForTimeline: Double? = nil
            var rhrForTimeline: Double? = nil
            var hrSamples: [(Date, Double)] = []

            for line in lines {
                if let d = line.data(using: .utf8),
                   let entry = try? decoder.decode(AdvancedLogger.LogEntry.self, from: d) {
                    entries.append(entry)
                    // 收集時間軸相關資料
                    if entry.type == .sleepDetected {
                        let date = Self.iso8601.date(from: entry.ts)
                        detectTimestamp = date
                        if let tp = entry.payload["thresholdPercent"], let val = tp.doubleValue {
                            thresholdPercentForTimeline = val
                        }
                    } else if entry.type == .sessionStart {
                        if let rhrValStr = entry.payload["rhr"]?.doubleValue {
                            rhrForTimeline = rhrValStr
                        }
                        sessionStartTS = Self.iso8601.date(from: entry.ts)
                        // 若尚未取得 thresholdPercent（通常在 sleepDetected 事件），嘗試從 sessionStart 取得
                        if thresholdPercentForTimeline == nil,
                           let tp = entry.payload["thresholdPercent"],
                           let tpVal = tp.doubleValue {
                            thresholdPercentForTimeline = tpVal
                        }
                    } else if entry.type == .hr {
                        if let bpmVal = entry.payload["bpm"]?.doubleValue {
                            if let date = Self.iso8601.date(from: entry.ts) {
                                hrSamples.append((date, bpmVal))
                            }
                        }
                    }
                }
            }
            // 尋找最後一筆有 avgSleepHR 的 sessionEnd
            for entry in entries.reversed() {
                if let log = entry as? AdvancedLogger.LogEntry,
                   log.type == .sessionEnd,
                   let avgHR = log.payload["avgSleepHR"],
                   let rhr = log.payload["rhr"] {
                    // 嘗試轉成 Double
                    let avgHRValue = avgHR.doubleValue
                    let rhrValue = rhr.doubleValue
                    if let avg = avgHRValue, let rhr = rhrValue, rhr > 0 {
                        let percent = Int(round(avg / rhr * 100))
                        tmpAvgSleepHR = "\(Int(round(avg))) BPM(\(percent)% RHR)"
                        break
                    }
                }
            }
            // 解析偏離比例（sessionEnd）
            for entry in entries.reversed() {
                if let log = entry as? AdvancedLogger.LogEntry, log.type == .sessionEnd {
                    if let ratioVal = log.payload["ratio"]?.doubleValue {
                        tmpDeviationPercent = String(format: "%.3f", ratioVal)
                    } else if let dev = log.payload["deviationPercent"], let devVal = dev.doubleValue {
                        let devInt = Int(round(devVal))
                        tmpDeviationPercent = devInt >= 0 ? "+\(devInt)%" : "\(devInt)%"
                    }
                    break
                }
            }
            // 解析異常評分 / 累計分數
            // 0) 先讀 sessionEnd.deltaScore 作為本次評分
            for entry in entries.reversed() {
                if let log = entry as? AdvancedLogger.LogEntry, log.type == .sessionEnd {
                    if let ds = log.payload["deltaScore"], let val = ds.doubleValue {
                        tmpAnomalyScore = String(Int(round(val)))
                    }
                    break
                }
            }
            // 1) 取 sessionEnd.profileCumulativeScore 作為累計分數
            for entry in entries.reversed() {
                if let log = entry as? AdvancedLogger.LogEntry, log.type == .sessionEnd {
                    if let profScore = log.payload["profileCumulativeScore"], let valStr = profScore.stringValue, let val = Double(valStr) {
                        tmpAnomalyTotal = String(Int(round(val)))
                        break // 找到即可跳出
                    }
                }
            }
            // 2) 若仍為 "-"，退而求其次使用 anomaly log 的 cumulativeScore
            if tmpAnomalyTotal == "-" {
                for entry in entries.reversed() {
                    if let log = entry as? AdvancedLogger.LogEntry, log.type == .anomaly {
                        if let score = log.payload["score"], let scoreVal = score.doubleValue {
                            tmpAnomalyScore = String(Int(round(scoreVal)))
                        }
                        if let total = log.payload["cumulativeScore"], let totalVal = total.doubleValue {
                            tmpAnomalyTotal = String(Int(round(totalVal)))
                        } else if let totalAlt = log.payload["totalScore"], let totalVal = totalAlt.doubleValue {
                            tmpAnomalyTotal = String(Int(round(totalVal)))
                        }
                        break
                    }
                }
            }
            // 解析 sessionEnd 的 detectedSleep 與 feedback log 的 accurate/type，推論漏/誤報
            for entry in entries.reversed() {
                if let log = entry as? AdvancedLogger.LogEntry, log.type == .sessionEnd {
                    if let detected = log.payload["detectedSleep"] {
                        if let b = detected.doubleValue { detectedSleep = (b != 0) }
                        else if let s = detected.stringValue { detectedSleep = (s == "true") }
                    }
                    break
                }
            }
            for entry in entries.reversed() {
                if let log = entry as? AdvancedLogger.LogEntry, log.type == .feedback {
                    if let acc = log.payload["accurate"] {
                        if let s = acc.stringValue, s == "null" {
                            feedbackAccurate = nil // 未評價
                        } else if let b = acc.doubleValue {
                            feedbackAccurate = (b != 0)
                        } else if let s = acc.stringValue {
                            feedbackAccurate = (s == "true")
                        }
                    }
                    break
                }
            }
            if let detected = detectedSleep, let accurateFlag = feedbackAccurate {
                if accurateFlag {
                    tmpDetectionError = "-" // 準確時顯示 -
                } else if feedbackAccurate == false {
                    tmpDetectionError = detected ? NSLocalizedString("false_positive_detection_error", comment: "誤報") : NSLocalizedString("false_negative_detection_error", comment: "漏報")
                }
            }
            // 解析 feedback/type、thresholdPercent、minDurationSeconds
            for entry in entries {
                if let log = entry as? AdvancedLogger.LogEntry, log.type == .sessionEnd {
                    // thresholdPercent 解析價用於顯示，移除 lastThreshold 判斷
                }
            }
            // 解析 thresholdPercent
            for entry in entries.reversed() {
                if let log = entry as? AdvancedLogger.LogEntry, log.type == .sessionEnd {
                    if let tp = log.payload["thresholdPercent"], let val = tp.doubleValue {
                        tmpThresholdPercent = String(Int(round(val))) + "%"
                    }
                    break
                }
            }
            // 系統判定
            if let detected = detectedSleep {
                tmpSystemDetection = detected ? NSLocalizedString("sleep", comment: "睡眠") : NSLocalizedString("not_sleeping", comment: "沒睡著")
            }
            // 用戶反饋顯示
            if let accFlag = feedbackAccurate {
                tmpUserFeedback = accFlag ? NSLocalizedString("accurate", comment: "準確") : NSLocalizedString("inaccurate", comment: "不準確")
            } else {
                tmpUserFeedback = NSLocalizedString("not_evaluated", comment: "未評價")
            }
            // 心率閾值調整 (短期) – 找到第一筆非 0 的 deltaPercentShort 才停止
            for entry in entries.reversed() {
                if let log = entry as? AdvancedLogger.LogEntry, log.type == .sessionEnd {
                    if let dps = log.payload["deltaPercentShort"], let v = dps.doubleValue {
                        deltaPercentShortVal = v
                        // 若值為非零，視為有效調整，結束搜尋
                        if abs(v) > 0.0001 { }
                        break
                    }
                    if let dds = log.payload["deltaDurationShort"], let v = dds.doubleValue { deltaDurationShortVal = Int(v) }
                }
            }
            // 心率閾值調整 (長期)
            for entry in entries.reversed() {
                if let log = entry as? AdvancedLogger.LogEntry, log.type == .optimization {
                    if let dp = log.payload["deltaPercent"], let v = dp.doubleValue { deltaPercentLongVal += v }
                    if let dd = log.payload["deltaDuration"], let v = dd.doubleValue { deltaDurationLongVal += Int(v) }
                    break
                }
            }
            // format displays
            if deltaPercentShortVal != 0 {
                let intVal = Int(round(deltaPercentShortVal))
                tmpThresholdShortStr = intVal > 0 ? "+\(intVal)%" : "\(intVal)%"
            }
            if deltaPercentLongVal != 0 {
                let intVal = Int(round(deltaPercentLongVal))
                thresholdLongDisplay = intVal > 0 ? "+\(intVal)%" : "\(intVal)%"
            }
            if deltaDurationShortVal != 0 {
                confirmationShortDisplay = deltaDurationShortVal > 0 ? "+\(deltaDurationShortVal)\(NSLocalizedString("seconds_unit_suffix", comment: "秒"))" : "\(deltaDurationShortVal)\(NSLocalizedString("seconds_unit_suffix", comment: "秒"))"
            }
            if deltaDurationLongVal != 0 {
                confirmationLongDisplay = deltaDurationLongVal > 0 ? "+\(deltaDurationLongVal)\(NSLocalizedString("seconds_unit_suffix", comment: "秒"))" : "\(deltaDurationLongVal)\(NSLocalizedString("seconds_unit_suffix", comment: "秒"))"
            }
            // trend
            for entry in entries.reversed() {
                if let log = entry as? AdvancedLogger.LogEntry, log.type == .sessionEnd {
                    if let trendVal = log.payload["trend"]?.doubleValue {
                        tmpTrend = String(format: "%.2f", trendVal)
                    }
                    if let src = log.payload["detectSource"]?.stringValue {
                        tmpDetectSource = src
                    }
                    break
                }
            }
            // 若 detectSource 缺失，嘗試推斷
            if tmpDetectSource == "-" {
                if tmpTrend != "-" {
                    tmpDetectSource = "trend"
                } else if let detected = detectedSleep, detected {
                    tmpDetectSource = "window"
                } else {
                    tmpDetectSource = "unknown"
                }
            }
            // 解析 adjustmentSourceShort
            for entry in entries.reversed() {
                if let log = entry as? AdvancedLogger.LogEntry, log.type == .sessionEnd {
                    if let src = log.payload["adjustmentSourceShort"]?.stringValue {
                        tmpAdjustmentSourceShort = src
                    }
                    break
                }
            }
            // 解析 adjustmentSourceLong
            for entry in entries.reversed() {
                if let log = entry as? AdvancedLogger.LogEntry, log.type == .optimization {
                    if let src = log.payload["adjustmentSourceLong"]?.stringValue {
                        tmpAdjustmentSourceLong = src
                    }
                    break
                }
            }
            // --- Fallback：若未偵測到睡眠，仍以 sessionStart 為時間軸中心 ---
            if detectTimestamp == nil {
                detectTimestamp = sessionStartTS
                timelineUseFullRange = true
            } else {
                timelineUseFullRange = false
            }
            // === 新增：時間軸資料計算 ===
            var generatedTimeline: [SleepTimelinePoint] = []
            if let detectTS = detectTimestamp, let rhr = rhrForTimeline {
                // 取偵測前後各7分鐘
                let windowStart = detectTS.addingTimeInterval(-420)
                let windowEnd = detectTS.addingTimeInterval(420)
                let filtered = hrSamples.filter { $0.0 >= windowStart && $0.0 <= windowEnd }
                let samplesForTimeline: [(Date, Double)] = filtered.isEmpty ? hrSamples : filtered
                for (ts, bpm) in samplesForTimeline {
                    let offset = ts.timeIntervalSince(detectTS)
                    let percent = (rhr > 0) ? (bpm / rhr * 100) : 0
                    // 只保留 50% – 140% 之間的資料，避免極端值破圖
                    guard percent >= 50, percent <= 140 else { continue }
                    generatedTimeline.append(SleepTimelinePoint(offsetSeconds: offset, percent: percent))
                }
                // 依時間排序
                generatedTimeline.sort { $0.offsetSeconds < $1.offsetSeconds }
            }
            // 計算 minutesRange (至少 5 分鐘，否則取最大偏移)
            var computedRange: Double = 5.0
            if let maxOffset = generatedTimeline.map({ abs($0.offsetSeconds) }).max() {
                computedRange = max(5.0, ceil(maxOffset / 60.0))
            }
            // 預先計算中心分鐘（判睡相對 start）
            let calculatedCenterMinute: Double = {
                guard let start = sessionStartTS, let detect = detectTimestamp else { return 0 }
                return detect.timeIntervalSince(start) / 60.0
            }()
            DispatchQueue.main.async {
                // 只顯示非 .hr 類型的日誌行，避免畫面被連續 HR 淹沒
                let filteredDisplayLines: [String] = entries.compactMap { entry in
                    if let log = entry as? AdvancedLogger.LogEntry {
                        return log.type == .hr ? nil : String(describing: log)
                    }
                    return String(describing: entry)
                }
                self.logLines = filteredDisplayLines
                self.avgSleepHRDisplay = tmpAvgSleepHR
                self.deviationPercentDisplay = tmpDeviationPercent
                self.anomalyScoreDisplay = tmpAnomalyScore
                self.anomalyTotalScoreDisplay = tmpAnomalyTotal
                self.detectionErrorDisplay = tmpDetectionError
                self.userFeedbackDisplay = tmpUserFeedback
                self.thresholdChangeDisplay = tmpThresholdChange
                self.confirmationTimeChangeDisplay = tmpConfirmationChange
                self.systemDetectionDisplay = tmpSystemDetection
                self.thresholdPercentDisplay = tmpThresholdPercent
                self.trendDisplay = tmpTrend
                self.detectSourceDisplay = tmpDetectSource
                // --- 組合短期/長期閾值變動字串 ---
                let composedShort: String = {
                    if tmpThresholdShortStr == "-" { return "-" }
                    if tmpAdjustmentSourceShort != "-" {
                        return tmpThresholdShortStr + " (" + tmpAdjustmentSourceShort + ")"
                    }
                    return tmpThresholdShortStr
                }()
                var tmpThresholdLongStr: String = "-"
                if thresholdLongDisplay != "-" { tmpThresholdLongStr = thresholdLongDisplay }
                let composedLong: String = {
                    if tmpThresholdLongStr == "-" { return "-" }
                    if tmpAdjustmentSourceLong != "-" {
                        return tmpThresholdLongStr + " (" + tmpAdjustmentSourceLong + ")"
                    }
                    return tmpThresholdLongStr
                }()

                self.thresholdShortDisplay = composedShort
                self.thresholdLongDisplay = composedLong
                self.timelinePoints = generatedTimeline
                self.timelineThresholdPercent = thresholdPercentForTimeline
                self.timelineMinutesRange = computedRange
                self.timelineCenterMinute = calculatedCenterMinute
                self.timelineUseFullRange = timelineUseFullRange
            }
        })
    }
    
    private func generateFakeLogFile() {
        let fakeLogLines = [
            "{\"ts\":\"2025-05-23T08:00:00.000Z\",\"type\":\"sessionStart\",\"payload\":{\"thresholdBPM\":60,\"rhr\":65,\"thresholdPercent\":94,\"minDurationSeconds\":180}}",
            "{\"ts\":\"2025-05-23T08:01:00.000Z\",\"type\":\"phaseChange\",\"payload\":{\"newPhase\":\"lightSleep\"}}",
            "{\"ts\":\"2025-05-23T08:10:00.000Z\",\"type\":\"hr\",\"payload\":{\"bpm\":58,\"phase\":\"lightSleep\",\"acc\":0.01}}",
            "{\"ts\":\"2025-05-23T08:20:00.000Z\",\"type\":\"anomaly\",\"payload\":{\"score\":2,\"totalScore\":5,\"adjustmentSourceAnomaly\":\"anomaly\"}}",
            "{\"ts\":\"2025-05-23T08:25:00.000Z\",\"type\":\"optimization\",\"payload\":{\"oldThreshold\":90,\"newThreshold\":92,\"deltaPercent\":2,\"oldDuration\":180,\"newDuration\":195,\"deltaDuration\":15,\"adjustmentSourceLong\":\"optimization\"}}",
            "{\"ts\":\"2025-05-23T08:30:00.000Z\",\"type\":\"feedback\",\"payload\":{\"type\":\"falsePositive\",\"accurate\":false}}",
            "{\"ts\":\"2025-05-23T08:31:00.000Z\",\"type\":\"sessionEnd\",\"payload\":{\"avgSleepHR\":62,\"rhr\":65,\"thresholdBPM\":60,\"thresholdPercent\":94,\"deviationPercent\":3.3,\"ratio\":1.03,\"deltaPercentShort\":2,\"deltaDurationShort\":15,\"trend\":-0.53,\"detectSource\":\"trend\",\"adjustmentSourceShort\":\"feedback\",\"detectedSleep\":true,\"notes\":\"測試用session\"}}"
        ]
        let content = fakeLogLines.joined(separator: "\n")
        let fileName = "powernap_session_" + DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .medium).replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-").replacingOccurrences(of: " ", with: "_") + ".log"
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!.appendingPathComponent("AdvancedLogFiles")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let fileURL = dir.appendingPathComponent(fileName)
        try? content.write(to: fileURL, atomically: true, encoding: .utf8)
        loadLogFiles()
    }
    
    private func fileDisplayName(from url: URL) -> String {
        let name = url.lastPathComponent.replacingOccurrences(of: "powernap_session_", with: "").replacingOccurrences(of: ".log", with: "")
        // 將 yyyy-MM-dd_HH-mm-ss 轉成容易閱讀的格式
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        if let date = formatter.date(from: name) {
            let out = DateFormatter()
            out.dateFormat = "MM/dd"
            let dateStr = out.string(from: date)
            out.dateFormat = "HH:mm"
            let timeStr = out.string(from: date)
            return "\(dateStr)\n\(timeStr)"
        }
        return name
    }
    
    // 共用日期解析器
    private static let iso8601: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
}

struct AdvancedLogsView_Previews: PreviewProvider {
    static var previews: some View {
        AdvancedLogsView()
    }
} 