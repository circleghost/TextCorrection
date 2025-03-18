# TextCorrection 狀態管理指南

本文檔詳細說明 TextCorrection 應用中的狀態管理策略，包括 AppState 的完整結構、狀態變更的處理流程以及線程安全策略。

## AppState 結構

AppState 是一個符合 `ObservableObject` 協議的類，作為整個應用的中央狀態存儲。它使用單例模式確保在整個應用程序中只有一個共享實例。

### 主要屬性

```swift
class AppState: ObservableObject {
    static let shared = AppState()
    
    // 文本相關狀態
    @Published var originalText: String = ""
    @Published var correctedText: String = ""
    @Published var changedWordsCount: Int = 0
    
    // 處理狀態
    @Published var isProcessing: Bool = false
    @Published var processingProgress: Double = 0.0
    @Published var lastProcessingTime: TimeInterval = 0.0
    @Published var errorMessage: String = ""
    
    // 窗口狀態
    @Published var isFloatingButtonVisible: Bool = false
    @Published var isTextWindowVisible: Bool = false
    @Published var isSettingsWindowOpen: Bool = false
    
    // 用戶偏好
    @Published var apiKey: String = ""
    @Published var isApiKeyValid: Bool = false
    @Published var isClipboardMonitoringEnabled: Bool = true
    @Published var showVisualEffects: Bool = true
    
    // 通知
    @Published var notifications: [Notification] = []
    
    // 其他狀態
    @Published var hasCopiedText: Bool = false
    @Published var lastCopiedText: String = ""
}
```

### 衍生屬性和計算屬性

```swift
extension AppState {
    var canProcessText: Bool {
        return !originalText.isEmpty && !isProcessing && isApiKeyValid
    }
    
    var hasProcessedText: Bool {
        return !correctedText.isEmpty
    }
    
    var formattedProcessingTime: String {
        return String(format: "%.2f", lastProcessingTime)
    }
}
```

### 狀態分組

AppState 中的狀態可以邏輯上分為以下幾組：

1. **文本狀態** - 與文本內容相關的狀態
   - `originalText`
   - `correctedText`
   - `changedWordsCount`

2. **處理狀態** - 與處理進度和錯誤相關的狀態
   - `isProcessing`
   - `processingProgress`
   - `lastProcessingTime`
   - `errorMessage`

3. **UI 狀態** - 與用戶界面顯示相關的狀態
   - `isFloatingButtonVisible`
   - `isTextWindowVisible`
   - `isSettingsWindowOpen`

4. **用戶偏好** - 與用戶設置相關的狀態
   - `apiKey`
   - `isApiKeyValid`
   - `isClipboardMonitoringEnabled`
   - `showVisualEffects`

5. **通知狀態** - 與用戶通知相關的狀態
   - `notifications`

## 方法和操作

### 狀態更新方法

AppState 提供了以下方法來更新或重置狀態：

```swift
func updateTextInfo(original: String, corrected: String) {
    self.originalText = original
    self.correctedText = corrected
    self.changedWordsCount = TextProcessing.calculateChangedWords(
        original: original,
        rewritten: corrected
    )
}

func resetProcessingState() {
    self.isProcessing = false
    self.processingProgress = 0.0
    self.errorMessage = ""
}

func addNotification(title: String, message: String, type: NotificationType) {
    let newNotification = Notification(
        id: UUID(),
        title: title,
        message: message,
        type: type,
        timestamp: Date()
    )
    
    DispatchQueue.main.async {
        self.notifications.append(newNotification)
        
        // 自動移除舊通知
        if self.notifications.count > 5 {
            self.notifications.removeFirst()
        }
    }
}
```

### 持久化與加載

某些狀態需要在應用程序重啟時保持不變：

```swift
private func loadSavedPreferences() {
    apiKey = KeychainManager.shared.retrieveAPIKey() ?? ""
    isClipboardMonitoringEnabled = UserDefaults.standard.bool(forKey: "isClipboardMonitoringEnabled")
    showVisualEffects = UserDefaults.standard.bool(forKey: "showVisualEffects")
}

func savePreferences() {
    if !apiKey.isEmpty {
        KeychainManager.shared.storeAPIKey(apiKey)
    }
    UserDefaults.standard.set(isClipboardMonitoringEnabled, forKey: "isClipboardMonitoringEnabled")
    UserDefaults.standard.set(showVisualEffects, forKey: "showVisualEffects")
}
```

## 狀態變更流程

### 基本狀態變更流程

1. **SwiftUI 視圖中的直接變更**:
   ```swift
   @EnvironmentObject private var appState: AppState
   
   Button("開始處理") {
       appState.isProcessing = true
   }
   ```

2. **通過方法變更複合狀態**:
   ```swift
   Button("重置") {
       appState.resetProcessingState()
   }
   ```

3. **從 AppKit 層面變更**:
   ```swift
   // 在 AppDelegate 中
   AppState.shared.isFloatingButtonVisible = true
   ```

### 狀態流向圖

```
用戶操作 ─────┬─────> SwiftUI 視圖 ─────> 直接修改 AppState 屬性
              │         │
              │         v
              │     調用 AppState 方法
              │         │
              │         v
              └────> AppKitBridge ─────> AppDelegate ─────> 修改 AppState
                                                             │
                                                             v
                                                      AppState 屬性變更
                                                             │
                                                             v
                                                   通知所有訂閱的觀察者
                                                             │
                                                             v
                                                      UI 自動更新
```

### 常見狀態變更場景

1. **文本處理開始**:
   ```
   用戶點擊處理按鈕 ─> AppState.isProcessing = true
                     AppState.processingProgress = 0.0
                     AppState.errorMessage = ""
   ```

2. **文本處理進度更新**:
   ```
   處理進度更新 ─> AppState.processingProgress = progress
   ```

3. **文本處理完成**:
   ```
   處理完成 ─> AppState.updateTextInfo(original, corrected)
              AppState.isProcessing = false
              AppState.processingProgress = 1.0
              AppState.lastProcessingTime = time
   ```

4. **文本處理錯誤**:
   ```
   處理錯誤 ─> AppState.isProcessing = false
              AppState.errorMessage = errorMessage
              AppState.addNotification(title, message, .error)
   ```

## 線程安全策略

### 當前的線程安全措施

目前 AppState 的線程安全主要依賴以下措施：

1. **使用 `@Published` 屬性**
   - SwiftUI 的 `@Published` 屬性發布者在主線程上發布更新
   - 對 `@Published` 屬性的讀取和寫入應在主線程上進行

2. **主線程封裝**
   ```swift
   func addNotification(title: String, message: String, type: NotificationType) {
       DispatchQueue.main.async {
           self.notifications.append(newNotification)
       }
   }
   ```

3. **AppDelegate 中的非同步處理**
   ```swift
   // 在 AppDelegate 中
   await MainActor.run {
       AppState.shared.isProcessing = false
   }
   ```

### 線程安全問題與解決方案

目前的實現存在一些潛在的線程安全問題：

1. **問題:** 多個線程同時訪問和修改 AppState 屬性
   **徵兆:** `Thread 1: Simultaneous accesses to 0x..., but modification requires exclusive access`
   **解決方案:**
   ```swift
   // 1. 所有修改操作應在主線程執行
   DispatchQueue.main.async {
       self.isProcessing = false
   }
   
   // 2. 使用任務隔離
   await MainActor.run {
       AppState.shared.isProcessing = false
   }
   ```

2. **問題:** 讀取和寫入操作之間的競爭條件
   **徵兆:** 狀態不一致或意外的狀態變化
   **解決方案:** 使用同步隊列或鎖

### 改進方案

建議以下改進來增強線程安全性：

#### 方案 1: 使用 actor 模型

將 AppState 重構為 actor 可以提供類型級別的線程安全保證：

```swift
actor AppStateManager {
    static let shared = AppStateManager()
    
    // 狀態
    var originalText: String = ""
    var correctedText: String = ""
    // ...其他屬性
    
    // 方法
    func updateTextInfo(original: String, corrected: String) {
        self.originalText = original
        self.correctedText = corrected
        // ...
    }
}

// 使用方式
Task {
    await AppStateManager.shared.updateTextInfo(original: text, corrected: correctedText)
}
```

#### 方案 2: 使用串行隊列

將所有狀態變更操作隔離到一個串行隊列中：

```swift
class AppState: ObservableObject {
    static let shared = AppState()
    
    private let stateQueue = DispatchQueue(label: "com.yourcompany.TextCorrection.AppStateQueue")
    
    @Published var originalText: String = ""
    // ...其他屬性
    
    func updateTextInfo(original: String, corrected: String) {
        stateQueue.async {
            DispatchQueue.main.async {
                self.originalText = original
                self.correctedText = corrected
                // ...
            }
        }
    }
}
```

#### 方案 3: 使用讀寫鎖

對於需要頻繁讀取但較少寫入的屬性，可以使用讀寫鎖：

```swift
class AppState: ObservableObject {
    static let shared = AppState()
    
    private let stateLock = NSRecursiveLock()
    
    private var _originalText: String = ""
    
    var originalText: String {
        get {
            stateLock.lock()
            defer { stateLock.unlock() }
            return _originalText
        }
        set {
            stateLock.lock()
            defer { 
                stateLock.unlock() 
                self.objectWillChange.send()
            }
            _originalText = newValue
        }
    }
    
    // ...其他屬性和方法
}
```

## 建議的最佳實踐

1. **統一更新路徑**
   - 所有 AppState 的修改應該統一通過其提供的方法進行
   - 不要直接從不同的地方修改屬性

2. **線程安全規則**
   - 在主線程上讀取和修改 UI 相關狀態
   - 後台線程的操作完成後，始終在主線程上更新狀態
   - 使用 `DispatchQueue.main.async` 或 `MainActor` 確保主線程更新

3. **狀態分組和封裝**
   - 將相關狀態組織為邏輯單元
   - 為每組狀態提供專用的更新方法

4. **避免狀態分散**
   - 不要在 AppState 之外存儲重要狀態
   - 使用 AppState 作為單一事實來源

5. **測試狀態更新**
   - 創建單元測試以驗證狀態更新的正確性
   - 測試多線程情況下的狀態一致性 