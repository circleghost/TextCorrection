# TextCorrection 依賴圖譜

本文檔詳細描述 TextCorrection 應用中各個類之間的引用關係、主要職責和提供的關鍵功能。

## 引用關係概覽

```
AppDelegate <───────────── TextCorrectionApp
     │
     ├──────┬─────┬─────┬─────┐
     ▼      ▼     ▼     ▼     ▼
PasteboardManager  StatusItemManager  HotKeyManager  TextWindowManager  OpenAIService
     │                 │              │               │                 │
     └─────────────────┴──────────────┘               │                 │
                │                                     │                 │
                ▼                                     │                 │
            AppKitBridge ◄────────────────────────────┘                 │
                │                                                       │
                ▼                                                       │
            AppState ◄───────────────────────────────────────┐          │
                │                                            │          │
                ▼                                            │          │
 ┌─────────┬────┴────┬────────────┐                          │          │
 ▼         ▼         ▼            ▼                          │          │
TextCorrectionView  SettingsView  FloatingButton  其他SwiftUI視圖        │
                                                            │          │
                       TextProcessing ◄─────────────────────┴──────────┘
```

## 各類職責與功能

### 核心協調類

#### `AppDelegate`
**職責**:
- 作為應用程式的主要控制中心
- 協調各功能模組的工作
- 處理應用生命週期事件

**主要功能**:
- `setupStateSubscriptions()`: 設置與 AppState 的訂閱關係
- `rewriteText()`: 處理文本校正的核心邏輯
- `directlyProcessHotkeySelection()`: 處理熱鍵觸發的文本校正
- `floatingButtonClicked()`: 處理懸浮按鈕點擊事件
- `showTextWindowWithDiff()`: 顯示帶有差異標記的文本窗口

**主要依賴**:
- `PasteboardManager`: 用於監控剪貼板
- `HotKeyManager`: 用於處理熱鍵功能
- `StatusItemManager`: 用於管理狀態欄圖標
- `TextWindowManager`: 用於管理文本顯示窗口
- `OpenAIService`: 用於與 OpenAI API 通信

#### `AppKitBridge`
**職責**:
- 連接 AppKit 和 SwiftUI 組件
- 提供 SwiftUI 訪問 AppKit 功能的介面

**主要功能**:
- `setAppDelegate()`: 設置 AppDelegate 引用
- `showFloatingButton()`: 顯示懸浮按鈕
- `hideFloatingButton()`: 隱藏懸浮按鈕
- `processText()`: 處理文本校正
- `notifyWindowStateChanged()`: 通知窗口狀態變化

**主要依賴**:
- `AppDelegate`: 弱引用，用於調用 AppKit 功能

#### `AppState`
**職責**:
- 集中管理應用狀態
- 提供狀態變更通知

**主要功能**:
- `updateTextInfo()`: 更新文本信息
- `addNotification()`: 添加通知
- `resetProcessingState()`: 重置處理狀態

**特性**:
- 使用 `ObservableObject` 實現響應式狀態管理
- 作為所有 SwiftUI 視圖的環境對象

### 系統功能管理器

#### `PasteboardManager`
**職責**:
- 監控系統剪貼板變化
- 處理剪貼板相關功能

**主要功能**:
- `startObserving()`: 開始監控剪貼板
- `stopObserving()`: 停止監控剪貼板
- `hotkeyTriggered()`: 處理熱鍵觸發事件
- `checkForPasteboardChanges()`: 檢查剪貼板變化

**主要依賴**:
- `AppDelegate`: 弱引用，用於回調

#### `HotKeyManager`
**職責**:
- 管理全局熱鍵
- 處理熱鍵觸發事件

**主要功能**:
- `setupHotKeys()`: 設置熱鍵
- `hotKeyTriggered()`: 處理熱鍵觸發
- `processSelectedText()`: 處理選中的文本
- `registerHotKey()`: 註冊熱鍵

**主要依賴**:
- `AppDelegate`: 弱引用，用於回調
- `AppKitBridge`: 用於獲取 AppDelegate 引用

#### `StatusItemManager`
**職責**:
- 管理狀態欄圖標
- 提供狀態欄菜單功能

**主要功能**:
- `setupStatusItem()`: 設置狀態欄圖標
- `setupMenu()`: 設置狀態欄菜單
- `updateStatusIcon()`: 更新狀態圖標

**主要依賴**:
- `AppDelegate`: 弱引用，用於回調

### UI 管理器

#### `TextWindowManager`
**職責**:
- 管理文本顯示窗口
- 處理文本差異顯示

**主要功能**:
- `showTextWindow()`: 顯示文本窗口
- `updateTextViewWithDiff()`: 更新文本視圖顯示差異
- `resizeWindowToFitContent()`: 調整窗口大小以適應內容

**主要依賴**:
- `AppDelegate`: 弱引用，用於回調
- `TextProcessing`: 用於處理文本差異比較

### 業務邏輯處理

#### `TextProcessing`
**職責**:
- 處理文本比較和差異顯示
- 提供文本處理工具方法

**主要功能**:
- `diffStrings()`: 比較兩個字符串的差異
- `compareTexts()`: 生成帶有差異標記的富文本
- `preprocessTexts()`: 預處理文本以優化比較
- `calculateChangedWords()`: 計算變更的詞數

**特性**:
- 靜態工具類，無實例狀態
- 實現基於 Myers 差異算法的優化版本

#### `OpenAIService`
**職責**:
- 與 OpenAI API 通信
- 處理 API 請求和響應

**主要功能**:
- `validateAPIKey()`: 驗證 API 金鑰
- `rewriteText()`: 請求 API 重寫文本
- `processStreamingResponse()`: 處理流式回應

**主要依賴**:
- 無主要內部依賴，僅依賴系統網絡API

### SwiftUI 視圖

#### `TextCorrectionView`
**職責**:
- 應用的主要 SwiftUI 視圖
- 顯示文本校正結果

**主要功能**:
- 顯示原始和校正後的文本
- 提供複製、設置等操作按鈕
- 顯示處理進度和特效

**主要依賴**:
- `AppState`: 環境對象，獲取狀態
- `AppKitBridge`: 用於調用 AppKit 功能

#### `SettingsView`
**職責**:
- 提供應用設置界面
- 管理用戶偏好

**主要功能**:
- API 設置管理
- 熱鍵配置
- 視覺效果設置

**主要依賴**:
- `AppState`: 環境對象，獲取和設置狀態

#### `FloatingButton`
**職責**:
- 提供懸浮在屏幕上的按鈕
- 觸發文本校正功能

**主要功能**:
- 顯示在剪貼板變化時
- 點擊時觸發文本處理

**主要依賴**:
- `AppState`: 環境對象，獲取狀態
- `AppKitBridge`: 用於調用 AppKit 功能

## 初始化流程

1. `TextCorrectionApp` 創建 `AppDelegate` 實例
2. `AppDelegate.init()` 創建各種管理器:
   - `PasteboardManager`
   - `HotKeyManager`
   - `StatusItemManager`
   - `TextWindowManager`
   - `OpenAIService`
3. `AppDelegate.applicationDidFinishLaunching()` 設置與 `AppState` 的訂閱
4. `TextCorrectionApp` 設置 `AppKitBridge` 的 `AppDelegate` 引用
5. 各 SwiftUI 視圖通過 `@EnvironmentObject` 獲取 `AppState` 引用

## 線程與執行上下文

- `AppDelegate` 方法主要在主線程 (Main Thread) 上執行
- 網絡請求和耗時處理在後台線程執行
- UI 更新統一在主線程上通過 `DispatchQueue.main.async` 或 `@MainActor` 執行
- `TextProcessing` 中的比較算法可以在任何線程上執行 