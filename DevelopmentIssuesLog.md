# PowerNap v2 開發問題日誌

## 類型定義重複問題 (2025-04-30)

### 問題描述
在專案初期開發階段，我們遇到了類型定義重複的問題。主要表現為：

1. 多個文件中重複定義了相同的協議和類型
   - `Services/Protocols/MotionServiceProtocol.swift` 中定義了動作服務協議
   - `Services/Protocols/ServiceProtocols.swift` 中可能也包含了相同或相似的協議定義
   - `Supporting Files/TypeImports.swift` 嘗試導入這些類型但可能造成衝突

2. 在不同的 Swift 文件間相互引用時出現編譯錯誤，通常表現為：
   - "Cannot find type 'MotionServiceProtocol' in scope"
   - "Circular dependency between files"
   - "Redundant conformance to protocol"

### 原因分析
1. **Target Membership 設置問題**：
   - 部分文件的 Target Membership 設置不正確，導致在某些目標中無法訪問特定類型
   - Watch App 和主應用之間的類型共享沒有正確設置

2. **模塊化結構設計不當**：
   - 過度分散的協議定義導致引用複雜度增加
   - 缺乏統一的類型管理策略

3. **Swift 的可見性(visibility)限制**：
   - 沒有正確使用 `public`、`internal` 等訪問修飾符
   - 跨目標共享類型時未考慮可見性問題

### 解決方案
1. **統一類型定義**：
   - 創建了 `Models/SharedTypes.swift` 作為統一類型定義的文件
   - 將所有共享類型、協議和枚舉集中在此文件中定義
   - 刪除了冗餘的協議定義文件

2. **正確設置可見性修飾符**：
   - 為所有共享類型添加 `public` 修飾符
   - 確保類型在不同的模塊和目標間可見

3. **優化文件結構**：
   - 刪除了 `Services/Protocols/MotionServiceProtocol.swift`
   - 刪除了 `Services/Protocols/ServiceProtocols.swift`
   - 刪除了 `Supporting Files/TypeImports.swift`

### 經驗教訓
1. **Swift 專案結構設計原則**：
   - 共享類型應集中管理，特別是在多目標專案中
   - 明確的命名空間和模塊化設計可以減少衝突

2. **可見性管理最佳實踐**：
   - 預設使用最嚴格的可見性級別，只在需要時開放
   - 對於共享類型，確保使用正確的 `public` 修飾符

3. **Target Membership 管理**：
   - 對於共享的類型定義文件，需要在所有相關目標中設置正確的 membership
   - 考慮使用 framework 或 package 來更好地管理共享代碼

## 專案設置及模塊化經驗 (2025-04-30)

後續開發中，我們將遵循以下原則：

1. 共享類型統一定義在 `Models/SharedTypes.swift`
2. 服務實現保持在獨立文件中，但協議定義集中管理
3. 視需要考慮將共享代碼遷移到獨立的 Swift Package 或 Framework

這些經驗將有助於減少類似問題在未來再次發生。 