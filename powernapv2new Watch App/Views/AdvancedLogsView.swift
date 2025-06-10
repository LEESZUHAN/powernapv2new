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
                Text("高級日誌分析")
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding(.vertical, 5)
                if logFiles.isEmpty {
                    Text("尚無記錄")
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
                        Text("重新整理")
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
                    Text("睡眠數據分析")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.bottom, 4)
                    // 心率數據
                    HStack {
                        Text("心率數據")
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
                        Text("偏離比例")
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
                        Text("異常評分")
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
                        Text("累計分數")
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
                        Text("閾值百分比")
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
                        Text("系統判定")
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
                        Text("漏/誤報")
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
                        Text("用戶反饋")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white)
                        Spacer()
                        Text(userFeedbackDisplay)
                            .font(.system(size: 12))
                            .foregroundColor(userFeedbackDisplay == "-" ? .gray : (userFeedbackDisplay == "準確" ? .green : .orange))
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 10)
                    .background(Color(white: 0.15))
                    .cornerRadius(8)
                    // 閾值調整（合併短/長/來源）
                    HStack {
                        Text("閾值調整")
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
                    // 確認時間（合併短/長）
                    HStack {
                        Text("確認時間")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white)
                        Spacer()
                        Text([confirmationShortDisplay, confirmationLongDisplay].filter { $0 != "-" }.joined(separator: " "))
                            .font(.system(size: 12))
                            .foregroundColor((confirmationShortDisplay == "-" && confirmationLongDisplay == "-") ? .gray : .blue)
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 10)
                    .background(Color(white: 0.15))
                    .cornerRadius(8)
                    // trend
                    HStack {
                        Text("心率趨勢 (trend)")
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
                        Text("判定來源")
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
                // 原始日誌區塊
                if !logLines.isEmpty {
                    Divider()
                        .background(Color.gray.opacity(0.3))
                        .padding(.vertical, 8)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("原始日誌")
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
            var tmpAdjustmentSourceAnomaly: String = "-"

            var detectedSleep: Bool? = nil
            var feedbackAccurate: Bool? = nil // nil 代表未評價
            var lastThreshold: Double? = nil
            var _newThreshold: Double? = nil // 保留供未來邏輯使用，暫不讀取
            var lastConfirmation: Int? = nil
            var _newConfirmation: Int? = nil // 保留供未來邏輯使用，暫不讀取
            for line in lines {
                if let d = line.data(using: .utf8),
                   let entry = try? decoder.decode(AdvancedLogger.LogEntry.self, from: d) {
                    entries.append(entry)
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
            // 解析異常評分 / 累計分數：取最後一筆 anomaly log
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
                if !accurateFlag {
                    tmpDetectionError = detected ? "誤報" : "漏報"
                }
            }
            // 解析 feedback/type、thresholdPercent、minDurationSeconds
            for entry in entries {
                if let log = entry as? AdvancedLogger.LogEntry, log.type == .sessionEnd {
                    if let t = log.payload["thresholdPercent"], let v = t.doubleValue {
                        if lastThreshold == nil { lastThreshold = v }
                        _newThreshold = v
                    }
                    if let c = log.payload["minDurationSeconds"], let v = c.doubleValue {
                        if lastConfirmation == nil { lastConfirmation = Int(v) }
                        _newConfirmation = Int(v)
                    }
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
                tmpSystemDetection = detected ? "睡著" : "沒睡著"
            }
            // 用戶反饋顯示
            if let accFlag = feedbackAccurate {
                tmpUserFeedback = accFlag ? "準確" : "不準確"
            } else {
                tmpUserFeedback = "未評價"
            }
            // 心率閾值調整 (短期)
            for entry in entries.reversed() {
                if let log = entry as? AdvancedLogger.LogEntry, log.type == .sessionEnd {
                    if let dps = log.payload["deltaPercentShort"], let v = dps.doubleValue { deltaPercentShortVal += v }
                    if let dds = log.payload["deltaDurationShort"], let v = dds.doubleValue { deltaDurationShortVal += Int(v) }
                    break
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
                thresholdShortDisplay = intVal > 0 ? "+\(intVal)%" : "\(intVal)%"
            }
            if deltaPercentLongVal != 0 {
                let intVal = Int(round(deltaPercentLongVal))
                thresholdLongDisplay = intVal > 0 ? "+\(intVal)%" : "\(intVal)%"
            }
            if deltaDurationShortVal != 0 {
                confirmationShortDisplay = deltaDurationShortVal > 0 ? "+\(deltaDurationShortVal)秒" : "\(deltaDurationShortVal)秒"
            }
            if deltaDurationLongVal != 0 {
                confirmationLongDisplay = deltaDurationLongVal > 0 ? "+\(deltaDurationLongVal)秒" : "\(deltaDurationLongVal)秒"
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
            // 解析 adjustmentSourceAnomaly
            for entry in entries.reversed() {
                if let log = entry as? AdvancedLogger.LogEntry, log.type == .anomaly {
                    if let src = log.payload["adjustmentSourceAnomaly"]?.stringValue {
                        tmpAdjustmentSourceAnomaly = src
                    }
                    break
                }
            }
            DispatchQueue.main.async {
                self.logLines = entries.map { String(describing: $0) }
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
                self.thresholdShortDisplay = thresholdShortDisplay + (tmpAdjustmentSourceShort != "-" ? " (" + tmpAdjustmentSourceShort + ")" : "")
                self.thresholdLongDisplay = thresholdLongDisplay + (tmpAdjustmentSourceLong != "-" ? " (" + tmpAdjustmentSourceLong + ")" : "")
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
}

struct AdvancedLogsView_Previews: PreviewProvider {
    static var previews: some View {
        AdvancedLogsView()
    }
} 