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
- [x] 動作檢測服務基礎實現 (MotionService.swift - 初步實現，需要解決類型引用問題) 
- [ ] 心率監測服務基礎實現
- [ ] 動作分析演算法實現
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