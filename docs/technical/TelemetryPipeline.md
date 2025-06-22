# Telemetry Pipeline 備忘錄

> 最新更新：2025-06-22

## 1. 背景緣起

早期版本（≤ v2.5.x）使用第三方 **TelemetryDeck** SDK 蒐集 app-side 事件，再轉送至 dashboard 分析。所有事件都透過 `TelemetryLogger.shared.log(name, params)` 寫入，並以字首 *telemetry…* 命名臨時參數（如 `telemetryParams`）。

## 2. 架構演進

| 時間 | 管道 | 說明 |
|------|------|------|
| v2.5.x 以前 | TelemetryDeck SDK | 直接呼叫 SDK，事件即時送出。 |
| v2.6.0 起    | **CloudKit**（自架） | 保留 `TelemetryLogger` 類別作為 *Facade*；其 `flush()` 會把快取事件轉存至 `CloudKitLogger`，再寫入 Private Database。 |

### 為何保留 `TelemetryLogger` 名稱？

1. **低成本遷移**：呼叫點眾多，改名風險高。
2. **相依隔離**：未來若再換回 SaaS，只要改 `TelemetryLogger` 實作即可。
3. **快取機制**：沿用「先緩衝、後 flush」的流程，避免 Session 未完成就寫入雲端。

## 3. 目前實作重點（v2.6.0）

* `TelemetryLogger`：
  * 仍暴露 `log(_:_: )`、`flush()` API。
  * 內部將事件存入 `[ (String, [String:String]) ]` buffer。
  * `flush()` 中呼叫 `CloudKitLogger.shared.save(...)` 逐筆寫入。
* 參數命名：
  * 既有變數 `telemetryParams`、`deltaScoreTele` 續用，不影響 CloudKit schema（本質上只是 `[String:String]`）。
  * 若需新增欄位，直接對 `telemetryParams` 新增 key。

## 4. 維護指引

1. **新增事件**：
   ```swift
   TelemetryLogger.shared.log("your_event", [
       "foo": "bar",
       // … more fields …
   ])
   ```
   不必理會是 Telemetry 或 CloudKit——交由 `TelemetryLogger` 處理。
2. **確保送出**：
   * App 生命週期結束前或 Session 結束後呼叫 `TelemetryLogger.shared.flush()`。
3. **改動雲端管道**：
   * 僅需修改 `TelemetryLogger.swift` 內部（或替換 `CloudKitLogger`）。呼叫端無需變更。
4. **命名整潔（選項）**：
   * 若日後要統一移除 "telemetry" 字首，建議批次重構：
     * `telemetryParams` → `eventParams`
     * `deltaScoreTele` → `deltaScore`
   * **切記** 同步更新 **所有** CloudKit 開啟的欄位名稱，並保持 backward-compat 讀取。

## 5. 可能的後續方向

* 加入離線佇列持久化（UserDefaults / CoreData），避免 app crash 遺失 buffer。
* 支援批次 `CKModifyRecordsOperation`，減少多筆寫入開銷。
* 若要重新啟用 TelemetryDeck，只需在 `TelemetryLogger` 的 `flush()` 中切換實作，再決定是否保留 CloudKit 備份。

---

若對本文件有疑問或需更新，請聯絡 `@Michael` 或於 PR 標記 **#telemetry-pipeline**。 