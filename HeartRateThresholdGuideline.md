# PowerNap 心率閾值智能調整系統指導文件

## 一、什麼是心率閾值調整系統 (What)

心率閾值調整系統是 PowerNap 應用的核心技術，用於準確檢測用戶的睡眠狀態。該系統通過設定和動態調整相對於用戶靜息心率(RHR)的百分比閾值，來判定用戶是否進入睡眠狀態。當用戶實時心率低於該閾值並維持指定時間，系統判定用戶已進入睡眠。

系統包含四大核心組件：
1. **基礎閾值計算**：根據用戶年齡組設定初始閾值百分比
2. **自動收斂機制**：分析睡眠數據，逐步優化個人化閾值
3. **手動調整界面**：允許用戶根據實際體驗進行調整
4. **異常處理策略**：處理壓力、姿勢變化等特殊情況

## 二、為什麼需要心率閾值調整系統 (Why)

### 1. 生理學原理

睡眠時人體進入副交感神經主導狀態，心率自然下降。不同用戶的睡眠心率與靜息心率的比例存在生理差異：
- 青少年：通常為 RHR 的 85-90%
- 成人：通常為 RHR 的 88-92%
- 銀髮族：通常為 RHR 的 92-95%

### 2. 個體差異挑戰

固定閾值無法適應所有用戶：
- 運動員的心率變化範圍可能更大
- 老年用戶心率變化可能較小
- 心臟疾病患者可能有非典型心率模式
- 藥物影響可能改變正常心率反應

### 3. 外部因素影響

多種因素會影響睡眠心率：
- 睡姿改變：俯臥時心率平均增加 4-5 BPM
- 壓力狀態：可能導致心率提高 4-8 BPM
- 環境溫度：高溫可能提高心率 2-4 BPM
- 飲食影響：酒精、咖啡因等

## 三、什麼時候進行心率閾值調整 (When)

### 1. 自動調整時機

系統在以下時機進行閾值自動優化：
- **初始使用後**：收集 3-5 次成功睡眠數據後
- **定期優化**：正常每 7-14 天進行一次閾值檢查
- **顯著變化後**：檢測到連續異常後
- **用戶反饋後**：收到準確度反饋後

### 2. 手動調整時機

建議用戶在以下情況進行手動調整：
- 系統連續 3 次以上無法正確檢測睡眠
- 用戶生活方式發生顯著變化（開始運動計劃、改變飲食習慣等）
- 服用影響心率的藥物期間
- 壓力水平顯著提升期間

## 四、在哪裡實現心率閾值調整 (Where)

### 1. 代碼實現位置

心率閾值調整系統在以下關鍵位置實現：
- `HeartRateThresholdOptimizer.swift`：核心優化算法
- `PowerNapServices.swift`：閾值管理和調整
- `UserSleepProfile.swift`：用戶配置存儲
- `HeartRateService.swift`：心率數據處理與分析

### 2. 用戶界面位置

- 主設置頁面的「心率閾值」選項
- 心率閾值詳細設置頁面中的調整滑桿
- 睡眠會話結束後的反饋提示界面

## 五、誰來使用心率閾值調整系統 (Who)

### 1. 最終用戶

- 尋求準確小睡檢測的普通用戶
- 具有非典型心率模式的特殊用戶
- 需要精確睡眠監測的專業用戶

### 2. 開發人員

- 核心開發團隊：實現和維護系統
- 算法工程師：優化閾值調整策略
- QA 團隊：測試系統在各種情況下的可靠性

## 六、如何實現心率閾值調整系統 (How)

### 1. 基礎閾值設定

```swift
// 根據年齡組設定基礎閾值百分比
func getBaseThresholdPercentage(for ageGroup: AgeGroup) -> Double {
    switch ageGroup {
    case .teen:
        return 0.875  // 87.5% for teens
    case .adult:
        return 0.9    // 90% for adults
    case .senior:
        return 0.935  // 93.5% for seniors
    }
}
```

### 2. 閾值計算算法

閾值計算融合多個因素：
```swift
func calculateThreshold(profile: UserSleepProfile, restingHR: Double) -> Double {
    // 基礎閾值
    let basePercentage = profile.ageGroup.heartRateThresholdPercentage
    
    // 用戶手動調整
    let manualAdjustment = profile.manualAdjustmentOffset
    
    // 敏感度調整
    let sensitivityAdjustment = sleepSensitivity * 0.1
    
    // 最終閾值計算
    let adjustedPercentage = basePercentage + manualAdjustment
    let finalThreshold = restingHR * adjustedPercentage * (1 + sensitivityAdjustment)
    
    // 確保閾值在安全範圍內
    return max(restingHR * 0.7, min(restingHR * 1.1, finalThreshold))
}
```

### 3. 自動收斂機制

系統通過分析睡眠數據自動優化閾值：
```swift
func analyzeAndOptimize(profile: UserSleepProfile, sleepData: [SleepSession]) -> Double? {
    // 確保有足夠數據
    guard sleepData.count >= 3 else { return nil }
    
    // 1. 計算平均睡眠心率
    let allHeartRates = sleepData.flatMap { $0.heartRates }
    let avgSleepHR = average(allHeartRates)
    
    // 2. 計算與靜息心率的比例
    let sleepToRestingRatio = avgSleepHR / restingHR
    
    // 3. 計算目標閾值（略高於實際比例）
    let targetThreshold = sleepToRestingRatio + 0.02
    
    // 4. 漸進式調整（每次最多變化2.5%）
    let currentThreshold = profile.hrThresholdPercentage
    let maxAdjustment = 0.025
    
    if abs(targetThreshold - currentThreshold) > maxAdjustment {
        // 大幅調整，採用漸進策略
        return currentThreshold + (targetThreshold > currentThreshold ? maxAdjustment : -maxAdjustment)
    } else {
        // 小幅調整，直接採用目標值
        return targetThreshold
    }
}
```

### 4. 反饋處理機制

針對用戶反饋進行智能調整：
```swift
func processFeedback(type: FeedbackType, profile: UserSleepProfile) -> Double {
    let currentThreshold = profile.hrThresholdPercentage
    
    // 計算調整權重（基於用戶數據量）
    let sessionsCount = profile.sleepSessionsCount
    let adjustmentWeight = min(0.7, max(0.1, 1.0 / Double(sessionsCount + 1)))
    
    switch type {
    case .falsePositive:  // 誤判為睡眠（過於寬鬆）
        // 降低閾值使判定更嚴格
        return currentThreshold - (0.03 * adjustmentWeight)
        
    case .falseNegative:  // 未檢測到睡眠（過於嚴謹）
        // 提高閾值使判定更寬鬆
        return currentThreshold + (0.03 * adjustmentWeight)
        
    case .accurate:
        // 準確檢測無需調整
        return currentThreshold
    }
}
```

### 5. 連續異常處理

處理連續異常情況的改進策略：
```swift
// 分析連續異常模式
func analyzeAbnormalPattern(recentSessions: [SleepSession]) -> AbnormalityType {
    let twoWeekSessions = recentSessions.filter { 
        Date().timeIntervalSince($0.date) < 14*86400 
    }
    
    let failedDetections = twoWeekSessions.filter { !$0.sleepDetected }.count
    let totalSessions = twoWeekSessions.count
    
    if failedDetections >= 3 && failedDetections <= 5 {
        return .temporary  // 暫時性異常
    } else if failedDetections > 5 {
        return .persistent // 持續性變化
    } else {
        return .normal     // 正常情況
    }
}

// 基於異常類型採取相應策略
func handleAbnormalPattern(type: AbnormalityType, profile: UserSleepProfile) {
    switch type {
    case .temporary:
        // 暫時性異常：增加ΔHR敏感度，維持閾值
        adjustDeltaHRSensitivity(increase: true)
        
    case .persistent:
        // 持續性變化：重新計算基線
        resetBaselineGradually(profile: profile)
        
    case .normal:
        // 正常情況：標準優化流程
        break
    }
}
```

### 6. 反饋平滑機制

使反饋調整更平滑穩定：
```swift
class FeedbackSmoother {
    private var pendingAdjustments: [(date: Date, adjustment: Double)] = []
    
    // 新增反饋調整請求
    func addFeedbackAdjustment(_ adjustment: Double) {
        // 分散到3天內逐步實現
        let perDayAdjustment = adjustment / 3.0
        
        // 添加到待處理隊列
        for day in 0..<3 {
            let futureDate = Date().addingTimeInterval(Double(day) * 86400)
            pendingAdjustments.append((futureDate, perDayAdjustment))
        }
    }
    
    // 獲取今日應用的調整值
    func getTodayAdjustment() -> Double {
        let today = Date()
        let todayAdjustments = pendingAdjustments.filter {
            Calendar.current.isDateInToday($0.date)
        }
        
        // 計算總調整值
        let totalAdjustment = todayAdjustments.reduce(0.0) { $0 + $1.adjustment }
        
        // 移除已處理的調整
        pendingAdjustments.removeAll { Calendar.current.isDateInToday($0.date) }
        
        return totalAdjustment
    }
}
```

## 七、系統測試與評估方法

### 1. 單元測試

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

### 2. 模擬測試

使用模擬數據測試系統反應：
```swift
func testThresholdOptimization() {
    // 創建模擬睡眠會話
    let sessions = createSimulatedSleepSessions(count: 5, heartRatePattern: .normal)
    
    // 測試優化算法
    let profile = UserSleepProfile.createDefault(forUserId: "test", ageGroup: .adult)
    let optimizedThreshold = analyzeAndOptimize(profile: profile, sleepData: sessions)
    
    // 驗證優化結果在合理範圍內
    XCTAssertNotNil(optimizedThreshold)
    if let threshold = optimizedThreshold {
        XCTAssert(threshold >= 0.85 && threshold <= 0.95)
    }
}
```

### 3. 極端場景測試

測試系統在極端情況下的表現：
```swift
func testExtremeCases() {
    // 測試高壓力情況
    let stressSessions = createSimulatedSleepSessions(count: 3, heartRatePattern: .highStress)
    
    // 測試藥物影響
    let medicationSessions = createSimulatedSleepSessions(count: 3, heartRatePattern: .medication)
    
    // 測試連續異常
    let persistentAbnormalSessions = createSimulatedSleepSessions(count: 7, heartRatePattern: .persistentHigh)
    
    // 驗證系統處理能力
    testSystemResponse(to: stressSessions)
    testSystemResponse(to: medicationSessions)
    testSystemResponse(to: persistentAbnormalSessions)
}
```

## 八、系統優化與迭代策略

### 1. 數據收集與分析

持續收集實際用戶數據用於進一步優化：
- 記錄用戶睡眠心率分佈
- 統計不同人群的閾值分佈
- 分析系統判定與用戶反饋的一致性

### 2. 算法優化方向

1. **個性化趨勢分析**：
   - 學習個體特定的心率變化模式
   - 建立用戶睡眠指紋
   
2. **多維度分析**：
   - 整合加速度數據
   - 若硬件支持，加入呼吸率數據
   
3. **機器學習模型**：
   - 開發基於用戶數據的分類模型
   - 使用多項特徵提取睡眠模式

### 3. 用戶反饋整合

- 設計更精細的反饋收集界面
- 允許用戶標記特殊情況（壓力、藥物等）
- 建立反饋-優化閉環

## 九、實施建議與最佳實踐

### 1. 性能考量

- 優化計算頻率，避免過度消耗電量
- 使用批處理方式處理心率數據
- 優化存儲策略，減少磁盤訪問

### 2. 隱私保護

- 本地處理敏感生理數據
- 匿名化用於分析的數據
- 明確獲取用戶同意

### 3. 用戶體驗設計

- 提供簡單易懂的閾值調整界面
- 使用視覺化展示閾值效果
- 提供適當的指導信息

## 十、常見問題與解決方案

1. **系統無法檢測到睡眠**
   - 原因：閾值設置過低或用戶心率特徵異常
   - 解決：提高閾值或調整敏感度

2. **頻繁誤判睡眠**
   - 原因：閾值設置過高
   - 解決：降低閾值或增加確認時間

3. **閾值經常波動**
   - 原因：數據不足或用戶心率變異性高
   - 解決：增加平滑因子，減少單次調整幅度

4. **特殊情況處理**
   - 壓力：暫時增加敏感度
   - 藥物：用戶標記特殊時期，系統暫停自動優化
   - 疾病：提供手動模式

---

本文檔將隨著系統發展持續更新，開發團隊應定期審查並優化心率閾值調整系統，確保其在各種情況下的準確性和可靠性。 