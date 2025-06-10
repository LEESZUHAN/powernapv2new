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
            let hrList = generateD3HR(day: day, sampleCount: sampleCount)
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
            // 1. 滑動視窗：最新 windowSamples 筆資料中，75% 低於 threshold 則判睡
            let windowS = profileNow2.minDurationSeconds
            let windowSamples = min(windowS, hrList.count)
            var belowCount = 0
            var sysDetect = false
            for (i,v) in hrList.enumerated() {
                if v < threshold { belowCount += 1 }
                if i >= windowSamples {
                    if hrList[i - windowSamples] < threshold { belowCount -= 1 }
                }
                if i >= windowSamples - 1 {
                    if Double(belowCount) / Double(windowSamples) >= 0.75 { sysDetect = true; break }
                }
            }
            // 2. ΔHR 輔助判定：若「最前面 deltaHRWindowSize 筆」與「最後面 deltaHRWindowSize 筆」平均差大於 4bpm 或 6%RHR，且後段低於 threshold，則判睡
            if !sysDetect, hrList.count >= deltaHRWindowSize*2 {
                let firstAvg = hrList.prefix(deltaHRWindowSize).reduce(0,+) / Double(deltaHRWindowSize)
                let lastAvg  = hrList.suffix(deltaHRWindowSize).reduce(0,+) / Double(deltaHRWindowSize)
                let delta = firstAvg - lastAvg
                if delta >= max(4.0, rhr*0.06) && lastAvg < threshold { sysDetect = true }
            }
            // 3. trend 輔助判定：若 trend < -0.15 且 avgHR < rhr*1.05，則判睡
            if !sysDetect && trend < -0.15 && avgHR < rhr * 1.05 {
                sysDetect = true
            }

            // ---- feedback 與閾值調整 ----
            let realSleep = true
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
            let thresholdRaw = profileNow2.hrThresholdPercentage * rhr
            let thresholdWithSens = effectiveThresholdPct * rhr
            let thresholdRawPct = profileNow2.hrThresholdPercentage * 100
            let thresholdSensPct = effectiveThresholdPct * 100
            let avgPct = avgHR / rhr * 100
            print("Day \(day+1): 平均HR=\(String(format: "%.1f", avgHR)) (\(String(format: "%.0f", avgPct))%)，ratio=\(String(format: "%.3f", ratio))，trend=\(String(format: "%.2f", trend))，系統判定=\(sysDetect ? "睡著" : "未睡著")，feedback=\(allDayFeedback.last!)，閾值=\(String(format: "%.1f", thresholdRaw)) (\(String(format: "%.0f", thresholdRawPct))%), +敏=\(String(format: "%.1f", thresholdWithSens)) (\(String(format: "%.0f", thresholdSensPct))%)")
        }

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
            // 前10分鐘 1.10–1.13
            for _ in 0..<(minuteSamples*10) { hrList.append(rhr * rand(1.10,1.13)) }
            // 10~30分鐘 緩降至1.00
            for i in 0..<(minuteSamples*20) {
                let ratio = 1.13 - 0.13 * Double(i) / Double(minuteSamples*20-1)
                hrList.append(rhr * rand(ratio-0.01, ratio+0.01))
            }
        } else if weekday == 5 || weekday == 6 { // 週末
            // 前10分鐘 1.05–1.10
            for _ in 0..<(minuteSamples*10) { hrList.append(rhr * rand(1.05,1.10)) }
            // 10~30分鐘 緩降至1.00
            for i in 0..<(minuteSamples*20) {
                let ratio = 1.10 - 0.10 * Double(i) / Double(minuteSamples*20-1)
                hrList.append(rhr * rand(ratio-0.01, ratio+0.01))
            }
        } else if weekday == 2 || weekday == 4 { // 週三、週五運動日
            // 前5分鐘 0.97–0.99
            for _ in 0..<(minuteSamples*5) { hrList.append(rhr * rand(0.97,0.99)) }
            // 5~15分鐘 線性降至0.88
            for i in 0..<(minuteSamples*10) {
                let ratio = 0.97 - 0.09 * Double(i) / Double(minuteSamples*10-1)
                hrList.append(rhr * rand(ratio-0.01, ratio+0.01))
            }
            // 15~30分鐘 維持0.88–0.90
            for _ in 0..<(minuteSamples*15) { hrList.append(rhr * rand(0.88,0.90)) }
        } else { // 週一至週五正常日
            for _ in 0..<sampleCount { hrList.append(rhr * rand(0.98,1.02)) }
        }
        return hrList
    }
} 