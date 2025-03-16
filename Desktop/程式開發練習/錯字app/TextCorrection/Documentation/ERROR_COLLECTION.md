# 錯誤收集與報告實施指南

本文檔詳細說明了如何在應用中實施和使用錯誤收集與報告系統，以便於追蹤和解決問題。

## 一、錯誤收集系統概述

我們已經實現了兩種主要的錯誤收集與報告機制：

1. **本地日誌系統** - 使用`ErrorReportingManager`進行本地日誌記錄和錯誤收集
2. **遠程崩潰分析** - 使用Firebase Crashlytics進行崩潰報告和錯誤追蹤

這兩種機制互相補充，共同為應用提供完整的錯誤監控和診斷能力。

## 二、本地日誌系統使用指南

### 1. 基本日誌記錄

在任何地方使用以下方式記錄日誌：

```swift
import Foundation

// 在需要使用的文件中導入

// 記錄不同級別的日誌
ErrorReportingManager.shared.log("普通信息", level: .info)
ErrorReportingManager.shared.log("警告信息", level: .warning)
ErrorReportingManager.shared.log("錯誤信息", level: .error)
ErrorReportingManager.shared.log("調試信息", level: .debug)
ErrorReportingManager.shared.log("嚴重錯誤", level: .critical)
```

### 2. 記錄錯誤

對於捕獲到的錯誤，使用專門的錯誤記錄方法：

```swift
do {
    // 可能拋出錯誤的代碼
} catch {
    // 記錄錯誤
    ErrorReportingManager.shared.recordNonFatalError(
        error, 
        additionalInfo: ["context": "文本處理", "textLength": 250]
    )
}
```

### 3. 查看日誌

開發或測試期間查看最近日誌：

```swift
// 獲取最近100行日誌
let recentLogs = ErrorReportingManager.shared.getRecentLogs(maxLines: 100)
print(recentLogs)

// 獲取所有日誌文件
let logFiles = ErrorReportingManager.shared.getLogFiles()
```

### 4. 日誌文件管理

日誌文件位於應用Documents目錄的Logs子目錄中，命名格式為`app_log_YYYY-MM-DD.log`。您可以：

- 查看特定日誌文件的內容
- 檢索所有日誌文件
- 通過集成的報告UI提交日誌

## 三、Firebase Crashlytics集成指南

### 1. 初始化設置

參照`FirebaseIntegration.swift`文件中的詳細說明完成Firebase設置：

1. 創建Firebase項目
2. 配置macOS應用
3. 添加必要的SDK依賴
4. 在應用啟動時初始化Firebase

### 2. 記錄錯誤到Crashlytics

一旦Firebase Crashlytics集成完成，可以這樣使用：

```swift
import FirebaseCrashlytics

// 記錄簡單信息
Crashlytics.crashlytics().log("用戶嘗試處理大文本")

// 記錄非致命錯誤
let error = NSError(domain: "TextProcessingError", code: 100, userInfo: [
    NSLocalizedDescriptionKey: "無法處理文本",
    "details": "API響應超時"
])
Crashlytics.crashlytics().record(error: error)

// 設置用戶ID以便追蹤特定用戶問題
Crashlytics.crashlytics().setUserID("user_12345")

// 添加自定義鍵值
Crashlytics.crashlytics().setCustomValue(textLength, forKey: "text_length")
Crashlytics.crashlytics().setCustomValue("zh-TW", forKey: "user_language")
```

### 3. 與本地日誌系統集成

為同時利用兩種系統，可以擴展`ErrorReportingManager`：

```swift
// 在ErrorReportingManager中添加Firebase支持
func recordNonFatalError(_ error: Error, additionalInfo: [String: Any]? = nil) {
    // 記錄到本地日誌
    log("非致命錯誤: \(error.localizedDescription)", level: .error)
    
    #if !DEBUG // 僅在非調試版本使用Crashlytics
    // 記錄到Firebase Crashlytics
    if FirebaseApp.app() != nil {
        Crashlytics.crashlytics().log("非致命錯誤: \(error.localizedDescription)")
        Crashlytics.crashlytics().record(error: error)
        
        // 添加附加信息
        if let info = additionalInfo, !info.isEmpty {
            for (key, value) in info {
                Crashlytics.crashlytics().setCustomValue(value, forKey: key)
            }
        }
    }
    #endif
}
```

## 四、用戶錯誤報告界面

### 1. 顯示錯誤報告界面

```swift
// 顯示錯誤報告界面
let error = NSError(domain: "AppError", code: 500, userInfo: [
    NSLocalizedDescriptionKey: "應用遇到了問題"
])

ErrorReportingManager.shared.showErrorReportUI(error: error) { reportData in
    if let data = reportData {
        // 發送報告到服務器
        ErrorReportingManager.shared.submitErrorReport(reportData: data) { success, message in
            if success {
                print("報告提交成功")
            } else {
                print("報告提交失敗: \(message ?? "未知錯誤")")
            }
        }
    }
}
```

### 2. 自定義錯誤報告視圖

`ErrorReportView`提供了一個基本的錯誤報告界面。您可以通過修改此視圖自定義報告界面：

- 添加更多用戶輸入字段
- 修改視覺風格
- 添加截圖功能

## 五、API錯誤處理最佳實踐

### 1. 結構化錯誤處理

```swift
enum APIError: Error, LocalizedError {
    case networkError(Error)
    case invalidResponse
    case serverError(Int)
    case parseError(Error)
    case rateLimited
    
    var errorDescription: String? {
        switch self {
        case .networkError(let error):
            return "網絡錯誤：\(error.localizedDescription)"
        case .invalidResponse:
            return "無效的伺服器響應"
        case .serverError(let code):
            return "伺服器錯誤，狀態碼：\(code)"
        case .parseError(let error):
            return "數據解析錯誤：\(error.localizedDescription)"
        case .rateLimited:
            return "請求頻率過高，請稍後再試"
        }
    }
}

func handleAPIError(_ error: Error) {
    // 記錄到錯誤報告系統
    ErrorReportingManager.shared.recordNonFatalError(error)
    
    // 根據錯誤類型採取不同行動
    if let apiError = error as? APIError {
        switch apiError {
        case .networkError:
            // 顯示網絡錯誤提示
            showNetworkErrorAlert()
        case .rateLimited:
            // 實施退避策略
            implementBackoffStrategy()
        default:
            // 顯示一般錯誤
            showGeneralErrorAlert(apiError.localizedDescription)
        }
    } else {
        // 未知錯誤類型
        showGeneralErrorAlert("發生未知錯誤")
    }
}
```

### 2. 為調試記錄操作上下文

```swift
func processText(_ text: String) {
    ErrorReportingManager.shared.log("開始處理文本，長度: \(text.count)", level: .info)
    
    // 記錄原始文本和處理後文本用於調試
    ErrorReportingManager.shared.log("原始文本: \(text)", level: .debug)
    
    // 文本處理邏輯...
    
    ErrorReportingManager.shared.log("處理後文本: \(processedText)", level: .debug)
    ErrorReportingManager.shared.log("文本處理完成，耗時: \(elapsedTime)秒", level: .info)
}
```

## 六、多線程崩潰的特殊處理

### 1. 檢測潛在的線程問題

```swift
// 檢查是否在主線程
func ensureMainThread(file: String = #file, function: String = #function, line: Int = #line) {
    if !Thread.isMainThread {
        ErrorReportingManager.shared.log("警告: 不在主線程但嘗試更新UI", level: .warning, file: file, function: function, line: line)
        
        // 在調試版本直接崩潰以便發現問題
        #if DEBUG
        fatalError("不在主線程但嘗試更新UI")
        #endif
    }
}
```

### 2. 修復主線程問題

```swift
// 確保在主線程更新UI
func updateUI() {
    ensureMainThread()
    
    // 或者更安全的方式:
    if Thread.isMainThread {
        // 直接更新UI
        performUIUpdates()
    } else {
        DispatchQueue.main.async {
            self.performUIUpdates()
        }
    }
}
```

## 七、測試和驗證

### 1. 測試日誌系統

```swift
func testLoggingSystem() {
    // 記錄測試消息
    ErrorReportingManager.shared.log("這是一條測試日誌", level: .info)
    
    // 驗證日誌文件存在且內容正確
    let logs = ErrorReportingManager.shared.getRecentLogs(maxLines: 10)
    XCTAssert(logs.contains("這是一條測試日誌"), "日誌未正確記錄")
}
```

### 2. 測試崩潰報告集成

```swift
func testCrashlytics() {
    // 注意: 此測試應在單獨的測試設備上運行，不要在生產環境測試崩潰
    
    // 1. 記錄自定義事件
    Crashlytics.crashlytics().log("測試Crashlytics")
    
    // 2. 記錄非致命錯誤
    let testError = NSError(domain: "TestDomain", code: 100, userInfo: nil)
    Crashlytics.crashlytics().record(error: testError)
    
    // 3. 設置用戶標識符
    Crashlytics.crashlytics().setUserID("test_user")
    
    // 注意: 測試致命崩潰將終止應用，應謹慎使用
    // Crashlytics.crashlytics().crash()
}
```

## 八、數據收集與隱私注意事項

### 1. 隱私考慮

當收集錯誤報告和日誌時，應謹記以下隱私原則：

- 不記錄可以識別用戶身份的信息，除非絕對必要
- 不記錄敏感數據（密碼、令牌等）
- 提供選項讓用戶控制收集的數據範圍
- 在隱私政策中明確說明收集的數據類型和用途

### 2. 日誌敏感數據處理

```swift
// 根據數據敏感度調整日誌級別
func logUserAction(action: String, data: Any) {
    // 一般操作用info
    ErrorReportingManager.shared.log("用戶執行操作: \(action)", level: .info)
    
    // 包含詳細數據的日誌使用debug級別，僅在開發環境可見
    #if DEBUG
    ErrorReportingManager.shared.log("操作詳情: \(data)", level: .debug)
    #endif
}
```

## 九、常見問題與解決方案

### 1. 日誌系統不工作

**問題**: 應用不產生日誌文件或日誌內容不完整。

**解決方案**:
- 檢查日誌目錄權限
- 確認`ErrorReportingManager`已正確初始化
- 驗證應用沙盒文件系統訪問權限

### 2. Firebase Crashlytics無法接收報告

**問題**: 崩潰發生但未在Firebase控制台顯示。

**解決方案**:
- 確認GoogleService-Info.plist設置正確
- 驗證Firebase正確初始化
- 檢查網絡連接
- 等待至少20分鐘（Crashlytics報告有延遲）
- 確認dSYM文件正確上傳

### 3. 多線程崩潰難以重現

**問題**: 用戶報告崩潰但無法在開發環境重現。

**解決方案**:
- 使用Crashlytics符號化崩潰報告
- 添加更多線程安全檢查
- 考慮使用actor模型（如計劃的AppState重構）隔離共享狀態
- 實施壓力測試腳本模擬高負載情況

## 十、結論

錯誤收集和報告系統是應用質量保障的關鍵組件。通過本地日誌和Firebase Crashlytics的結合使用，我們可以全面了解應用的健康狀況、快速識別問題並提高用戶體驗。

請記住定期審核收集的錯誤數據，尋找模式和趨勢，並優先修復那些影響最大的問題。 