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

        let rhr: Double = 60 // 假設靜息
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
            for _ in 0..<200 {
                let hr: Double
                if day < 15 {
                    hr = rhr * Double.random(in: 0.98...1.02, using: &generator) + Double.random(in: -2...2, using: &generator)
                } else if fastSleep {
                    hr = rhr * Double.random(in: 0.78...0.82, using: &generator) + Double.random(in: -2...2, using: &generator)
                } else {
                    hr = rhr * Double.random(in: 0.85...0.90, using: &generator) + Double.random(in: -2...2, using: &generator)
                }
                sumHR += hr
                hrList.append(hr)
                session = session.addingHeartRate(hr)
            }
            let avgHR = sumHR / 200.0
            allDayAvgHR.append(avgHR)
            session = session.completing()
            let profileNow2 = userManager.getUserProfile(forUserId: userId)!
            let threshold = profileNow2.hrThresholdPercentage * rhr
            let ratio = avgHR / threshold
            let sysDetect = hrList.filter { $0 < threshold }.count > 100
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
            } else if !sysDetect && realSleep {
                feedback = .falseNegative
                allDayFeedback.append("漏報")
            } else if sysDetect && !realSleep && avgHR >= rhr * 0.80 && avgHR < rhr * 0.90 {
                if Double.random(in: 0...1, using: &generator) < 0.5 {
                    feedback = .falsePositive
                    allDayFeedback.append("誤報")
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
            let profileNow3 = userManager.getUserProfile(forUserId: userId)!
            let threshold2 = profileNow3.hrThresholdPercentage * rhr
            let thresholdPercent = (rhr > 0) ? (profileNow3.hrThresholdPercentage * 100) : 0
            let dailyScore = profileNow3.dailyDeviationScore
            let cumulativeScore = profileNow3.cumulativeScore
            print("Day \(day+1): 平均HR=\(String(format: "%.1f", avgHR))，ratio=\(String(format: "%.3f", ratio))，今日分數=\(dailyScore)，累計分數=\(cumulativeScore)，系統判定=\(sysDetect ? "睡著" : "未睡著")，feedback=\(allDayFeedback.last!)，閾值=\(String(format: "%.1f", threshold2)) (\(String(format: "%.0f", thresholdPercent))%)")
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