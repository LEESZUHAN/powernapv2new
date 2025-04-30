# 開發問題解決方案 - 2025-04-30

## Swift類型引用問題

在PowerNap應用中，我們遇到了類型引用的問題。在修復`MotionService.swift`文件的過程中，出現了無法找到以下類型的錯誤：

- `MotionServiceProtocol`
- `MotionIntensity`
- `MotionAnalysisWindow`
- `SlidingWindow`
- `AdaptiveThresholdSystem`

### 模塊引用機制

Swift的模塊引用機制和其他語言有所不同。在Swift中：

1. 同一個Target中的所有類型自動對所有文件可見，不需要顯式導入
2. 但每個Swift文件必須能夠獨立編譯，因此不能有循環引用
3. 類型定義必須唯一，不能在多個文件中重複定義

### 解決方案

1. 確保所有共享類型定義在`Models/SharedTypes.swift`文件中
2. 特定服務的具體實現在各自的服務文件中（如`SlidingWindow.swift`）
3. 在使用這些類型的文件中，不需要顯式導入，但建議添加註釋說明類型來源
4. 如果出現循環引用問題，考慮：
   - 重構代碼結構，消除循環依賴
   - 將共享部分提取到單獨的文件中

### 注意事項

- 不要在多個文件中定義同名類型，即使內部實現不同
- 避免在文件A引用文件B的類型，同時在文件B引用文件A的類型
- 組織好類型層次，從基礎類型到復雜服務
- 使用`public`、`internal`、`private`等訪問修飾符控制類型可見性

這些注意事項將幫助我們避免未來遇到類似的類型引用問題。 