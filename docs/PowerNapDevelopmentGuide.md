# PowerNap 開發指南與最佳實踐

> 本文檔整合了專案前期開發中的關鍵經驗教訓與解決方案，旨在為當前和未來的開發提供參考。

## 目錄

1. [架構設計原則](#1-架構設計原則)
2. [開發最佳實踐](#2-開發最佳實踐)
3. [常見問題解決方案](#3-常見問題解決方案)
4. [程式碼規範](#4-程式碼規範)
5. [Swift特性的正確使用](#5-swift特性的正確使用)

## 1. 架構設計原則

### 1.1 單一職責原則
* **服務分離**: 讓每個Service專注於特定領域（健康、運動、通知等）
* **明確界限**: 避免服務間過度耦合，使用協議或事件通知進行溝通

### 1.2 依賴管理
* **清晰的依賴方向**: ViewModel持有並管理Service，避免Service反向依賴ViewModel
* **依賴注入**: 在初始化時明確傳入依賴項，提高可測試性和可維護性
* **避免循環依賴**: 如果A依賴B，B不應直接或間接依賴A

### 1.3 數據流設計
* **單向數據流**: 從Service到ViewModel到View，避免複雜的雙向綁定
* **發布-訂閱模式**: 使用Combine框架實現松耦合的數據流通
* **狀態管理**: 使用明確定義的狀態枚舉控制UI和業務邏輯流程

## 2. 開發最佳實踐

### 2.1 統一共享類型定義
* **單一來源**: 共享模型類型（如`AgeGroup`）應只有一個定義，放在專用文件中
* **正確的訪問控制**: 確保類型至少是`internal`可見性（默認）或根據需要設為`public`
* **示例**: 

```swift
// AgeGroup.swift
import Foundation

public enum AgeGroup: String, CaseIterable, Codable, Identifiable {
    case teen = "青少年 (10-17歲)"
    case adult = "成人 (18-59歲)"
    case senior = "銀髮族 (60歲以上)"
    
    public var id: String { self.rawValue }
    
    public var heartRateThresholdPercentage: Double {
        switch self {
        case .teen: return 0.875  // 87.5%
        case .adult: return 0.9   // 90%
        case .senior: return 0.935 // 93.5%
        }
    }
    
    public var minDurationForSleepDetection: TimeInterval {
        switch self {
        case .teen: return 120    // 2分鐘
        case .adult: return 180   // 3分鐘 
        case .senior: return 240  // 4分鐘
        }
    }
}
```

### 2.2 ViewModel與服務初始化
* **屬性聲明**: 使用實際服務類型宣告依賴

```swift
@MainActor
class PowerNapViewModel: ObservableObject {
    private let healthKitService: HealthKitService
    private let motionService: MotionService
    private let sleepDetectionService: SleepDetectionService
    // ... 其他服務
```

* **依賴注入**: 在`init`方法內部創建服務實例，避免在參數列表提供預設值

```swift
init() {
    // 基礎服務初始化
    self.healthKitService = HealthKitService()
    self.motionService = MotionService()
    self.notificationService = NotificationService()
    
    // 使用基礎服務初始化複合服務
    self.sleepDetectionService = SleepDetectionService(
        healthKitService: self.healthKitService,
        motionService: self.motionService
    )
    
    // 設置數據綁定
    setupBindings()
    
    // 加載用戶設置
    loadUserPreferences()
}
```

### 2.3 數據綁定
* **使用Combine**: 使用`assign(to:)`或`sink`訂閱服務發布的更新

```swift
private func setupBindings() {
    healthKitService.$latestHeartRate
        .receive(on: DispatchQueue.main)
        .assign(to: &$heartRate)
    
    sleepDetectionService.$currentSleepState
        .receive(on: DispatchQueue.main)
        .sink { [weak self] state in
            self?.currentSleepState = state
            self?.handleSleepStateChange(state)
        }
        .store(in: &cancellables)
}
```

### 2.4 版本控制與提交
* **小步提交**: 每完成一個功能點或修復一個問題就提交
* **明確的提交信息**: 使用一致的格式，如"[FIX] 修復心率顯示錯誤"或"[FEATURE] 添加睡眠統計圖表"
* **功能分支**: 為每個新功能或重大修改創建專用分支

## 3. 常見問題解決方案

### 3.1 命名一致性問題
* **問題**: 專案中存在命名不一致，如從HRV（心率變異性）到HR（心率）的轉換混亂
* **解決方案**: 
  * 使用全局搜索找出所有相關引用
  * 確保命名反映實際含義（如`heartRate`而非`hrv`）
  * 保持UI和程式碼中術語的一致性

### 3.2 類型導入問題
* **問題**: "Cannot find type 'X' in scope"等錯誤
* **解決方案**:
  * 確保必要的`import`語句存在
  * 檢查類型定義的可見性（`public`, `internal`等）
  * 確認文件已添加到正確的Target
  * 檢查是否有重複定義造成的衝突

### 3.3 編譯效能問題
* **問題**: "The compiler is unable to type-check this expression in reasonable time"
* **解決方案**:
  * 將複雜視圖拆分為更小的子視圖組件
  * 避免在視圖中包含複雜的計算或條件判斷
  * 使用`@ViewBuilder`封裝複雜的視圖構建邏輯

### 3.4 異步處理問題
* **問題**: 錯誤使用`async/await`或`Task`
* **解決方案**:
  * 確保異步方法在`async`函數或`Task`中調用
  * 正確處理異步方法的返回值，特別是可能為nil的情況
  * 注意`@MainActor`隔離對異步調用的影響

### 3.5 Xcode頑固的建置錯誤
當遇到即使清理後仍然存在的類型找不到問題時，按以下順序嘗試：

1. **確認Target Membership**: 檢查所有相關文件是否正確添加到當前App Target
2. **檢查訪問控制**: 確保所有需要被引用的類型至少是`internal`可見性
3. **標準清理**:
   * Product -> Clean Build Folder (Shift+Command+K)
   * 刪除Derived Data: `rm -rf ~/Library/Developer/Xcode/DerivedData/YOUR_PROJECT_NAME*`
4. **深度清理**:
   * 退出Xcode
   * 刪除`.swiftpm`資料夾、`.xcworkspace`文件和`.xcodeproj/xcuserdata`資料夾
   * 重新打開項目
5. **最終手段**:
   * 創建新Target或新項目
   * 將代碼和資源有序地遷移

## 4. 程式碼規範

### 4.1 命名慣例
* **變數命名**: 使用駝峰式命名，如`heartRate`, `sleepDetectionThreshold`
* **類型命名**: 使用大駝峰式，如`HeartRateService`, `SleepState`
* **縮寫處理**: 對於常見縮寫，保持一致大小寫，如`url`或`URL`, `id`或`ID`
* **枚舉值**: 使用小駝峰式，如`case isMonitoring`, `case sleepDetected`

### 4.2 文件組織
* **協議在前**: 先定義協議，再實現類型
* **按功能分組**: 相關功能放在一起，不同功能間用`// MARK: - 功能區塊`分隔
* **訪問控制順序**: 按`public`, `internal`, `fileprivate`, `private`順序排列

```swift
// MARK: - 公開接口
public func startMonitoring() { ... }

// MARK: - 內部輔助方法
private func processSensorData(_ data: SensorData) { ... }
```

### 4.3 註釋規範
* **使用目的性註釋**: 解釋"為什麼"而不是"做了什麼"
* **標記TODO和FIXME**: 使用統一格式，如`// TODO: 實現自動調整邏輯`
* **複雜算法說明**: 對不明顯的實現邏輯提供註釋

### 4.4 錯誤處理
* **使用可選值**: 優先使用可選值表示可能缺失的數據
* **結構化錯誤**: 使用`Result`或自定義`Error`類型
* **避免強制展開**: 優先使用optional binding或optional chaining

## 5. Swift特性的正確使用

### 5.1 Actor模型與並發
* **正確使用@MainActor**: 在需要更新UI的視圖模型上使用
* **隔離規則**: 理解Actor隔離對方法調用和初始化的影響
* **Task與異步**: 使用`Task`和`async/await`替代傳統的閉包回調

### 5.2 Combine框架應用
* **數據流轉換**: 利用`.map`, `.filter`等操作符轉換數據流
* **記憶體管理**: 使用`[weak self]`避免閉包中的循環引用
* **訂閱存儲**: 使用`cancellables`集合管理訂閱生命週期

### 5.3 SwiftUI最佳實踐
* **狀態管理**: 合理使用`@State`, `@Binding`, `@ObservedObject`等
* **視圖結構**: 保持每個視圖的單一職責，拆分複雜視圖
* **性能優化**: 使用`@ViewBuilder`和`AnyView`時要注意對渲染性能的影響

---

本指南總結了從先前開發中獲得的寶貴經驗，遵循這些原則和實踐將有助於避免常見陷阱，提高代碼質量和開發效率。隨著專案發展，我們將繼續更新和完善這份指南。 