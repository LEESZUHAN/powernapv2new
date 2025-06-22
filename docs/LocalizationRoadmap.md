# Localization & Release Roadmap

> 目標：支援 zh-Hant（繁中）、en、ja、ko 四語系並持續透過 CI/CD 整合流程自動化打包 / 上傳。

---
## 1. 待辦清單（App 內文案）

- [ ] **字串抽離**
  - 將 `Text("…")` 或 `"…"` 文字改為 `NSLocalizedString` / SwiftUI key。
  - 域：Watch App 全部 `.swift` 檔。
- [ ] **建立 .strings**
  - Base.lproj/Localizable.strings（視 Xcode 自動產生）
  - zh-Hant.lproj/Localizable.strings
  - en.lproj/Localizable.strings
  - ja.lproj/Localizable.strings
  - ko.lproj/Localizable.strings
- [ ] **填入翻譯**（初期可複製 EN 內容）
  - zh-Hant：完整翻譯
  - English：完整翻譯
  - 日文/韓文：MVP 先放英文
- [ ] **Plural / 變數字串**
  - 需要複數時新增 Localizable.stringsdict
- [ ] **Assets 本地化**（若未使用文字圖片可跳過）

## 2. 待辦清單（App Store Connect Metadata）

- [ ] 在 **App 資訊 › 本地化** 新增 English、Japanese、Korean
- [ ] 上傳對應語言的
  - App 名稱
  - Subtitle（副標題）
  - Description
  - Keywords
  - Release notes（可共用英文）
- [ ] 截圖：Apple Watch 3 張即可。若無翻譯差異，可沿用一套。

---
## 3. CI/CD 流程概念

| 階段 | 任務 | 工具 |
|------|------|------|
| **CI (Continuous Integration)** | 1) `git push` 時自動執行 xcodebuild test / lint<br>2) 若 `main` 分支標籤 `v*`，自動產生 `*.ipa` 供 TestFlight | GitHub Actions + `macos-latest` runner + `xcodebuild` / `fastlane gym` |
| **CD (Continuous Delivery)** | 3) `fastlane pilot upload` 將生成的 ipa 上傳至 TestFlight<br>4) （可選）同時呼叫 `cktool` 匯出 CloudKit schema 作為備份 | Fastlane |
| **人工步驟** | 5) 在 ASC 指派 Build、編輯 Metadata、按「Submit for Review」 | App Store Connect UI |

> 小結：CI 部分確保程式編譯與單元測試通過；CD 部分把最新 Build 自動送到 TestFlight，縮短每次翻譯／文字修改後的人工作業。

---
## 4. 建議 Git 流程

1. `main`：穩定、可隨時上架。
2. `feat/locale-ja` / `feat/locale-ko`：語言開發分支。
3. 完成後發 PR → merge `main`。
4. 打 `git tag v1.0.2` → GitHub Action 觸發打包 / 上傳 TestFlight。

---
## 5. 參考指令

```bash
# 產生本地化檔（Xcode 15）
# File ▸ Export Localizations

# fastlane 範例（Fastfile）
lane :beta do
  increment_build_number(xcodeproj: "powernapv2new.xcodeproj")
  build_app(scheme: "powernapv2new", export_method: "app-store")
  upload_to_testflight(skip_waiting_for_build_processing: true)
end
``` 