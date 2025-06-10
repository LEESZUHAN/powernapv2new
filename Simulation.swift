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

        // 亂數產生 30 天睡眠會話
        let days = 30
        var generator = SystemRandomNumberGenerator()
        var lowAnomalyDays = Set<Int>()
        while lowAnomalyDays.count < 2 {
            lowAnomalyDays.insert(Int.random(in: 0..<days, using: &generator))
        }
        var highAnomalyDays = Set<Int>()
        while highAnomalyDays.count < 2 {
            let d = Int.random(in: 0..<days, using: &generator)
            if !lowAnomalyDays.contains(d) { highAnomalyDays.insert(d) }
        }

        // 劇烈組 B-3：藥物 & 碎片午睡
        let betaBlockerDays = Set(3...5)      // Day4-6 低 HR 0.78-0.84
        let coughMedDays    = Set([11,12])    // Day12-13 高 HR + 咳嗽高峰
        let fragmentDays    = Set(19...21)    // Day20-22 HR 0.95 持續波動

        let rhr: Double = 60 // 假設靜息心率（預設閾值仍 90%）

        var allDayAvgHR: [Double] = []
        var allDayFeedback: [String] = []
        var allDaySysDetect: [Bool] = []
        var allDayRealSleep: [Bool] = []

        for day in 0..<days {
            // 每天開始前，確保 profile 有正確的 restingHR
            var profileNow = userManager.getUserProfile(forUserId: userId)!
            profileNow.lastRestingHR = rhr
            userManager.saveUserProfile(profileNow)

            var session = SleepSession.create(userId: userId)
            var sumHR = 0.0
            var hrList: [Double] = []
            for i in 0..<200 {
                let hr: Double
                // 決定今日HR模式
                if betaBlockerDays.contains(day) {
                    // β-blocker 低 HR 0.78–0.84
                    let factor = Double.random(in: 0.78...0.84, using: &generator)
                    hr = rhr * factor + Double.random(in: -1...1, using: &generator)
                } else if coughMedDays.contains(day) {
                    // 咳嗽藥：1.08–1.12，且每2分鐘(120樣本)前15樣本峰值1.20
                    if i % 120 < 15 {
                        hr = rhr * 1.20 + Double.random(in: -2...2, using: &generator)
                    } else {
                        let factor = Double.random(in: 1.08...1.12, using: &generator)
                        hr = rhr * factor + Double.random(in: -2...2, using: &generator)
                    }
                } else if fragmentDays.contains(day) {
                    // 碎片睡：平均 0.95 並輕微波動
                    let factor = Double.random(in: 0.93...0.97, using: &generator)
                    hr = rhr * factor + Double.random(in: -3...3, using: &generator)
                } else {
                    // 正常日：0.98–1.02
                    let factor = Double.random(in: 0.98...1.02, using: &generator)
                    hr = rhr * factor + Double.random(in: -1...1, using: &generator)
                }
                sumHR += hr
                hrList.append(hr)
                session = session.addingHeartRate(hr)
            }
            let avgHR = sumHR / 200.0
            allDayAvgHR.append(avgHR)
            session = session.completing()
            let profileNow2 = userManager.getUserProfile(forUserId: userId)!
            // 加入使用者敏感度：+5%
            let effectiveThresholdPercent = profileNow2.hrThresholdPercentage + 0.05
            let threshold = effectiveThresholdPercent * rhr
            let ratio = avgHR / threshold
            // 計算趨勢
            let trend = calculateHeartRateTrend(from: hrList)
            let windowSeconds = profileNow2.minDurationSeconds // 例如成人 180 秒
            let windowSamples = min(windowSeconds, hrList.count)
            let requiredRatio = 0.75
            var belowCount = 0
            var sysDetect = false
            for (i, v) in hrList.enumerated() {
                if v < threshold { belowCount += 1 }

                if i >= windowSamples {
                    // 移除滑動窗口前端的值
                    if hrList[i - windowSamples] < threshold {
                        belowCount -= 1
                    }
                }

                if i >= windowSamples - 1 {
                    let ratioBelow = Double(belowCount) / Double(windowSamples)
                    if ratioBelow >= requiredRatio {
                        sysDetect = true
                        break
                    }
                }
            }
            // 若比例不足，檢查 ΔHR（前/後段平均差）
            if !sysDetect {
                let firstHalfAvg = hrList.prefix(100).reduce(0,+)/100.0
                let secondHalfAvg = hrList.suffix(100).reduce(0,+)/100.0
                let delta = firstHalfAvg - secondHalfAvg
                if delta >= max(4.0, rhr * 0.06) && (secondHalfAvg < threshold) {
                    sysDetect = true
                }
            }
            // A-3 無快/慢入睡區分，全程 realSleep = true
            let realSleep: Bool = true
            allDaySysDetect.append(sysDetect)
            allDayRealSleep.append(realSleep)
            let feedback: SleepSession.SleepFeedback
            if sysDetect && !realSleep {
                feedback = .falsePositive
                allDayFeedback.append("誤報")
                userManager.adjustHeartRateThreshold(forUserId: userId, feedbackType: .falsePositive)
            } else if !sysDetect && realSleep {
                feedback = .falseNegative
                allDayFeedback.append("漏報")
                userManager.adjustHeartRateThreshold(forUserId: userId, feedbackType: .falseNegative)
            } else if sysDetect && realSleep && avgHR < threshold * 0.90 {
                // 閾值與平均 HR 差距 >10% → 使用者可能尚未入睡；50% 機率回報誤報
                if Double.random(in: 0...1, using: &generator) < 0.5 {
                    feedback = .falsePositive
                    allDayFeedback.append("誤報")
                    userManager.adjustHeartRateThreshold(forUserId: userId, feedbackType: .falsePositive)
                } else {
                    feedback = .accurate
                    allDayFeedback.append("準確")
                }
            } else {
                feedback = .accurate
                allDayFeedback.append("準確")
            }
            session = session.withFeedback(feedback)
            session = session.withRatioToThreshold(ratio)
            userManager.saveSleepSession(session)
            // 重新取得最新 profile（調整後）
            let profileNow3 = userManager.getUserProfile(forUserId: userId)!
            let thresholdRaw = profileNow3.hrThresholdPercentage * rhr
            let thresholdWithSens = (profileNow3.hrThresholdPercentage + 0.05) * rhr
            let thresholdRawPct = profileNow3.hrThresholdPercentage * 100
            let thresholdSensPct = (profileNow3.hrThresholdPercentage + 0.05) * 100
            let avgPct = avgHR / rhr * 100
            let dailyScore = profileNow3.dailyDeviationScore
            let cumulativeScore = profileNow3.cumulativeScore
            print("Day \(day+1): 平均HR=\(String(format: "%.1f", avgHR)) (\(String(format: "%.0f", avgPct))%)，ratio=\(String(format: "%.3f", ratio))，trend=\(String(format: "%.2f", trend))，今日分數=\(dailyScore)，累計分數=\(cumulativeScore)，系統判定=\(sysDetect ? "睡著" : "未睡著")，feedback=\(allDayFeedback.last!)，閾值=\(String(format: "%.1f", thresholdRaw)) (\(String(format: "%.0f", thresholdRawPct))%), +敏=\(String(format: "%.1f", thresholdWithSens)) (\(String(format: "%.0f", thresholdSensPct))%)")
        }

        print("\n已生成 30 天睡眠資料（前15天98~102%，後15天一半快入睡(78~82%)、一半慢入睡(85~90%)），feedback 依據系統判斷與用戶真實自動產生")

        let optimizer = HeartRateThresholdOptimizer()
        let triggered = optimizer.checkAndOptimizeThreshold(userId: userId, restingHR: rhr, force: true)
        print("強制觸發優化: \(triggered)")

        // 等待優化結果（最長12秒），確保主佇列有機會執行
        for _ in 0..<60 { // 60 * 0.2 = 12 秒
            if case .optimizing = optimizer.optimizationStatus {
                RunLoop.current.run(until: Date().addingTimeInterval(0.2))
            } else {
                break
            }
        }

        switch optimizer.optimizationStatus {
        case .optimized(let result):
            print("\n===== 優化結果 =====")
            print("舊閾值百分比: \(String(format: "%.2f", result.previousThreshold*100))%")
            print("新閾值百分比: \(String(format: "%.2f", result.newThreshold*100))%")
            print("調整類型: \(result.adjustmentType.rawValue)")
            print("分析資料點: \(result.dataPointsAnalyzed)")
            print("信心度: \(String(format: "%.2f", result.confidenceLevel))")
            print("每日平均HR: \(allDayAvgHR.map{String(format: "%.1f", $0)}.joined(separator: ", "))")
            print("每日系統判定: \(allDaySysDetect.map{ $0 ? "睡著" : "未睡著" }.joined(separator: ", "))")
            print("每日feedback: \(allDayFeedback.joined(separator: ", "))")
            print("每日閾值: \((0..<allDayAvgHR.count).map{ _ in String(format: "%.1f", userManager.getUserProfile(forUserId: userId)!.hrThresholdPercentage * rhr) }.joined(separator: ", "))")
            
            // 收斂方向提示僅供調試，此處先移除向上收斂警告
            print("\n收斂流程完成，閾值由 \(String(format: "%.2f%%", result.previousThreshold*100)) → \(String(format: "%.2f%%", result.newThreshold*100))")
        default:
            print("優化未完成或失敗，最終狀態: \(optimizer.optimizationStatus)")
        }
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
} 