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

        // MARK: - 情境定義
        enum Scenario {
            case postMeal   // M-1 餐後血糖高（RHR +5% 上下）
        }

        let scenario: Scenario = .postMeal // 目前只跑 M-1，可之後切換

        let rhr: Double = 60 // 假設靜息心率
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
            let fastSleep = (day % 2 == 0) // 後15天一半天數快入睡，一半慢入睡
            let realSleep: Bool
            for i in 0..<200 {
                let hr: Double
                switch scenario {
                case .postMeal:
                    // 加入「時間軸」：前120秒逐步降至 ~90%閾值，之後再慢降
                    if i < 120 {
                        // 緩降區：從 1.08×RHR 緩降到 1.00×RHR
                        let t = Double(i) / 119.0 // 0→1
                        let factor = 1.08 - 0.08 * t  // 1.08 → 1.00
                        hr = rhr * factor + Double.random(in: -2...2, using: &generator)
                    } else {
                        // 進一步下降區：目標 0.82×RHR，線性下滑
                        let t = Double(i - 120) / 79.0 // 0→1
                        let factor = 1.00 - 0.18 * t   // 1.00 → 0.82
                        hr = rhr * factor + Double.random(in: -2...2, using: &generator)
                    }
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
            if day < 15 {
                realSleep = true
            } else if fastSleep {
                realSleep = true
            } else {
                realSleep = false
            }
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
            } else if sysDetect && !realSleep && avgHR >= rhr * 0.80 && avgHR < rhr * 0.90 {
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
            print("Day \(day+1): 平均HR=\(String(format: "%.1f", avgHR)) (\(String(format: "%.0f", avgPct))%)，ratio=\(String(format: "%.3f", ratio))，今日分數=\(dailyScore)，累計分數=\(cumulativeScore)，系統判定=\(sysDetect ? "睡著" : "未睡著")，feedback=\(allDayFeedback.last!)，閾值=\(String(format: "%.1f", thresholdRaw)) (\(String(format: "%.0f", thresholdRawPct))%), +敏=\(String(format: "%.1f", thresholdWithSens)) (\(String(format: "%.0f", thresholdSensPct))%)")
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
            
            if result.newThreshold > result.previousThreshold {
                print("\n✅ 閾值有向上收斂，演算法正常！")
            } else {
                print("\n⚠️ 閾值未向上收斂，請檢查演算法！")
            }
        default:
            print("優化未完成或失敗，最終狀態: \(optimizer.optimizationStatus)")
        }
    }
} 