# CloudKit Workflow ＆ 資料優化指南

> 初版：2025-06-22

---

## A. 雲端工作流程（Workflow）白話教學

### 0. 三個基本維度
1. **Environment**：Development／Production
2. **Zone**：預設 `powernap_private_zone`
3. **Record Type**：`TelemetryEvent`（欄位：`name`、`params`、`timestamp`、`appVersion`、`schemaVersion`…）

### 1. 準備工作
* Dashboard 建立索引：`name`＋`timestamp`＋`appVersion`。
* `TelemetryLogger` 固定寫入：`appVersion`、`buildNumber`、`schemaVersion`。

### 2. 小量即時檢視
Dashboard → **Data › Records** → Filter 例如：
```
name == "session_end" AND appVersion == "2.6.1"
```

### 3. 大量匯出兩條路線
1. **Dashboard Export** ：介面操作 → JSON，臨時分析用。
2. **自動化腳本（推薦）**
   * 呼叫 CloudKit Web API `records/query`，帶 `continuationMarker` 迴圈拉取。
   * Save 為 NDJSON / CSV 於本地再分析。

### 4. 資料分版本策略
* **線上分**：Query 時附 `appVersion` 條件。
* **本地分**：一次抓日期範圍，再用 `pandas` 依 `appVersion` 分群。

### 5. 每日排程範例
1. 02:00 下載最近 24h Production 資料。
2. 備份至 S3／GDrive。
3. 觸發 Notebook 做統計 → 產生 Markdown 報表 → Slack 通知。

### 6. 安全 & 配額
* Token 設為 *Read-Only*。
* 善用 `desiredKeys` 減流量。
* CloudKit 免費層：每日 ~10 GB / 2 M requests，記得分片＋sleep。

---

## B. 可以拿來優化什麼？靈感清單

| # | 想法 | 需要的欄位 | 成果 |
|---|------|------------|------|
| 1 | **Trend 門檻微調**：畫 `trend` vs. 誤判率曲線，若 –0.10 已飆高，將 –0.20 提高至 –0.12 | `trend`, `detectSource`, `feedbackType` | 減少誤判 |
| 2 | **Ratio→DeltaScore 線性化**：`ratio` 分箱觀察 `deltaScore` 平均值 | `ratio`, `deltaScore` | 讓分數更平滑 |
| 3 | **累計分數觸發率**：每日 `profileCumulativeScore ≥ 8` 佔比 | `profileCumulativeScore` | 評估門檻是否需調高 |
| 4 | **喚醒延遲監控**：`session_end` 到 `stopAlarm` 時差 | `timestamp`, `name` | 找通知延遲瓶頸 |
| 5 | **裝置差異**：新增 `deviceModel`，分析舊機型錯誤率 | `deviceModel`, `accurate` | 針對性優化 |
| 6 | **Config 回寫**：分析後把最佳門檻寫回 `PN_Config` Record，App 啟動時拉取 | - | 動態參數下發 |
| 7 | **A/B 測試**：加入 `experimentGroup` 欄位隨機分組 | `experimentGroup`, 多事件 | 比較不同演算法 |
| 8 | **Dashboard 可視化**：Metabase / Grafana + Materialized View | - | 一站式監控 |
| 9 | **資料品質守門**：Python validator 檢查缺欄、倒時差 | - | 自動開 Issue |

---

### 後續 Roadmap
* 離線 Buffer 持久化（UserDefaults / CoreData）。
* `CKModifyRecordsOperation` 批次寫入。
* 若回歸 TelemetryDeck，只需替換 `TelemetryLogger.flush()`，CloudKit 可改作備份管道。

> 如有更新需求請 PR 並標註 `#cloud-workflow`。 