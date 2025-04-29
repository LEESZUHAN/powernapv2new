# WatchOS SwiftUI 佈局指南 (PowerNap應用)

> 本文檔記錄了SwiftUI在WatchOS環境中的佈局最佳實踐，特別適用於PowerNap應用開發。同時包含了對這些建議的分析評估。

## 基本佈局容器

### 主要容器元素
* **VStack**：垂直排列元素
  * 適合主視圖的整體結構
  * 使用spacing參數控制元素間距
  * 例：`VStack(spacing: 10) { /* 元素 */ }`

* **HStack**：水平排列元素
  * 適合並排按鈕、標籤與值的配對
  * 例：`HStack { Text("標籤") Spacer() Text("值") }`

* **ZStack**：層疊元素（前後堆疊）
  * 用於創建覆蓋效果，如背景動畫
  * 例：`ZStack { Circle()/* 背景 */ VStack { /* 前景內容 */ } }`

### 空間控制
* **Spacer()**：創建彈性空間，推開元素
  * 在Stack內用於對齊或分散元素
  * 例：`VStack { Spacer() Text("居中") Spacer() }`

* **padding()**：添加內邊距
  * 可指定方向和大小：`.padding(.horizontal, 10)`
  * 無參數時應用預設間距：`.padding()`

* **frame()**：控制尺寸
  * 固定尺寸：`.frame(width: 100, height: 50)`
  * 最大尺寸：`.frame(maxWidth: .infinity)`
  * 最小尺寸：`.frame(minHeight: 40)`

## 複雜佈局容器

* **ScrollView**：處理可能超出螢幕的內容
  * 通常包含一個VStack：`ScrollView { VStack { /* 內容 */ } }`

* **Form/List**：設定與資料展示
  * 結構化設定項：`Form { Section("區塊標題") { /* 項目 */ } }`
  * 配合ForEach使用：`List { ForEach(items) { item in /* 項目視圖 */ } }`

* **TabView**：分頁導航
  * 用於頂層導航：`TabView(selection: $tab) { /* 各頁面 */ }`
  * WatchOS中，頁面可通過左右滑動切換

## 對齊與調整

### 對齊修飾器
* **.multilineTextAlignment(.center)**：多行文字對齊
* **.frame(maxWidth: .infinity, alignment: .leading)**：容器內對齊

### 視圖修飾
* **.font(.title)，.foregroundColor(.blue)**：文字樣式
* **.buttonStyle(.borderedProminent)**：按鈕樣式
* **.tint(.green)**：色調

## WatchOS特定考量

### 螢幕空間
* 謹慎使用間距，Apple Watch螢幕有限
* 使用.font(.caption)等較小字體

### List佈局
* 使用`.listRowInsets(EdgeInsets())`控制行間距
* `.listRowBackground(Color.clear)`調整行背景

## 組織複雜視圖

### 子視圖抽取
* 使用@ViewBuilder創建可重用視圖組件
* 例：`@ViewBuilder private func statusView() -> some View { /* 視圖內容 */ }`

### 條件渲染
* 使用if和switch基於狀態顯示不同UI

---

## 分析評估

### 非常適用的建議

1. **使用ScrollView處理內容溢出**：在WatchOS中尤為重要，因為螢幕空間極其有限，我們實際應用中也採用了這點

2. **謹慎控制間距**：建議使用較小間距和字體大小非常合理，符合Apple官方指南

3. **組件化視圖**：抽取子視圖的建議可以極大提高代碼可維護性

4. **TabView和滑動導航**：WatchOS中左右滑動是主要導航方式，這點建議很到位

### 可以補充的部分

1. **Digital Crown互動**：指南中未提及如何利用Digital Crown，它是WatchOS的獨特輸入方式，建議：
   ```swift
   // 例如與ScrollView結合使用
   ScrollView {
     // 內容
   }
   .focusable(true)
   .digitalCrownRotation($scrollAmount)
   ```

2. **適配不同尺寸**：WatchOS有多種尺寸（38mm到45mm不等），建議使用GeometryReader來適配：
   ```swift
   GeometryReader { geometry in
     // 根據geometry.size.width調整佈局
   }
   ```

3. **深色模式考量**：WatchOS主要使用深色背景，因此顏色對比度尤為重要：
   * 淺色文字在深色背景上
   * 高對比色用於突出重要元素

4. **省電考慮**：某些布局和視覺效果會增加電池消耗，尤其是動畫效果，建議：
   * 減少複雜動畫
   * 避免過度使用高亮色背景

5. **可達性**：考慮較大的觸控目標(>44pt)，增加按鈕之間的間距

### 目前PowerNap應用布局實踐

我們的PowerNap應用已經應用了很多這些最佳實踐：

1. 使用ScrollView確保所有內容可見
2. 採用清晰的視覺層次（主功能區和測試區分開）
3. 使用適當的字體大小和按鈕尺寸
4. 基於狀態切換不同UI（準備、監測、倒計時三種狀態）

建議繼續優化：
* 考慮採用TabView實現更多頁面（如統計頁面）
* 可進一步利用Digital Crown增強交互
* 增加適當的視覺反饋（例如狀態轉變時的微動畫） 