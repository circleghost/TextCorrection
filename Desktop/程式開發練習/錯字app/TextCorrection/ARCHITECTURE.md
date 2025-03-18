# TextCorrection 應用架構設計

## 架構概述

TextCorrection 是一個混合架構的 macOS 應用程式，同時利用 AppKit 和 SwiftUI 的優勢。AppKit 負責系統級功能（如剪貼板監控、熱鍵設置），而 SwiftUI 則用於現代化的使用者界面設計。

這種混合架構使應用程式能夠:
1. 使用 AppKit 訪問底層系統功能
2. 利用 SwiftUI 實現易於開發和維護的現代 UI
3. 兩者之間通過橋接層進行通信

## 主要模組及其關係

```
+-------------------+      +-------------------+      +-------------------+
|                   |      |                   |      |                   |
|   AppDelegate     |<---->|   AppKitBridge    |<---->|  SwiftUI Views    |
|   (AppKit)        |      |  (Bridge Layer)   |      |                   |
|                   |      |                   |      |                   |
+-------------------+      +-------------------+      +-------------------+
        ^                          ^                         ^
        |                          |                         |
        v                          v                         v
+-------------------+      +-------------------+      +-------------------+
|                   |      |                   |      |                   |
|   系統功能管理器    |      |    AppState       |      |    UI 組件        |
| (PasteboardManager,|     |  (Shared State)   |      | (TextWindowManager,|
|  HotKeyManager 等) |      |                   |      |  特效視圖等)       |
+-------------------+      +-------------------+      +-------------------+
                                    ^
                                    |
                                    v
                           +-------------------+
                           |                   |
                           |   業務邏輯處理     |
                           | (TextProcessing,  |
                           |  OpenAIService 等)|
                           |                   |
                           +-------------------+
```

### 核心模組說明

1. **AppDelegate (AppKit 核心)**
   - 應用程式的主要控制點
   - 管理應用生命週期
   - 協調各種管理器的工作
   - 處理系統級事件和通知

2. **AppKitBridge (橋接層)**
   - 連接 AppKit 和 SwiftUI 組件
   - 提供 SwiftUI 訪問 AppKit 功能的介面
   - 轉發狀態變更和事件

3. **AppState (共用狀態)**
   - 集中存儲應用狀態
   - 使用 ObservableObject 實現狀態的響應式管理
   - 所有 UI 組件都通過 EnvironmentObject 訪問

4. **系統功能管理器**
   - **PasteboardManager**: 監控剪貼板變化
   - **HotKeyManager**: 處理熱鍵註冊和觸發
   - **StatusItemManager**: 管理狀態欄圖標

5. **文本處理模組**
   - **TextProcessing**: 處理文本比較和差異顯示
   - **OpenAIService**: 與 OpenAI API 通信

6. **UI 組件**
   - **TextWindowManager**: 管理文本顯示窗口
   - **TextCorrectionView**: 主要 SwiftUI 視圖
   - **SettingsView**: 設置界面

## 數據流圖

### 熱鍵觸發文本處理流程

```
用戶按下熱鍵 → HotKeyManager.hotKeyTriggered() → 發送 HotkeyTriggered 通知
                                               ↓
PasteboardManager 收到通知 → 設置 isHotkeyTriggeredChange 標誌
                                               ↓
HotKeyManager.processSelectedText() → AppDelegate.directlyProcessHotkeySelection()
                                               ↓
                             更新 AppState.originalText
                                               ↓
                             顯示文本窗口 (TextWindowManager)
                                               ↓
                             AppDelegate.rewriteText() → 模擬 API 請求處理
                                               ↓
                             TextProcessing.diffStrings() → 比較文本差異
                                               ↓
                             TextWindowManager.updateTextViewWithDiff() → 顯示結果
```

### 浮動按鈕觸發文本處理流程

```
剪貼板內容變化 → PasteboardManager 檢測變化 → 顯示浮動按鈕
                                               ↓
用戶點擊浮動按鈕 → AppDelegate.floatingButtonClicked() → 隱藏浮動按鈕
                                               ↓
                            更新 AppState.originalText
                                               ↓
                            顯示文本窗口 (TextWindowManager)
                                               ↓
                            AppDelegate.rewriteText() → 模擬 API 請求處理
                                               ↓
                            TextProcessing.diffStrings() → 比較文本差異
                                               ↓
                            TextWindowManager.updateTextViewWithDiff() → 顯示結果
```

## 核心類之間的引用關係

- **AppDelegate**
  - 持有: `PasteboardManager`, `HotKeyManager`, `StatusItemManager`, `TextWindowManager`
  - 被引用: `AppKitBridge`, `TextCorrectionApp`
  
- **AppKitBridge**
  - 持有: 對 `AppDelegate` 的弱引用
  - 被引用: 所有 SwiftUI 視圖, `HotKeyManager`

- **AppState**
  - 單例模式，被全局訪問
  - 被引用: 所有 SwiftUI 視圖, `AppDelegate`, `AppKitBridge`

- **HotKeyManager**
  - 持有: 對 `AppDelegate` 的弱引用
  - 被引用: `AppDelegate`

- **TextProcessing**
  - 靜態工具類，不持有其他類的引用
  - 被引用: `AppDelegate`, `TextWindowManager`

## 線程安全與非同步處理

- 所有 UI 更新操作在主線程 (`MainActor`) 上執行
- `Task` 和 `async/await` 用於非阻塞操作
- 使用 `DispatchQueue.main.async` 確保 UI 操作的線程安全
- 關鍵類標記為 `@unchecked Sendable` 以支持跨任務邊界傳遞

## 潛在改進點

1. **強化線程安全**
   - 將 `AppState` 改為符合 `actor` 協議的類型
   - 或添加更完善的同步機制

2. **減少循環引用風險**
   - 進一步審查弱引用的使用
   - 確保生命週期管理更加明確

3. **模組化重構**
   - 更清晰地分離關注點
   - 減少模組間的直接依賴

4. **單向數據流**
   - 考慮採用更嚴格的單向數據流架構
   - 減少狀態管理的複雜性 