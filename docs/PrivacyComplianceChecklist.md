# PowerNap 隱私合規待辦 Checklist

> 依 2025/06/13 盤點結果，為避免 App Store 審核被拒，請依序完成下列項目。

---
## 1. 隱私政策文件 (PrivacyPolicy.md / .html)

### 必改內容
1. **使用 & 診斷資料章節**（新增）
   - 說明收集項目：安裝 ID、裝置型號、OS 版本、Crash 堆疊、session_* 事件。
   - 儲存位置：Apple iCloud CloudKit PublicDB（與 Apple ID 不關聯）。
   - 收集目的：偵錯與演算法優化。
   - 保留期限：24 個月。
   - 使用者權利：設定頁可停用「Share anonymous usage data」。
2. **修正文案**
   - 將「不會將您的**任何**資料上傳」改為「不會上傳 **健康** 資料；僅上傳匿名使用／診斷資料」。
3. **Crash Logs via TestFlight / Store**（新增說明）
   - 若啟用 TestFlight / 'Share With App Developers'，本 App 會接收 Apple 匿名化 Crash 報告。
4. **Data Retention**
   - 補充使用／診斷資料保留最長 2 年。

> 參考段落草稿見文件底部「範例段落」。

---
## 2. Onboarding 前導頁

| 權限 | 說明文字 | 已實作 | 備註 |
|------|----------|--------|------|
| HealthKit | 需要讀取心率、靜息心率與睡眠分析以進行睡眠偵測與喚醒 | ☐ | `requestHealthKitPermissions()` 前顯示 |
| Motion & Fitness (如用) | 用於檢測動作以避免誤判睡眠 | ☐ | CMMotionActivity/Accelerometer |
| 通知 | 用於鬧鐘震動喚醒 | ☐ | `requestNotificationPermissions()` 前 |
| 分享使用資料 (選填) | Toggle：Share anonymous usage & crash data | ☐ | 預設 OFF，決定是否寫入 CloudKit usage 訊號 |

---
## 3. Info.plist 說明字串檢查 ✅
- [x] `NSHealthShareUsageDescription`
- [x] `NSHealthUpdateUsageDescription`
- [x] `NSMotionUsageDescription`（若使用）

---
## 4. App Store Connect → App Privacy 問卷對應
- 資料類型：Health & Fitness / App Usage / Diagnostics
- 目的：App Functionality, Analytics, Product Improvement
- 資料連結：**不連結**使用者
- Tracking：無

---
## 5. Crash 收集方案（擇一）
1. **MetricsKit + CloudKitLogger**（完全 Apple 端）
2. **Sentry Apple SDK**（即時 Stacktrace）

> 若維持 TestFlight / Store Crash 回傳，也需在政策中說明。

---
## 範例段落（可直接複製到 PrivacyPolicy.md）
```markdown
### 使用 & 診斷資料
為了偵測崩潰及評估演算法準確度，PowerNap 會在 **您同意的前提下** 收集「匿名化使用統計」及「崩潰診斷」。

收集資訊包含：
- 隨機安裝 ID（無法回推個人身分）
- 裝置型號、系統版本
- 功能事件代碼（session_start / session_end / session_feedback）
- 崩潰堆疊 (Crash log)

**儲存位置**：Apple iCloud CloudKit 公用資料庫（僅開發者可存取，與個人 Apple ID 不關聯）

**保留期限**：最長 24 個月

**用途**：改善演算法準確度、修復錯誤

**選擇權**：您可於「設定 → PowerNap → 分享使用資料」隨時停用。
```

---
> 完成以上項目後，再次提交 App Store 審核，可降低隱私相關拒件風險。 