# PowerNap 技術文檔導覽圖（v1.0.0）

> **文件定位說明**：本文件是 PowerNap 專案的技術文檔導覽圖，提供所有技術文檔的組織架構、相互關係及建議閱讀順序。本文檔旨在幫助新開發者、維護者和審閱者快速了解技術文檔系統，高效獲取所需資訊。
> 
> **特別注意**：本文件僅作為整體文檔結構的導覽，不包含具體技術實現細節。請根據您的需求，參照下方指引訪問相應的技術文檔。

## 一、文檔體系概述

PowerNap 技術文檔體系採用分層級結構，從專案概述到具體技術實現，由上至下包含以下層次：

```
TOP LEVEL
+------------------+     +---------------------+
| ProjectGuideline |-----| DevelopmentOutline |  <-- 專案層
+------------------+     +---------------------+
         |                         |
         v                         v
+----------------------------------+
|      AlgorithmDevelopmentPlan    |  <-- 規劃層
+----------------------------------+
         |
         v
+----------------------------------+
|      SleepDetectionSystem        |  <-- 系統層
+----------------------------------+
        / \
       /   \
      v     v
+------------+    +------------------+
| HeartRate  |----|  Convergence     |  <-- 模組層
| System     |    |  System          |
+------------+    +------------------+
      |                  |
      v                  v
+----------------------------------+
|      TechnicalParamsTable        |  <-- 參數層
+----------------------------------+
```

## 二、文檔內容與關係

### 1. 專案層文檔

專案層文檔提供 PowerNap 專案的整體視角和開發規劃：

| 文檔名稱 | 主要內容 | 適用讀者 | 更新頻率 |
|---------|---------|---------|---------|
| [ProjectGuideline.md](./ProjectGuideline.md) | 專案概述、核心功能、基本架構、使用流程 | 所有相關人員、新加入的開發者 | 低（僅在重大功能變更時） |
| [DevelopmentOutline.md](./DevelopmentOutline.md) | 開發進度規劃、階段目標、里程碑 | 專案管理者、開發團隊 | 中（隨開發進度更新） |

### 2. 規劃層文檔

規劃層文檔提供演算法和技術實現的整體規劃：

| 文檔名稱 | 主要內容 | 適用讀者 | 更新頻率 |
|---------|---------|---------|---------|
| [AlgorithmDevelopmentPlan.md](./AlgorithmDevelopmentPlan.md) | 演算法開發路線圖、技術選型、實現計劃 | 開發者、技術架構師 | 中（隨技術方向調整更新） |

### 3. 系統層文檔

系統層文檔提供主要功能系統的整體設計和實現：

| 文檔名稱 | 主要內容 | 適用讀者 | 更新頻率 |
|---------|---------|---------|---------|
| [SleepDetectionSystem.md](./SleepDetectionSystem.md) | 睡眠檢測系統整體架構、流程、組件關係 | 開發者、測試人員 | 中（功能迭代時更新） |

### 4. 模組層文檔

模組層文檔提供具體功能模組的詳細實現：

| 文檔名稱 | 主要內容 | 適用讀者 | 更新頻率 |
|---------|---------|---------|---------|
| [HeartRateSystem.md](./HeartRateSystem.md) | 心率監測與閾值調整系統的詳細設計與實現 | 開發者、維護者 | 高（功能改進時頻繁更新） |
| [ConvergenceSystem.md](./ConvergenceSystem.md) | 收斂機制與睡眠確認系統的詳細設計與實現 | 開發者、維護者 | 高（功能改進時頻繁更新） |

### 5. 參數層文檔

參數層文檔提供系統中使用的標準化參數定義：

| 文檔名稱 | 主要內容 | 適用讀者 | 更新頻率 |
|---------|---------|---------|---------|
| [TechnicalParamsTable.md](./TechnicalParamsTable.md) | 所有技術參數的標準定義、數值範圍和預設值 | 開發者、測試人員、維護者 | 高（參數調整時更新） |

## 三、建議閱讀順序

根據不同角色和需求，我們建議以下閱讀順序：

### 新加入的開發者

1. [ProjectGuideline.md](./ProjectGuideline.md) - 了解專案概述和基本架構
2. [SleepDetectionSystem.md](./SleepDetectionSystem.md) - 了解睡眠檢測系統整體設計
3. 根據分配任務選擇閱讀 [HeartRateSystem.md](./HeartRateSystem.md) 或 [ConvergenceSystem.md](./ConvergenceSystem.md)
4. [TechnicalParamsTable.md](./TechnicalParamsTable.md) - 了解相關技術參數

### 專案管理者

1. [ProjectGuideline.md](./ProjectGuideline.md) - 了解專案概述
2. [DevelopmentOutline.md](./DevelopmentOutline.md) - 了解開發進度規劃
3. [AlgorithmDevelopmentPlan.md](./AlgorithmDevelopmentPlan.md) - 了解技術實現規劃

### 技術審閱者

1. [ProjectGuideline.md](./ProjectGuideline.md) - 了解專案概述
2. [SleepDetectionSystem.md](./SleepDetectionSystem.md) - 了解技術架構
3. [HeartRateSystem.md](./HeartRateSystem.md) 和 [ConvergenceSystem.md](./ConvergenceSystem.md) - 了解核心模組實現
4. [TechnicalParamsTable.md](./TechnicalParamsTable.md) - 審閱技術參數設定

### 測試人員

1. [SleepDetectionSystem.md](./SleepDetectionSystem.md) - 了解系統功能流程
2. [TechnicalParamsTable.md](./TechnicalParamsTable.md) - 了解預期參數範圍和預設值
3. 根據測試需求選擇閱讀模組文檔

## 四、文檔維護指南

為確保技術文檔的一致性和準確性，請遵循以下維護原則：

1. **參數更新規則**：
   - 任何參數變更必須先更新 [TechnicalParamsTable.md](./TechnicalParamsTable.md)
   - 更新後確保相關模組文檔中的參數值保持一致

2. **版本控制**：
   - 所有文檔均包含版本號和對應的代碼版本
   - 重大更新時增加主版本號，小幅調整時增加次版本號

3. **文檔更新流程**：
   - 代碼實現變更後，相應更新對應文檔
   - 提交文檔更新時，在 commit 訊息中註明更新範圍和原因
   - 重大文檔變更需經技術負責人審核

4. **文檔結構規範**：
   - 所有文檔均包含文件定位說明和與其他文件的關係說明
   - 技術參數使用統一的表達方式（例如：百分比、時間單位）
   - 代碼示例應確保與實際實現一致

## 五、已棄用文檔

以下文檔已合併至新的文檔結構中，僅作為歷史參考：

| 舊文檔名稱 | 內容去向 | 棄用原因 |
|-----------|---------|---------|
| HeartRateThresholdGuideline.md | 合併至 HeartRateSystem.md | 內容重疊，整合為完整系統文檔 |
| HeartRateAlgorithmGuideline.md | 合併至 HeartRateSystem.md | 內容重疊，整合為完整系統文檔 |
| convergence_algorithm.md | 合併至 ConvergenceSystem.md | 內容重疊，整合為完整系統文檔 |
| SleepConfirmationAlgorithm.md | 合併至 ConvergenceSystem.md | 內容重疊，整合為完整系統文檔 |
| SleepDetectionGuideline.md | 升級為 SleepDetectionSystem.md | 擴展為系統層文檔 |

## 六、未來文檔計劃

未來將根據專案發展需要，擴展技術文檔體系：

1. **用戶反饋系統文檔**：計劃添加用戶反饋系統的技術文檔
2. **UI/UX設計文檔**：計劃添加與技術實現相關的 UI/UX 設計文檔
3. **API參考文檔**：計劃添加模組間接口定義的 API 參考文檔
4. **測試案例庫**：計劃添加標準測試案例和預期結果文檔

---

**版本記錄**：
- v1.0.0 (2024-05-20)：初始版本，建立技術文檔導覽圖
- 對應代碼版本：PowerNap v2.3.1 