# PowerNap 演算法開發計劃

## 開發階段與技術路線

### 第一階段：基礎設計與準備

1. **共享類型定義**
   - 創建單一的類型定義文件，包含所有演算法需要的共享枚舉和結構體
   - 確保正確設置訪問控制級別和Target Membership

2. **服務接口設計**
   - 定義清晰的服務接口（協議），分離實現與接口

### 第二階段：核心服務實現

3. **動作檢測服務 (MotionDetectionService)**
   - 實現動作數據收集
   - 設計動作分析演算法
   - 定義靜止狀態閾值和時間窗口
   
   **動作分析窗口實現計劃**：
   - **滑動窗口機制實現**：
     - 定義數據結構：使用環形緩衝區(circular buffer)或雙端隊列(deque)存儲時間戳和動作強度
     - 窗口更新策略：每秒將新數據加入窗口，同時移除最舊的數據點
     - 支持多窗口並行：同時維護年齡組特定窗口(1-5分鐘)和短窗口(20秒)
     - 計算時間優化：使用增量計算法，避免每次重新計算整個窗口
     ```swift
     // 滑動窗口示例實現
     class SlidingWindow {
         private var dataPoints: [(timestamp: Date, intensity: Double)]
         private let windowDuration: TimeInterval
         
         // 添加新數據點並移除過期數據
         func addDataPoint(_ intensity: Double, timestamp: Date = Date()) {
             dataPoints.append((timestamp, intensity))
             let cutoffTime = timestamp.addingTimeInterval(-windowDuration)
             dataPoints = dataPoints.filter { $0.timestamp > cutoffTime }
         }
         
         // 計算靜止佔比
         func calculateStationaryPercentage(threshold: Double) -> Double {
             let stationarySamples = dataPoints.filter { $0.intensity < threshold }.count
             return Double(stationarySamples) / Double(dataPoints.count)
         }
     }
     ```
   
   - **百分比閾值判定法**：
     - 依據年齡組配置計算靜止比例要求(80%-90%)
     - 計算公式：靜止時間佔比 = 靜止樣本數 / 總樣本數
     - 條件滿足邏輯：當靜止佔比 ≥ 要求百分比且持續達到確認時間，判定為睡眠狀態
     - 實時更新評估：每秒重新評估一次靜止狀態
   
   - **自適應閾值系統**：
     - 數據基礎：收集最近5分鐘的動作數據樣本
     - 統計分析：計算平均值(μ)和標準差(σ)
     - 閾值計算：new_threshold = μ + σ
     - 限制保護：應用0.015~0.05的硬性限制，防止極端值
     - 平滑過渡：使用指數加權移動平均(EWMA)實現平滑閾值變化
     ```swift
     // 自適應閾值示例實現
     func calculateAdaptiveThreshold(recentMotionData: [Double]) -> Double {
         let mean = recentMotionData.reduce(0, +) / Double(recentMotionData.count)
         let variance = recentMotionData.map { pow($0 - mean, 2) }.reduce(0, +) / Double(recentMotionData.count)
         let stdDev = sqrt(variance)
         
         // 基本閾值 = 平均值 + 標準差
         var newThreshold = mean + stdDev
         
         // 應用限制
         newThreshold = max(0.015, min(0.05, newThreshold))
         
         // 平滑過渡 (α = 0.3, 賦予新值30%權重)
         currentThreshold = 0.7 * currentThreshold + 0.3 * newThreshold
         
         return currentThreshold
     }
     ```
   
   - **微動處理優化**：
     - 異常值過濾：使用中值濾波器消除突發干擾
     - 模式識別：區分有意識動作和睡眠中自然微動
     - 頻率域分析：分析動作的頻率特徵，識別睡眠相關動作
     - 情境自適應：在已確認睡眠狀態後提高動作閾值寬容度

   - **多設備數據融合**：
     - 若用戶同時佩戴多個設備(如手錶和耳機)，實現數據融合策略
     - 加權算法：根據設備可靠性分配權重
     - 衝突解決機制：當不同設備數據不一致時的決策邏輯

4. **心率監測服務 (HeartRateMonitorService)**
   - 實現心率數據收集
   - 設計心率分析演算法
   - 定義心率閾值和變化檢測

### 第三階段：整合與協調

5. **睡眠檢測協調器 (SleepDetectionCoordinator)**
   - 整合動作和心率服務
   - 實現綜合判定邏輯
   - 管理數據流和狀態轉換

6. **與現有ViewModel整合**
   - 設計清晰的依賴注入方式
   - 確保正確處理Actor隔離

### 第四階段：測試與優化

7. **單元測試設置**
   - 為各個服務和協調器建立測試案例
   - 模擬不同場景下的數據輸入

8. **參數優化**
   - 根據測試數據調整閾值和時間窗口

## 實施策略

1. **循序漸進**：先完成一個小組件，確保它正確工作後再進行下一步
2. **頻繁驗證**：每實現一個關鍵功能就進行編譯和測試
3. **分離關注點**：每個服務專注於自己的職責
4. **明確依賴**：清晰表述各組件之間的依賴關係
5. **文檔驅動**：先寫文檔說明，再實現代碼

## 開發進度追蹤

### 第一階段
- [x] 共享類型定義文件創建 (SharedTypes.swift)
- [x] 服務接口設計完成 (ServiceProtocols.swift)

### 第二階段
- [x] 動作檢測服務基礎實現 (MotionService.swift) 
- [x] 滑動窗口機制實現 (內聯在MotionService.swift中)
- [x] 自適應閾值系統實現 (內聯在MotionService.swift中)
- [x] 動作分析窗口完整實現（滑動窗口與百分比閾值判定）
- [x] 解決模塊導入問題 (通過內聯實現解決)
- [ ] 心率監測服務基礎實現
- [ ] 心率分析演算法實現

### 第三階段
- [ ] 睡眠檢測協調器設計
- [ ] 睡眠檢測綜合判定邏輯實現
- [ ] 與ViewModel整合

### 第四階段
- [ ] 單元測試建立
- [ ] 參數優化完成
- [ ] 完整流程測試

## 遇到的問題與解決方案

### 類型引用問題
1. **問題描述**：在實現服務時遇到了類型引用問題。無法直接引用SharedTypes.swift中定義的類型，導致編譯錯誤。
2. **當前解決方案**：採用以下步驟解決：
   - 刪除所有重複的類型定義，只保留SharedTypes.swift中的定義
   - 確保所有協議和服務實現文件中都正確導入了模組
   - 確保SharedTypes.swift和所有協議文件都添加到了正確的Target Membership
3. **最終解決方案**：確保以下文件結構：
   - Models/SharedTypes.swift - 包含所有共享類型定義
   - Services/Protocols/ServiceProtocols.swift - 包含所有服務協議
   - Services/MotionService.swift - 動作服務實現
   - 所有文件都確保添加到同一個Target

### 模塊導入問題
1. **問題描述**：即使正確設置了Target Membership，在新創建的文件（如SlidingWindow.swift和AdaptiveThresholdSystem.swift）中仍無法正確引用其他文件中定義的類型。

2. **解決方案**：
   - **方案一（短期）**：將核心類型直接內聯到各服務實現文件中，避免復雜的導入關係
   ```swift
   // 例如將SlidingWindow類直接寫在MotionService.swift中
   private class SlidingWindow {
       // 實現...
   }
   ```
   
   - **方案二（中期）**：創建一個共享的Utils.swift文件，包含所有輔助類
   ```swift
   // Utils.swift
   import Foundation
   
   // 滑動窗口實現
   public class SlidingWindow {
       // 實現...
   }
   
   // 自適應閾值系統
   public class AdaptiveThresholdSystem {
       // 實現...
   }
   ```
   
   - **方案三（長期）**：將共享組件移至獨立的Swift Package
   ```swift
   // 創建獨立的Package：PowerNapCore
   // 然後在主項目中引用
   import PowerNapCore
   ```

3. **執行計劃**：
   - 已採用方案一，成功將SlidingWindow和AdaptiveThresholdSystem內聯到MotionService中
   - 後續考慮在專案穩定後改為方案二或方案三

### 平台兼容性問題
1. **問題描述**：不同平台（watchOS、iOS、macOS）對CoreMotion的支持不同，導致編譯警告或錯誤。
2. **解決方案**：使用條件編譯標記 (#if os(watchOS)) 來隔離平台特定代碼，並為非目標平台提供適當的替代實現。
   - 對於非watchOS平台，創建模擬類來替代原生API
   ```swift
   #if os(watchOS)
   private let motionManager = CMMotionManager()
   #else
   private class MockMotionManager {
       // 模擬實現...
   }
   private let motionManager = MockMotionManager()
   #endif
   ```

### 建置系統問題
1. **問題描述**：即使確保了類型定義的一致性，Xcode仍可能報告類型或模塊不存在的錯誤。
2. **解決方案**：
   - 執行完全清理 (Product > Clean Build Folder)
   - 刪除DerivedData文件夾 (~/Library/Developer/Xcode/DerivedData)
   - 重新啟動Xcode
   - 最極端情況下，可能需要重建項目結構 

## 動作窗口與年齡組配置考慮

### 現有配置
- 目前在SharedTypes.swift中，年齡組別(AgeGroup)同時影響：
  - 心率閾值百分比：影響判定用戶處於睡眠狀態的心率標準
  - 最小檢測時間窗口：影響判定靜止狀態所需的最短時間
  - 動作分析窗口配置：不同年齡組使用不同的窗口大小和採樣頻率

### 優缺點分析
**優點**：
- 整合考慮生理特性：不同年齡組確實存在睡眠模式差異
- 配置簡化：使用單一變量控制多個參數，減少配置複雜度
- 統一邏輯：保持判定邏輯的一致性

**缺點**：
- 過度耦合：心率閾值和動作窗口可能需要獨立調整
- 個體差異：即使在同一年齡組內，個體差異也可能很大
- 維護複雜：修改某一方面可能意外影響另一方面

### 改進建議
- 考慮引入更細粒度的配置項，允許心率和動作分析參數獨立調整
- 添加自適應學習機制，隨時間調整參數以適應個體特性
- 保留年齡組作為初始配置的基礎，但允許後續微調

### 滑動窗口與自適應機制的實現細節

**滑動窗口實現**：
- **數據結構**：使用固定大小的環形緩衝區，減少內存重分配
- **時間複雜度**：保持O(1)的添加和移除操作
- **空間複雜度**：針對5分鐘窗口，最多存儲300個樣本點
- **容錯設計**：處理可能的數據缺失和採樣間隔不一致問題
- **初始化處理**：窗口未滿時的特殊邏輯

**自適應閾值機制**：
- **更新頻率**：默認每60秒重新計算一次閾值
- **初始閾值**：首次運行使用固定閾值(0.02)
- **學習曲線**：隨著使用時間增加，閾值調整幅度逐漸減小
- **用戶特定模型**：長期存儲用戶特定的閾值調整歷史
- **環境因素**：考慮佩戴位置、環境振動等因素影響

## 下一階段計劃

### 心率監測服務
1. **基本架構設計**：
   - 參考動作服務的成功設計模式
   - 注意可測試性和模擬功能

2. **數據採集**：
   - 從HealthKit讀取用戶心率
   - 處理心率數據缺失和異常值

3. **分析算法**：
   - 實現心率下降檢測
   - 自適應靜息心率判定
   - 考慮年齡組特定的心率閾值

4. **與動作服務整合**：
   - 準備清晰的接口用於後續整合 