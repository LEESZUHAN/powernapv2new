# PowerNap 專案

## 專案概述

PowerNap 是一款專為 Apple Watch 設計的應用程式，旨在協助使用者進行高效的短暫小睡（Power Nap）。應用的核心功能是偵測使用者何時進入睡眠狀態，並在使用者預設的時間長度後將其喚醒，以獲取最佳的休息效果而不干擾夜間睡眠規律。

本倉庫包含 PowerNap 應用的源代碼和技術文檔。

## 技術文檔

### 開發指南與最佳實踐

- [PowerNapDevelopmentGuide.md](docs/PowerNapDevelopmentGuide.md) - 開發最佳實踐、架構原則、常見問題解決方案與程式碼規範

### 功能文檔

所有功能相關技術文檔位於 [docs/technical/](docs/technical/) 目錄下，包括：

#### 專案層文檔

- [ProjectGuideline.md](docs/technical/ProjectGuideline.md) - 專案概述、核心功能、基本架構、使用流程
- [DevelopmentOutline.md](docs/technical/DevelopmentOutline.md) - 開發進度規劃、階段目標、里程碑

#### 規劃層文檔

- [AlgorithmDevelopmentPlan.md](docs/technical/AlgorithmDevelopmentPlan.md) - 演算法開發路線圖、技術選型、實現計劃

#### 系統層文檔

- [SleepDetectionSystem.md](docs/technical/SleepDetectionSystem.md) - 睡眠檢測系統整體架構、流程、組件關係

#### 模組層文檔

- [HeartRateSystem.md](docs/technical/HeartRateSystem.md) - 心率監測與閾值調整系統的詳細設計與實現
- [ConvergenceSystem.md](docs/technical/ConvergenceSystem.md) - 收斂機制與睡眠確認系統的詳細設計與實現

#### 參數層文檔

- [TechnicalParamsTable.md](docs/technical/TechnicalParamsTable.md) - 所有技術參數的標準定義、數值範圍和預設值

#### 導覽文檔

- [TechnicalDocumentationMap.md](docs/technical/TechnicalDocumentationMap.md) - 完整的技術文檔導覽

更多信息請參閱 [docs/README.md](docs/README.md)。

## 開發環境與技術要求

- 開發語言：Swift
- 框架：SwiftUI（介面）、HealthKit（健康數據）、CoreMotion（動作感測）
- 目標 OS：watchOS 10.0+
- 開發工具：最新版 Xcode

## 版本信息

當前版本：v2.3.1 (2024-05-20)

### 近期變更摘要（v2.3.2 計畫）

* 2024-06-10：
  * ΔHR 改為輔助訊號，新增三條觸發條件
  * trend 門檻調整為 –0.20，並加入 HR < 1.10×RHR 保護
  * 異常分數門檻 scoreThreshold 由 12 → **8**
  * 日誌 payload 新增 `trend`、`detectSource`、`schemaVersion`
  * TechnicalParamsTable.md、HeartRateSystem.md、ConvergenceSystem.md 已同步更新

更多信息請參閱 [docs/README.md](docs/README.md)。

PowerNap重視用戶隱私。我們僅收集改善功能所必要的資料，並**不會**與第三方共享您的健康資訊。若您在 App 內啟用「分享使用資料」，系統僅會上傳*去識別化*的使用統計與崩潰診斷（不含任何健康資料）至 Apple iCloud CloudKit。詳情請參閱[隱私政策](PrivacyPolicy.html)。 