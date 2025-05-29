import XCTest
@testable import powernapv2new_Watch_App

final class SimulationTests: XCTestCase {
    func testThresholdOptimizer14Days() {
        let userId = "testUser"
        let userManager = UserSleepProfileManager.shared
        let profile = UserSleepProfile.createDefault(forUserId: userId, ageGroup: .adult)
        userManager.saveUserProfile(profile)

        let days = 14
        var generator = SystemRandomNumberGenerator()
        var highLowDays = Set<Int>()
        while highLowDays.count < 4 {
            highLowDays.insert(Int.random(in: 0..<days, using: &generator))
        }

        let rhr: Double = 60
        for day in 0..<days {
            var session = SleepSession.create(userId: userId)
            for _ in 0..<200 {
                var hr = Double.random(in: 55...65, using: &generator)
                if highLowDays.contains(day) {
                    let offset = Bool.random(using: &generator) ? 1.1 : 0.85
                    hr = rhr * offset + Double.random(in: -2...2, using: &generator)
                }
                session = session.addingHeartRate(hr)
            }
            session = session.completing()
            if Bool.random(using: &generator) {
                session = session.withDetectedSleepTime(session.startTime.addingTimeInterval(300))
            }
            let roll = Double.random(in: 0...1, using: &generator)
            let feedback: SleepSession.SleepFeedback
            if roll < 0.1 {
                feedback = .falsePositive
            } else if roll < 0.2 {
                feedback = .falseNegative
            } else {
                feedback = .accurate
            }
            session = session.withFeedback(feedback)
            userManager.saveSleepSession(session)
        }

        let optimizer = HeartRateThresholdOptimizer()
        let triggered = optimizer.checkAndOptimizeThreshold(userId: userId, restingHR: rhr, force: true)
        XCTAssertTrue(triggered, "應該能觸發優化")

        // 等待優化完成（最多12秒）
        for _ in 0..<60 {
            if case .optimizing = optimizer.optimizationStatus {
                RunLoop.current.run(until: Date().addingTimeInterval(0.2))
            } else {
                break
            }
        }

        switch optimizer.optimizationStatus {
        case .optimized(let result):
            print("舊閾值: \(result.previousThreshold), 新閾值: \(result.newThreshold)")
            XCTAssertLessThan(result.newThreshold, result.previousThreshold, "新閾值應該比舊閾值低（因為有HR偏低天）")
        default:
            XCTFail("優化未完成或失敗，狀態: \(optimizer.optimizationStatus)")
        }
    }
} 