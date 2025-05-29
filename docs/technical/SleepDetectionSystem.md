# PowerNap 睡眠檢測系統（v1.0.0）

> **文件定位說明**：本文件是 PowerNap 應用的睡眠檢測系統總體技術文檔，提供系統架構、工作流程和主要元件的完整描述。本文作為睡眠檢測相關技術的頂層文檔，為開發者提供全面的系統理解。
> 
> **與其他文件的關係**：
> - 本文件是睡眠檢測系統的頂層設計文檔，提供系統整體架構和工作流程
> - 心率監測與閾值部分的詳細實現請參考 [HeartRateSystem.md](./HeartRateSystem.md)
> - 收斂演算法與睡眠確認的詳細實現請參考 [ConvergenceSystem.md](./ConvergenceSystem.md)
> - 若需了解專案整體架構和功能，請參考 [ProjectGuideline.md](./ProjectGuideline.md)
> - 若需了解演算法開發計劃，請參考 [AlgorithmDevelopmentPlan.md](./AlgorithmDevelopmentPlan.md)

## 一、系統概述

PowerNap 應用使用多層次的檢測系統來準確判定用戶何時進入睡眠狀態，確保在用戶真正入睡後才開始計時。本系統結合心率監測、動作檢測和自適應優化機制，提供個性化的睡眠檢測體驗。

### 核心特點

1. **多源數據融合**：結合心率和動作數據進行睡眠狀態判定
2. **個性化閾值調整**：根據用戶年齡組和使用歷史動態調整判定參數
3. **收斂學習機制**：根據實際使用和用戶反饋持續優化檢測準確度
4. **運動員模式**：針對心臟功能特別強的用戶提供特殊判定模式
5. **異常處理機制**：處理環境和生理因素引起的異常數據

## 二、系統架構

### 整體架構圖

```
+--------------------------------------------------+
|                 睡眠檢測系統                      |
+--------------------------------------------------+
|                    |                             |
v                    v                             v
+---------------+ +----------------+ +---------------------------+
|  心率監測子系統 | |  動作檢測子系統  | |  用戶設定檔和閾值管理子系統  |
+---------------+ +----------------+ +---------------------------+
|  • 數據採集    | |  • 加速度監測   | |  • 年齡組閾值               |
|  • 異常檢測    | |  • 靜止比例計算  | |  • 個人化調整               |
|  • 閾值比較    | |  • 姿勢變化檢測  | |  • 歷史數據分析             |
+-------+-------+ +--------+-------+ +-------------+-------------+
        |                  |                       |
        v                  v                       v
    +----------------------------------------------|-------------+
    |                  睡眠確認系統                 |             |
    +----------------------------------------------|-------------+
    |     • 多階段判定流程     • 狀態轉換機制        |             |
    |     • 時間閾值控制       • 信心度計算          |             |
    +----------------------------------------------|-------------+
                                                  |
                                                  v
                                    +----------------------------+
                                    |       收斂機制與參數優化     |
                                    +----------------------------+
                                    | • 反饋學習   • 漸進式調整    |
                                    | • 優化觸發   • 參數限制     |
                                    +----------------------------+
```

### 主要元件

1. **心率監測子系統**：監測和分析用戶心率數據，判定是否符合睡眠心率特徵
2. **動作檢測子系統**：監測用戶動作，計算靜止比例，判定是否處於靜止狀態
3. **用戶設定檔和閾值管理子系統**：儲存和管理用戶特定參數和閾值設定
4. **睡眠確認系統**：融合心率和動作判定結果，確認用戶是否已入睡
5. **收斂機制與參數優化**：根據使用數據和用戶反饋優化判定參數

## 三、檢測流程與機制

### 睡眠檢測基本流程

睡眠檢測採用多階段判定機制，遵循以下基本流程：

1. **初始化**：
   - 啟動感測器監測
   - 載入用戶設定檔和閾值參數
   - 獲取靜息心率基準

2. **持續監測**：
   - 每15-30秒進行一次評估
   - 分析心率是否穩定下降至閾值以下
   - 計算動作靜止程度

3. **初步判定**：
   - 當心率低於閾值，標記為「可能睡眠」
   - 持續監測以避免誤判

4. **睡眠確認**：
   - 心率持續保持在閾值以下，且動作維持穩定
   - 達到指定的確認時間後判定為已入睡
   - 啟動睡眠計時器

5. **後續處理**：
   - 記錄檢測數據
   - 會話結束後應用收斂機制更新參數

### 年齡組特定閾值標準

PowerNap 根據不同年齡群體的生理特徵，設定差異化的檢測標準：

| 年齡組 | 判定標準 | 確認時間 | 實現值 | 參考來源 |
|--------|----------|----------|--------|----------|
| 10–17 歲 (青少年) | 低於 RHR 的 85-90% | ≥ 2 分鐘 | 87.5% | 實際代碼實現及測試結果 |
| 18–59 歲 (成人) | 低於 RHR 的 88-92% | ≥ 3 分鐘 | 90.0% | Burgess 1999 成人實驗夜間及午睡資料 |
| ≥ 60 歲 (銀髮族) | 低於 RHR 的 92-95% | ≥ 4 分鐘 | 93.5% | 實際代碼實現及測試結果 |

### 多源數據融合

系統採用多層次數據融合策略，提高檢測準確度：

1. **心率數據**（主要判定依據）：
   - 比較即時心率與靜息心率的比值
   - 計算心率變化趨勢和穩定度
   - 應用年齡組特定閾值判定

2. **動作數據**（輔助判定依據）：
   - 計算加速度傳感器數據標準差
   - 分析靜止比例（靜止時間 / 總觀察時間）
   - 檢測姿勢變化和微動情況

3. **融合判定**：
   - 心率條件：即時HR ≤ RHR × 閾值百分比
   - 動作條件：靜止比例 ≥ 設定閾值（通常為 85%）
   - 時間條件：上述兩條件同時滿足持續時間 ≥ 年齡組確認時間

## 四、核心演算法與實現

### 心率條件判定

心率判定是睡眠檢測的核心，通過計算心率降低比例實現：

```swift
func checkHeartRateCondition(currentHR: Double, restingHR: Double, profile: UserSleepProfile) -> Bool {
    // 1. 獲取調整後的閾值
    let baseThreshold = getBaseThresholdPercentage(for: profile.ageGroup)
    let adjustedThreshold = baseThreshold + profile.manualAdjustmentOffset
    
    // 2. 計算心率閾值
    let hrThreshold = restingHR * adjustedThreshold
    
    // 3. 運動員模式特殊處理
    if profile.athleteMode && restingHR < 45 {
        // 運動員使用絕對下降值而非百分比
        let hrDropThreshold: Double = 5.0  // 5 bpm 作為下降門檻
        return currentHR <= (restingHR - hrDropThreshold)
    }
    
    // 4. 標準模式判定
    return currentHR <= hrThreshold
}
```

### 動作條件判定

動作檢測用於確認用戶是否處於靜止狀態，避免假陽性：

```swift
func checkMotionCondition(accelerationData: [AccelerationSample], profile: UserSleepProfile) -> Bool {
    // 1. 計算加速度標準差
    let stdDeviation = calculateStandardDeviation(accelerationData)
    
    // 2. 計算靜止時間比例
    let restingThreshold = 0.03  // 標準差閾值，小於此值視為靜止
    let restingSamples = accelerationData.filter { $0.magnitude < restingThreshold }.count
    let restingRatio = Double(restingSamples) / Double(accelerationData.count)
    
    // 3. 獲取用戶特定的靜止比例閾值
    let baseRestingRatioThreshold = getBaseRestingRatioThreshold(for: profile.ageGroup)
    let adjustedRestingRatioThreshold = baseRestingRatioThreshold + profile.restingRatioAdjustment
    
    // 4. 判定是否滿足動作靜止條件
    return restingRatio >= adjustedRestingRatioThreshold
}

func getBaseRestingRatioThreshold(for ageGroup: AgeGroup) -> Double {
    switch ageGroup {
    case .teen:
        return 0.8  // 青少年活動度通常較高，設定較低的閾值
    case .adult:
        return 0.85 // 成人標準閾值
    case .senior:
        return 0.9  // 銀髮族活動度通常較低，需要更高的靜止比例
    }
}
```

### 睡眠確認狀態機

睡眠確認採用狀態機實現，以處理不同檢測階段：

```swift
enum SleepDetectionState {
    case monitoring          // 初始監測狀態
    case possibleSleep       // 可能睡眠（初步條件滿足）
    case confirming          // 確認中（等待確認時間）
    case sleepConfirmed      // 睡眠確認完成
}

class SleepDetectionStateMachine {
    private var currentState: SleepDetectionState = .monitoring
    private var stateEntryTime: Date?
    
    func processNewData(hrConditionMet: Bool, 
                       motionConditionMet: Bool, 
                       currentTime: Date,
                       confirmationTime: TimeInterval) -> SleepDetectionState {
        
        switch currentState {
        case .monitoring:
            if hrConditionMet && motionConditionMet {
                currentState = .possibleSleep
                stateEntryTime = currentTime
            }
            
        case .possibleSleep:
            if hrConditionMet && motionConditionMet {
                currentState = .confirming
                stateEntryTime = currentTime
            } else {
                currentState = .monitoring
                stateEntryTime = nil
            }
            
        case .confirming:
            if !hrConditionMet || !motionConditionMet {
                currentState = .monitoring
                stateEntryTime = nil
            } else if let entryTime = stateEntryTime, 
                      currentTime.timeIntervalSince(entryTime) >= confirmationTime {
                currentState = .sleepConfirmed
            }
            
        case .sleepConfirmed:
            // 保持在睡眠確認狀態
            break
        }
        
        return currentState
    }
}
```

## 五、個人化與適應性機制

### 個人化心率模型

系統通過用戶設定檔儲存與更新個人化參數：

```swift
struct UserSleepProfile: Codable {
    // 基本信息
    let userId: String
    let ageGroup: AgeGroup
    
    // 心率閾值設定
    var hrThresholdPercentage: Double  // 例如 0.9 表示 RHR 的 90%
    var minDurationSeconds: Int        // 維持低心率需要的時間（秒）
    
    // 靜止比例相關參數
    var baseRestingRatioThreshold: Double // 基於年齡組的基礎靜止比例
    var restingRatioAdjustment: Double = 0.0 // 用戶調整值
    
    // 用戶手動調整
    var manualAdjustmentOffset: Double = 0.0
    
    // 特殊模式標記
    var athleteMode: Bool = false
    var fragmentedSleepMode: Bool = false
    
    // 統計數據和模型狀態
    var sleepSessionsCount: Int = 0
    var lastModelUpdateDate: Date?
    
    // 收斂機制相關參數
    var consecutiveThresholdAdjustments: Int = 0
    var lastAdjustmentDirection: Int = 0  // 1增加, -1減少, 0無變化
}
```

### 收斂機制觸發條件

系統會在以下情況觸發參數優化：

1. **定期優化**：
   - 每14天進行一次強制參數審核
   - 收集至少3個新會話後，距離上次更新7天以上

2. **反饋驅動優化**：
   - 接收到用戶明確反饋後
   - 檢測到可能的誤判模式

3. **特殊情況觸發**：
   - 睡眠模式顯著變化
   - 檢測成功率低於閾值

### 用戶反饋機制

系統提供用戶反饋界面，收集使用體驗並優化參數：

1. **反饋類型**：
   - 準確檢測（positive）：檢測結果符合用戶實際體驗
   - 誤報（false positive）：系統錯誤判定已入睡
   - 漏報（false negative）：系統未能檢測到實際睡眠

2. **參數調整策略**：
   - 誤報反饋：降低閾值百分比，增加確認時間
   - 漏報反饋：增加閾值百分比，減少確認時間
   - 連續同類反饋：加大調整幅度

## 六、實現細節與技術挑戰

### 核心服務類

睡眠檢測系統包含以下核心服務：

```swift
class SleepDetectionService {
    // 子系統服務
    private let heartRateService: HeartRateServiceProtocol
    private let motionService: MotionServiceProtocol
    private let profileManager: UserProfileManagerProtocol
    
    // 檢測組件
    private let sleepConfirmation: SleepConfirmationSystem
    private let detectionStateMachine: SleepDetectionStateMachine
    private let convergenceEngine: ConvergenceEngine
    
    // 檢測狀態
    private var sleepDetected: Bool = false
    private var detectionConfidence: Double = 0.0
    private var currentSession: SleepSession?
    
    // 核心方法
    func startMonitoring()
    func stopMonitoring()
    func processSensorData(heartRate: Double, motion: [AccelerationSample], timestamp: Date)
    func onSleepDetected(timestamp: Date, confidence: Double)
    func submitUserFeedback(feedback: SleepFeedback)
}
```

### 資料儲存與分析

系統需要儲存和分析歷史數據，為收斂機制提供依據：

```swift
class SleepSessionStorage {
    // 保存會話數據
    func saveSession(_ session: SleepSession)
    
    // 獲取歷史數據
    func getRecentSessions(count: Int) -> [SleepSession]
    func getSessionsInTimeRange(from: Date, to: Date) -> [SleepSession]
    
    // 數據統計與分析
    func getAverageSleepHeartRate() -> Double?
    func getAverageDetectionTime() -> TimeInterval?
    func getFalsePositiveRate() -> Double?
}
```

### 技術挑戰與解決方案

開發過程中面臨的主要挑戰及解決方案：

1. **Apple Watch 傳感器取樣頻率限制**
   - **挑戰**：HealthKit 心率數據更新間隔約為5秒，可能導致錯過短暫心率變化
   - **解決方案**：實施數據平滑和預測機制，通過趨勢分析而非單點值判斷

2. **電池使用優化**
   - **挑戰**：持續監測可能導致電池過快消耗
   - **解決方案**：實施階段性監測策略，根據會話階段調整監測頻率

3. **多樣性用戶適應**
   - **挑戰**：不同用戶心率模式差異巨大
   - **解決方案**：基於年齡組的基礎參數 + 自適應收斂機制 + 特殊用戶群體模式（如運動員模式）

4. **誤判與漏判平衡**
   - **挑戰**：提高檢測靈敏度會增加誤判率，反之則增加漏判率
   - **解決方案**：多維度指標融合判定 + 用戶反饋優化 + 可調整的靈敏度設定

## 七、測試與驗證

### 測試方法學

系統測試採用三層次方法：

1. **單元測試**：
   - 測試各子系統和組件的獨立功能
   - 驗證算法在不同輸入下的正確性

2. **整合測試**：
   - 測試子系統間的協同工作
   - 模擬真實數據流驗證判定邏輯

3. **真實用戶測試**：
   - 招募不同年齡組和心率特徵的測試用戶
   - 收集實際使用數據和主觀反饋

### 驗證標準

1. **準確度指標**：
   - 真陽性率（檢測到實際睡眠）> 85%
   - 假陽性率（誤報睡眠）< 15%
   - 平均檢測延遲 < 實際入睡後 2 分鐘

2. **用戶體驗指標**：
   - 用戶感知準確度（通過反饋評估）> 80%
   - 用戶滿意度評分 > 4.2/5.0

### 使用者測試結果

初步使用者測試結果顯示系統在以下方面表現良好：

- 對成人用戶群體的整體檢測準確率達到 88%
- 經過 3-5 次使用後，收斂機制使個人化檢測準確率提升 10-15%
- 青少年和老年用戶群體初始準確率較低（72-76%），但隨著使用次數增加，收斂機制逐步提高準確率

主要改進方向：
- 提高對不同睡姿變化的適應性
- 加強對特殊心率模式（如心律不齊）的處理
- 優化收斂速度，使系統更快適應個人特徵

## 八、未來發展方向

### 短期優化目標

1. **收斂速度提升**：
   - 優化調整速度，縮短適應期
   - 改進初始參數估計算法

2. **異常數據處理**：
   - 增強對環境干擾的過濾能力
   - 實施數據質量評估機制

3. **電池效率優化**：
   - 實施更智能的能源管理策略
   - 根據預測睡眠模式調整監測頻率

### 中期發展計劃

1. **整合其他生理指標**：
   - 加入血氧飽和度（如硬件支持）
   - 整合呼吸率變化
   - 考慮皮膚溫度變化特徵

2. **機器學習模型升級**：
   - 開發基於深度學習的睡眠階段檢測
   - 建立個性化睡眠預測模型

3. **睡眠質量分析**：
   - 增加深度睡眠檢測功能
   - 提供睡眠質量指數和改善建議

### 長期技術願景

1. **跨設備數據整合**：
   - 與智能床墊、環境傳感器等外部設備整合
   - 實現更全面的睡眠環境分析

2. **健康生態系統整合**：
   - 與飲食、運動等健康資料交叉分析
   - 建立個人化健康生態系統

3. **預測性功能**：
   - 基於歷史數據預測最佳休息時段
   - 提供個性化的休息建議

## 九、技術參數詳情

### 系統核心參數表

| 參數名稱 | 說明 | 預設值 | 調整範圍 |
|---------|------|---------|--------|
| HeartRateThresholdTeen | 青少年心率閾值百分比 | 87.5% | 85-90% |
| HeartRateThresholdAdult | 成人心率閾值百分比 | 90.0% | 88-92% |
| HeartRateThresholdSenior | 銀髮族心率閾值百分比 | 93.5% | 92-95% |
| ConfirmationTimeTeen | 青少年睡眠確認時間 | 120 秒 | 90-180 秒 |
| ConfirmationTimeAdult | 成人睡眠確認時間 | 180 秒 | 120-240 秒 |
| ConfirmationTimeSenior | 銀髮族睡眠確認時間 | 240 秒 | 180-300 秒 |
| RestingRatioThresholdTeen | 青少年靜止比例閾值 | 80% | 75-85% |
| RestingRatioThresholdAdult | 成人靜止比例閾值 | 85% | 80-90% |
| RestingRatioThresholdSenior | 銀髮族靜止比例閾值 | 90% | 85-95% |
| AthleteHRDropThreshold | 運動員心率下降絕對值閾值 | 5 bpm | 3-8 bpm |
| BaseConvergenceAdjustment | 基礎收斂調整量 | 1% | 0.5-2% |
| MaxConsecutiveAdjustmentEffect | 最大連續調整效果 | 50% | 30-70% |

### 常用對象與方法參考

```swift
// 睡眠會話數據結構
struct SleepSession: Codable {
    let id: UUID
    let userId: String
    let startTime: Date
    let endTime: Date?
    
    var detectedSleepTime: Date?
    var detectionConfidence: Double?
    
    var heartRates: [Double]
    var motionData: [AccelerationSample]?
    
    enum SleepFeedback: Int, Codable {
        case none
        case accurate
        case falsePositive
        case falseNegative
    }
    
    var userFeedback: SleepFeedback?
}

// 加速度樣本
struct AccelerationSample: Codable {
    let timestamp: Date
    let x: Double
    let y: Double
    let z: Double
    
    var magnitude: Double {
        return sqrt(x*x + y*y + z*z)
    }
}

// 年齡組枚舉
enum AgeGroup: Int, Codable {
    case teen   // 10-17歲
    case adult  // 18-59歲
    case senior // 60歲以上
}

// 調整方向枚舉
enum AdjustmentDirection: Int {
    case decrease = -1
    case noChange = 0
    case increase = 1
}
```

## 十、常見問題與解決方案

### 技術問題

1. **無法獲取靜息心率**
   - **解決方案**：使用過去7天清晨心率平均值，或基於年齡提供默認值

2. **心率數據波動大**
   - **解決方案**：應用移動平均平滑處理，忽略短暫波動

3. **使用後閾值越調越高/低**
   - **解決方案**：實施參數邊界限制，防止閾值飄移

### 使用問題

1. **無法檢測到睡眠**
   - **解決方案**：
     - 確保手錶佩戴正確
     - 使用手動模式調高閾值百分比
     - 檢查最近的壓力、藥物等影響因素

2. **過早檢測到睡眠**
   - **解決方案**：
     - 調低閾值百分比，使檢測更嚴格
     - 啟用「高強度檢測」模式增加確認時間

3. **檢測後喚醒不及時**
   - **解決方案**：
     - 確認通知權限已開啟
     - 調整手錶震動強度
     - 嘗試不同的喚醒聲音

---

**版本記錄**：
- v1.0.0 (2024-05-20)：初始版本，更新和整合自 SleepDetectionGuideline.md
- 對應代碼版本：PowerNap v2.3.1 