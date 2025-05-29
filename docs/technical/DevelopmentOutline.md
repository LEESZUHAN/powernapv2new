# PowerNap 開發進度大綱

> **文件定位說明**：本文件是 PowerNap 項目的整體開發進度指南，提供完整的階段性任務規劃，著重於實現步驟和成果檢查點。本文不包含具體演算法實現細節，僅提供架構性描述。若需了解具體演算法開發計劃，請參考 [AlgorithmDevelopmentPlan.md](AlgorithmDevelopmentPlan.md)；若需了解特定功能的技術實現，請參考相應的專項文檔（如 [HeartRateSystem.md](HeartRateSystem.md)、[ConvergenceSystem.md](ConvergenceSystem.md) 和 [SleepDetectionSystem.md](SleepDetectionSystem.md)）。完整的文檔導覽請參考 [TechnicalDocumentationMap.md](TechnicalDocumentationMap.md)。

## 概述

PowerNap是一個Apple Watch應用程式，幫助用戶通過短時間休息提高精神狀態。應用通過心率和動作監測檢測用戶的睡眠狀態，並在設定的時間到達後喚醒用戶。

### 技術棧
- **語言與框架**：Swift、SwiftUI、Combine
- **主要Apple框架**：HealthKit、CoreMotion、WatchKit、UserNotifications
- **關鍵API**：WKExtendedRuntimeSession、HKWorkoutSession、UNUserNotificationCenter

### 開發架構
- **MVVM架構**：使用PowerNapViewModel作為核心ViewModel
- **服務模組化**：將功能拆分為多個獨立服務
- **協調器模式**：使用SleepDetectionCoordinator協調多個服務

## 第一階段：基礎架構與權限設置

### 1. 專案基礎搭建
- 創建WatchOS專案結構
- 配置基本Info.plist設置
- 設置必要的App Capabilities
- 實現基本TabView UI框架

### 2. 權限系統實現
- 配置HealthKit權限請求
  - 心率讀取權限
  - 健康數據寫入權限
- 配置通知權限請求
- 實現權限檢查與請求流程

### 3. 基本資料模型定義
- 創建Models目錄並實現SharedTypes.swift，定義：
  - SleepState枚舉（awake、resting、lightSleep、deepSleep）
  - AgeGroup枚舉（teen、adult、senior）
  - MotionIntensity枚舉（none到intense五個等級）
  - 基本數據結構與協議

**成果檢查點**：
- 應用能夠啟動並顯示基本UI框架
- 能夠請求並獲取必要權限
- 基本數據類型已定義並可使用

## 第二階段：核心服務實現

### 1. 心率服務實現
- 創建Services目錄
- 實現HeartRateService.swift，包含：
  - 使用HealthKit請求並獲取實時心率數據
  - 計算並監測靜息心率(RHR)
  - 實現心率閾值計算與判定
  - 發布心率相關數據流

### 2. 動作監測服務實現
- 實現MotionService.swift，包含：
  - 使用CoreMotion收集加速度數據
  - 計算動作強度和靜止持續時間
  - 實現動作窗口分析
  - 發布動作狀態數據流

### 3. 睡眠檢測協調器實現
- 實現SleepDetectionCoordinator.swift，包含：
  - 整合心率與動作數據
  - 實現狀態機轉換邏輯
  - 開發滑動窗口分析算法
  - 實現基於年齡組的差異化檢測參數

### 4. 輔助服務實現
- 實現HeartRateAnomalyTracker.swift（心率異常追蹤）
- 實現HeartRateThresholdOptimizer.swift（閾值優化）
- 實現SlidingWindow.swift（滑動窗口處理）

**成果檢查點**：
- 心率數據成功獲取並顯示
- 動作數據成功分析並分類
- 睡眠狀態檢測系統基本運作
- 服務之間的通信正常工作

## 第三階段：核心業務邏輯與用戶設定檔

### 1. 用戶睡眠設定檔
- 實現UserSleepProfile.swift，包含：
  - 用戶偏好設置存儲
  - 自動參數優化邏輯
  - 用戶反饋處理機制

### 2. PowerNap服務實現
- 實現PowerNapServices.swift，包含：
  - 小睡會話生命週期管理
  - 服務協調與事件處理
  - 數據記錄系統
  - 反饋收集與處理

### 3. 睡眠服務整合
- 實現SleepServices.swift，包含：
  - 協調多個監測服務
  - 整合睡眠狀態判斷
  - 提供綜合睡眠狀態數據

### 4. 背景執行優化
- 在PowerNapServices中實現：
  - WKExtendedRuntimeSession配置
  - HKWorkoutSession管理
  - 背景任務處理與恢復

**成果檢查點**：
- 用戶設定能夠保存並應用
- 完整的小睡監測流程可運行
- 背景執行能夠持續監測數據
- 基本數據記錄功能正常工作

## 第四階段：用戶界面與交互實現

### 1. 主頁面實現
- 完善ContentView.swift，包含：
  - 實現設定時間選擇器
  - 開始/停止按鈕邏輯
  - 睡眠狀態指示器
  - 計時器顯示

### 2. 數據頁面實現
- 在ContentView中添加數據頁面，顯示：
  - 即時心率與閾值
  - 運動強度與狀態
  - 睡眠判定進度
  - 系統參數與配置

### 3. 設置頁面實現
- 實現設置頁面，包含：
  - 年齡組選擇
  - 閾值微調選項
  - 睡眠確認時間設置
  - 系統偏好配置

### 4. 數據記錄頁面實現
- 實現數據記錄頁面，包含：
  - 顯示歷史睡眠記錄
  - 心率、動作和睡眠分析數據
  - 記錄篩選與排序
  - 詳細數據視圖

### 5. 睡眠確認時間設定組件
- 實現Views/SleepConfirmationTimeSettingView.swift
- 實現Views/SleepConfirmationTimeButton.swift
- 實現Views/MinimumNapDurationCalculator.swift

**成果檢查點**：
- 完整的TabView界面可正常運作
- 所有頁面的交互功能正常
- 設置能夠正確保存與應用
- 數據記錄能夠顯示並分析

## 第五階段：喚醒系統與通知

### 1. 通知系統實現
- 在PowerNapServices中實現：
  - UNUserNotificationCenter配置
  - 通知內容與觸發條件設置
  - 通知響應處理

### 2. 喚醒流程實現
- 實現startWakeUpSequence方法，包含：
  - 階段性喚醒通知
  - 震動與聲音模式
  - 用戶響應處理

### 3. 計時系統完善
- 完善計時邏輯：
  - 基於睡眠檢測的計時開始
  - 背景計時保持
  - 計時UI更新
  - 超時處理

**成果檢查點**：
- 通知系統可正常發送與接收
- 喚醒序列能夠正確執行
- 計時系統在前後台均運作正常
- 用戶能夠響應或取消喚醒

## 第六階段：數據分析與優化

### 1. 數據記錄系統完善
- 完善PowerNapServices中的數據記錄：
  - 實現四大情境數據記錄（真陽性、假陰性、假陽性、真陰性）
  - CSV格式時間序列數據
  - 批量寫入與儲存優化
  - 自動清理過期記錄

### 2. 心率閾值自動優化系統
- 完善閾值收斂演算法：
  - 基於用戶反饋的不對稱調整
  - 漸進式小步調整策略
  - 防止極端值和過度收斂
  - 長期學習與適應

### 3. 電池與性能優化
- 實現電池優化策略：
  - 批量處理與寫入
  - 數據收集間隔優化
  - 計算頻率控制
  - 日誌記錄優化

**成果檢查點**：
- 數據記錄系統完整且高效
- 閾值自動優化系統可正常學習
- 應用電池消耗合理
- 整體性能流暢無卡頓

## 第七階段：測試與發布準備

### 1. 功能測試
- 開發測試計劃與案例：
  - 四大情境測試（真陽性、假陰性、假陽性、真陰性）
  - 極限條件測試
  - 長時間運行測試
  - 用戶反饋模擬

### 2. 兼容性測試
- 測試不同設備與系統版本：
  - Apple Watch Series 6+
  - watchOS 10.0+
  - 各種錶盤尺寸

### 3. 發布準備
- 準備App Store材料：
  - 應用描述與關鍵詞
  - 螢幕截圖與預覽
  - 隱私政策
  - 審核資料

**成果檢查點**：
- 所有功能正常且穩定運行
- 應用在不同設備上兼容良好
- 發布材料準備完成
- 應用準備好提交審核

## 進階功能（可選）

### 1. 碎片化睡眠模式支持
- 實現短暫睡眠與微覺醒檢測：
  - 縮短睡眠確認時間
  - 調整心率監測靈敏度
  - 優化狀態轉換邏輯

### 2. 自適應敏感度系統
- 實現用戶級別的敏感度調整：
  - 閾值調整偏移量
  - 用戶反饋學習系統
  - 個性化檢測參數

### 3. 健康數據整合
- 實現與Apple健康應用整合：
  - 睡眠數據寫入
  - 睡眠質量分析
  - 關聯健康指標分析 