# AppState Actor模型重構計劃

## 1. 概述

將`AppState`從傳統的引用類型（class）重構為Swift的actor模型，以解決多線程同時訪問的問題。這將為應用提供更好的線程安全保障，減少潛在的數據競爭問題。

## 2. 現存問題

目前`AppState`作為應用的中心狀態管理器，被多個組件同時訪問和修改，導致：

1. 出現同時訪問錯誤（Simultaneous access errors）
2. 數據不一致性問題
3. 需要手動使用`DispatchQueue.main.async`確保UI更新在主線程執行
4. 缺乏結構化的線程安全機制

## 3. 重構範圍評估

這是一個重大重構，影響範圍包括：

- `AppState`類本身的完整重構
- 所有使用`AppState`的視圖和組件需要調整訪問方式
- 需要重新設計某些同步操作流程
- 可能需要更新測試用例

## 4. 重構步驟

### 第一階段：準備工作

1. **版本控制保護：**
   - 確保當前代碼已提交到GitHub
   - 為重構創建新的分支`feature/actor-appstate`

2. **識別所有AppState使用點：**
   - 使用代碼搜索找出所有引用`AppState`的地方
   - 記錄重要的使用模式和潛在的線程問題

3. **建立測試基準：**
   - 確保現有的測試覆蓋了關鍵功能
   - 記錄現有的性能指標作為對比

### 第二階段：AppState改造

1. **將AppState類轉換為actor：**

```swift
// 現有實現
class AppState: ObservableObject {
    @Published var originalText: String = ""
    // ...其他屬性
}

// 重構後
actor AppState {
    @MainActor @Published var originalText: String = ""
    // ...其他屬性
}
```

2. **處理ObservableObject協議：**
   - 由於actor不能直接符合ObservableObject協議，需要實現一個分離的觀察者模式
   - 考慮創建一個`AppStateObserver`類作為UI綁定的中介

```swift
@MainActor
class AppStateObserver: ObservableObject {
    @Published var originalText: String = ""
    // ...其他UI相關屬性
    
    private let appState: AppState
    
    init(appState: AppState) {
        self.appState = appState
        // 初始化同步
        Task {
            await updateFromAppState()
        }
    }
    
    func updateFromAppState() async {
        originalText = await appState.originalText
        // ...同步其他屬性
    }
    
    func updateAppState() async {
        await appState.setOriginalText(originalText)
        // ...更新其他屬性
    }
}
```

3. **實現隔離更新方法：**

```swift
actor AppState {
    private(set) var originalText: String = ""
    
    func setOriginalText(_ text: String) {
        originalText = text
        // 可以在這裡添加其他邏輯，如通知觀察者
    }
    
    // 實現更多狀態修改方法
}
```

### 第三階段：更新使用點

1. **更新環境注入：**

```swift
struct TextCorrectionApp: App {
    let appState = AppState()
    @StateObject private var appStateObserver: AppStateObserver
    
    init() {
        let state = AppState()
        _appStateObserver = StateObject(wrappedValue: AppStateObserver(appState: state))
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appStateObserver)
                .environment(\.appState, appState)
        }
    }
}

// 環境值擴展
struct AppStateKey: EnvironmentKey {
    static let defaultValue = AppState()
}

extension EnvironmentValues {
    var appState: AppState {
        get { self[AppStateKey.self] }
        set { self[AppStateKey.self] = newValue }
    }
}
```

2. **更新視圖中的使用：**

```swift
struct SomeView: View {
    @EnvironmentObject var stateObserver: AppStateObserver
    @Environment(\.appState) var appState
    
    var body: some View {
        VStack {
            Text(stateObserver.originalText)
            
            Button("更新文本") {
                Task {
                    await appState.setOriginalText("新文本")
                    await stateObserver.updateFromAppState()
                }
            }
        }
    }
}
```

3. **更新非視圖組件中的使用：**

```swift
class SomeService {
    private let appState: AppState
    
    init(appState: AppState) {
        self.appState = appState
    }
    
    func processText() async {
        let text = await appState.originalText
        // 處理邏輯
        let result = "處理結果"
        await appState.setOriginalText(result)
    }
}
```

### 第四階段：性能優化和測試

1. **優化異步流程：**
   - 識別重複的`await`調用
   - 使用`TaskGroup`並行處理多個任務
   - 實現高效的狀態批量更新

2. **測試重構後的代碼：**
   - 編寫專門測試actor隔離的單元測試
   - 測試UI響應性和狀態一致性
   - 執行壓力測試檢驗線程安全性

## 5. 風險評估

1. **兼容性風險：**
   - Swift的actor相對較新，可能與某些iOS版本不兼容
   - 某些現有第三方庫可能不容易與actor一起使用

2. **性能風險：**
   - actor操作涉及異步開銷，可能影響某些關鍵路徑的性能
   - 需要評估對UI響應性的影響

3. **技術風險：**
   - 團隊可能需要時間適應actor編程模型
   - 調試actor相關問題可能需要新的技術

## 6. 分階段實施計劃

鑑於重構範圍和複雜性，建議分階段實施：

### 階段 A：核心重構（2-3天）
- 將`AppState`轉換為actor
- 創建`AppStateObserver`
- 更新關鍵路徑

### 階段 B：全面適配（3-4天）
- 更新所有視圖和組件
- 解決發現的兼容性問題
- 運行初步測試

### 階段 C：優化和測試（2-3天）
- 性能優化
- 全面測試
- 文檔更新

## 7. 回滾計劃

如果發現重大問題，回滾步驟如下：

1. 中止正在進行的重構分支
2. 切換回主分支
3. 如有必要，將已經實施的改進作為單獨修復應用到主分支

## 8. 文檔和知識共享

重構完成後，應更新以下文檔：

1. 更新`STATE_MANAGEMENT.md`，說明actor模型的使用
2. 為開發者創建`ACTOR_GUIDELINES.md`，詳細解釋如何正確使用新模型
3. 在代碼中添加適當的注釋，特別是在棘手或不直觀的部分

## 9. 結論

將`AppState`重構為actor模型是一項重要但複雜的工作，可以顯著提高應用的穩定性和線程安全。通過謹慎的計劃和分階段實施，可以最小化風險同時獲得actor模型帶來的好處。

建議先將此計劃提交審核，並在團隊中討論可能的優化和調整，然後再開始實施。 