import Foundation

// 引入現有模型檔案（需要同一個編譯單元）
// 這個腳本僅供 CLI 測試，並不加入 Xcode Target。

@main
struct SimulationApp {
    static func main() {
        let userId = "testUser"
        let userManager = UserSleepProfileManager.shared
        // 建立或重置用戶
        let profile = UserSleepProfile.createDefault(forUserId: userId, ageGroup: .adult)
        userManager.saveUserProfile(profile)

        // === D-3 腳本（生活型態混合） ===
        let days = 60
        let sampleCount = 200
        let rhr: Double = 60
        // === 指定 20 天為「未睡著」的清醒日 (0-based index) ===
        let awakeDays: Set<Int> = [2, 5, 8, 11, 14, 17, 20, 23, 26, 29,
                                    32, 35, 38, 41, 44, 47, 50, 53, 56, 58]
        let deltaHRWindowSize = 60 // ΔHR 視窗大小

        var allDayAvgHR: [Double] = []
        var allDayFeedback: [String] = []
        var allDaySysDetect: [Bool] = []

        for day in 0..<days {
            // 更新靜息心率 (模擬)
            var profileNow = userManager.getUserProfile(forUserId: userId)!
            profileNow.lastRestingHR = rhr
            userManager.saveUserProfile(profileNow)

            // 建立 Session 並寫入 HR 樣本
            var session = SleepSession.create(userId: userId)
            // 若屬於清醒日，產生 Awake HR；否則使用 D-3 腳本
            let isAwake = awakeDays.contains(day)
            let hrList = isAwake ? generateAwakeHR(sampleCount: sampleCount, rhr: rhr)
                                 : generateD3HR(day: day, sampleCount: sampleCount)
            for hr in hrList { session = session.addingHeartRate(hr) }

            // 完成會話並統計
            session = session.completing()
            let avgHR = hrList.reduce(0, +) / Double(hrList.count)
            allDayAvgHR.append(avgHR)

            // 取得最新 Profile（可能因前一日 feedback 而變動）
            let profileNow2 = userManager.getUserProfile(forUserId: userId)!
            let effectiveThresholdPct = profileNow2.hrThresholdPercentage + 0.05
            let threshold = effectiveThresholdPct * rhr
            let ratio = avgHR / threshold
            let trend = calculateHeartRateTrend(from: hrList)

            // ---- 睡眠判定 ----
            let windowS = profileNow2.minDurationSeconds
            let windowSamples = min(windowS, hrList.count)
            var sysDetect = false
            var detectSource = ""
            let thresholdRaw = profileNow2.hrThresholdPercentage * rhr // 未加敏感度的原始閾值
            var belowCountSens = 0 // 使用 +敏 閾值
            var belowCountRaw  = 0 // 使用 raw 閾值

            var slidingRatioSens: Double = 0.0
            var slidingRatioRaw : Double = 0.0

            for (i, v) in hrList.enumerated() {
                if v < threshold { belowCountSens += 1 }
                if v < thresholdRaw { belowCountRaw += 1 }

                if i >= windowSamples {
                    if hrList[i - windowSamples] < threshold { belowCountSens -= 1 }
                    if hrList[i - windowSamples] < thresholdRaw { belowCountRaw -= 1 }
                }

                if i >= windowSamples - 1 {
                    slidingRatioSens = Double(belowCountSens) / Double(windowSamples)
                    slidingRatioRaw  = Double(belowCountRaw)  / Double(windowSamples)

                    // 主要偵測：Sens ratio ≥ 0.75
                    if slidingRatioSens >= 0.75 {
                        sysDetect = true; detectSource = "滑動視窗"; break
                    }
                }
            }

            // 2. ΔHR 輔助判定（僅 raw ratio 在 0.60~0.85 之間時考慮）
            if !sysDetect && slidingRatioRaw >= 0.60 && slidingRatioRaw < 0.85 && hrList.count >= deltaHRWindowSize*2 {
                let firstWindow = hrList.prefix(deltaHRWindowSize)
                let lastWindow  = hrList.suffix(deltaHRWindowSize)
                let firstAvg = firstWindow.reduce(0,+) / Double(deltaHRWindowSize)
                let lastAvg  = lastWindow.reduce(0,+) / Double(deltaHRWindowSize)
                let delta = firstAvg - lastAvg

                // 額外條件：前段必須明顯高於 raw threshold
                let firstAbove = firstAvg > thresholdRaw * 1.05

                // 末段必須低於 raw threshold，且 90% 以下
                let lastBelow = lastWindow.filter { $0 < thresholdRaw }.count
                let lastRatio = Double(lastBelow) / Double(deltaHRWindowSize)

                if firstAbove && delta >= max(10.0, rhr*0.12) && lastAvg < thresholdRaw && lastRatio >= 0.90 {
                    sysDetect = true; detectSource = "ΔHR"
                }
            }

            // 3. trend 輔助判定
            if !sysDetect && (
                (trend < -0.15 && avgHR < rhr * 1.05) ||
                (trend < -0.20 && avgHR < rhr * 1.10)
            ) {
                sysDetect = true; detectSource = "trend"
            }

            // ---- feedback 與閾值調整 ----
            let realSleep = !awakeDays.contains(day)
            let feedback: SleepSession.SleepFeedback
            if sysDetect && !realSleep {
                feedback = .falsePositive; allDayFeedback.append("誤報")
                userManager.adjustHeartRateThreshold(forUserId: userId, feedbackType: .falsePositive)
            } else if !sysDetect && realSleep {
                feedback = .falseNegative; allDayFeedback.append("漏報")
                userManager.adjustHeartRateThreshold(forUserId: userId, feedbackType: .falseNegative)
            } else if sysDetect && realSleep && threshold > avgHR * 1.15 {
                if Double.random(in: 0...1) < 0.5 {
                    feedback = .falsePositive; allDayFeedback.append("誤報")
                    userManager.adjustHeartRateThreshold(forUserId: userId, feedbackType: .falsePositive)
                } else {
                    feedback = .accurate; allDayFeedback.append("準確")
                }
            } else {
                feedback = .accurate; allDayFeedback.append("準確")
            }

            // 保存 Session
            session = session.withFeedback(feedback)
            session = session.withRatioToThreshold(ratio)
            userManager.saveSleepSession(session)
            allDaySysDetect.append(sysDetect)

            // ---- 每日輸出 ----
            let thresholdWithSens = effectiveThresholdPct * rhr
            let thresholdRawPct = profileNow2.hrThresholdPercentage * 100
            let thresholdSensPct = effectiveThresholdPct * 100
            let avgPct = avgHR / rhr * 100
            let src = detectSource.isEmpty ? "-" : detectSource
            print("Day \(day+1): 平均HR=\(String(format: "%.1f", avgHR)) (\(String(format: "%.0f", avgPct))%)，ratio=\(String(format: "%.3f", ratio))，trend=\(String(format: "%.2f", trend))，系統判定=\(sysDetect ? "睡著" : "未睡著")，實際=\(realSleep ? "睡著" : "未睡著")，來源=\(src)，feedback=\(allDayFeedback.last!)，閾值=\(String(format: "%.1f", thresholdRaw)) (\(String(format: "%.0f", thresholdRawPct))%)，+敏=\(String(format: "%.1f", thresholdWithSens)) (\(String(format: "%.0f", thresholdSensPct))%)")
        }

        // ---- 自動統計 ----
        let summary = Dictionary(grouping: allDayFeedback, by: { $0 }).mapValues { $0.count }
        let accurateDays = summary["準確", default: 0]
        let missDays     = summary["漏報", default: 0]
        let falseDays    = summary["誤報", default: 0]
        print("\n===== 統計 =====")
        print("準確: \(accurateDays) 天, 漏報: \(missDays) 天, 誤報: \(falseDays) 天")

        // ---- Summary 與 Optimizer ----
        print("\n已生成 \(days) 天 D-3 腳本資料")

        let optimizer = HeartRateThresholdOptimizer()
        let triggered = optimizer.checkAndOptimizeThreshold(userId: userId, restingHR: rhr, force: true)
        print("強制觸發優化: \(triggered)")

        for _ in 0..<60 {
            if case .optimizing = optimizer.optimizationStatus { RunLoop.current.run(until: Date().addingTimeInterval(0.2)) } else { break }
        }

        if case .optimized(let result) = optimizer.optimizationStatus {
            print("\n===== 優化結果 =====")
            print("舊閾值百分比: \(String(format: "%.2f", result.previousThreshold*100))%")
            print("新閾值百分比: \(String(format: "%.2f", result.newThreshold*100))%")
            print("調整類型: \(result.adjustmentType.rawValue)")
            print("分析資料點: \(result.dataPointsAnalyzed)")
            print("信心度: \(String(format: "%.2f", result.confidenceLevel))")
        }

        return // 避免落入任何遺留程式碼
    }

    // === 新增：計算 heartRateTrend（加權線性斜率，與主程式相同的加權線性斜率） ===
    static func calculateHeartRateTrend(from hrSeries: [Double], sampleInterval: Double = 1.0) -> Double {
        // Mimic HeartRateService.calculateHeartRateTrend()
        guard hrSeries.count >= 3 else { return 0.0 }

        var sumX = 0.0, sumY = 0.0, sumXY = 0.0, sumX2 = 0.0, weights = 0.0
        for (i, hr) in hrSeries.enumerated() {
            let x = Double(i) * sampleInterval  // 使用秒為單位
            let weight = 1.0 + Double(i) * 0.2  // 與主程式相同的權重策略
            sumX  += x * weight
            sumY  += hr * weight
            sumXY += x * hr * weight
            sumX2 += x * x * weight
            weights += weight
        }

        let meanX = sumX / weights
        let meanY = sumY / weights
        let slope = (sumXY - sumX * meanY) / (sumX2 - sumX * meanX)

        // 標準化到 [-1,1]，假設『心率每分鐘變化 2BPM』為基準
        let normalizedSlope = slope * 30.0 / 2.0  // 30 秒對應主程式係數
        return max(min(normalizedSlope, 1.0), -1.0)
    }

    // === D-3 腳本（生活型態混合） ===
    static func generateD3HR(day: Int, sampleCount: Int) -> [Double] {
        // D-3 腳本修正版：
        // - 週一至週五：正常作息，HR 0.98–1.02。
        // - 週三、週五：下班後運動，隔日午休 HR 下降幅度大（0.97→0.88）。
        // - 週末（day%7==5,6）：前夜晚睡/小酌，午休 HR 較高（1.05–1.10），入睡後 HR 緩降但不明顯。
        // - 月底（day==27,28,29）：工作壓力高，午休 HR 1.10–1.13，入睡後 HR 緩降至 1.00。
        let rhr: Double = 60
        var hrList: [Double] = []
        let minuteSamples = sampleCount / 30 // 假設 30 分鐘 nap
        let rand = { (a: Double, b: Double) in Double.random(in: a...b) }
        let weekday = day % 7
        if day >= 27 && day <= 29 { // 月底壓力
            // 前10分鐘 0.97–1.00
            for _ in 0..<(minuteSamples*10) { hrList.append(rhr * rand(0.97,1.00)) }
            // 10~30分鐘 緩降至0.87
            for i in 0..<(minuteSamples*20) {
                let ratio = 1.00 - 0.13 * Double(i) / Double(minuteSamples*20-1)
                hrList.append(rhr * rand(ratio-0.01, ratio+0.01))
            }
        } else if weekday == 5 || weekday == 6 { // 週末
            // 週末極限跳升：前10分鐘 1.05–1.10 RHR
            for _ in 0..<(minuteSamples*10) { hrList.append(rhr * rand(1.05,1.10)) }
            // 10~30分鐘 緩降至1.00
            for i in 0..<(minuteSamples*20) {
                let ratio = 1.10 - 0.10 * Double(i) / Double(minuteSamples*20-1)
                hrList.append(rhr * rand(ratio-0.01, ratio+0.01))
            }
        } else if weekday == 2 || weekday == 4 { // 週三、週五運動日
            // 前5分鐘 0.84–0.86
            for _ in 0..<(minuteSamples*5) { hrList.append(rhr * rand(0.84,0.86)) }
            // 5~15分鐘 線性降至0.75
            for i in 0..<(minuteSamples*10) {
                let ratio = 0.84 - 0.09 * Double(i) / Double(minuteSamples*10-1)
                hrList.append(rhr * rand(ratio-0.01, ratio+0.01))
            }
            // 15~30分鐘 維持0.75–0.77
            for _ in 0..<(minuteSamples*15) { hrList.append(rhr * rand(0.75,0.77)) }
        } else { // 週一至週五正常日
            for _ in 0..<sampleCount { hrList.append(rhr * rand(0.85,0.89)) }
        }
        return hrList
    }

    // === ΔHR 靈敏度專用腳本 ===
    static func generateDeltaHRTestHR(day: Int, sampleCount: Int) -> [Double] {
        // 前半段高HR（1.10），後半段緩降至0.98，ΔHR容易達標但滑動視窗不一定
        let rhr: Double = 60
        var hrList: [Double] = []
        let half = sampleCount / 2
        for _ in 0..<half { hrList.append(rhr * 1.10 + Double.random(in: -0.5...0.5)) }
        for i in 0..<half {
            let ratio = 1.10 - 0.12 * Double(i) / Double(half-1) // 緩降至0.98
            hrList.append(rhr * ratio + Double.random(in: -0.5...0.5))
        }
        return hrList
    }

    // === 生成未睡著（Awake）HR 序列 ===
    static func generateAwakeHR(sampleCount: Int, rhr: Double) -> [Double] {
        var hrList: [Double] = []
        var current = rhr * Double.random(in: 1.08...1.15)
        for _ in 0..<sampleCount {
            // 隨機微幅波動 ±0.3 bpm，夾在 1.05~1.18 RHR 之間
            current += Double.random(in: -0.3...0.3)
            current = min(max(current, rhr * 1.05), rhr * 1.18)
            hrList.append(current)
        }
        return hrList
    }
} 