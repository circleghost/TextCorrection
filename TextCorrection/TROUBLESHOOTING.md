# 錯字app 常見錯誤與解決方案記錄

本文檔記錄了開發過程中遇到的常見錯誤和解決方案，以便日後查閱和避免同樣的問題。

## 目錄

1. [平台相容性問題](#平台相容性問題)
2. [未使用變數警告](#未使用變數警告)
3. [尾隨閉包警告](#尾隨閉包警告)
4. [運行時崩潰問題](#運行時崩潰問題)
5. [信號中斷與記憶體問題](#信號中斷與記憶體問題)

---

## 平台相容性問題

| 錯誤訊息 | 文件位置 | 解決方法 |
|---------|---------|---------|
| `'page(indexDisplayMode:)' is unavailable in macOS` | WelcomeView.swift | 使用條件編譯指令區分不同平台：<br>`#if os(iOS)`<br>`.tabViewStyle(.page(indexDisplayMode: .never))`<br>`#else`<br>`.tabViewStyle(.automatic)`<br>`#endif` |

## 未使用變數警告

| 錯誤訊息 | 文件位置 | 解決方法 |
|---------|---------|---------|
| `Initialization of immutable value 'hotKeyModifiers' was never used` | AppState.swift | 將未使用的變數改為下劃線：<br>`let _ = self.hotKeyModifiers` |
| `Initialization of immutable value 'hotKeyCharacter' was never used` | AppState.swift | 將未使用的變數改為下劃線：<br>`let _ = self.hotKeyCharacter` |
| `Immutable value 'firstChar' was never used` | HotKeyManager.swift | 將未使用的變數改為下劃線：<br>`if keyString.count == 1, let _ = keyString.first {` |
| `Initialization of immutable value 'task' was never used` | StatusItemManager.swift | 將未使用的變數改為下劃線：<br>`let _ = Task<Void, Never>(...) {` |

## 尾隨閉包警告

| 錯誤訊息 | 文件位置 | 解決方法 |
|---------|---------|---------|
| `Trailing closure in this context is confusable with the body of the statement` | OpenAIService.swift | 使用顯式參數形式代替尾隨閉包：<br>`bytes.reduce(into: Data(), { data, byte in ... })` |

## 運行時崩潰問題

| 錯誤訊息 | 文件位置 | 解決方法 |
|---------|---------|---------|
| `"time interval must be greater than 0"` | NotificationManager.swift | 1. 將默認延遲值從 0 改為 0.1<br>2. 增加安全檢查：<br>`let safeDelay = max(0.1, delay)`<br>3. 使用安全值創建觸發器 |

## 信號中斷與記憶體問題

| 錯誤訊息 | 文件位置 | 可能原因與解決方法 |
|---------|---------|-----------------|
| `Thread 53: signal SIGABRT` | AppDelegate.swift | **問題描述**：在文本處理過程中發生崩潰，特別是在 `extractMarkdownBlock` 方法中。<br><br>**可能原因**：<br>1. 字符串處理中的越界問題<br>2. 文本拼接過程中內存分配失敗<br>3. 處理大量文本時的內存管理問題<br>4. 文本格式處理不當，如 Markdown 格式解析錯誤<br><br>**解決方案**：<br>1. 檢查 `AppDelegate.swift` 第 305 行附近的 `rewriteText()` 方法中的 `extractMarkdownBlock` 閉包<br>2. 確保字符串操作時進行適當的邊界檢查<br>3. 對長文本進行分批處理，避免一次性處理過大的文本<br>4. 在文本拼接過程中使用 `StringBuilder` 或類似的高效率字符串構建方法<br>5. 檢查是否有循環引用導致內存無法釋放<br>6. 確保處理 Markdown 格式時有足夠的容錯機制<br>7. 在關鍵代碼段增加 try-catch 機制以防止應用崩潰<br>8. 考慮在錯誤發生時記錄完整狀態以便調試 |

### SIGABRT 崩潰案例分析

根據錯誤堆棧信息，崩潰發生在處理長文本時，涉及以下關鍵變數：

```
newContent: String = "次"
cumulativeResponse: String = "```\n跑步膝蓋痛的常見原因：解析跑步時膝蓋疼痛的成因，如：熱身不足、姿勢不良、場地選擇不當等。 \n正確跑步姿勢的 N 大關鍵技巧：詳細且逐一完整說明正確的跑步姿勢關鍵有哪些，確保跑步時的穩定性與安全性。 \n跑步前的熱身運動：介紹跑前動態暖身的重要性，提升關節靈活度與肌肉彈性，減少受傷風險。 \n選擇適合的跑步場地：提醒避免過硬的水泥地或崎嶇不平的路段，減少關節與膝蓋的衝擊。 \n挑選適合的跑鞋與裝備：解釋跑鞋對於跑步的影響，建議選擇具備支撐性、避震效果佳的專業跑鞋，並根據腳型與跑步習慣進行挑選。 \n掌握跑步時間與距離：建議跑步新手從短距離開始，逐步增加跑量，控制跑步時間，每"
textToProcess: String = "跑步膝蓋痛的常見原因：解析跑步時膝蓋疼痛的成因，如：熱身不足、姿勢不良、場地選擇不當等。\n正確跑步姿勢的N大關鍵技巧：詳細且逐一完整說明正確的跑步姿勢關鍵有哪些，確保跑步時的穩定性與安全性。\n跑步前的熱身運動：介紹跑前動態暖身的重要性，提升關節靈活度與肌肉彈性，減少受傷風險。\n選擇適合的跑步場地：提醒避免過硬的水泥地或崎嶇不平的路段，減少關節與膝蓋的衝擊。\n挑選適合的跑鞋與裝備：解釋跑鞋對於跑步的影響，建議選擇具備支撐性、避震效果佳的專業跑鞋，並根據腳型與跑步習慣進行挑選。\n掌握跑步時間與距離：建議跑步新手從短距離開始，逐步增加跑量，控制跑步時間，每次約30-60分鐘，維持穩定速度，避免過度負荷膝蓋。\n"
```

**分析與修復建議**：

1. **問題特徵**：觀察到 `cumulativeResponse` 字串與 `textToProcess` 內容幾乎相同，但 `cumulativeResponse` 以 "```\n" 開頭並且在末尾被截斷，可能是在處理 Markdown 代碼塊時出錯。

2. **修復方向**：
   - 在 `rewriteText()` 和 `extractMarkdownBlock` 方法中增加異常處理
   - 檢查字串拼接操作，特別是在處理 Markdown 格式時
   - 檢查文本長度限制，確保不會超出處理能力
   - 在處理大型響應時分段處理，而非一次性拼接
   - 改進內存管理，避免大量臨時字串對象

3. **代碼改進示例**：
   ```swift
   // 原始代碼可能類似：
   let extractMarkdownBlock: (String) -> String = { text in
       // 處理 Markdown 格式...
       return formattedText
   }
   
   // 改進後：
   let extractMarkdownBlock: (String) -> String = { text in
       guard !text.isEmpty else { return "" }
       
       // 安全地處理文本長度
       if text.count > 10000 {
           // 分段處理或返回錯誤
           logger.warning("文本過長，可能導致處理問題: \(text.count) 字符")
           // 考慮分批處理
       }
       
       do {
           // 原處理邏輯...
           return formattedText
       } catch {
           logger.error("Markdown 處理錯誤: \(error)")
           return text // 返回原文本作為降級處理
       }
   }
   ```

通過以上改進，可以有效減少此類崩潰問題的發生。

## 最佳實踐建議

1. **平台相容性檢查**：
   - 在使用特定平台 API 時，始終使用條件編譯 `#if os(iOS)` / `#if os(macOS)` 進行區分
   - 查閱文檔確認 API 可用性，特別是 SwiftUI 修飾符

2. **變數使用規範**：
   - 對於僅用於類型檢查或條件判斷的變數，直接使用下劃線 `_` 
   - 當使用 Task 或其他非同步操作時，若不需要引用該任務，使用 `let _ = Task {...}`

3. **尾隨閉包最佳實踐**：
   - 在可能導致混淆的情況下，使用顯式參數形式 `.reduce(into: Data(), { ... })`
   - 在巢狀結構中特別注意尾隨閉包的使用

4. **安全參數值檢查**：
   - 對於特殊的系統 API 調用，檢查參數值的合法範圍
   - 對於時間間隔，確保值始終大於系統要求的最小值（例如 `UNTimeIntervalNotificationTrigger` 需要大於 0）
   - 使用 `max()` 函數確保參數不會低於最小安全閾值

5. **字符串處理安全**：
   - 對長文本進行分批處理
   - 在處理大量文本時監控內存使用情況
   - 使用安全的字符串操作方法，避免索引越界
   - 考慮使用 `NSAttributedString` 等可優化的文本處理類

6. **錯誤處理與日誌記錄**：
   - 在應用程式中加入適當的錯誤捕獲並記錄日誌
   - 使用條件檢查防止潛在的非法參數值
   - 加入適當的異常處理機制，避免崩潰直接影響用戶

遵循這些原則可以幫助避免類似的錯誤，提高代碼的健壯性和跨平台相容性。 