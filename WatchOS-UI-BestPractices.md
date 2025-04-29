# WatchOS SwiftUI 佈局最佳實踐指南

## 基本佈局容器

### VStack, HStack 和 ZStack
- **VStack**：垂直排列元素
  - 適合主視圖的整體結構
  - 使用spacing參數控制元素間距
  - 例：`VStack(spacing: 10) { /* 元素 */ }`
  
- **HStack**：水平排列元素
  - 適合並排按鈕、標籤與值的配對
  - 例：`HStack { Text("標籤") Spacer() Text("值") }`
  
- **ZStack**：層疊元素（前後堆疊）
  - 用於創建覆蓋效果，如背景動畫
  - 例：`ZStack { Circle()/* 背景 */ VStack { /* 前景內容 */ } }`

> **評論**：這三種基本容器確實是WatchOS UI設計的基石。VStack尤其適合Apple Watch的垂直螢幕佈局，幾乎所有畫面都以VStack作為主要結構非常合理。ZStack對於設計復雜UI元素（如自定義進度指示器）尤其有用。

## 空間控制

- **Spacer()**：創建彈性空間，推開元素
  - 在Stack內用於對齊或分散元素
  - 例：`VStack { Spacer() Text("居中") Spacer() }`
  
- **padding()**：添加內邊距
  - 可指定方向和大小：`.padding(.horizontal, 10)`
  - 無參數時應用預設間距：`.padding()`
  
- **frame()**：控制尺寸
  - 固定尺寸：`.frame(width: 100, height: 50)`
  - 最大尺寸：`.frame(maxWidth: .infinity)`
  - 最小尺寸：`.frame(minHeight: 40)`

> **評論**：空間控制是WatchOS UI設計的關鍵考量，尤其因為螢幕空間有限。使用`frame(maxWidth: .infinity)`確實是讓按鈕等元素擴展填滿可用空間的好方法。不過，需要注意在有限空間內過度使用padding可能導致內容擠壓。

## 複雜佈局容器

- **ScrollView**：處理可能超出螢幕的內容
  - 通常包含一個VStack：`ScrollView { VStack { /* 內容 */ } }`
  
- **Form/List**：設定與資料展示
  - 結構化設定項：`Form { Section("區塊標題") { /* 項目 */ } }`
  - 配合ForEach使用：`List { ForEach(items) { item in /* 項目視圖 */ } }`
  
- **TabView**：分頁導航
  - 用於頂層導航：`TabView(selection: $tab) { /* 各頁面 */ }`
  - WatchOS中，頁面可通過左右滑動切換

> **評論**：ScrollView在WatchOS應用中確實至關重要，我們在PowerNap應用中的實踐證明了這點。TabView的頁面滑動非常適合分階段顯示相關但不同的內容。不過，Form在WatchOS上佔用空間較大，除非是設置頁面，否則可能考慮使用更緊湊的自定義版面。

## 對齊與調整

- **對齊修飾器**：
  - `.multilineTextAlignment(.center)`：多行文字對齊
  - `.frame(maxWidth: .infinity, alignment: .leading)`：容器內對齊
  
- **視圖修飾**：
  - `.font(.title)`，`.foregroundColor(.blue)`：文字樣式
  - `.buttonStyle(.borderedProminent)`：按鈕樣式
  - `.tint(.green)`：色調

> **評論**：對齊控制對於專業外觀至關重要。特別同意使用`.frame(maxWidth: .infinity, alignment: .leading)`這種方式來控制整體對齊。不過，對於按鈕樣式，我們在PowerNap中發現自定義樣式（背景+圓角）通常比`.buttonStyle()`提供更好的控制。

## WatchOS特定考量

- **螢幕空間**：
  - 謹慎使用間距，Apple Watch螢幕有限
  - 使用`.font(.caption)`等較小字體
  
- **List佈局**：
  - 使用`.listRowInsets(EdgeInsets())`控制行間距
  - `.listRowBackground(Color.clear)`調整行背景

> **評論**：這點非常關鍵！WatchOS開發必須考慮螢幕尺寸限制。字體選擇確實是平衡可讀性和空間利用率的關鍵。我們在PowerNap應用中使用了較大字體來顯示睡眠倒計時（因為重要），而使用較小字體顯示次要信息，這種差異化很重要。

## 組織複雜視圖

- **子視圖抽取**：
  - 使用@ViewBuilder創建可重用視圖組件
  - 例：`@ViewBuilder private func statusView() -> some View { /* 視圖內容 */ }`
  
- **條件渲染**：
  - 使用if和switch基於狀態顯示不同UI

> **評論**：視圖抽取對於保持代碼可維護性極為重要。我們在PowerNap中使用了`private var preparingView: some View {}`這種方式來分離不同狀態的UI，非常有效。對於條件渲染，switch語句確實是處理多種狀態UI的最佳方式，比嵌套if-else更清晰。

## 總體評價

這份SwiftUI佈局指南提供了非常紮實的WatchOS UI開發建議。大部分原則我都強烈同意，特別是關於使用ScrollView處理溢出內容、適當使用spacing和padding控制空間、以及抽取子視圖組織代碼的建議。

我們在PowerNap應用中已經實踐了許多這些原則，如以VStack為主框架、使用ScrollView確保所有內容可見、通過子視圖分離不同UI狀態等。

如果要提出任何補充，我會建議：

1. **考慮Digital Crown交互**：設計UI時，考慮用戶如何使用Digital Crown進行滾動和選擇
2. **動態字體支持**：WatchOS支持動態字體大小，可以使用`.dynamicTypeSize()`來增強可訪問性
3. **GeometryReader的謹慎使用**：在需要精確控制尺寸和位置時可以使用，但應謹慎使用以避免佈局問題
4. **黑色背景優先**：WatchOS UI最好使用黑色背景以節省電池，並讓UI與錶盤邊緣融合

這份指南應成為我們持續開發PowerNap及未來WatchOS應用的參考標準。 