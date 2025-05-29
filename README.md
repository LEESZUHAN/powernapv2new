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