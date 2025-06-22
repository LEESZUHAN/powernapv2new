# PowerNap 心率監測與閾值調整系統（v1.0.0）

> **文件定位說明**：本文件是 PowerNap 專案中心率監測與閾值調整系統的主要技術文檔，結合了原 HeartRateThresholdGuideline.md 和 HeartRateAlgorithmGuideline.md 的內容。本文詳細描述了心率監測原理、判定機制、閾值調整策略及個人化模型的完整實現方案。
> 
> **與其他文件的關係**：
> - 本文件與 [ConvergenceSystem.md](./ConvergenceSystem.md) 配合使用，後者專注於收斂算法的具體實現
> - 有關整體睡眠檢測機制，請參考 [SleepDetectionSystem.md](./SleepDetectionSystem.md)
> - 有關整體演算法開發計劃，請參考 [AlgorithmDevelopmentPlan.md](./AlgorithmDevelopmentPlan.md)
> - 若需了解專案整體架構和功能，請參考 [ProjectGuideline.md](./ProjectGuideline.md)

## 一、心率監測系統概述

心率監測系統是 PowerNap 應用的核心技術基礎，用於準確檢測用戶的睡眠狀態。該系統通過設定和動態調整相對於用戶靜息心率(RHR)的百分比閾值，來判定用戶是否進入睡眠狀態。當用戶實時心率低於該閾值並維持指定時間，系統判定用戶已進入睡眠。

### 核心組件

系統包含四大核心組件：
1. **基礎心率閾值計算**：根據用戶年齡組設定初始閾值百分比
2. **自動收斂機制**：分析睡眠數據，逐步優化個人化閾值
3. **手動調整界面**：允許用戶根據實際體驗進行調整
4. **異常處理策略**：處理壓力、姿勢變化等特殊情況

### 基於年齡組的閾值標準

| 年齡組 | 判定標準 | 確認時間 | 實現值 | 參考來源 |
|--------|----------|----------|--------|----------|
| 10–17 歲 (青少年) | 低於 RHR 的 85-90% | ≥ 2 分鐘 | 87.5% | 實際代碼實現及測試結果 |
| 18–59 歲 (成人) | 低於 RHR 的 88-92% | ≥ 3 分鐘 | 90.0% | Burgess 1999 成人實驗夜間及午睡資料 |
| ≥ 60 歲 (銀髮族) | 低於 RHR 的 92-95% | ≥ 4 分鐘 | 93.5% | 實際代碼實現及測試結果 |

## 二、心率監測的生理學基礎

### 睡眠時心率變化

睡眠時人體進入副交感神經主導狀態，心率自然下降：
- 典型成人：睡眠心率比靜息心率降低 5-10%
- 運動訓練者：下降幅度可能更大，高達 15-20%
- 老年人：下降幅度通常較小，約 2-5%

### 個體差異挑戰

固定閾值無法適應所有用戶：
- 運動員的心率變化範圍可能更大
- 老年用戶心率變化可能較小
- 心臟疾病患者可能有非典型心率模式
- 藥物影響可能改變正常心率反應

### 外部因素影響

多種因素會影響睡眠心率：
- 睡姿改變：俯臥時心率平均增加 4-5 BPM
- 壓力狀態：可能導致心率提高 4-8 BPM
- 環境溫度：高溫可能提高心率 2-4 BPM
- 飲食影響：酒精、咖啡因等刺激物

## 三、心率監測流程與機制

### 靜息心率獲取

1. **主要來源**：從 HealthKit 讀取用戶的靜息心率(RHR)數據
2. **備用策略**：若無法獲取，使用過去7天清晨心率平均值估算
3. **最低保障**：若無任何歷史數據，使用年齡組特定的默認值

### 心率分析流程

1. **年齡組判定**：
   - 基於用戶設定的年齡組選擇適當的閾值百分比
   - 不同年齡組使用不同的判定時間窗口

2. **運動員模式判斷**：
   - 若用戶 RHR < 40 bpm，自動啟用運動員模式
   - 運動員模式使用心率下降幅度（≥ 5 bpm）作為輔助判準
   - 結合 HeartRateAnomalyTracker 和靜止比例閾值判斷，降低對單一心率判定的依賴

3. **實時監測**：
   - 每 15-30 秒評估一次睡眠狀態
   - 將當前心率與閾值（RHR × 年齡組閾值比例）比較

4. **下降判定**：
   - 非運動員模式：當當前心率 ≤ RHR × 閾值比例時，判定為心率條件滿足
   - 運動員模式：當當前心率 < RHR - hrDropThreshold 時，判定為心率條件滿足

### ΔHR 輔助判定（v2.4 更新）

> 自 2024-06-10 起，ΔHR 不再作為獨立的「立即判睡」條件，而改為在滑動視窗不足 75 % 時的**輔助信號**。只有同時滿足下列三項，才視為有效：
>
> 1. ΔHR ≥ **max(10 bpm, RHR × 12 %)**
> 2. 前 60 筆心率平均 > *rawThreshold* × **1.05**
> 3. 後 60 筆樣本中 ≥ 90 % < *rawThreshold*
>
> 其中 *rawThreshold* = `heartRateThreshold × 0.95`（未含 buffer）。若條件成立，`detectSource` 會標記為 `"ΔHR"`，並僅在滑窗 near-miss 時提供「加分」作用。

### trend 輔助判定（v2.4 更新）

* 斜率門檻由 **–0.50** 調整為 **–0.20**。
* 只有在 `currentHR < 1.10 × RHR` 時才允許 trend 補判，以避免高 HR 錯判。

### 判定優先序

1. **滑動視窗**：75 % 樣本低於 (+敏) 閾值 → 立即判睡。
2. 若滑窗未滿足：
   a. trend 條件達標 → 判睡。
   b. ΔHR 條件達標 → 判睡。
3. 其他情況 → 等待下一輪評估。

## 四、核心數據結構與服務

### HeartRateService 實現
```swift
class HeartRateService: HeartRateServiceProtocol {
    // 關鍵屬性
    private(set) var currentHeartRate: Double = 0
    private(set) var restingHeartRate: Double = 60
    private(set) var heartRateThreshold: Double = 54 // 默認值，將根據RHR和閾值百分比動態計算
    private(set) var isProbablySleeping: Bool = false
    
    // 關鍵方法
    func startMonitoring()
    func stopMonitoring()
    func calculateHeartRateThreshold(for ageGroup: AgeGroup)
    func checkSleepCondition(motionState: Bool) -> Bool
}
```

### HeartRateAnomalyTracker 實現
> ⚠️ **注意：自 2025-06 起，HeartRateAnomalyTracker 評分與基線重置功能已暫時停用**（目前僅保留 Stub 類別以維持接口相容性；異常評分改由 UserSleepProfile 的 ratio→分數→累計分數 系統處理）。

```swift
class HeartRateAnomalyTracker {
    // 追蹤心率異常情況
    // 計算心率偏離度
    // 提供異常評分
    
    func trackHeartRate(_ heartRate: Double, timestamp: Date = Date())
    func resetBaseline()
    func getAnomalyScore() -> Double
}
```

### 核心計算邏輯
```swift
func calculateHeartRateThreshold(for ageGroup: AgeGroup) {
    // 獲取用戶的閾值調整設定
    let profile = userProfileManager.getUserProfile(forUserId: userId)
    let adjustmentOffset = profile?.manualAdjustmentOffset ?? 0.0
    
    // 根據年齡組選擇基本閾值百分比
    let basePercentage: Double
    switch ageGroup {
    case .teen:
        basePercentage = 0.875 // 87.5% for teens
    case .adult:
        basePercentage = 0.9   // 90% for adults
    case .senior:
        basePercentage = 0.935 // 93.5% for seniors
    }
    
    // 應用用戶的手動調整值
    let adjustedPercentage = basePercentage + adjustmentOffset
    
    // 計算實際心率閾值
    heartRateThreshold = restingHeartRate * adjustedPercentage
}
```

## 五、個人化心率模型實施方案

### 用戶睡眠設定檔

系統使用 `UserSleepProfile` 結構體儲存用戶的睡眠設定檔和調整參數：

```swift
public struct UserSleepProfile: Codable {
    // 基本信息
    public let userId: String
    public let ageGroup: AgeGroup
    
    // 心率閾值設定
    public var hrThresholdPercentage: Double  // 例如 0.9 表示 RHR 的 90%
    public var minDurationSeconds: Int        // 維持低心率需要的時間（秒）
    
    // 模型狀態追蹤
    public var firstUseDate: Date?            // 首次使用日期
    public var lastModelUpdateDate: Date?     // 最後一次模型更新日期
    public var sleepSessionsCount: Int        // 記錄的睡眠次數
    
    // 統計數據
    public var averageSleepHR: Double?        // 平均睡眠心率
    public var minSleepHR: Double?            // 最低睡眠心率
    public var sleepHRVariance: Double?       // 睡眠心率變異
    public var truePositiveRate: Double?      // 準確檢測率（如果有反饋）
    
    // 用戶手動調整值，範圍通常是 -0.05 到 +0.05
    public var manualAdjustmentOffset: Double = 0.0
    
    // 用戶反饋統計
    public var accurateDetectionCount: Int = 0   // 用戶反饋檢測準確的次數
    public var inaccurateDetectionCount: Int = 0 // 用戶反饋檢測不準確的次數
    
    // 靜止比例相關參數
    public var baseRestingRatioThreshold: Double // 基於年齡組的基礎靜止比例
    public var restingRatioAdjustment: Double = 0.0 // 用戶調整值，範圍-0.1到0.1之間
    
    // 睡眠確認時間收斂算法相關參數
    public var consecutiveDurationAdjustments: Int = 0 // 連續同方向的時間調整次數
    public var lastDurationAdjustmentDirection: Int = 0 // 最後一次時間調整方向
    public var sessionsSinceLastDurationAdjustment: Int = 0 // 自上次時間調整後的會話數
    public var durationAdjustmentStopped: Bool = false // 時間調整是否已經停止
    
    // 反饋類型相關參數
    public var consecutiveFeedbackAdjustments: Int = 0 // 連續反饋調整次數
    public var lastFeedbackType: SleepSession.SleepFeedback? = nil // 最後一次反饋類型
    
    // 碎片化睡眠模式
    public var fragmentedSleepMode: Bool = false // 是否啟用碎片化睡眠模式
}
```

### 自動優化觸發條件

系統會根據以下條件觸發閾值優化：

1. **首次優化**：
   - 累積至少5次睡眠記錄後
   - 自首次使用起至少7天

2. **定期優化**：
   - 距離上次更新超過14天時強制更新
   - 累積3次以上新會話且距離上次更新至少7天時更新
   - 有新的用戶反饋且距離上次更新至少3天時更新

### 閾值自動優化實現

```swift
public func analyzeAndOptimize(profile: UserSleepProfile, 
                               restingHR: Double,
                               recentSessions: [SleepSession]) -> OptimizedThresholds? {
    // 創建初始優化閾值
    var optimizedThresholds = OptimizedThresholds()
    
    // 收集心率數據
    let allHeartRates = recentSessions.flatMap { $0.heartRates }
    let avgHR = allHeartRates.reduce(0, +) / Double(allHeartRates.count)
    let minHR = allHeartRates.min() ?? (restingHR * 0.9)
    
    // 計算加權閾值（最低心率佔70%權重，平均心率佔30%權重）
    let lowHRPercentage = minHR / restingHR
    let avgHRPercentage = avgHR / restingHR
    var adjustedThreshold = (lowHRPercentage * 0.7) + (avgHRPercentage * 0.3)
    
    // 睡眠確認時間分析
    var adjustedDuration: TimeInterval = Double(profile.minDurationSeconds)
    
    // 分析睡眠檢測時間
    let sessionsWithSleepDetected = recentSessions.filter { $0.detectedSleepTime != nil }
    if !sessionsWithSleepDetected.isEmpty {
        // 計算平均檢測時間
        let detectionTimes = sessionsWithSleepDetected.compactMap { session -> TimeInterval? in
            guard let detectedTime = session.detectedSleepTime else { return nil }
            return detectedTime.timeIntervalSince(session.startTime)
        }
        
        if !detectionTimes.isEmpty {
            // 理想的確認時間約為平均檢測時間的20%
            let idealConfirmationTime = max(detectionTimes.reduce(0, +) / 
                                          Double(detectionTimes.count) * 0.2, 60)
            adjustedDuration = min(max(idealConfirmationTime, 60), 360)
        }
    }
    
    // 根據用戶反饋進行調整
    let sessionsWithFeedback = recentSessions.filter { 
        $0.userFeedback != .none && $0.userFeedback != nil 
    }
    
    if !sessionsWithFeedback.isEmpty {
        let falsePositives = sessionsWithFeedback.filter { 
            $0.userFeedback == .falsePositive 
        }.count
        let falseNegatives = sessionsWithFeedback.filter { 
            $0.userFeedback == .falseNegative 
        }.count
        let totalWithFeedback = sessionsWithFeedback.count
        
        // 根據反饋類型調整參數
        if falsePositives > totalWithFeedback / 3 {
            // 較多假陽性，增加確認時間
            adjustedDuration += 45
        }
        if falseNegatives > totalWithFeedback / 4 {
            // 較多假陰性，減少確認時間
            adjustedDuration -= 30
        }
    }
    
    // 確保參數在合理範圍內
    adjustedThreshold = min(max(adjustedThreshold, 0.70), 1.10)
    adjustedDuration = min(max(adjustedDuration, 60), 360)
    
    // 設置優化後的閾值
    optimizedThresholds.thresholdPercentage = adjustedThreshold
    optimizedThresholds.confirmationDuration = adjustedDuration
    
    return optimizedThresholds
}
```

## 六、手動閾值調整機制

### 手動調整範圍與機制

- **調整範圍**：用戶可調整 ±5% 的範圍（-0.05 到 +0.05）
- **UI 表示**：「判定較嚴格」（負向調整）到「判定較寬鬆」（正向調整）
- **效果說明**：
  - **正向調整 (+%, UI 標示「判定較寬鬆」)** 會提高心率門檻值，使 App **更容易**判定入睡
  - **負向調整 (-%, UI 標示「判定較嚴格」)** 會降低心率門檻值，使 App **更難**判定入睡

### 實現代碼
```swift
func updateUserManualAdjustment(profile: inout UserSleepProfile, adjustment: Double) {
    // 確保調整值在合理範圍內
    let limitedAdjustment = min(max(adjustment, -0.05), 0.05)
    
    // 應用調整
    profile.manualAdjustmentOffset = limitedAdjustment
    
    // 保存用戶配置
    saveUserProfile(profile)
    
    // 重新計算當前心率閾值
    recalculateCurrentThreshold()
}
```

## 七、系統測試與評估方法

### 單元測試

對各個組件進行獨立測試：
```swift
func testThresholdCalculation() {
    // 測試不同年齡組的基礎閾值
    XCTAssertEqual(getBaseThresholdPercentage(for: .teen), 0.875)
    XCTAssertEqual(getBaseThresholdPercentage(for: .adult), 0.9)
    XCTAssertEqual(getBaseThresholdPercentage(for: .senior), 0.935)
    
    // 測試閾值計算邏輯
    let profile = UserSleepProfile.createDefault(forUserId: "test", ageGroup: .adult)
    profile.manualAdjustmentOffset = 0.02
    let threshold = calculateThreshold(profile: profile, restingHR: 60.0)
    XCTAssertEqual(threshold, 55.2, accuracy: 0.1)
}
```

### 模擬測試

使用模擬數據測試系統反應：
```swift
func testThresholdOptimization() {
    // 創建模擬睡眠會話
    let sessions = createSimulatedSleepSessions(count: 5, heartRatePattern: .normal)
    
    // 測試優化算法
    let profile = UserSleepProfile.createDefault(forUserId: "test", ageGroup: .adult)
    let optimizedThresholds = analyzeAndOptimize(profile: profile, 
                                                restingHR: 60.0, 
                                                recentSessions: sessions)
    
    // 驗證優化結果在合理範圍內
    XCTAssertNotNil(optimizedThresholds)
    if let thresholds = optimizedThresholds {
        XCTAssert(thresholds.thresholdPercentage >= 0.85 && 
                  thresholds.thresholdPercentage <= 0.95)
        XCTAssert(thresholds.confirmationDuration >= 60 && 
                  thresholds.confirmationDuration <= 360)
    }
}
```

## 八、系統優化與迭代策略

### 數據收集與分析

持續收集實際用戶數據用於進一步優化：
- 記錄用戶睡眠心率分佈和模式
- 統計不同人群的閾值分佈（按年齡、性別、運動習慣分類）
- 分析心率閾值收斂過程的收斂速度和穩定性
- 分析系統判定與用戶反饋的一致性，計算準確率

### 算法優化方向

1. **加權指標優化**：
   - 當前實現中最低心率佔70%權重，平均心率佔30%
   - 後續可考慮動態調整權重，根據心率穩定性調整比例
   
2. **多維度分析**：
   - 整合加速度數據與心率數據的聯合判定
   - 分析睡眠時心率變異性(HRV)特徵
   - 若硬件支持，加入呼吸率數據輔助判定
   
3. **機器學習模型**：
   - 建立基於用戶反饋的分類模型
   - 結合多項生理特徵提取個性化睡眠模式

## 九、常見問題與解決方案

1. **系統無法檢測到睡眠**
   - 原因：閾值設置過低或用戶心率特徵異常
   - 解決：使用UI中的手動調整功能增加閾值數值（向右移動滑桿），使判定更寬鬆

2. **頻繁誤判睡眠**
   - 原因：閾值設置過高或確認時間過短
   - 解決：使用UI中的手動調整功能降低閾值數值（向左移動滑桿），使判定更嚴格

3. **閾值經常波動**
   - 原因：數據不足或用戶心率變異性高
   - 解決：增加收斂機制中的平滑因子，降低調整速度，減小單次調整幅度

4. **特殊情況處理**
   - 壓力：暫時增加手動調整值（+2-3%），壓力期間結束後恢復
   - 藥物：部分藥物可能影響心率，可在設置中標記特殊時期，暫停自動優化
   - 疾病：提供手動模式，允許用戶完全自定義閾值參數

5. **手動調整後仍不理想**
   - 原因：單一參數調整可能不足以應對複雜情況
   - 解決：嘗試啟用「碎片化睡眠模式」或使用高級設置調整多項參數

---

**版本記錄**：
- v1.0.0 (2024-05-20)：初始版本，合併 HeartRateThresholdGuideline.md 和 HeartRateAlgorithmGuideline.md
- 對應代碼版本：PowerNap v2.3.1 