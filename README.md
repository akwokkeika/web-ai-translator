# AI 漫畫翻譯

內建瀏覽器截圖，經 Gemini、OpenAI 或本機 Ollama 翻譯後把譯文疊回對話框。目前先做 Android APK。

## 建置

需要本機已安裝 Flutter，以及 Android SDK。

```bat
flutter pub get
flutter build apk --release
```

APK 輸出在 `build/app/outputs/flutter-apk/app-release.apk`。

## 使用

1. 安裝 APK 後打開 App
2. 右上選單 → 模型設定，選擇 Gemini、OpenAI 或 Ollama 並填入對應資料
3. 在網址列進入漫畫網站
4. 畫面出現漫畫後按「翻譯本頁」
5. 點氣泡可改譯文

## API

- **Gemini**：填 Google API Key 與模型 ID，預設請求 `generativelanguage.googleapis.com`
- **OpenAI**：填 OpenAI API Key 與支援看圖的模型（例如 `gpt-4o`）。Endpoint 可改成相容服務
- **Ollama**：本機預設 `http://127.0.0.1:11434`。Android 模擬器用 `10.0.2.2`；實體手機請填電腦區網 IP，並讓 Ollama 監聽 `0.0.0.0`
