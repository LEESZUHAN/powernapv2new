# PowerNap 本地化待辦清單 - 複查更新版

## 🎯 複查結果摘要

經過全面複查，發現之前已完成約95%的本地化工作，但仍有少數遺漏項目需要處理。

## 📍 第一階段發現：剩餘需要本地化的硬編碼中文文字

### 🔍 ContentView.swift 剩餘項目

#### ShareUsageSettingView 中的硬編碼文字 (Line 2907-2913)
```swift
Line 2907: Text("分享匿名使用資料")
Line 2913: Text("分享匿名使用資料，協助我們持續優化偵測，讓更多人享有高品質小睡體驗。此設定不會上傳任何可識別個人或健康數據，您可隨時關閉。")
```

### 🔍 AdvancedLogsView.swift 剩餘項目

#### 硬編碼字符串比較 (Line 228)
```swift
Line 228: .foregroundColor(userFeedbackDisplay == "-" ? .gray : (userFeedbackDisplay == "準確" ? .green : .orange))
```
需要修改為使用NSLocalizedString比較而非硬編碼中文。

### 🔍 SleepConfirmationTimeSettingView.swift 剩餘項目

#### AlertMessage 硬編碼文字 (Line 260, 287, 309, 318, 336)
```swift
Line 260: alertMessage = "確認時間已設為 \(formattedTime)"
Line 287: alertMessage = "確認時間已重置為 \(timeString)"
Line 309: alertMessage = "已開啟智慧學習，將基於現有設定 \(formattedTime) 繼續優化"
Line 318: alertMessage = "已關閉智慧學習，系統將不再自動調整確認時間"
Line 336: alertMessage = "已開啟智慧學習，將基於現有設定 \(formattedTime) 繼續優化"
```

## 🎯 需要新增的本地化 Key

### ShareUsageSettingView 相關
- `share_anonymous_usage_data_toggle` = "分享匿名使用資料"
- `share_usage_detailed_description_toggle` = "分享匿名使用資料，協助我們持續優化偵測，讓更多人享有高品質小睡體驗。此設定不會上傳任何可識別個人或健康數據，您可隨時關閉。"

### AlertMessage 相關
- `confirmation_time_set_to` = "確認時間已設為 %@"
- `confirmation_time_reset_to` = "確認時間已重置為 %@"
- `smart_learning_enabled_with_setting` = "已開啟智慧學習，將基於現有設定 %@ 繼續優化"
- `smart_learning_disabled_message` = "已關閉智慧學習，系統將不再自動調整確認時間"

### AdvancedLogsView 比較邏輯
- 需要修改 `userFeedbackDisplay == "準確"` 的比較邏輯為使用本地化字符串常量

## ✅ 已完成的本地化工作回顧

### 已完全本地化的區域：
1. **ContentView.swift** (95%+ 完成)
   - ✅ 所有 NavigationTitle 已本地化
   - ✅ 碎片化睡眠設置完全本地化
   - ✅ 引導頁面完全本地化
   - ✅ 說明頁面完全本地化
   - ✅ 反饋系統完全本地化
   - ✅ 心率閾值設置完全本地化
   - ✅ 年齡組設置完全本地化

2. **AdvancedLogsView.swift** (95%+ 完成)
   - ✅ 所有UI文字已本地化
   - ⚠️ 僅剩字符串比較邏輯需修正

3. **SleepConfirmationTimeSettingView.swift** (90%+ 完成)
   - ✅ 所有UI文字已本地化
   - ⚠️ 僅剩AlertMessage需本地化

4. **其他Views目錄文件**
   - ✅ SleepConfirmationTimeButton.swift 完全本地化
   - ✅ MinimumNapDurationCalculator.swift 無需本地化（僅註釋）

## 📊 本地化完成度統計

- **總體完成度**: ~97%
- **剩餘工作量**: ~10個字符串需要本地化處理
- **優先級**: 中等（主要為用戶提示信息）

## 🚀 下一步行動計劃

### 第二階段需要執行的具體任務：

1. **更新 Localizable.strings** (zh-Hant.lproj & en.lproj)
   - 添加 4 個新的本地化鍵值對

2. **修改 ContentView.swift**
   - 替換 ShareUsageSettingView 中的 2 個硬編碼文字

3. **修改 AdvancedLogsView.swift**
   - 修正字符串比較邏輯為使用本地化常量

4. **修改 SleepConfirmationTimeSettingView.swift**
   - 替換 5 個 alertMessage 賦值為使用 NSLocalizedString

### 預計完成時間
- 工作量較小，預計 15-20 分鐘內可完成全部剩餘本地化工作
- 完成後將達到 ~99%+ 的本地化覆蓋率

## 📝 備註

本次複查確認了之前的本地化工作質量很高，只有少數邊緣項目被遺漏。主要集中在：
1. 設定頁面的動態提示信息
2. 日誌分析的邏輯比較
3. 分享設定的重複文字

這些項目的本地化將進一步提升應用的用戶體驗一致性。

## 第一階段發現：需要本地化的硬編碼中文文字

### 📍 ContentView.swift

#### 碎片化睡眠設置區塊 (Line 2614-2671)
```swift
Line 2614: Text("碎片化睡眠模式說明")
Line 2619: Text("如果您經常經歷睡眠碎片化（頻繁短暫醒來），啟用此模式可以提高睡眠檢測準確度。")
Line 2625: Text("啟用後的變化：")
Line 2630: Text("• 縮短睡眠確認時間以捕捉短暫睡眠")
Line 2636: Text("• 優化對微覺醒的處理")
Line 2642: Text("• 調整心率監測模式，適應快速變化")
Line 2654: Text("適用情境")
Line 2659: Text("• 淺眠者：容易短暫醒來的睡眠習慣")
Line 2665: Text("• 環境敏感者：對環境聲音或光線敏感")
Line 2671: Text("• 午休困難者：難以持續維持午休狀態")
```

#### 引導頁面區塊 (Line 2710-2843)
```swift
Line 2710: Text("歡迎使用")
Line 2738: Text("什麼是 PowerNap？")
Line 2743: Text("PowerNap 是專為 Apple Watch 打造的科學小睡工具，結合心率與動作偵測...")
Line 2747: Text("下一頁")
Line 2776: Text("如何正確使用？")
Line 2781: Text("PowerNap 會透過心率與動作資料自動判定入睡，初期準確率約 70–90%...")
Line 2785: Text("下一頁")
Line 2814: Text("如何回報檢測準確度？")
Line 2820: Text("準確 － PowerNap 準時以震動喚醒且感受良好時，請點選...")
Line 2825: Text("分享匿名使用資料")
Line 2831: Text("分享匿名使用資料，協助我們持續優化偵測，讓更多人享有高品質小睡體驗。")
Line 2843: Text("開始使用")
```

#### 說明頁面完整內容 (Line 2936-3030)
```swift
Line 2936: Label("什麼是 PowerNap？", systemImage: "sparkles")
Line 2939: Label("如何正確使用？", systemImage: "questionmark.circle")
Line 2942: Label("如何回報檢測準確度？", systemImage: "hand.thumbsup")
Line 2945: Label("作者的話", systemImage: "person.crop.circle")
Line 2958: Text("什麼是 PowerNap？")
Line 2962: Text("PowerNap 是一款專為 Apple Watch 用戶打造的科學小睡應用...")
Line 2978: Text("如何正確使用？")
Line 2982: Text("PowerNap 會透過心率與動作資料自動判定入睡，初期準確率約 70–90%...")
Line 2998: Text("如何回報檢測準確度？")
Line 3002: Text("準確 － PowerNap 準時以震動喚醒且感受良好時，請點選...")
Line 3018: Text("作者的話")
Line 3023: Text("身為一個曾經每晚醒來 12～15 次、長期受失眠困擾的人...")
```

#### NavigationTitle 硬編碼
```swift
Line 2291: .navigationTitle("心率閾值")
Line 2411: .navigationTitle("檢測敏感度") 
Line 2462: .navigationTitle("年齡組設置")
Line 2684: .navigationTitle("碎片化睡眠")
Line 2924: .navigationTitle("資料分享")
Line 2948: .navigationTitle("說明")
Line 2969: .navigationTitle("什麼是 PowerNap？")
Line 2989: .navigationTitle("如何正確使用？")
Line 3009: .navigationTitle("如何回報檢測準確度？")
Line 3030: .navigationTitle("作者的話")
```

### 📍 AdvancedLogsView.swift

#### 硬編碼文字
```swift
Line 505: "+\(deltaDurationShortVal)秒" / "\(deltaDurationShortVal)秒"
Line 508: "+\(deltaDurationLongVal)秒" / "\(deltaDurationLongVal)秒"
Line 451: "誤報"
Line 451: "漏報"
```

### 📍 從截圖觀察到的英文混雜問題
- "Current Heart Rate Threshold" 應該顯示為中文
- "When heart rate is below this threshold and stable..." 描述文字
- "Enable Fragmented Sleep Mode" 開關文字

## 需要新增的本地化 Key

### 碎片化睡眠相關
- fragmented_sleep_mode_explanation
- fragmented_sleep_description
- changes_after_enabling
- shorten_confirmation_time
- optimize_micro_awakening
- adjust_hr_monitoring
- light_sleeper
- environment_sensitive
- nap_difficulty

### 引導頁面相關
- welcome_to
- what_is_powernap_onboarding
- powernap_description_onboarding
- next_page
- how_to_use_correctly_onboarding
- how_to_use_description_onboarding
- how_to_report_accuracy_onboarding
- how_to_report_description_onboarding
- share_anonymous_usage_data
- share_usage_description_onboarding
- start_using

### 說明頁面相關
- info_menu_labels (4個)
- detailed_content_keys (4個完整內容)

### 導航標題相關
- heart_rate_threshold_title
- detection_sensitivity_title
- age_group_setting_title
- fragmented_sleep_title
- data_sharing_title
- help_title
- info_titles (4個)

### 其他
- seconds_unit_suffix
- false_positive_detection_error
- false_negative_detection_error 