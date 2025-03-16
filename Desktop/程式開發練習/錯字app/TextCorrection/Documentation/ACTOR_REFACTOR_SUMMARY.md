# AppState Actor 重構總結

## 重構概述

本次重構將 `AppState` 從基於 `ObservableObject` 的類轉換為 Swift 的 actor 模型，以解決多線程訪問和數據一致性問題。重構還引入了 `AppStateObserver` 作為 SwiftUI 視圖的數據源，以及環境鍵系統用於在 SwiftUI 環境中傳遞 actor 和 observer 實例。

## 主要變更

### 1. AppState 轉換為 Actor

- 移除了 `ObservableObject` 協議和 `@Published` 屬性包裝器
- 移除了手動線程同步機制（如 `DispatchQueue`）
- 利用 actor 的隔離特性確保線程安全
- 所有屬性現在都是 actor 隔離的
- 所有方法都是隔離的，需要使用 `await` 調用

```swift
// 舊版本
class AppState: ObservableObject {
    @Published var isProcessing: Bool = false
    
    private let queue = DispatchQueue(label: "com.yourcompany.TextCorrection.AppState")
    
    func updateProcessingStatus(_ isProcessing: Bool) {
        queue.async {
            DispatchQueue.main.async {
                self.isProcessing = isProcessing
            }
        }
    }
}

// 新版本
actor AppState {
    var isProcessing: Bool = false
    
    func updateProcessingStatus(_ isProcessing: Bool) {
        self.isProcessing = isProcessing
    }
}
```

### 2. 引入 AppStateObserver

創建了一個新的 `AppStateObserver` 類，作為 SwiftUI 視圖的數據源：

- 實現 `ObservableObject` 協議，提供 `@Published` 屬性
- 定期從 `AppState` actor 讀取數據並更新自身狀態
- 提供方法將 UI 操作轉發到 `AppState` actor
- 使用 `@MainActor` 確保所有 UI 更新在主線程上執行

```swift
@MainActor
class AppStateObserver: ObservableObject {
    @Published var isProcessing: Bool = false
    
    private let appState: AppState
    private var monitorTask: Task<Void, Never>?
    
    init(appState: AppState) {
        self.appState = appState
        startMonitoring()
    }
    
    private func startMonitoring() {
        monitorTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.updateFromAppState()
                try? await Task.sleep(nanoseconds: 50_000_000) // 50毫秒
            }
        }
    }
    
    private func updateFromAppState() async {
        self.isProcessing = await appState.isProcessing
        // 更新其他屬性...
    }
    
    func updateProcessingStatus(_ isProcessing: Bool) {
        Task {
            await appState.updateProcessingStatus(isProcessing)
        }
    }
}
```

### 3. 環境鍵系統

實現了 SwiftUI 環境鍵系統，用於在視圖層次結構中傳遞 `AppState` 和 `AppStateObserver` 實例：

```swift
struct AppStateKey: EnvironmentKey {
    static let defaultValue = AppState.shared
}

struct AppStateObserverKey: EnvironmentKey {
    static let defaultValue = AppStateObserver(appState: AppState.shared)
}

extension EnvironmentValues {
    var appState: AppState {
        get { self[AppStateKey.self] }
        set { self[AppStateKey.self] = newValue }
    }
    
    var appStateObserver: AppStateObserver {
        get { self[AppStateObserverKey.self] }
        set { self[AppStateObserverKey.self] = newValue }
    }
}

extension View {
    func withAppState(_ appState: AppState = AppState.shared) -> some View {
        let observer = AppStateObserver(appState: appState)
        return self
            .environmentObject(observer)
            .environment(\.appState, appState)
            .environment(\.appStateObserver, observer)
    }
}
```

### 4. 更新 SwiftUI 視圖

所有 SwiftUI 視圖都已更新，以使用 `AppStateObserver` 進行數據綁定，並在需要時通過環境鍵訪問 `AppState` actor：

```swift
struct SomeView: View {
    @EnvironmentObject private var appStateObserver: AppStateObserver
    @Environment(\.appState) private var appState
    
    var body: some View {
        VStack {
            // 使用 appStateObserver 進行 UI 綁定
            Text("處理中: \(appStateObserver.isProcessing ? "是" : "否")")
            
            Button("開始處理") {
                // 使用 appStateObserver 更新狀態
                appStateObserver.updateProcessingStatus(true)
            }
            
            Button("直接訪問 Actor") {
                // 需要時直接訪問 actor
                Task {
                    await appState.printDebugState()
                }
            }
        }
    }
}
```

### 5. 更新 AppDelegate 和 AppKitBridge

- `AppDelegate` 現在使用 `AppStateObserver` 進行數據綁定，並在需要時通過 Task 訪問 `AppState` actor
- `AppKitBridge` 也已更新，使用 `AppStateObserver` 進行數據綁定，並在需要時通過 Task 訪問 `AppState` actor

## 重構優勢

### 1. 線程安全

- Actor 模型提供了編譯時的線程安全保證，消除了數據競爭和同步問題
- 不再需要手動管理 `DispatchQueue` 或其他同步機制
- 編譯器強制執行隔離規則，防止意外的並發訪問

### 2. 代碼清晰度

- 明確的 actor 隔離邊界使代碼更易於理解和維護
- 清晰的職責分離：`AppState` 負責數據管理，`AppStateObserver` 負責 UI 綁定
- 使用 `async/await` 語法使異步代碼更易讀

### 3. 性能改進

- 減少了不必要的線程切換和同步開銷
- 更精細的並發控制，只在需要時進行異步操作
- 更高效的狀態更新機制，減少了不必要的 UI 刷新

### 4. 可測試性

- 更容易模擬和測試 `AppState` 的行為，因為它不再直接與 UI 綁定
- 可以獨立測試 `AppStateObserver` 的 UI 更新邏輯
- 更清晰的依賴關係，便於單元測試

## 潛在挑戰和解決方案

### 1. 異步 API 的複雜性

**挑戰**：所有 actor 方法都是異步的，需要使用 `await` 調用，這可能增加代碼複雜性。

**解決方案**：
- 使用 `AppStateObserver` 作為中間層，隱藏異步複雜性
- 在 `AppStateObserver` 中使用 `Task` 包裝異步調用，使 UI 代碼保持同步風格

### 2. 遷移現有代碼

**挑戰**：將現有代碼遷移到 actor 模型需要大量更改，可能引入錯誤。

**解決方案**：
- 分階段遷移，先創建 actor 和 observer，然後逐步更新視圖
- 使用編譯器警告和錯誤指導遷移過程
- 全面的測試確保功能正確性

### 3. 性能監控

**挑戰**：需要確保新的架構不會引入性能問題，特別是在頻繁更新時。

**解決方案**：
- 調整 `AppStateObserver` 的更新頻率（目前為 50ms）
- 實現選擇性更新，只在值實際變化時觸發 UI 更新
- 使用性能分析工具監控應用程序行為

## 結論

將 `AppState` 重構為 actor 模型是一個重要的架構改進，解決了多線程訪問和數據一致性問題。通過引入 `AppStateObserver` 和環境鍵系統，我們保持了與 SwiftUI 的良好集成，同時獲得了 actor 模型的所有優勢。

這種架構為應用程序提供了更好的可擴展性、可維護性和穩定性，特別是在處理複雜的並發場景時。雖然遷移過程需要大量工作，但長期收益遠超過短期成本。 