String buildTranslatePrompt(String language, int width, int height) {
  return '''
你是專業漫畫翻譯。請分析這張漫畫截圖。
圖片尺寸：$width x $height px。

任務：
1. 找出所有對白氣泡、旁白框中的文字
2. 翻譯成$language
3. 回傳每個文字區塊的位置

只回傳 JSON，格式：
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

座標規則：
- x, y, w, h 是相對整張圖的比例，範圍 0 到 1
- x,y 是框的左上角
- 框要覆蓋整個對話氣泡，寧可稍大不要切字
- 擬聲字、效果字可略過
- 保持角色語氣，不要解釋，只要譯文
''';
}
