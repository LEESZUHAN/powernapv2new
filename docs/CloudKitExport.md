# CloudKit 資料匯出成 CSV – 逐步教學

本文件示範如何將 **iCloud.com.powernap** 容器中的資料批次匯出，轉成 CSV 供 Python/Excel 進一步分析。

---
## 0. 目錄
1. 前置準備
2. 產生管理 Token
3. 單次完整匯出（JSON → CSV）
4. 增量匯出（指定日期區間）
5. Python 讀取範例

---
## 1. 前置準備
| 項目 | 說明 |
|------|------|
| macOS / Linux | 已安裝 Xcode 或 Xcode Command Line Tools （內含 `cktool`） |
| jq             | `brew install jq`  (mac) 或 `sudo apt-get install jq` (ubuntu) |
| Python         | 3.9+，並安裝 pandas：`pip install pandas` |

> **Team ID** 與 **Container ID** 之後的指令請自行替換。

---
## 2. 產生 CloudKit 管理 Token（只需一次）
```bash
xcrun cktool save-token --type management
```
1. 會自動開啟瀏覽器登入 CloudKit Console。
2. 點擊「Generate Token」並複製。
3. 回到終端機貼上後，即完成 Token 儲存。

---
## 3. 單次完整匯出
以下以 `session_end` Record Type 為例，匯出 *Development / PublicDB / _defaultZone* 的所有紀錄。

```bash
# 匯出成 JSON
TEAM_ID="YOUR_TEAM_ID"
CONTAINER="iCloud.com.powernap"

xcrun cktool query-records \
  --team-id "$TEAM_ID" \
  --container-id "$CONTAINER" \
  --zone-name _defaultZone \
  --database-type public \
  --environment development \
  --record-type session_end \
  --output-format json \
  --output-file session_end.json

# 轉成 CSV（挑選常用欄位）
jq -r '
  .records[] | [
    .recordName,
    .fields.userId.value,
    (.fields.timestamp.value | todateiso8601),
    .fields.trend.value,
    .fields.ratio.value,
    .fields.detectSource.value
  ] | @csv
' session_end.json > session_end.csv
```
> 其他 Record Type（`session_start`, `app_launch` …）僅需改 `--record-type` 與輸出檔名即可。

---
## 4. 增量匯出（依時間）
若只想抓 2025-06-01 後的新增紀錄：
```bash
xcrun cktool query-records \
  --team-id "$TEAM_ID" \
  --container-id "$CONTAINER" \
  --zone-name _defaultZone \
  --database-type public \
  --environment production \
  --record-type session_end \
  --filters "timestamp >= 2025-06-01T00:00:00Z" \
  --output-format json \
  --output-file session_end_202506.json
```

---
## 5. Python 讀取範例
```python
import pandas as pd

# 讀取剛才 jq 轉出的 CSV
 df = pd.read_csv('session_end.csv',
                  names=['recordName','userId','timestamp','trend','ratio','detectSource'])

# 把 timestamp 轉 datetime
 df['timestamp'] = pd.to_datetime(df['timestamp'])

# 範例：計算各使用者每日 trend 平均
 df['date'] = df['timestamp'].dt.date
 daily = df.groupby(['userId','date'])['trend'].mean().reset_index()
 print(daily.head())
```

> 後續可用 pandas / numpy / sklearn 執行您提到的收斂分析、ROC 門檻測試等。

---
### 常見問題
1. **Q: 匯出時顯示權限錯誤？**  
   A: 確認已產生管理 Token，且使用的 Apple ID 具備開發者帳號權限。
2. **Q: 要改成 Production 資料庫？**  
   A: 把 `--environment development` 改 `production`，其他參數相同。
3. **Q: jq 行數太長想保留全部欄位？**  
   A: `jq -r '.records[] | @json' file.json > all.jsonl` 之後再用 Python 解析。

---
###### Last update: 2025-06-13 