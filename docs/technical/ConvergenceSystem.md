# PowerNap 收斂與睡眠確認系統（v1.0.0）

> **文件定位說明**：本文件是 PowerNap 專案中收斂機制與睡眠確認系統的主要技術文檔，結合了原 convergence_algorithm.md 和 SleepConfirmationAlgorithm.md 的內容。本文詳細描述了收斂機制的原理、睡眠確認流程以及兩者如何協同工作提高睡眠檢測的準確性。
> 
> **與其他文件的關係**：
> - 本文件與 [HeartRateSystem.md](./HeartRateSystem.md) 配合使用，後者專注於心率監測與閾值調整的整體系統
> - 有關整體睡眠檢測機制，請參考 [SleepDetectionSystem.md](./SleepDetectionSystem.md)
> - 有關整體演算法開發計劃，請參考 [AlgorithmDevelopmentPlan.md](./AlgorithmDevelopmentPlan.md)
> - 若需了解專案整體架構和功能，請參考 [ProjectGuideline.md](./ProjectGuideline.md)

## 一、收斂機制基本原理

### 什麼是收斂機制

收斂機制是 PowerNap 應用中的核心自適應系統，旨在根據用戶的實際睡眠生理特徵和使用反饋，持續優化心率和動作閾值參數，使睡眠檢測更加精準。該機制能夠逐步「學習」用戶的睡眠模式，並針對個人特徵調整判定標準。

### 為什麼需要收斂機制

1. **生理差異適應**：不同用戶的心率下降模式存在顯著差異
2. **環境適應性**：環境因素如溫度、噪音和壓力等會影響睡眠模式
3. **穩定性提升**：減少單次數據異常引起的判定偏差
4. **個性化體驗**：為每位用戶創建專屬的睡眠檢測標準

## 二、收斂算法核心實現

### 基於梯度的自適應調整算法

收斂機制採用漸進式調整策略，根據用戶睡眠數據和反饋情況，按照特定的調整量逐步優化參數：

```swift
func adjustThreshold(currentValue: Double, 
                     targetDirection: AdjustmentDirection, 
                     userProfile: UserSleepProfile) -> Double {
    // 基礎調整量
    let baseAdjustment: Double = 0.01 // 1% 的基礎調整量
    
    // 調整係數，用於控制調整速度
    var adjustmentCoefficient: Double = 1.0
    
    // 根據連續同向調整次數增加調整幅度
    if userProfile.consecutiveThresholdAdjustments > 0 && 
       userProfile.lastAdjustmentDirection == targetDirection.rawValue {
        // 每次連續同向調整增加 10% 的調整量
        adjustmentCoefficient += Double(min(userProfile.consecutiveThresholdAdjustments, 5)) * 0.1
    } else {
        // 方向變更，重置調整係數
        adjustmentCoefficient = 0.8 // 首次變向時降低調整量
    }
    
    // 根據已有會話數量調整係數
    if userProfile.sleepSessionsCount < 10 {
        // 初始階段，調整幅度較大
        adjustmentCoefficient *= 1.2
    } else if userProfile.sleepSessionsCount > 30 {
        // 穩定階段，調整幅度較小
        adjustmentCoefficient *= 0.8
    }
    
    // 計算最終調整量
    let adjustmentAmount = baseAdjustment * adjustmentCoefficient
    
    // 應用調整
    let newValue: Double
    switch targetDirection {
    case .increase:
        newValue = min(currentValue + adjustmentAmount, 1.0) // 上限為 1.0（100%）
    case .decrease:
        newValue = max(currentValue - adjustmentAmount, 0.7) // 下限為 0.7（70%）
    case .noChange:
        newValue = currentValue
    }
    
    return newValue
}
```

### 衰減因子與遞減調整

為了避免過度調整，系統實現了衰減機制：

```swift
func calculateDecayFactor(sessions: Int, lastChangeDirection: AdjustmentDirection) -> Double {
    // 基礎衰減因子
    let baseDecay = 1.0
    
    // 會話數量影響
    let sessionFactor = min(sessions / 10.0, 3.0) * 0.1
    
    // 方向變更影響
    let directionFactor = lastChangeDirection == .noChange ? 0.2 : 0.0
    
    // 最終衰減因子
    return min(baseDecay - sessionFactor - directionFactor, 0.95)
}
```

### 異常評分與觸發門檻（v2.4 更新）

| 指標 | 條件 (ratio = AvgHR / Threshold) | 加分 |
|------|---------------------------------|------|
| 極端低 | ratio < **0.94** | +3 |
| 偏低   | 0.94 ≤ ratio < 0.97 | +2 |
| 正常   | 0.97 ≤ ratio ≤ 1.06 | +0 |
| 偏高   | 1.06 < ratio ≤ 1.10 | +2 |
| 極端高 | ratio > **1.10** | +3 |

* **scoreThreshold**：由原 12 分下調至 **8 分**。累積分數 ≥ 8 時觸發 `adjustHeartRateThreshold`。  
* **加分條件**：
  1. `session.detectedSleepTime != nil`（系統已判睡）；或  
  2. ratio 落在「極端區」(<0.94 或 >1.10)。
  清醒且 ratio 在正常／偏區間者將不累積分數，避免髒資料干擾。

> 此邏輯與 `UserSleepProfile.swift` 中 `calculateDeviationScore`、`scoreThreshold = 8` 完全對應。

### 反饋學習機制

系統會記錄並分析用戶的反饋情況，調整參數優化方向：

```swift
func processFeedback(feedback: SleepFeedback, profile: inout UserSleepProfile) {
    switch feedback {
    case .falsePositive:
        // 誤判為睡眠（用戶實際未睡）
        // 增加心率門檻，使判定更嚴格
        profile.hrThresholdPercentage = adjustThreshold(
            currentValue: profile.hrThresholdPercentage,
            targetDirection: .decrease,
            userProfile: profile
        )
        
        // 可能需要增加確認時間
        if profile.minDurationSeconds < 240 {
            profile.minDurationSeconds += 15
        }
        
        // 記錄反饋方向
        updateConsecutiveFeedbackCount(profile: &profile, feedback: .falsePositive)
        
    case .falseNegative:
        // 未能判定為睡眠（用戶實際已睡）
        // 降低心率門檻，使判定更寬鬆
        profile.hrThresholdPercentage = adjustThreshold(
            currentValue: profile.hrThresholdPercentage,
            targetDirection: .increase,
            userProfile: profile
        )
        
        // 可能需要減少確認時間
        if profile.minDurationSeconds > 90 {
            profile.minDurationSeconds -= 15
        }
        
        // 記錄反饋方向
        updateConsecutiveFeedbackCount(profile: &profile, feedback: .falseNegative)
        
    case .accurate:
        // 準確判定，輕微調整以強化當前參數
        // 記錄準確判定
        profile.accurateDetectionCount += 1
        
        // 如果連續準確反饋較多，減小調整幅度
        if profile.consecutiveFeedbackAdjustments > 2 {
            profile.consecutiveFeedbackAdjustments = 0
        }
    }
    
    // 更新反饋時間和次數
    profile.lastFeedbackTime = Date()
    profile.lastFeedbackType = feedback
}
```

## 三、睡眠確認流程與機制

### 多階段睡眠確認模型

睡眠確認採用多階段判定模型，結合心率數據和動作數據，實現高準確度的睡眠判定：

```swift
struct SleepConfirmationSystem {
    // 核心參數
    let hrThresholdPercentage: Double   // 心率閾值百分比
    let motionThreshold: Double         // 動作閾值
    let minConfirmationTime: TimeInterval // 最小確認時間
    
    // 心率確認追蹤
    private var consecutiveHRConfirmations: Int = 0
    
    // 動作確認追蹤
    private var motionStabilityScore: Double = 0
    
    // 睡眠確認核心方法
    func confirmSleep(currentHR: Double, 
                      restingHR: Double, 
                      motionLevel: Double, 
                      timeInState: TimeInterval) -> SleepConfirmationResult {
        // 計算當前心率是否符合閾值
        let hrThreshold = restingHR * hrThresholdPercentage
        let hrConditionMet = currentHR <= hrThreshold
        
        // 計算動作是否穩定
        let motionConditionMet = motionLevel <= motionThreshold
        
        // 更新心率確認計數
        if hrConditionMet {
            consecutiveHRConfirmations += 1
        } else {
            consecutiveHRConfirmations = max(0, consecutiveHRConfirmations - 2)
        }
        
        // 更新動作穩定分數
        if motionConditionMet {
            motionStabilityScore = min(1.0, motionStabilityScore + 0.2)
        } else {
            motionStabilityScore = max(0.0, motionStabilityScore - 0.3)
        }
        
        // 多階段判定
        let preliminary = consecutiveHRConfirmations >= 3
        let motionStable = motionStabilityScore >= 0.7
        let timeConditionMet = timeInState >= minConfirmationTime
        
        // 生成結果
        var result = SleepConfirmationResult()
        result.hrConditionMet = hrConditionMet
        result.motionConditionMet = motionConditionMet
        result.preliminarySleepDetected = preliminary && motionStable
        result.sleepConfirmed = result.preliminarySleepDetected && timeConditionMet
        result.confidence = calculateConfidence(hrDelta: (restingHR - currentHR) / restingHR,
                                             motionScore: motionStabilityScore,
                                             timeRatio: timeInState / minConfirmationTime)
        
        return result
    }
    
    // 計算檢測信心值
    private func calculateConfidence(hrDelta: Double, 
                                    motionScore: Double, 
                                    timeRatio: Double) -> Double {
        // 心率貢獻（佔50%）
        let hrConfidence = min(hrDelta * 2.0, 1.0) * 0.5
        
        // 動作貢獻（佔30%）
        let motionConfidence = motionScore * 0.3
        
        // 時間貢獻（佔20%）
        let timeConfidence = min(timeRatio, 1.0) * 0.2
        
        return hrConfidence + motionConfidence + timeConfidence
    }
}
```

### 睡眠確認結果結構

```swift
struct SleepConfirmationResult {
    var hrConditionMet: Bool = false
    var motionConditionMet: Bool = false
    var preliminarySleepDetected: Bool = false
    var sleepConfirmed: Bool = false
    var confidence: Double = 0.0
    
    var statusDescription: String {
        if sleepConfirmed {
            return "睡眠已確認 (信心度: \(Int(confidence * 100))%)"
        } else if preliminarySleepDetected {
            return "初步檢測到睡眠，等待確認"
        } else if hrConditionMet {
            return "心率條件已滿足，等待動作穩定"
        } else if motionConditionMet {
            return "動作穩定，等待心率降低"
        } else {
            return "等待睡眠條件滿足"
        }
    }
}
```

## 四、收斂機制與睡眠確認的協同工作流程

### 整合流程

1. **初始參數設定**：
   - 根據用戶年齡組選擇初始心率閾值百分比
   - 設定初始動作閾值和確認時間

2. **即時睡眠判定**：
   - 睡眠確認系統進行多維度分析
   - 判定用戶是否進入睡眠狀態

3. **會話結束後優化**：
   - 收集本次睡眠會話數據
   - 更新用戶睡眠設定檔
   - 調整心率閾值和確認時間參數

4. **用戶反饋處理**：
   - 根據用戶反饋結果優先調整對應參數
   - 更新反饋統計和調整方向記錄

### 代碼實現

```swift
class SleepDetectionEngine {
    // 組件
    private let heartRateService: HeartRateServiceProtocol
    private let motionService: MotionServiceProtocol
    private let sleepConfirmation: SleepConfirmationSystem
    private let convergenceEngine: ConvergenceEngine
    
    // 狀態追蹤
    private var sleepDetected: Bool = false
    private var detectionStartTime: Date?
    private var currentSession: SleepSession?
    
    // 睡眠檢測主流程
    func processSensorData(heartRate: Double, motion: Double, timestamp: Date) {
        // 檢查是否已經檢測到睡眠
        if sleepDetected { return }
        
        // 獲取當前用戶設定檔
        let profile = userProfileManager.getCurrentProfile()
        
        // 配置睡眠確認系統
        let confirmationConfig = SleepConfirmationConfig(
            hrThresholdPercentage: profile.hrThresholdPercentage,
            motionThreshold: profile.motionThreshold,
            minConfirmationTime: TimeInterval(profile.minDurationSeconds)
        )
        
        // 獲取靜息心率
        let restingHR = heartRateService.getRestingHeartRate()
        
        // 計算處於當前狀態的時間
        let timeInState = detectionStartTime != nil ? 
            timestamp.timeIntervalSince(detectionStartTime!) : 0
        
        // 進行睡眠確認
        let result = sleepConfirmation.confirmSleep(
            currentHR: heartRate,
            restingHR: restingHR,
            motionLevel: motion,
            timeInState: timeInState
        )
        
        // 處理結果
        if result.preliminarySleepDetected && detectionStartTime == nil {
            // 初次達到初步睡眠條件，記錄開始時間
            detectionStartTime = timestamp
        } else if !result.preliminarySleepDetected && detectionStartTime != nil {
            // 條件不再滿足，重置開始時間
            detectionStartTime = nil
        }
        
        // 檢查是否已確認睡眠
        if result.sleepConfirmed && !sleepDetected {
            sleepDetected = true
            
            // 記錄睡眠檢測時間和信心度
            currentSession?.detectedSleepTime = timestamp
            currentSession?.detectionConfidence = result.confidence
            
            // 通知系統睡眠已被檢測到
            notifySleepDetected(confidence: result.confidence)
        }
    }
    
    // 會話結束處理
    func endSession(userFeedback: SleepFeedback?) {
        guard let session = currentSession else { return }
        
        // 添加用戶反饋
        if let feedback = userFeedback {
            session.userFeedback = feedback
        }
        
        // 儲存會話
        sessionStorage.saveSession(session)
        
        // 應用收斂機制優化參數
        let profile = userProfileManager.getCurrentProfile()
        convergenceEngine.optimizeParameters(
            profile: profile,
            session: session,
            feedback: userFeedback
        )
        
        // 重置狀態
        resetDetectionState()
    }
}
```

## 五、收斂參數與調整策略

### 閾值調整參數表

| 參數名稱 | 說明 | 調整範圍 | 預設值 |
|---------|------|---------|--------|
| baseAdjustment | 基礎調整量 | 0.005~0.02 | 0.01 |
| maxConsecutiveEffect | 連續同向調整最大影響因子 | 0.3~0.6 | 0.5 |
| initialBoostFactor | 初始階段調整增益 | 1.0~1.5 | 1.2 |
| stableStageFactor | 穩定階段調整降低係數 | 0.5~0.9 | 0.8 |
| falsePositivePenalty | 假陽性反饋懲罰係數 | 1.1~1.5 | 1.2 |
| falseNegativeBoost | 假陰性反饋增益係數 | 1.1~1.5 | 1.3 |
| decayBase | 調整衰減基礎係數 | 0.9~1.0 | 0.95 |

### 收斂流程狀態機

收斂機制通過狀態機管理優化過程：

1. **初始階段** (1-5 次會話)：
   - 較大調整幅度 (1.2x)
   - 無方向持續性要求
   - 重點適應用戶基本特徵

2. **積極優化階段** (6-15 次會話)：
   - 標準調整幅度 (1.0x)
   - 開始考慮調整方向持續性
   - 重點找到用戶個人閾值區間

3. **精細調整階段** (16-30 次會話)：
   - 略小調整幅度 (0.9x)
   - 強化調整方向持續性影響
   - 重點優化確認時間參數

4. **穩定維護階段** (>30 次會話)：
   - 小調整幅度 (0.8x)
   - 主要基於用戶反饋調整
   - 專注於特殊情況處理

## 六、使用案例與實際效果

### 案例分析：運動員用戶

**初始情況**：
- 25歲男性用戶，靜息心率43 bpm
- 由於靜息心率低，心率下降幅度較大
- 初始心率閾值設置為 RHR 的 90% (38.7 bpm)

**收斂過程**：
1. 前3次使用時，系統未能檢測到睡眠
2. 用戶提供假陰性反饋
3. 收斂機制調整心率閾值至 RHR 的 92% (39.6 bpm)
4. 又一次未檢測到睡眠，用戶再次提供假陰性反饋
5. 系統檢測到連續同向反饋，加大調整幅度
6. 閾值調整至 RHR 的 95% (40.9 bpm)
7. 後續使用中，檢測成功率提升至 80%
8. 經過10次使用後，閾值穩定在 RHR 的 96% (41.3 bpm)

**最終效果**：
- 閾值優化後的等待時間縮短了平均46%
- 檢測準確率從初始的 40% 提升至 92%
- 用戶滿意度明顯提高

### 案例分析：睡眠模式不穩定用戶

**初始情況**：
- 42歲女性用戶，靜息心率68 bpm
- 睡眠時心率波動較大，有時直接降低，有時緩慢下降
- 初始心率閾值設置為 RHR 的 90% (61.2 bpm)

**收斂過程**：
1. 頭5次使用中，有3次過早檢測到睡眠（假陽性）
2. 系統根據反饋降低閾值至 88% (59.8 bpm)
3. 假陽性問題仍存在
4. 系統不僅繼續降低閾值，還增加確認時間從 180 秒至 240 秒
5. 經過調整，假陽性問題減少，但出現偶爾的假陰性
6. 系統進一步調整參數，最終找到平衡點：心率閾值 87% (59.2 bpm)，確認時間 210 秒

**最終效果**：
- 假陽性率從初始的 60% 降低至 10% 以下
- 假陰性率維持在 15% 左右
- 整體準確率達到 85%，符合用戶期望

## 七、測試與評估方法

### 測試環境與方法

對收斂機制的測試採用了以下方法：

1. **模擬數據測試**：
   - 創建模擬睡眠數據集，覆蓋多種心率模式
   - 模擬不同用戶反饋場景
   - 評估系統收斂速度和穩定性

2. **歷史數據回溯測試**：
   - 使用實際用戶歷史數據
   - 比較收斂前後的檢測準確率
   - 評估不同人群的收斂效果差異

3. **實時反饋測試**：
   - 招募測試用戶進行實際使用
   - 收集反饋並追蹤參數調整過程
   - 評估主觀滿意度與客觀準確率

### 測試代碼示例

```swift
func testConvergenceWithSimulatedData() {
    // 創建模擬用戶設定檔
    var profile = UserSleepProfile.createDefault(forUserId: "test_user", ageGroup: .adult)
    
    // 創建收斂引擎
    let convergenceEngine = ConvergenceEngine()
    
    // 模擬一系列睡眠會話
    let sessions = createSimulatedSessions(pattern: .initialFalseNegatives)
    
    // 運行收斂過程
    for (index, session) in sessions.enumerated() {
        // 模擬用戶反饋
        let feedback: SleepFeedback?
        if index < 3 {
            feedback = .falseNegative
        } else if index == 8 {
            feedback = .falsePositive
        } else {
            feedback = index % 5 == 0 ? .accurate : nil
        }
        
        // 應用收斂調整
        convergenceEngine.optimizeParameters(
            profile: &profile,
            session: session,
            feedback: feedback
        )
        
        // 記錄調整後的參數
        print("Session \(index + 1): threshold = \(profile.hrThresholdPercentage), " +
              "duration = \(profile.minDurationSeconds)")
    }
    
    // 驗證最終參數是否在合理範圍內
    XCTAssert(profile.hrThresholdPercentage >= 0.85 && 
              profile.hrThresholdPercentage <= 0.95, 
              "Final threshold should be in reasonable range")
    
    XCTAssert(profile.minDurationSeconds >= 120 && 
              profile.minDurationSeconds <= 300, 
              "Final duration should be in reasonable range")
}
```

## 八、未來優化方向

### 短期優化計劃

1. **動態衰減因子**：
   - 根據用戶反饋一致性動態調整衰減因子
   - 提高參數穩定性，減少不必要的波動

2. **多維度確認時間調整**：
   - 將確認時間調整與心率變化速率關聯
   - 快速心率下降時縮短確認時間，緩慢下降時延長確認時間

3. **異常數據排除**：
   - 增強對異常睡眠會話的識別
   - 排除特殊情況（如壓力、疾病）對收斂過程的影響

### 長期發展路線

1. **機器學習模型**：
   - 收集足夠數據後，開發基於機器學習的睡眠檢測模型
   - 整合多維度生理數據，提取個性化睡眠特徵

2. **情境感知調整**：
   - 結合活動歷史、日曆資訊等上下文
   - 根據用戶當天情況預先調整檢測參數

3. **睡眠質量評估整合**：
   - 結合睡眠深度估計，提供更全面的睡眠體驗
   - 收斂優化不僅針對檢測時機，還考慮睡眠質量因素

## 九、常見問題與解決方案

### 技術挑戰與解決方法

1. **收斂速度與穩定性平衡**
   - **問題**：調整速度過快導致不穩定，過慢影響用戶體驗
   - **解決方案**：實施階段性收斂策略，初期快速收斂，後期精細調整

2. **特殊用戶群體適應**
   - **問題**：極端心率模式用戶（如資深運動員）難以適應
   - **解決方案**：增加特殊人群專屬模式，調整基礎參數範圍

3. **收斂阻塞與重置**
   - **問題**：某些情況下收斂過程可能進入局部最優解
   - **解決方案**：實施收斂重置機制，當連續多次反饋不一致時觸發重新學習

### 開發者常見問題

1. **如何確定初始參數？**
   - 基於年齡組選擇基礎閾值（青少年87.5%，成人90%，老年人93.5%）
   - 考慮用戶的靜息心率水平，特殊情況下進行初始調整

2. **如何處理多樣性數據？**
   - 使用加權數據統計方法，重點考慮最近會話數據
   - 異常值排除策略，過濾可能的錯誤數據

3. **如何評估收斂效果？**
   - 追蹤關鍵指標：假陽性率、假陰性率、收斂速度、參數穩定性
   - 用戶滿意度調查，評估主觀感受與客觀數據的一致性

---

**版本記錄**：
- v1.0.0 (2024-05-20)：初始版本，合併 convergence_algorithm.md 和 SleepConfirmationAlgorithm.md
- 對應代碼版本：PowerNap v2.3.1 