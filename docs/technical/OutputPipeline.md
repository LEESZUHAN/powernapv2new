# 輸出管線＆資料串流總覽

> 最後更新：2025-06-22

本文檔統一說明 PowerNap 在「一場小睡」期間，如何產生、計算並上傳各式資料；以及後續在裝置第三頁（開發日誌）與 CloudKit Dashboard 上的查看方法。

---

## 0. 名詞速覽

| 名稱 | 位置 | 角色 |
|------|------|------|
| **TelemetryLogger** | `Watch App/TelemetryLogger.swift` | 對外 façade。緩衝所有事件 → flush 時交給 **CloudKitLogger** |
| **CloudKitLogger** | `Watch App/CloudKitLogger.swift` | 實際寫入 CloudKit PublicDB |
| **AdvancedLogger** | `Watch App/AdvancedLogger.swift` | 開發者用高級日誌，僅存在裝置內，可在「第三頁」即時查看 |
| **SleepDataLogger** | `SleepDataLogger` 類 | 將高頻監測數據寫入 CSV，位於 `~/Documents/LogFiles/` |
| **sessionId** | 由 `startNap()` 產生 | 串聯同一場小睡的所有事件 |

---

## 1. 時序圖（文字版）

```
使用者點「開始小睡」
 ├─ TelemetryLogger.log(session_start)
 │    └─ fields: durationSeconds, rhr, thresholdBPM, sessionId
 ├─ AdvancedLogger.sessionStart
 └─ SleepDataLogger.startNewSession → 建立 CSV
        ↓（數分鐘監測 & 定時 logSleepData）
使用者被鬧鈴叫醒／手動結束
 ├─ PowerNapViewModel.stopNap()
 │    ├─ recordFinalSleepData() 計算 ratio/trend…
 │    ├─ TelemetryLogger.log(session_end, status=pre_feedback)
 │    └─ AdvancedLogger.sessionEnd (pre-feedback)
 │
 │ ＊此時若 App 被殺死 → Cloud 仍有 pre_feedback，可作 fallback
 │
 ├─ （UI 顯示反饋彈窗）
 │
用戶按下「準確／不準」
 ├─ TelemetryLogger.log(session_feedback)
 ├─ TelemetryLogger.log(session_end, status=post_feedback)
 ├─ TelemetryLogger.flush()  // 立即寫雲端
 └─ AdvancedLogger.sessionEnd (post-feedback)
```

---

## 2. 各事件詳解

### 2.1 session_start
* 產生時機：`startNap()`；永遠 1 筆。
* 主要欄位：`durationSeconds`, `rhr`, `thresholdBPM`, `sessionId`, `appVersion`…
* 作用：紀錄「起始參數」，日後可觀察用戶是否手動改變設定值。

### 2.2 session_end（pre_feedback）
* 產生時機： `stopNap()` 立即計算並上傳。
* `status = "pre_feedback"`。
* 萬一 APP Crash／用戶不給反饋 → Cloud 仍至少有這筆。

### 2.3 session_feedback
* 產生時機：`processFeedback()` 收到 UI 選擇後立即寫入。
* 欄位：`accurate`, `feedbackType`, `ratio`, `trend`, …

### 2.4 session_end（post_feedback）
* 同 `processFeedback()`，重新計算所有指標後上傳。
* `status = "post_feedback"`。
* 分析時優先使用此筆；若不存在則 fallback pre_feedback。

### 2.5 AdvancedLogger
* 類別：`phaseChange`, `hr`, `sessionStart`, `sessionEnd`…
* 僅供 Watch 上第三頁「原始日誌」即時檢查；不會上雲。

### 2.6 CSV（SleepDataLogger）
* 檔名：`powernap_session_YYYY-MM-DD_HH-mm-ss.csv`
* 每 10 秒批次寫入：心率、加速度、閾值、趨勢…
* 自動保留 14 天。

---

## 3. 第三頁「原始日誌」查看法

1. 在 Watch App 主畫面向右滑兩次（或點右上 debug 圖示）。
2. 依時間倒序顯示 `AdvancedLogger` 的 `LogEntry`。
3. 觀察關鍵：
   • `sessionStart` / `sessionEnd` 欄位值是否合理。
   • `phaseChange` 是否按照 awake → lightSleep → deepSleep 流動。
   • `hr`、`anomaly` 分數是否瞬間跳動。

---

## 4. CloudKit Dashboard 快速查詢

```txt
環境   : Development
Zone    : _defaultZone  （未來可改自訂 zone）
Record  : session_end
Filter  : sessionId == "XXX" AND status == "post_feedback"
```

* 想看「沒有反饋」的場景 ⇒ 將 `status` 換成 `pre_feedback`。
* 想一次抓一週所有結果 ⇒ `timestamp >= 2025-06-13` + `recordType == "session_end"`。

---

## 5. 雲端資料對應表

| Record Type | 必帶欄位 | 補帶欄位（自動） |
|-------------|----------|-------------------|
| session_start | sessionId, durationSeconds | appVersion, buildNumber |
| session_end  | sessionId, status, ratio, trend, deltaScore | appVersion, buildNumber |
| session_feedback | sessionId, accurate, feedbackType | appVersion, buildNumber |

> `appVersion` / `buildNumber` 由 `TelemetryLogger.log()` 自動填入；開發者無需理會。

---

## 6. 分析建議

1. 以 `sessionId` 作為主鍵，LEFT JOIN：
   ```sql
   SELECT *
   FROM session_end AS end_final   -- status = post_feedback
   LEFT JOIN session_feedback AS fb USING (sessionId)
   LEFT JOIN session_start  AS st USING (sessionId)
   ```
2. 沒找到 `post_feedback` 時，可用 `pre_feedback` 代表最終結果。
3. 常用 K P I：
   • `deltaScore` 分佈 & 趨勢
   • `cumulativeScore` 週期性變化
   • `ratio` vs. `feedbackType` 交叉表

---

## 7. 風險＆已知無害錯誤

| 錯誤訊息 | 成因 | 影響 | 處置 |
|-----------|------|------|------|
| `ZoneChanges + error: OTHER` | Dashboard 對 PublicDB `_defaultZone` 做 `fetchZoneChanges` | 噪音 | 無須理會；程式已改用 `queryRecords` |
| CloudKit quota approaching | 每日大量 export | 暫無 | 將 export 排程分片、加 `desiredKeys` |

---

## 8. Roadmap

* 改用 **PrivateDB + powernap_private_zone**，細分每位使用者資料。  
* 對 `session_end` 做 **CKModifyRecordsOperation** 批次上傳，降低 API hit。  
* `session_summary` Record Type（可選）：後端雲函數自動整合三筆事件，供 BI 工具直接讀取。

---

> 若文件需更新，請於 PR 標註 `#output-pipeline`。 