# TextCorrection 測試策略

本文檔說明 TextCorrection 應用的測試策略，包括單元測試、集成測試和 UI 測試的方法、覆蓋範圍，以及如何測試關鍵功能點。

## 測試層次

### 單元測試 (Unit Tests)

單元測試關注於驗證小的、獨立的代碼單元的行為，例如單個類或方法。

#### 覆蓋範圍

| 模組 | 測試重點 | 測試方法 |
|------|---------|---------|
| TextProcessing | 文本差異比較算法 | `testDiffStrings`, `testOptimizeDiff` |
| TextProcessing | 預處理和後處理方法 | `testPreprocessTexts`, `testPostProcessDiff` |
| TextProcessing | 字元變更計數 | `testCalculateChangedWords` |
| OpenAIService | API 請求和回應處理 | `testRewriteText`, `testValidateAPIKey` |
| AppState | 狀態更新和通知 | `testUpdateTextInfo`, `testResetProcessingState` |

#### 測試示例: TextProcessing 的單元測試

```swift
import XCTest
@testable import TextCorrection

final class TextProcessingTests: XCTestCase {
    
    // 測試基本的差異比較功能
    func testDiffStrings() {
        // 測試 1: 完全相同的文本
        let result1 = TextProcessing.diffStrings("相同文本", "相同文本")
        XCTAssertEqual(result1.count, 1)
        if case .equal(let text) = result1[0] {
            XCTAssertEqual(text, "相同文本")
        } else {
            XCTFail("應為相等類型")
        }
        
        // 測試 2: 完全不同的文本
        let result2 = TextProcessing.diffStrings("舊文本", "新文本")
        XCTAssertEqual(result2.count, 2)
        
        // 測試 3: 帶有換行符的文本
        let result3 = TextProcessing.diffStrings("第一行\n第二行", "第一行\n修改後的第二行")
        XCTAssertEqual(result3.count, 3) // 第一行相等 + 換行符相等 + 第二行差異
    }
    
    // 測試帶有換行符的差異比較
    func testDiffStringsWithNewlines() {
        let oldText = "第一段\n第二段\n第三段"
        let newText = "第一段\n修改後的第二段\n第三段"
        
        let result = TextProcessing.diffStrings(oldText, newText)
        
        // 驗證結果: 應該有 5 個元素 (第一段相等 + 換行符 + 第二段差異 + 換行符 + 第三段相等)
        XCTAssertEqual(result.count, 5)
        
        // 驗證每個段落的處理是獨立的
        if case .equal(let text1) = result[0] {
            XCTAssertEqual(text1, "第一段")
        } else {
            XCTFail("第一段應為相等")
        }
        
        if case .equal(let newline1) = result[1] {
            XCTAssertEqual(newline1, "\n")
        } else {
            XCTFail("第一個換行符應為相等")
        }
        
        // 第二段應有差異
        if case .delete(let deleted) = result[2] {
            XCTAssertEqual(deleted, "第二段")
        } else {
            XCTFail("應有刪除內容")
        }
        
        if case .insert(let inserted) = result[3] {
            XCTAssertEqual(inserted, "修改後的第二段")
        } else {
            XCTFail("應有插入內容")
        }
    }
    
    // 測試計算變更詞數
    func testCalculateChangedWords() {
        let original = "這是一個測試文本，包含中文和English。"
        let rewritten = "這是一個修改後的測試，包含中文和English words。"
        
        let changedWords = TextProcessing.calculateChangedWords(original: original, rewritten: rewritten)
        
        // 應該識別出「修改後的」和「words」這些變化
        XCTAssertEqual(changedWords, 5) // 假設算法會計算出正確的變更詞數
    }
}
```

### 集成測試 (Integration Tests)

集成測試關注於驗證多個組件之間的交互是否正確。

#### 覆蓋範圍

| 測試類型 | 測試重點 | 測試方法 |
|---------|---------|---------|
| AppDelegate 與管理器 | 生命週期管理和初始化 | `testAppDelegateInitialization` |
| 橋接層測試 | AppKitBridge 與 AppDelegate 交互 | `testAppKitBridgeWithAppDelegate` |
| 狀態訂閱 | 狀態變更和訂閱響應 | `testStateSubscriptions` |
| 文本處理流程 | 從文本獲取到顯示差異 | `testCompleteTextProcessingFlow` |

#### 測試示例: AppDelegate 與管理器的整合測試

```swift
import XCTest
@testable import TextCorrection

final class AppDelegateIntegrationTests: XCTestCase {
    
    var appDelegate: AppDelegate!
    
    override func setUp() {
        super.setUp()
        appDelegate = AppDelegate()
    }
    
    override func tearDown() {
        appDelegate = nil
        super.tearDown()
    }
    
    // 測試 AppDelegate 初始化時是否正確創建所有管理器
    func testAppDelegateInitialization() {
        XCTAssertNotNil(appDelegate.pasteboardManager, "PasteboardManager 應正確初始化")
        XCTAssertNotNil(appDelegate.hotKeyManager, "HotKeyManager 應正確初始化")
        XCTAssertNotNil(appDelegate.statusItemManager, "StatusItemManager 應正確初始化")
        XCTAssertNotNil(appDelegate.textWindowManager, "TextWindowManager 應正確初始化")
    }
    
    // 測試 AppDelegate 與 AppState 之間的訂閱關係
    func testStateSubscriptions() {
        // 模擬 AppDelegate 設置訂閱
        appDelegate.setupStateSubscriptions()
        
        // 模擬改變 AppState 的某個屬性
        AppState.shared.isProcessing = true
        
        // 這裡需要等待一小段時間讓訂閱處理完成
        let expectation = XCTestExpectation(description: "等待狀態變更處理")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
        
        // 驗證 AppDelegate 是否對狀態變化做出了響應
        // 這需要根據實際實現調整
    }
    
    // 測試文本處理流程
    func testTextProcessingFlow() {
        // 設置原始文本
        let originalText = "這是原始文本"
        AppState.shared.originalText = originalText
        
        // 啟動處理流程
        appDelegate.rewriteText()
        
        // 模擬等待處理完成
        let expectation = XCTestExpectation(description: "等待文本處理完成")
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 5.0)
        
        // 驗證處理後的狀態
        XCTAssertFalse(AppState.shared.isProcessing, "處理完成後應將狀態設為false")
        XCTAssertNotEqual(AppState.shared.correctedText, "", "校正後的文本不應為空")
    }
}
```

### UI 測試 (UI Tests)

UI 測試關注於驗證使用者界面的行為和互動。

#### 覆蓋範圍

| 測試類型 | 測試重點 | 測試方法 |
|---------|---------|---------|
| 基本 UI 元素 | 視窗顯示和按鈕點擊 | `testWindowsAndButtons` |
| 設置界面 | 設置項變更和保存 | `testSettingsView` |
| 文本窗口 | 文本顯示和交互 | `testTextWindowInteraction` |
| 懸浮按鈕 | 按鈕顯示和點擊事件 | `testFloatingButtonBehavior` |

#### 測試示例: UI 測試

```swift
import XCTest

final class TextCorrectionUITests: XCTestCase {
    
    var app: XCUIApplication!
    
    override func setUp() {
        super.setUp()
        app = XCUIApplication()
        app.launch()
        
        // 等待應用程式完全啟動
        let statusItem = app.statusItems.firstMatch
        XCTAssertTrue(statusItem.waitForExistence(timeout: 5.0))
    }
    
    // 測試設置窗口的顯示和交互
    func testSettingsWindow() {
        // 點擊狀態欄圖標
        let statusItem = app.statusItems.firstMatch
        statusItem.click()
        
        // 從菜單中選擇設置選項
        app.menuItems["設定"].click()
        
        // 驗證設置窗口已顯示
        let settingsWindow = app.windows["設定"]
        XCTAssertTrue(settingsWindow.exists)
        
        // 測試在設置窗口中進行交互
        let apiKeyField = settingsWindow.textFields["API金鑰"]
        XCTAssertTrue(apiKeyField.exists)
        
        // 輸入測試值
        apiKeyField.click()
        apiKeyField.typeText("test-api-key")
        
        // 點擊保存按鈕
        settingsWindow.buttons["保存"].click()
        
        // 關閉設置窗口
        settingsWindow.buttons[XCUIIdentifierCloseWindow].click()
    }
    
    // 測試文本處理流程
    func testTextProcessingFlow() {
        // 模擬複製文本到剪貼板
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString("這是測試文本", forType: .string)
        
        // 等待懸浮按鈕出現
        let floatingButton = app.windows["浮動按鈕"].buttons.firstMatch
        XCTAssertTrue(floatingButton.waitForExistence(timeout: 5.0))
        
        // 點擊懸浮按鈕
        floatingButton.click()
        
        // 等待文本窗口出現
        let textWindow = app.windows.matching(identifier: "TextWindow").firstMatch
        XCTAssertTrue(textWindow.waitForExistence(timeout: 5.0))
        
        // 等待處理完成
        let processedTextExists = NSPredicate(format: "exists == true")
        let processedTextView = textWindow.textViews.firstMatch
        expectation(for: processedTextExists, evaluatedWith: processedTextView, handler: nil)
        waitForExpectations(timeout: 10.0, handler: nil)
        
        // 驗證窗口中顯示了處理後的文本
        XCTAssertTrue(processedTextView.value != nil)
        
        // 測試複製按鈕功能
        textWindow.buttons["複製"].click()
        
        // 驗證文本是否已複製到剪貼板
        let copiedText = pasteboard.string(forType: .string)
        XCTAssertNotNil(copiedText)
    }
}
```

## 特殊功能點測試

### 段落換行處理測試

#### 測試目標
驗證文本比較算法在處理包含多個段落（由換行符分隔）的文本時的正確性。

#### 測試策略
1. 創建包含多個段落的原始文本和修改後文本
2. 確保每個段落被獨立處理和比較
3. 驗證換行符的處理和顯示

#### 測試用例

```swift
func testParagraphHandling() {
    // 測試數據：多段落文本
    let originalText = """
    第一段內容。
    第二段有一些需要修改的錯字。
    第三段內容保持不變。
    """
    
    let modifiedText = """
    第一段內容。
    第二段修改後的內容，沒有錯字。
    第三段內容保持不變。
    """
    
    // 執行差異比較
    let diffResult = TextProcessing.diffStrings(originalText, modifiedText)
    
    // 記錄用於驗證的中間結果
    logger.debug("原始文本:\n\(originalText)")
    logger.debug("修改後文本:\n\(modifiedText)")
    
    // 輸出差異結果供檢查
    var resultDescription = "差異結果:\n"
    for change in diffResult {
        switch change {
        case .equal(let text):
            resultDescription += "相等: '\(text)'\n"
        case .insert(let text):
            resultDescription += "插入: '\(text)'\n"
        case .delete(let text):
            resultDescription += "刪除: '\(text)'\n"
        }
    }
    logger.debug(resultDescription)
    
    // 驗證各段落是否正確處理
    // 第一段和第三段應該完全相等，第二段有差異
    // 換行符應該獨立保留
    
    // 模擬生成富文本結果並顯示
    let font = NSFont.systemFont(ofSize: 14)
    let richText = TextProcessing.compareTexts(original: originalText, rewritten: modifiedText, customFont: font)
    
    // 將富文本顯示在測試窗口中
    showTestWindow(withText: richText)
}

// 創建測試窗口顯示結果
func showTestWindow(withText text: NSAttributedString) {
    let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
        styleMask: [.titled, .closable, .resizable],
        backing: .buffered,
        defer: false
    )
    window.title = "段落處理測試"
    
    let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
    textView.isEditable = false
    textView.textStorage?.setAttributedString(text)
    
    let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
    scrollView.documentView = textView
    scrollView.hasVerticalScroller = true
    
    window.contentView = scrollView
    window.makeKeyAndOrderFront(nil)
    
    // 等待用戶確認
    let alert = NSAlert()
    alert.messageText = "請檢查段落分隔處理結果"
    alert.informativeText = "檢查測試窗口中的文本顯示，確認段落處理是否正確"
    alert.addButton(withTitle: "確認")
    alert.runModal()
    
    window.close()
}
```

### 其他關鍵功能點測試

1. **熱鍵觸發測試**
   - 測試熱鍵註冊和觸發流程
   - 驗證熱鍵事件處理鏈
   - 確認文本選中和處理功能

2. **剪貼板監控測試**
   - 測試剪貼板變化檢測
   - 驗證懸浮按鈕顯示邏輯
   - 確認剪貼板內容獲取準確性

3. **狀態同步測試**
   - 測試 AppState 的狀態變更通知
   - 驗證多個組件之間的狀態同步
   - 確認 UI 更新響應狀態變化

## 測試環境設置

### 模擬對象 (Mocks) 和存根 (Stubs)

為了隔離測試並專注於特定組件，以下組件應該創建模擬版本:

1. **模擬 OpenAIService**
   ```swift
   class MockOpenAIService: OpenAIService {
       var validateAPIKeyResult: Result<Void, OpenAIError> = .success(())
       var rewriteTextResult: Result<String, OpenAIError> = .success("模擬的API響應")
       
       override func validateAPIKey(_ apiKey: String) async throws {
           if case .failure(let error) = validateAPIKeyResult {
               throw error
           }
       }
       
       override func rewriteText(_ text: String, apiKey: String) async throws -> String {
           if case .success(let result) = rewriteTextResult {
               return result
           } else if case .failure(let error) = rewriteTextResult {
               throw error
           }
           return ""
       }
   }
   ```

2. **模擬 PasteboardManager**
   ```swift
   class MockPasteboardManager: PasteboardManager {
       var simulatedClipboardText: String?
       
       override func checkForPasteboardChanges() {
           if let text = simulatedClipboardText {
               // 模擬剪貼板變化
               appDelegate?.showFloatingButton(forText: text)
           }
       }
   }
   ```

3. **測試專用 AppDelegate**
   ```swift
   class TestAppDelegate: AppDelegate {
       // 覆蓋初始化方法，使用測試模擬對象
       override init() {
           super.init()
           openAIService = MockOpenAIService()
           pasteboardManager = MockPasteboardManager(appDelegate: self)
       }
   }
   ```

### 測試資料

為了確保測試的一致性和可重現性，應該創建一套固定的測試資料:

1. **文本比較測試數據集**
   - 簡單的單詞和短句變更
   - 多段落文本變更
   - 僅有段落順序變化的文本
   - 包含特殊符號和標點的文本
   - 中英文混合文本

2. **API 響應模擬數據**
   - 成功的 API 回應
   - 錯誤回應（不同類型）
   - 流式回應模擬

## 持續整合與測試自動化

1. **本地測試運行**
   ```bash
   # 運行所有單元測試
   xcodebuild test -project TextCorrection.xcodeproj -scheme TextCorrection -destination 'platform=macOS'
   
   # 運行特定測試類
   xcodebuild test -project TextCorrection.xcodeproj -scheme TextCorrection -destination 'platform=macOS' -only-testing:TextCorrectionTests/TextProcessingTests
   ```

2. **CI 流程整合**
   - 在每次推送和合併請求時運行測試套件
   - 設置覆蓋率閾值和報告
   - 測試失敗時自動通知

## 測試覆蓋率目標

| 模組 | 目標覆蓋率 | 優先級 |
|------|----------|-------|
| TextProcessing | 90% | 高 |
| 核心邏輯類 | 80% | 高 |
| UI 交互 | 60% | 中 |
| 輔助功能 | 40% | 低 |

## 測試報告和文檔

1. **測試報告格式**
   - 測試覆蓋率報告
   - 失敗測試詳細信息
   - 性能測試結果

2. **故障排查指南**
   - 如何使用測試結果診斷問題
   - 常見測試失敗的解決方案 