# 項目Scratchpad

## 項目概述
TextCorrection是一個專注於文字自動糾錯功能的macOS應用程式。該應用使用多個依賴庫如Differ、DifferenceKit、HotKey、KeychainAccess和PythonKit來實現功能。

---

## 當前進度
- [x] 任務1: 解決項目無法運行的問題
- [x] 任務2: 調整 cursor rules 設定
- [x] 任務3: 改進 SettingsView UI 界面設計 (Linear App 風格)
- [x] 任務4: 優化其他視圖的 UI 設計
- [x] 任務5: 優化 AppKit 與 SwiftUI 混合開發架構
- [x] 任務6: 整合視窗和特效，移除多餘視窗

---

## 遇到的問題與解決方案

### 問題1: XCode播放執行鍵無法點擊
**狀態**: 已解決
**相關文件**: 項目設定文件
**可能原因**:
1. 沒有選擇正確的scheme或target
2. 項目配置問題
3. 缺少必要的依賴或依賴版本不匹配
4. 編譯錯誤
5. 沒有配置正確的simulator或device
6. 項目需要先build才能run

**檢查結果**:
- 項目中已存在名為`TextCorrection.xcscheme_^#shared#^_`的scheme，記錄在xcschememanagement.plist中
- 但找不到xcshareddata目錄，這可能意味著共享scheme文件缺失或損壞
- 項目中有三個主要target：TextCorrection (主應用)、TextCorrectionTests、TextCorrectionUITests

**解決方案**:
- 創建新的TextCorrection scheme：
  - 選擇「Product」>「Scheme」>「New Scheme...」
  - 從列表中選擇「TextCorrection」作為Target
  - 給scheme命名為「TextCorrection」
  - 確保勾選「Shared」選項
- 成功創建scheme後項目可以正常運行

### 問題2: 需要調整 cursor rules
**狀態**: 已解決
**相關文件**: `cursor-rules/text-correction-project.mdc`
**目標**: 優化自動糾錯的規則配置和改進開發架構規範
**解決方案**:
- 添加更詳細的混合架構開發原則:
  - 明確定義AppKit與SwiftUI的職責分工
  - 規範組件間通信機制
  - 提供模塊化設計指導
- 添加Linear App風格UI設計指南:
  - 定義了配色方案、字體選擇
  - 優化間距和佈局標準
  - 規範元素設計和動效指南

### 問題3: UI 界面需要改進
**狀態**: 進行中
**相關文件**: 
- `TextCorrection/SettingsView.swift`
- `TextCorrection/PreferencesView.swift`
- 其他UI相關文件
**目標**: 
- 設計更大、更美觀的設定視窗
- 採用 Linear App 風格設計 (簡潔、現代、功能性強)
- 改善整體使用者體驗
**已完成工作**:
- 完全重寫了SettingsView，使用Linear App風格:
  - 視窗尺寸從350x430增加到450x600
  - 引入了分頁式設計
  - 自定義了按鈕、開關和卡片樣式
  - 添加了更多細節和說明文字
  - 改進了佈局和間距
  - 定義了統一的UI常量和顏色
**待處理**:
- 其他視圖的UI改進

### 問題4: AppKit 和 SwiftUI 混合架構優化
**狀態**: 待解決
**相關文件**:
- `TextCorrection/AppDelegate.swift`
- `TextCorrection/TextCorrectionApp.swift`
- 其他架構相關文件
**目標**:
- 確保 AppKit 和 SwiftUI 高效協同工作
- 各自發揮優勢：AppKit處理系統層面功能，SwiftUI負責現代化UI
- 建立清晰的模塊化結構

### 問題5: SettingsView 編譯錯誤
**狀態**: 已解決
**相關文件**: `TextCorrection/SettingsView.swift`
**錯誤信息**:
1. Referencing subscript 'subscript(dynamicMember:)' requires wrapper 'EnvironmentObject<AppState>.Wrapper'
2. Cannot call value of non-function type 'Binding<Subject>'
3. Value of type 'AppState' has no dynamic member 'updateApiKeyStatus' using key path from root type 'AppState'

**問題原因**:
- 在重構UI時，嘗試調用AppState中不存在的方法`updateApiKeyStatus`
- AppState類中缺少該方法導致編譯錯誤

**解決方案**:
- 將`appState.updateApiKeyStatus(true)`替換為直接設置屬性：`appState.isApiKeyValid = true`
- 保持與AppState類的現有API一致

### 問題6: 多線程同時訪問錯誤
**狀態**: 待解決
**相關文件**: `TextCorrection/AppDelegate.swift`
**錯誤信息**:
- Thread 1: Simultaneous accesses to 0x6000014b4e50, but modification requires exclusive access

**問題原因**:
1. 在AppDelegate的setupStateSubscriptions()中對AppState進行了非線程安全的訪問
2. 多個Combine訂閱可能同時修改AppState的屬性
3. 在不同的DispatchQueue中訪問共享狀態沒有適當的同步機制

**解決方案**:
1. **使用序列化訪問**:
   - 所有對AppState的修改都應該在主線程(MainActor)上進行
   - 使用DispatchQueue.main.async確保UI更新在主線程上執行

2. **改進AppState實現**:
   - 將AppState設為符合actor協議的類型
   - 或在AppState中添加同步機制，如使用串行隊列

3. **避免過多的訂閱**:
   - 整合和減少對同一數據的多個訂閱
   - 考慮使用更簡單的單向數據流模式

4. **臨時解決方案**:
   - 在AppDelegate.swift中找到setupStateSubscriptions()方法
   - 將所有sink回調中的狀態修改操作包裹在DispatchQueue.main.async中

### 問題7: 存在多個視窗且特效分散
**狀態**: 已解決
**相關文件**:
- `TextCorrection/AppDelegate.swift`
- `TextCorrection/TextCorrectionView.swift`
- `TextCorrection/TextWindowManager.swift`

**問題原因**:
1. 應用程式同時顯示主視窗和"AI 測豹"視窗，造成用戶體驗混亂
2. 特效功能分散在不同視窗中，沒有統一管理
3. 視窗間的邏輯關係不明確

**解決方案**:
1. **整合視窗**:
   - 移除額外的"AI 測豹"視窗
   - 將所有功能集中到主視窗中
   - 在AppDelegate的showSwiftUITextWindow方法中調整邏輯，使用既有視窗管理器

2. **增強特效**:
   - 將特效整合到主視窗中：
     - 添加流光效果(FlowingGlowView)
     - 添加粒子效果(ParticleEffectView)
     - 增強按鈕和UI元素的視覺效果
   - 所有特效都可以通過AppState中的設置開關來控制

3. **統一文本處理**:
   - 在AppDelegate中添加processText方法，集中處理文本校正邏輯
   - 添加模擬處理進度的功能
   - 使文本校正有動態視覺反饋

4. **改進動畫體驗**:
   - 添加文本顯示/隱藏的平滑過渡動畫
   - 添加複製成功的視覺反饋
   - 根據用戶設定自動控制特效

**核心修改**:
- TextCorrectionView.swift: 增加流光特效、粒子效果和其他視覺元素
- AppDelegate.swift: 修改視窗管理邏輯，不再創建多餘視窗
- 所有特效和UI動畫都受AppState中相關設置控制，尊重用戶偏好

### 問題8: 熱鍵觸發時出現 EXC_BAD_ACCESS 錯誤
**狀態**: 已解決
**相關文件**:
- `TextCorrection/HotKeyManager.swift`
- `TextCorrection/TextCorrectionView.swift`

**問題原因**:
1. 熱鍵觸發時，HotKeyManager 中的資源清理不完整，導致訪問已釋放的記憶體
2. 在 SwiftUI 中使用了已棄用的 onChange 方法 API
3. 熱鍵觸發後的處理流程存在多個路徑，可能導致資源競爭

**解決方案**:
1. **增強 HotKeyManager 的資源清理**:
   - 完善 cleanup 方法，確保所有資源都被正確釋放
   - 添加詳細的日誌記錄，幫助追蹤資源生命週期
   - 確保在 deinit 時正確清理所有資源

2. **統一熱鍵處理流程**:
   - 修改 hotKeyTriggered 方法，優先使用 TextWindowManager 處理文本
   - 修改 processSelectedText 方法，確保使用一致的處理路徑
   - 添加錯誤處理和備選方案

3. **更新 SwiftUI API**:
   - 更新 TextCorrectionView 中的 onChange 方法，適配 macOS 14.0 的新 API 格式
   - 移除舊的參數格式 `{ oldValue, newValue in }` 改為 `{ newValue in }`

**核心修改**:
- HotKeyManager.swift: 增強 cleanup 方法，統一熱鍵處理流程
- TextCorrectionView.swift: 更新 onChange 方法 API
- 添加更多錯誤處理和日誌記錄，幫助診斷問題

### 問題9: 熱鍵觸發不直接開始文本比較
**狀態**: 已解決
**相關文件**:
- `TextCorrection/HotKeyManager.swift`
- `TextCorrection/AppDelegate.swift`
- `TextCorrection/PasteboardManager.swift`

**問題原因**:
1. 熱鍵觸發後顯示懸浮按鈕，而不是直接進行文本校正
2. 多個代碼路徑導致行為不一致
3. 剪貼板監控系統檢測到熱鍵觸發的複製操作，仍然顯示浮動按鈕

**解決方案**:
1. **統一熱鍵處理流程**:
   - 添加 `directlyProcessHotkeySelection` 專用方法處理熱鍵觸發
   - 修改 `processSelectedText` 和 `hotKeyTriggered` 方法使用新方法
   - 確保熱鍵觸發後直接開始文本比較處理

2. **區分正常剪貼板變更和熱鍵觸發**:
   - 在熱鍵觸發時發送通知 `HotkeyTriggered`
   - PasteboardManager 添加觀察者接收通知
   - 當變更由熱鍵觸發時，不顯示浮動按鈕

3. **簡化處理流程**:
   - 直接獲取剪貼板文本
   - 顯示文本窗口
   - 立即開始處理文本比較
   - 不再顯示懸浮按鈕

**核心修改**:
- `AppDelegate.swift`: 添加 `directlyProcessHotkeySelection` 方法
- `HotKeyManager.swift`: 修改熱鍵處理流程，使用新方法，並發送通知
- `PasteboardManager.swift`: 添加熱鍵觸發通知監聽，以區分正常剪貼板變更和熱鍵觸發

### 問題7: SettingsView.swift 中的編譯錯誤
**狀態**: 已解決
**相關文件**: `TextCorrection/SettingsView.swift`
**錯誤訊息**: "Extraneous '}' at top level" (多餘的大括號)
**可能原因**:
1. 代碼結構中大括號嵌套不正確
2. 文件末尾有多餘的大括號

**解決方案**:
- 檢查文件結構，發現在 `#Preview` 區塊後有一個多餘的大括號
- 刪除多餘的大括號，確保文件結構正確
- 確認 `SettingsView` 結構和 `#Preview` 區塊都有正確的閉合大括號

**學習經驗**:
- 在進行大型重構或添加新功能時，要特別注意代碼的結構和大括號的嵌套
- 使用代碼編輯器的自動縮進和括號匹配功能可以幫助避免這類問題
- 定期編譯項目可以及早發現和解決語法錯誤

### 問題10: 熱鍵觸發時 AppDelegate 不存在
**狀態**: 已解決
**相關文件**: 
- `TextCorrection/HotKeyManager.swift`
- `TextCorrection/TextCorrectionApp.swift`
- `TextCorrection/AppKitBridge.swift`

**問題現象**:
```
[熱鍵觸發] 已發送HotkeyTriggered通知
模擬 Command+C 複製操作
[熱鍵觸發] 已執行模擬複製操作
[熱鍵觸發] 等待剪貼板更新
[熱鍵觸發] 從剪貼板獲取到文本，長度: 66
[熱鍵觸發] AppDelegate不存在，無法處理文本
```

**問題原因**:
1. 在 SwiftUI 應用程序中，AppDelegate 的引用在某些情況下未被正確持有或未正確傳遞
2. HotKeyManager 使用了弱引用（weak）持有 AppDelegate，這可能導致 AppDelegate 被釋放
3. AppDelegate 在 SwiftUI 生命週期中可能在某些點被釋放或替換
4. AppKitBridge 沒有被正確設置 AppDelegate 引用

**解決方案**:
1. **強化 AppDelegate 引用鏈**:
   - 在 TextCorrectionApp 初始化時顯式設置 AppKitBridge 的 AppDelegate 引用
   - 在 TextCorrectionApp 視圖出現時再次確認 AppKitBridge 已獲取 AppDelegate 引用

2. **改進 HotKeyManager 的容錯機制**:
   - 當無法從實例變量獲取 AppDelegate 時，嘗試從 AppKitBridge 獲取
   - 當兩種方式都無法獲取 AppDelegate 時，直接使用 AppKitBridge 來顯示文本窗口
   - 添加更詳細的日誌記錄，幫助追蹤 AppDelegate 引用狀態

3. **使用多層級回退機制**:
   - 主要方式: 使用 HotKeyManager 持有的 AppDelegate 引用
   - 次要方式: 使用 AppKitBridge 中的 AppDelegate 引用
   - 最終回退: 直接使用 AppKitBridge 的 showTextCorrectionWindow 方法

**學習經驗**:
- SwiftUI 和 AppKit 混合使用時，需要特別注意對象的生命週期和引用關係
- 使用 weak 引用時應考慮對象可能被釋放的情況，並提供合適的回退機制
- 在多架構混合開發中，建立一個穩固的橋接層（如 AppKitBridge）非常重要
- 詳細的日誌記錄對於診斷和解決複雜的生命週期和引用問題至關重要

### 問題11: 熱鍵觸發文本比較後文字消失
**狀態**: 已解決
**相關文件**: 
- `TextCorrection/AppDelegate.swift`
- `TextCorrection/HotKeyManager.swift`
- `TextCorrection/CORE_FUNCTIONS.md`

**問題現象**:
```
檢測到熱鍵觸發的剪貼板變化，不顯示浮動按鈕
API請求成功，開始處理回應
流式回應處理完成，總字符數: 54
文本處理狀態更新: false
收到新的原始文本，長度: 44字符
文本已更新：原始字符數 44，校正後字符數 46，變更詞數 21
顯示文本差異窗口
文本處理完成，用時: 1.09秒，變更詞數: 21
隱藏浮動按鈕
通知：窗口狀態變化 - floatingButton: false
[處理文本] 進度達到100%，準備調用completeTextProcessing
完成文本處理
[處理文本] 已生成修正文本，長度: 44
[處理文本] 在主線程上更新最終狀態
文本處理狀態更新: false
收到新的原始文本，長度: 44字符
文本處理耗時: 763829542.63秒
[處理文本] 開始更新文本視圖，顯示差異
[處理文本] 文本視圖和窗口大小已更新
```

**問題原因**:
1. 熱鍵觸發路徑與懸浮按鈕觸發路徑使用了不同的文本處理方法
2. 熱鍵觸發使用 `processText()` 方法，而懸浮按鈕使用 `rewriteText()` 方法
3. 這兩種不同的處理方法在文本比較階段有不同的實現，導致顯示結果不一致
4. 此外，處理時間計算異常（顯示為 763829542.63 秒）表明時間計算邏輯有問題

**解決方案**:
1. **統一處理邏輯**:
   - 修改 `AppDelegate.directlyProcessHotkeySelection()` 方法，使其使用與懸浮按鈕相同的 `rewriteText()` 方法處理文本
   - 替換原有的 `processText(text)` 調用為 `rewriteText()`

2. **記錄核心功能邏輯**:
   - 創建 `CORE_FUNCTIONS.md` 文件，詳細記錄應用的核心功能和處理邏輯
   - 記錄文本比較功能的兩種觸發路徑（熱鍵和懸浮按鈕）及其處理流程
   - 記錄文本差異比較算法和關鍵方法
   - 記錄常見問題和解決方案

**學習經驗**:
- 在多路徑觸發相同功能時，應確保使用相同的處理邏輯以避免不一致
- 應建立並維護核心功能文檔，以便團隊成員理解系統工作原理
- 時間計算應在處理開始時重置計時器，並在處理結束時立即計算，避免使用過時的時間戳

---

## 已完成功能
- [x] 創建項目Scheme解決運行問題
- [x] 更新開發規範和cursor rules
- [x] 重新設計SettingsView:
  - 相關文件: `TextCorrection/SettingsView.swift`
  - 設計結果: 分頁式界面、Linear App風格、更大視窗尺寸
- [x] 修復SettingsView編譯錯誤:
  - 相關文件: `TextCorrection/SettingsView.swift`
  - 修復結果: 解決了AppState方法調用問題
- [x] 整合視窗和特效:
  - 相關文件: `TextCorrection/AppDelegate.swift`, `TextCorrection/TextCorrectionView.swift`
  - 設計結果: 單一視窗體驗，統一的特效系統，更合理的UI流程
- [x] 修復熱鍵觸發時的 EXC_BAD_ACCESS 錯誤:
  - 相關文件: `TextCorrection/HotKeyManager.swift`, `TextCorrection/TextCorrectionView.swift`
  - 修復結果: 增強資源清理，統一處理流程，更新 API
- [x] 修復熱鍵觸發不直接開始文本比較的問題:
  - 相關文件: `TextCorrection/HotKeyManager.swift`, `TextCorrection/AppDelegate.swift`
  - 修復結果: 熱鍵觸發後直接開始文本比較處理，不再顯示懸浮按鈕

---

## 技術決策和討論結論

### 決策1: 採用 AppKit 和 SwiftUI 混合架構
**背景**: 項目需要兼顧系統層面功能與現代化UI
**討論**: AppKit能更好地處理系統層面功能如剪貼板監控、熱鍵等，而SwiftUI提供更現代化和易於開發的UI構建方式
**結論**: 使用混合架構，讓兩者各自發揮優勢
**日期**: 2024-06-20

### 決策2: UI設計風格參考 Linear App
**背景**: 需要更美觀、專業的用戶界面
**討論**: Linear App擁有簡潔、現代的UI設計，功能性強而不繁瑣
**結論**: 採用類似Linear的設計語言，包括配色、間距、動效等
**日期**: 2024-06-20

### 決策3: 引入分頁式設定界面
**背景**: 原設定界面功能雜亂、難以尋找特定選項
**討論**: 分頁式設計可以組織相關設定，提高用戶體驗
**結論**: 設計包含「一般設定」「API設定」「進階設定」三個頁面的界面
**日期**: 2024-06-20

### 決策4: 狀態管理優化
**背景**: 項目使用全局AppState進行狀態管理，但缺乏線程安全考慮
**討論**: 隨著項目複雜度增加，並發訪問問題逐漸顯現，需要改進狀態管理策略
**結論**: 實施更嚴格的線程安全措施，考慮採用actor模型或其他多線程安全的模式
**日期**: 2024-06-20

### 決策5: 整合視窗和特效
**背景**: 應用程式同時顯示多個視窗，造成體驗不佳
**討論**: 多視窗設計增加了複雜性，分散了用戶注意力，並導致特效和功能分散
**結論**: 將所有功能集中在主視窗中，提供統一的體驗，並按需顯示特效
**日期**: 2024-06-21

---

## 下一步計劃
1. 修復多線程同時訪問錯誤，確保AppState的線程安全性
2. 進一步優化特效性能，確保在低性能設備上也有良好體驗
3. 添加更多自定義選項，讓用戶可以精確控制特效的強度和風格
4. 實現真實的API校正功能，替換目前的模擬實現
5. 增加主題支持，允許用戶在深色和淺色模式間切換
6. 添加單元測試確保UI組件正常工作

---

## 備註
* 項目使用Swift Package Manager管理依賴
* 依賴庫版本：
  - Differ 1.4.6
  - DifferenceKit 1.3.0
  - HotKey main (a3cf605)
  - KeychainAccess master (e0c7..)
  - PythonKit master (6fee761)
* Linear App UI風格參考: https://linear.app
* AppKit與SwiftUI混合開發參考資料可查閱Apple官方文檔
* UI元素尺寸統一為按8pt間距系統設計
* 在進行UI改進時需注意與現有的AppState類保持API一致性
* 注意多線程安全：任何對共享狀態的修改都應該考慮同步機制

---

最後更新時間: 2024-06-20 