# PowerNap - 優化您的小睡體驗

PowerNap是一款專為Apple Watch設計的應用程式，旨在監測和優化短時間小睡。通過精確的睡眠狀態檢測技術，PowerNap僅在確認您真正入睡後才開始計時，確保您獲得最佳的休息效果。

## 功能特點

* **精確的睡眠檢測**：利用心率和動作感測器技術，準確識別入睡狀態
* **智能喚醒**：在理想的睡眠周期時間喚醒您，避免深度睡眠引起的睡眠慣性
* **睡眠數據分析**：追蹤和分析您的小睡模式和質量
* **個人化設置**：根據個人需求調整小睡時長和喚醒方式
* **智慧學習**：應用會記錄睡眠檢測表現，自動優化個人化參數

## 為什麼選擇PowerNap?

PowerNap與其他睡眠應用的最大區別在於其精確的睡眠檢測技術。大多數應用只是簡單地設定計時器，不考慮您是否真正入睡。PowerNap通過監測心率變化和運動模式，只有在確認您已進入睡眠狀態後才開始計時，這確保您獲得真正有效的休息時間。

## 安裝指南

1. 在Apple Watch上打開App Store
2. 搜索"PowerNap"
3. 點擊下載並安裝應用程式

## 支援資源

* [使用指南](Usage.md)
* [常見問題](FAQ.md)
* [聯絡支援團隊](Contact.md)

## 隱私政策

PowerNap重視用戶隱私。我們僅收集改善功能所必要的資料，並**不會**與第三方共享您的健康資訊。若您在 App 內啟用「分享使用資料」，系統僅會上傳*去識別化*的使用統計與崩潰診斷（不含任何健康資料）至 Apple iCloud CloudKit。詳情請參閱[隱私政策](PrivacyPolicy.html)。

## 版權信息

© 2025 PowerNap Team。保留所有權利。

# PowerNap 技術文檔

本資料夾包含PowerNap專案的所有技術文檔。

## 文檔目錄

### 技術文檔 (`technical/`)

- **ProjectGuideline.md** - 專案概述與核心功能
- **DevelopmentOutline.md** - 開發進度與階段規劃
- **AlgorithmDevelopmentPlan.md** - 演算法開發計劃
- **TechnicalDocumentationMap.md** - 技術文檔導覽圖
- **SleepDetectionSystem.md** - 睡眠檢測系統總體架構
- **HeartRateSystem.md** - 心率監測與閾值調整系統
- **ConvergenceSystem.md** - 收斂與睡眠確認系統
- **TechnicalParamsTable.md** - 技術參數表

## 閱讀指南

新開發者請按照以下順序閱讀文檔：

1. ProjectGuideline.md
2. SleepDetectionSystem.md
3. 根據任務需要選擇閱讀HeartRateSystem.md或ConvergenceSystem.md
4. 參考TechnicalParamsTable.md了解相關技術參數

完整的文檔組織結構與閱讀建議請參考 [TechnicalDocumentationMap.md](technical/TechnicalDocumentationMap.md)。 