# 瀏覽器翻譯 / Browser Translator

倉庫 / Repository: https://github.com/akwokkeika/web-ai-translator

內建瀏覽器截圖，經 Gemini、OpenAI 或本機 Ollama 辨識畫面上的文字並翻譯後，把譯文疊回網頁。目前先做 Android APK。

An Android app with a built-in browser. It screenshots the current page, asks Gemini, OpenAI, or local Ollama to locate and translate on-screen text, then overlays the translation on the page.

**本專案全部由 [Cursor](https://cursor.com) AI 撰寫。**  
**This entire project was created by [Cursor](https://cursor.com) AI.**

**免責聲明 / Disclaimer：** 本項目**只供學習與研究程式設計之用**，不提供任何擔保，作者不對使用後果負責。使用者須自行遵守著作權、網站條款與各地法律。  
This project is **for learning and programming study only**. It is provided with no warranty. The authors are not responsible for how it is used. You must comply with copyright law, website terms, and local law.

授權 / License: [GNU General Public License v3.0 or later](LICENSE)

---

## 中文

### 這是什麼

在 App 裡打開網頁，等畫面載入後按「翻譯本頁」。程式會：

1. 截取目前 WebView 畫面
2. 把圖片送到你選擇的視覺模型
3. 解析模型回傳的文字區塊座標與譯文
4. 把譯文疊在網頁上，並跟著頁面捲動
5. 依網址自動保存，下次打開同一頁會還原 overlay

也可手動畫框、改譯文、對齊位置，以及把書籤與 overlay 匯出／匯入。

### 免責聲明

本項目**只供學習與研究程式設計之用**，用來示範：內建瀏覽器、畫面截圖、視覺模型 API，以及把譯文疊回網頁。

- **不是**官方翻譯器，也**不是**任何網站的授權閱讀或發行工具。
- 網頁上的文字、圖像與其他內容，著作權仍屬原作者與網站。本程式不授予你複製、翻譯、散布這些內容的權利。
- 「學習用途」**不能**自動構成合理使用／公平處理，也**不能**免除侵權責任。
- 截圖會送到你設定的 Gemini、OpenAI 或本機 Ollama。雲端供應商如何處理圖片，以他們的條款為準。
- 作者、貢獻者與 Cursor AI **不對**任何使用方式、資料外洩、帳號停權、民事或刑事後果負責。本軟體依 GPL **現況提供、沒有擔保**。
- 使用本程式即表示你自行承擔法律風險，並承諾只在你有權檢視的內容上、且符合當地法律的前提下操作。

### Cursor AI 聲明

本倉庫的應用程式碼、架構、UI、翻譯管線與說明文件，皆由 Cursor AI 在對話中建立與修改。人工只負責提出需求、驗證結果與發布。若你 fork 或引用本專案，請保留本聲明、免責聲明與 GPL 授權。

### 主要功能

- 內建瀏覽器：網址列、前進／後退、重新整理、桌面／手機 User-Agent、書籤
- 多模型後端：Google Gemini、OpenAI（及相容接口）、本機 Ollama
- 網頁 overlay：譯文疊在文字區塊上，捲動時跟著走
- 手動編輯：拖曳新增框、調大小、改譯文、微調整頁對齊、顯示原文／譯文
- 依網址保存 overlay；書籤與 overlay 可 JSON 匯出／匯入（合併或取代）
- 目標語言：繁體中文、简体中文、English、한국어、日本語、Tiếng Việt
- 譯文字級：先用最小字級換行，框太小才再縮小
- API 金鑰只存在本機 `SharedPreferences`，不會上傳到本專案伺服器

### 運作流程

```
網頁 (InAppWebView)
        │
        ├─ JS 注入：蒐集捲動／視窗尺寸 → Flutter
        │
        ▼
   按「翻譯本頁」
        │
        ├─ WebView JPEG 截圖
        ├─ 壓縮／縮寬後上傳（最寬 1400px）
        ├─ 依設定選擇 Gemini / OpenAI / Ollama
        ├─ prompt 要求只回 JSON（原文、譯文、相對座標）
        ├─ 解析文字框，轉成頁面捲動座標
        └─ 與本頁既有 overlay 合併（視窗內的 AI 框會被新結果取代；手動框會保留）
        │
        ▼
   PageOverlayLayer 疊在網頁上並寫入 OverlayStore
```

座標有兩套：

- **相對截圖比例** `x, y, w, h`（0–1）：模型回傳、截圖結果頁使用
- **頁面座標** `x, w` 仍為相對寬度，`yPx, hPx` 為頁面像素：網頁 overlay 用來對齊捲動

### 專案結構

```
lib/
  main.dart                 啟動、載入設定／書籤／overlay、進入瀏覽器頁
  theme.dart                深色木紋風格主題
  models/
    ai_provider.dart        Gemini / OpenAI / Ollama
    bubble.dart             單次翻譯結果（截圖座標）
    overlay_page.dart       依網址保存的 overlay 頁與文字框
    bookmark.dart           書籤
  screens/
    browser_screen.dart     主畫面：WebView、工具列、翻譯、overlay
    settings_screen.dart    模型、金鑰、endpoint、語言、字級、測試連線
    result_screen.dart      最近一次截圖＋可點選編輯的文字框
    bookmarks_screen.dart   書籤／overlay 列表、匯出匯入
  services/
    settings_store.dart     本機設定
    bookmark_store.dart     書籤持久化
    overlay_store.dart      overlay 持久化與合併
    overlay_coords.dart     URL key、截圖座標轉換、視窗內合併
    page_metrics.dart       WebView 捲動度量與注入腳本
    image_prep.dart         截圖解碼與壓縮
    translate_prompt.dart   翻譯 prompt
    page_translator.dart    翻譯器介面
    translator_factory.dart 依 provider 建立翻譯器
    gemini_translator.dart  Gemini generateContent
    openai_translator.dart  OpenAI chat/completions（含相容服務）
    ollama_translator.dart  Ollama 原生 API，或 /v1 相容接口
    bubble_parser.dart      從模型 JSON 抽出文字框
    api_json.dart           API 回應解析輔助
    text_fit.dart           框內自動換行／縮字
    library_backup.dart     書籤＋overlay JSON
  widgets/
    page_overlay.dart       網頁上的 overlay 層與編輯手勢
    bubble_text.dart        文字框排版
android/                    Flutter Android 宿主（需 INTERNET）
```

### 畫面說明

**瀏覽器（`BrowserScreen`）**  
主畫面。WebView 預設顯示說明首頁。網址列可貼網址；沒有 `http` 且像網域會自動加 `https://`，否則當 Google 搜尋。底部「翻譯本頁」截圖並翻譯。overlay 工具列可開關疊層、進入編輯、顯示原文、上下微調、清除本頁。返回鍵優先走網頁歷史。

**設定（`SettingsScreen`）**  
選擇 API 來源並填模型名稱。可測連線。金鑰可隱藏顯示。OpenAI endpoint 可改成 Groq、LM Studio 等相容服務。Ollama 預設 `http://127.0.0.1:11434`；Android 模擬器常用 `10.0.2.2`；實體手機請填電腦區網 IP，並讓 Ollama 聽 `0.0.0.0`。

**截圖結果（`ResultScreen`）**  
翻譯成功後可從 SnackBar 打開。顯示截圖與文字框，可縮放、改譯文、切換原文／譯文。此頁編輯不會自動寫回網頁 overlay。

**書籤（`BookmarksScreen`）**  
書籤與「只有 overlay、沒有書籤」的頁面會一起列出。點列項開啟網址。可匯出 JSON，匯入時選合併或取代。刪書籤不會刪 overlay，除非另外刪 overlay。

### 翻譯器行為

三者共用 `PageTranslator`：輸入 JPEG 與長寬，輸出文字框列表；另提供 `ping` 測連線。

| 來源 | 預設 endpoint | 注意 |
| --- | --- | --- |
| Gemini | `https://generativelanguage.googleapis.com/v1beta` | 需 API Key 與模型 ID（例如 `gemini-2.5-flash`） |
| OpenAI | `https://api.openai.com/v1` | 需支援看圖的模型（例如 `gpt-4o`） |
| Ollama | `http://127.0.0.1:11434` | 需本機已拉視覺模型（例如 `llava`、`qwen2.5vl`） |

模型必須回 JSON：

```json
{
  "bubbles": [
    {
      "original": "原文",
      "translated": "譯文",
      "x": 0.0,
      "y": 0.0,
      "w": 0.0,
      "h": 0.0,
      "vertical": false
    }
  ]
}
```

`bubbles` 是程式使用的欄位名稱，代表畫面上的文字框。`x,y` 是框左上角相對整張圖的比例。解析時若模型給像素而非 0–1，會依圖寬高換算。

### 建置

需要 Flutter 與 Android SDK。

```bat
flutter pub get
flutter build apk --release
```

APK 在 `build/app/outputs/flutter-apk/app-release.apk`。

除錯安裝：

```bat
flutter run
```

### 使用步驟

1. 安裝 APK 並打開 App
2. 右上選單 → 模型設定，選 Gemini、OpenAI 或 Ollama 並填資料；可先按「測試連線」
3. 在網址列進入網頁，必要時切桌面版
4. 畫面出現後按「翻譯本頁」
5. 譯文會疊在畫面上；點文字框可改譯文
6. 編輯模式：空白處拖曳新增框，選取後拖角落改大小
7. 書籤頁可匯出／匯入書籤與 overlay

### 隱私與限制

- 本項目只供學習，詳見上方〈免責聲明〉。
- 截圖會送到你設定的模型供應商（或本機 Ollama）。請自行遵守網站條款與著作權。
- 目前以 Android 為主；WebView 截圖、捲動對齊在部分網站可能不準。
- 翻譯品質取決於你選的視覺模型；框位不準時可手動調整。
- 本程式按 GPL 提供，**沒有擔保**。

### 授權（GPL-3.0-or-later）

Copyright (C) 2026 akwokkeika

本程式為自由軟體：你可以依自由軟體基金會發布的 GNU 通用公眾授權條款第 3 版，或（由你選擇）任何更新版本，重散布及／或修改本程式。

本程式的散布是希望它有用，但**沒有任何擔保**；甚至沒有適售性或特定用途適用性的默示擔保。詳見 GNU 通用公眾授權。

你應該已隨本程式收到一份 GNU 通用公眾授權副本；若沒有，請見 <https://www.gnu.org/licenses/>。

完整條文見倉庫根目錄 [`LICENSE`](LICENSE)。

重點（非正式摘要，以 LICENSE 為準）：

- 可以為任何目的使用、修改、散布
- 散布時必須附上原始碼（或書面的取得方式）與本授權
- 修改版也必須用 GPL 發布（copyleft）
- 不可把本程式併入專有封閉軟體後再散布

---

## English

### What this is

Open a web page inside the app, wait for it to load, then tap **Translate this page**. The app will:

1. Capture the current WebView screenshot
2. Send the image to the vision model you configured
3. Parse text-box coordinates and translations from the model JSON
4. Overlay the text on the page, tracking scroll
5. Save overlays per URL so they restore the next time you open the same page

You can also draw boxes by hand, edit translations, nudge alignment, and export/import bookmarks plus overlays.

### Disclaimer

This project is **for learning and programming study only**. It demonstrates an in-app browser, screenshots, vision-model APIs, and overlaying translations on a web page.

- It is **not** an official translator, and **not** a licensed reader or distribution tool for any website.
- Copyright in page text, images, and other site content remains with the original authors and sites. This program does **not** give you the right to copy, translate, or distribute that content.
- “Educational use” does **not** automatically qualify as fair use / fair dealing, and it does **not** waive infringement liability.
- Screenshots are sent to the Gemini, OpenAI, or local Ollama endpoint you configure. Cloud providers handle images under their own terms.
- The authors, contributors, and Cursor AI are **not responsible** for any use of this software, data leakage, account suspension, or civil or criminal consequences. The software is provided under the GPL **as is, with no warranty**.
- By using this program you accept the legal risk yourself, and you agree to operate it only on content you are allowed to view and only where local law permits.

### Cursor AI statement

All application code, architecture, UI, translation pipeline, and this documentation in this repository were created and revised by Cursor AI in chat. A human provided requirements, verified results, and published the project. If you fork or reuse this project, please keep this statement, the disclaimer, and the GPL license.

### Features

- Built-in browser: address bar, back/forward, reload, desktop/mobile user agent, bookmarks
- Multiple backends: Google Gemini, OpenAI (and compatible endpoints), local Ollama
- Page overlay: translations sit on detected text regions and follow scroll
- Manual edit: drag to add boxes, resize, edit text, nudge the whole overlay, toggle original/translated
- Per-URL overlay persistence; JSON export/import of bookmarks and overlays (merge or replace)
- Target languages: Traditional Chinese, Simplified Chinese, English, Korean, Japanese, Vietnamese
- Font fitting: wrap at the configured minimum size first; shrink only if the box is still too small
- API keys stay in on-device `SharedPreferences`; this project has no backend that collects them

### How it works

```
Web page (InAppWebView)
        │
        ├─ Injected JS: scroll/viewport metrics → Flutter
        │
        ▼
   Tap "Translate this page"
        │
        ├─ JPEG screenshot from the WebView
        ├─ Resize/compress for upload (max width 1400px)
        ├─ Call Gemini / OpenAI / Ollama from settings
        ├─ Prompt asks for JSON only (original, translation, relative boxes)
        ├─ Parse text boxes and map them onto page-scroll coordinates
        └─ Merge with the current overlay (AI boxes in view are replaced; manual boxes are kept)
        │
        ▼
   PageOverlayLayer draws on the page; OverlayStore writes to disk
```

There are two coordinate systems:

- **Screenshot ratios** `x, y, w, h` (0–1): model output and the screenshot result screen
- **Page coordinates**: `x, w` stay width ratios; `yPx, hPx` are page pixels so the overlay can follow scroll

### Project layout

```
lib/
  main.dart                 Startup, load stores, open the browser screen
  theme.dart                Dark wood-stamp Material theme
  models/
    ai_provider.dart        Gemini / OpenAI / Ollama
    bubble.dart             One translation pass (screenshot coords)
    overlay_page.dart       Saved overlay page and text boxes
    bookmark.dart           Bookmark
  screens/
    browser_screen.dart     Main UI: WebView, chrome, translate, overlay
    settings_screen.dart    Model, keys, endpoints, language, font, ping
    result_screen.dart      Last screenshot with tappable text boxes
    bookmarks_screen.dart   Library list, export/import
  services/
    settings_store.dart     Local settings
    bookmark_store.dart     Bookmark persistence
    overlay_store.dart      Overlay persistence and merge
    overlay_coords.dart     URL keys, coord mapping, in-view merge
    page_metrics.dart       WebView metrics and injected script
    image_prep.dart         Screenshot decode and JPEG prep
    translate_prompt.dart   Translation prompt
    page_translator.dart    Translator interface
    translator_factory.dart Provider factory
    gemini_translator.dart  Gemini generateContent
    openai_translator.dart  OpenAI chat/completions (compat endpoints too)
    ollama_translator.dart  Native Ollama API, or /v1 compatible mode
    bubble_parser.dart      Extract text boxes from model JSON
    api_json.dart           Response parsing helpers
    text_fit.dart           Wrap-then-shrink font fitting
    library_backup.dart     Combined bookmark + overlay JSON
  widgets/
    page_overlay.dart       Overlay layer and edit gestures
    bubble_text.dart        Text-box typography
android/                    Flutter Android host (INTERNET permission)
```

### Screens

**Browser (`BrowserScreen`)**  
Main screen. The WebView starts on an in-app help page. Paste a URL; missing `http` plus a dotted host becomes `https://`, otherwise it becomes a Google search. **Translate this page** captures and translates. The overlay toolbar toggles the layer, edit mode, original text, vertical nudge, and clear. The system back button prefers WebView history.

**Settings (`SettingsScreen`)**  
Pick a provider and fill in the model name. Test connection is available. Keys can be shown/hidden. The OpenAI endpoint can point at compatible servers such as Groq or LM Studio. Ollama defaults to `http://127.0.0.1:11434`. Use `10.0.2.2` on the Android emulator. On a physical phone, use your PC's LAN IP and bind Ollama to `0.0.0.0`.

**Result (`ResultScreen`)**  
Opened from the success snackbar. Shows the screenshot and text boxes with pinch-zoom, edit, and original/translated toggle. Edits here are not written back to the page overlay.

**Bookmarks (`BookmarksScreen`)**  
Lists bookmarks together with overlay-only pages. Tap a row to open the URL. Export writes a JSON file. Import can merge or replace. Deleting a bookmark keeps the overlay unless you delete the overlay separately.

### Translators

All three implement `PageTranslator`: JPEG plus dimensions in, text-box list out, plus `ping`.

| Provider | Default endpoint | Notes |
| --- | --- | --- |
| Gemini | `https://generativelanguage.googleapis.com/v1beta` | Needs an API key and model ID (e.g. `gemini-2.5-flash`) |
| OpenAI | `https://api.openai.com/v1` | Needs a vision-capable model (e.g. `gpt-4o`) |
| Ollama | `http://127.0.0.1:11434` | Needs a local vision model (e.g. `llava`, `qwen2.5vl`) |

Expected JSON:

```json
{
  "bubbles": [
    {
      "original": "source text",
      "translated": "translation",
      "x": 0.0,
      "y": 0.0,
      "w": 0.0,
      "h": 0.0,
      "vertical": false
    }
  ]
}
```

`bubbles` is the field name used in code for on-screen text boxes. `x,y` is the top-left of the box as a fraction of the full image. If the model returns pixels instead of 0–1 ratios, the parser converts using image width and height.

### Build

Flutter and the Android SDK are required.

```bat
flutter pub get
flutter build apk --release
```

The APK is written to `build/app/outputs/flutter-apk/app-release.apk`.

Debug run:

```bat
flutter run
```

### Usage

1. Install the APK and open the app
2. Menu → Model settings: choose Gemini, OpenAI, or Ollama and fill in the fields; optionally tap **Test connection**
3. Open a web page in the address bar; switch to desktop mode if needed
4. When the page is visible, tap **Translate this page**
5. Translations overlay the page; tap a text box to edit
6. Edit mode: drag on empty space to add a box; drag a corner to resize
7. Use the bookmarks screen to export/import bookmarks and overlays

### Privacy and limits

- This project is for learning only; see the Disclaimer above.
- Screenshots are sent to the model provider you configure (or to local Ollama). Follow the website’s terms and copyright law.
- Android is the current target. WebView screenshots and scroll alignment can drift on some sites.
- Quality depends on the vision model. Adjust boxes by hand when detection is off.
- The program is provided under the GPL **with no warranty**.

### License (GPL-3.0-or-later)

Copyright (C) 2026 akwokkeika

This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful, but **WITHOUT ANY WARRANTY**; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with this program. If not, see <https://www.gnu.org/licenses/>.

The full license text is in [`LICENSE`](LICENSE).

Informal summary (the [`LICENSE`](LICENSE) file controls):

- Use, modify, and share for any purpose
- When you distribute, include the source (or a written offer) and this license
- Modified versions must also be released under the GPL (copyleft)
- You may not incorporate this program into proprietary closed-source software and redistribute it
