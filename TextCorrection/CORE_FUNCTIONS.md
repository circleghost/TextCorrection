# 錯字App核心功能文檔

本文檔記錄了錯字App的核心功能和處理邏輯，以供開發和維護參考。

## 文本比較功能

文本比較是應用的核心功能，用於分析原始文本和校正後文本的差異，並以視覺化方式呈現。

### 觸發路徑

文本比較功能有兩種主要觸發路徑：

1. **熱鍵觸發流程**:
   - 用戶按下設定的熱鍵組合
   - `HotKeyManager.processSelectedText()` 被調用
   - 發送 `HotkeyTriggered` 通知
   - 模擬 Command+C 複製選中文本
   - 從剪貼板獲取文本
   - 調用 `AppDelegate.directlyProcessHotkeySelection()`
   - 顯示文本窗口
   - 調用 `AppDelegate.rewriteText()` 開始文本處理

2. **懸浮按鈕觸發流程**:
   - 用戶複製文本到剪貼板
   - `PasteboardManager` 檢測到剪貼板變化
   - 顯示懸浮按鈕
   - 用戶點擊懸浮按鈕
   - 調用 `AppDelegate.floatingButtonClicked()`
   - 顯示文本窗口
   - 調用 `AppDelegate.rewriteText()` 開始文本處理

> **重要**：這兩種觸發路徑必須使用相同的處理邏輯 (`rewriteText()`)，以確保一致性。使用 `processText()` 會導致比較結果顯示邏輯不一致。

### 文本處理流程

1. **文本獲取**:
   - 從剪貼板獲取文本或從熱鍵觸發獲取文本
   - 將原始文本存儲到 `AppState.originalText` 和 `AppDelegate.originalText`

2. **API處理** (模擬或實際API調用):
   - 啟動流式處理 (`AppDelegate.rewriteText()` 方法)
   - 設置 `AppState.isProcessing = true`
   - 模擬進度更新 (0% 到 100%)
   - 處理原始文本並生成校正文本
   - 完成處理後計算變更詞數

3. **差異比較**:
   - 使用 `TextProcessing.diffStrings()` 獲取初步差異
   - 使用 `TextProcessing.optimizeDiff()` 優化差異以提高可讀性
   - 調用 `TextWindowManager.updateTextViewWithDiff()` 顯示差異

4. **結果顯示**:
   - 將差異轉換為富文本 (NSAttributedString)
   - 相同部分顯示為普通文本
   - 刪除部分顯示為帶刪除線的紅色文本
   - 插入部分顯示為帶綠色背景的綠色文本
   - 更新文本視窗並調整大小以適應內容

5. **完成與清理**:
   - 設置 `AppState.isProcessing = false`
   - 更新處理統計信息 (字符數、變更詞數、處理時間)

## 文本差異比較算法

文本差異比較是基於優化過的Myers差異算法實現的，經過了針對中文文本的特殊優化。

### 關鍵方法：

1. **TextProcessing.preprocessTexts()**:
   ```swift
   // 預處理文本以優化比較效果
   static func preprocessTexts(original: String, rewritten: String) -> (String, String)
   ```

2. **TextProcessing.diffStrings()**:
   ```swift
   // 獲取兩個字符串的差異
   static func diffStrings(_ oldString: String, _ newString: String) -> [DiffChange]
   ```

3. **TextProcessing.optimizeDiff()**:
   ```swift
   // 優化差異以提高可讀性
   static func optimizeDiff(_ diff: [DiffChange]) -> [DiffChange]
   ```

4. **TextWindowManager.updateTextViewWithDiff()**:
   ```swift
   // 使用差異更新文本視圖
   func updateTextViewWithDiff(originalText: String, newText: String, textView: NSTextView)
   ```

### 差異顯示樣式：

- **相同文本**：普通白色文本
- **刪除文本**：帶刪除線的紅色文本
- **插入文本**：帶綠色背景的綠色文本

## 熱鍵功能

熱鍵功能允許用戶使用鍵盤快捷鍵觸發文本校正。

### 熱鍵處理流程：

1. **初始化**：在 `AppDelegate.initializeManagersSafely()` 中初始化 `HotKeyManager`
2. **設置**：在 `HotKeyManager.setupHotKey()` 中根據用戶設置註冊熱鍵
3. **觸發**：當用戶按下熱鍵時，調用 `HotKeyManager.processSelectedText()`
4. **處理**：模擬複製操作，獲取選中文本，然後調用 `AppDelegate.directlyProcessHotkeySelection()`

## 剪貼板監控功能

剪貼板監控功能允許應用檢測用戶複製的文本並顯示懸浮按鈕。

### 剪貼板監控流程：

1. **初始化**：在 `AppDelegate.initializeManagersSafely()` 中初始化 `PasteboardManager`
2. **監控**：使用定時器定期檢查剪貼板變化
3. **處理**：當檢測到剪貼板變化時，顯示懸浮按鈕
4. **觸發**：用戶點擊懸浮按鈕後，調用 `AppDelegate.floatingButtonClicked()`

## 常見問題和解決方案

### 熱鍵觸發文本比較後文字消失

**問題描述**：  
使用熱鍵觸發功能時，在處理完成顯示 "文本視圖和窗口大小已更新" 後，比較的文字會消失。

**原因**：  
熱鍵觸發路徑使用了 `processText()` 方法，而懸浮按鈕使用 `rewriteText()` 方法，兩者內部實現不同。

**解決方案**：  
修改 `AppDelegate.directlyProcessHotkeySelection()` 方法，使其使用與懸浮按鈕相同的 `rewriteText()` 方法處理文本。

```swift
// 修改前
processText(text)

// 修改後
rewriteText()
```

### 處理時間顯示異常

**問題描述**：  
有時文本處理時間顯示為異常大的數值，如 "763829542.63秒"。

**原因**：  
時間計算使用了 `Date().timeIntervalSince(startTime)`，但 `startTime` 沒有正確初始化或更新。

**解決方案**：  
確保在處理開始前重置 `startTime = Date()`，並在處理結束時立即計算時間差。 