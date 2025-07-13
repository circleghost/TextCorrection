import Cocoa
import SwiftUI
import Carbon
import HotKey
import KeychainAccess
import os.log
import Combine
import ApplicationServices
import UserNotifications

// 確保在整個檔案都可以使用 AppState
import Foundation

// 安全的 API 金鑰管理
struct SecureAPIKeyManager {
    private static let keychain = Keychain(service: "com.yourcompany.TextCorrection")
        .accessibility(.whenUnlockedThisDeviceOnly)
        .synchronizable(false)
    
    @Sendable
    static func getAPIKey() -> String {
        do {
            // 從安全的 Keychain 獲取 API 金鑰
            return try keychain.get("OpenAIApiKey") ?? ""
        } catch {
            print("無法安全取得 API 金鑰: \(error)")
            return ""
        }
    }
    
    static func setAPIKey(_ key: String) throws {
        guard !key.isEmpty else {
            try keychain.remove("OpenAIApiKey")
            return
        }
        
        // 基本驗證 API 金鑰格式
        guard key.hasPrefix("sk-") && key.count > 20 else {
            throw APIKeyError.invalidFormat
        }
        
        try keychain.set(key, key: "OpenAIApiKey")
    }
    
    static func removeAPIKey() throws {
        try keychain.remove("OpenAIApiKey")
    }
}

enum APIKeyError: LocalizedError {
    case invalidFormat
    case storageError
    
    var errorDescription: String? {
        switch self {
        case .invalidFormat:
            return "API 金鑰格式無效"
        case .storageError:
            return "無法儲存 API 金鑰"
        }
    }
}

// 向後兼容的函數
@Sendable
func getOpenAIApiKey() -> String {
    return SecureAPIKeyManager.getAPIKey()
}

// 移除不安全的 Sendable 聲明

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    var statusItemManager: StatusItemManager!
    var pasteboardManager: PasteboardManager!
    var textWindowManager: TextWindowManager!
    var openAIService: OpenAIService!
    var hotKeyManager: HotKeyManager!
    
    // 創建日誌對象
    private let logger = Logger(subsystem: "com.yourcompany.TextCorrection", category: "AppDelegate")
    
    // Combine訂閱集合
    private var cancellables = Set<AnyCancellable>()
    
    var floatingButton: NSWindow?
    private var lastSelectedText: String?
    private var isRewriting = false
    private var isProcessingCopy = false
    
    // 新增顏色常量
    let addedTextColor = NSColor(red: 0.0, green: 0.5, blue: 0.0, alpha: 1.0) // 深綠色
    let deletedTextColor = NSColor(red: 0.8, green: 0.0, blue: 0.0, alpha: 1.0) // 深紅色
    
    private let compareThreshold = 100 // 累積多少字符後進行比較
    
    var currentTextView: NSTextView?
    var copyButton: NSButton?
    var statsView: NSTextField?
    var shortcutView: NSTextField?
    var settingsButton: NSButton?
    
    private var apiResponseText: String = ""
    private var apiReturnedText: String = ""

    var originalText: String = ""

    let customFont: NSFont

    // 系統提示詞
    private let systemPrompt = """
    你是一名專業的台灣繁體中文雜誌編輯，幫我檢查給定內容的錯字及語句文法。請特別注意以下規則：
    1. 中文與英文之間，中文與數字之間應有空格，例如 FLAC，JPEG，Google Search Console 。
    2. 注重標點符號的正確使用，包括避免中英文標點混用。例如：括號應該使用全形（）而非半形()。
    3. 修正不恰當的斷句，並注意句與句之間邏輯連貫性的順暢。
    4. 糾正錯字、錯詞和語法錯誤。
    5. 優化繁體中文表達，使文字更精簡、專業。
    
    請將更正後的內容放在兩個三個反引號之間。不需要講解修改的原因。只需要給出修改後的文本。
    """

    private var isApiKeyValid: Bool = false

    private var welcomeWindow: NSWindow?
    var textWindow: NSWindow?
    private var settingsWindow: NSWindow?
    private var swiftUITextWindow: NSWindow?
    private var feedbackWindow: NSWindow?
    private var logsWindow: NSWindow?
    
    // 新增一個標記應用程序是否正在終止的屬性
    var isTerminating = false
    
    // 選中的文本
    private var correctedText: String = ""
    
    // 添加粉圓體字體輔助方法 - 改為靜態方法
    private static func getPungyuFont(size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        // 嘗試多種可能的粉圓體字體名稱
        let fontNames = ["jf-openhuninn", "JF Open Huninn", "粉圓體", "jf粉圓體", "JF粉圓體"]
        
        for name in fontNames {
            if let font = NSFont(name: name, size: size) {
                return font
            }
        }
        
        // 如果找不到粉圓體，回退到系統字體
        return NSFont.systemFont(ofSize: size, weight: weight)
    }

    override init() {
        // 初始化自定義字體為粉圓體 - 使用靜態方法
        customFont = AppDelegate.getPungyuFont(size: 14)
        
        super.init()
    }
    
    /// 應用程式啟動
    func applicationDidFinishLaunching(_ notification: Notification) {
        // 初始化日誌系統
        logger.info("應用程式啟動中...")
        
        // 先檢查 API key 是否存在，不存在則顯示設定畫面
        if getOpenAIApiKey().isEmpty {
            logger.info("未找到 API key，顯示設定畫面")
            // 延遲一點時間確保應用程式完全載入
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                guard let self = self else { return }
                
                // 使用統一的方法顯示設定窗口
                self.showSettings()
                
                // 添加一個提示通知
                AppState.shared.addNotification(
                    title: "需要 API key",
                    message: "請輸入 OpenAI API key 以啟用文字校正功能",
                    type: .warning
                )
            }
        }
        
        // 配置狀態欄圖標和菜單
        statusItemManager = StatusItemManager(appDelegate: self)
        
        // 初始化剪貼簿監控
        pasteboardManager = PasteboardManager(appDelegate: self)
        
        // 初始化 LogManager
        _ = LogManager.shared
        
        // 記錄應用啟動
        logger.infoWithManager("===== 應用程式啟動 =====")
        
        AppKitBridge.shared.appDelegate = self
        
        // 設置通知中心代理（通過擴展實現）
        UNUserNotificationCenter.current().delegate = self
        
        // 使用AccessibilityManager檢查權限
        Task { @MainActor in
            AccessibilityManager.checkPermissionsOnLaunch()
        }
        
        // 設置狀態訂閱
        setupStateSubscriptions()
        
        // 初始化各個管理器
        initializeManagersSafely()
        
        // 初始化UI元素
        initializeUI()
        
        // 檢查API Key是否有效
        validateApiKey()
        
        // 打印初始狀態（用於調試）
        AppState.shared.printDebugState()
        AppKitBridge.shared.printDebugState()
        
        // 發送啟動通知
        Task {
            do {
                try await NotificationManager.shared.sendNotification(
                    title: "錯字糾正已啟動",
                    message: "應用程式已在背景運行，可以通過菜單欄圖標或熱鍵使用。",
                    type: .info,
                    delay: 1.0
                )
            } catch {
                logger.error("發送啟動通知時出錯: \(error.localizedDescription)")
            }
        }
    }
    
    /// 檢查輔助功能權限
    @MainActor
    func checkAccessibilityPermissions() {
        // 檢查是否已授予輔助功能權限
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false]
        let accessEnabled = AXIsProcessTrustedWithOptions(options as CFDictionary)
        
        if !accessEnabled {
            logger.warning("應用程式缺少輔助功能權限")
            
            // 顯示提示並提供快速連結到系統偏好設定
            let alert = NSAlert()
            alert.messageText = "需要輔助功能權限"
            alert.informativeText = "熱鍵功能和一些自動化操作需要輔助功能權限。請前往「系統設定」→「隱私與安全性」→「輔助使用」允許本應用程式。"
            alert.alertStyle = .warning
            alert.addButton(withTitle: "打開系統設定")
            alert.addButton(withTitle: "稍後設定")
            
            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                // 打開系統偏好設定的輔助功能面板
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                    NSWorkspace.shared.open(url)
                }
            }
        } else {
            logger.info("應用程式已獲得輔助功能權限")
        }
    }
    
    /// 設置與AppState的訂閱關係
    private func setupStateSubscriptions() {
        // 訂閱文本窗口狀態變化
        AppState.shared.$isTextWindowOpen
            .sink { [weak self] isOpen in
                self?.logger.debug("文本窗口狀態變更: \(isOpen)")
                if !isOpen && self?.textWindow != nil {
                    DispatchQueue.main.async {
                        self?.textWindow?.close()
                        self?.textWindow = nil
                    }
                }
            }
            .store(in: &cancellables)
        
        AppState.shared.$isSettingsWindowOpen
            .sink { [weak self] isOpen in
                guard let self = self else { return }
                self.logger.debug("設定視窗狀態變更: \(isOpen)")
                
                if isOpen && self.settingsWindow == nil {
                    DispatchQueue.main.async {
                        self.createSettingsWindow()
                    }
                }
                if !isOpen && self.settingsWindow != nil {
                    DispatchQueue.main.async {
                        self.logger.debug("關閉設定視窗")
                        self.settingsWindow?.close()
                        self.settingsWindow = nil
                    }
                }
            }
            .store(in: &cancellables)
        
        // 訂閱剪貼板監控狀態變化
        AppState.shared.$isClipboardMonitoringEnabled
            .sink { [weak self] isEnabled in
                // 使用主線程更新UI和APP狀態
                DispatchQueue.main.async {
                    self?.logger.debug("剪貼板監控狀態變更: \(isEnabled)")
                    if isEnabled {
                        self?.pasteboardManager?.startMonitoring()
                    } else {
                        self?.pasteboardManager?.stopMonitoring()
                    }
                }
            }
            .store(in: &cancellables)
    }
    
    /// 安全地初始化所有管理器 - 捕獲任何可能的錯誤
    private func initializeManagersSafely() {
        logger.info("開始初始化所有管理器")
        
        // 使用 autoreleasepool 確保內存及時釋放
        autoreleasepool {
            // 初始化服務和管理器
            openAIService = OpenAIService()
            logger.info("OpenAI服務初始化完成")
            
            textWindowManager = TextWindowManager(appDelegate: self)
            logger.info("文本窗口管理器初始化完成")
            
            statusItemManager = StatusItemManager(appDelegate: self)
            logger.info("狀態欄管理器初始化完成")
            
            // 初始化熱鍵管理器
            initializeHotKeyManager(appDelegate: self)
            
            // 初始化剪貼板監視器
            pasteboardManager = PasteboardManager(appDelegate: self)
            logger.info("剪貼板監視器初始化完成")
            
            // 啟動剪貼板監視（如果啟用）
            if AppState.shared.isClipboardMonitoringEnabled {
                logger.info("啟動剪貼板監視")
                pasteboardManager.startMonitoring()
            }
            
            logger.info("所有管理器初始化完成")
        }
    }

    // 初始化UI元素
    private func initializeUI() {
        // 臨時空實現
        logger.info("初始化UI元素")
    }
    
    // 檢查API Key是否有效
    private func validateApiKey() {
        // 臨時空實現
        logger.info("檢查API Key有效性")
    }
    
    // 重寫文本
    func rewriteText() {
        // 確保在主線程執行
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in
                self?.rewriteText()
            }
            return
        }
        
        logger.info("重寫文本: 開始（在主線程上）")
        
        // 確保我們有原始文本
        let textToProcess = AppState.shared.originalText
        if textToProcess.isEmpty {
            logger.error("無法重寫文本：原始文本為空")
            AppState.shared.errorMessage = "無文本可處理"
            return
        }
        
        // 設置處理狀態
        AppState.shared.isProcessing = true
        AppState.shared.processingProgress = 0.1
        AppState.shared.errorMessage = ""
        
        // 詳細記錄API調用前的文本
        logger.info("開始處理文本，長度: \(textToProcess.count)字符")
        logger.debug("API調用前文本內容:\n\(textToProcess)")
        
        // 開始計時
        let startTime = Date()
        
        // 保存原始文本到AppState - 使用安全更新方法
        AppState.shared.safelyUpdate(\.originalText, value: textToProcess)
        
        // 開始處理標記 - 使用安全更新方法
        AppState.shared.safelyUpdate(\.isProcessing, value: true)
        AppState.shared.safelyUpdate(\.processingProgress, value: 0.1)
        
        // 使用 autoreleasepool 減少內存壓力
        autoreleasepool {
            // 獲取需要的參數，避免在 Task 內部捕獲 self
            let currentTextView = self.currentTextView
            // 直接複製函數實現到本地域，避免捕獲 self
            let extractMarkdownBlock: @Sendable (String) -> String = { text in
                // 確保文本不為空並有效
                guard !text.isEmpty else {
                    return ""
                }
                
                // 使用更安全的模式處理文本
                let pattern = "```([\\s\\S]*?)```"
                
                if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                    // 保護檢查：確保 text.utf16.count 在有效範圍內
                    let nsRange = NSRange(location: 0, length: min(text.utf16.count, Int.max - 1))
                    
                    if let match = regex.firstMatch(in: text, options: [], range: nsRange) {
                        if match.numberOfRanges > 1, let range = Range(match.range(at: 1), in: text) {
                            // 安全地提取字符串範圍
                            let result = String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
                            return result
                        }
                    }
                }
                
                // 如果沒有找到代碼塊，安全地清理文本
                // 使用更安全的方式替換文本而不是直接替換
                let components = text.components(separatedBy: "```")
                let joinedText = components.joined(separator: "")
                return joinedText.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            let systemPromptCopy = self.systemPrompt
            let textWindowManager = self.textWindowManager
            // 獲取 AI 服務引用（新的統一服務）
            let aiService = OpenAIService()
            let selectedModel = AppSettings.shared.selectedModel
            
            // 獲取 self 的弱引用，供後續閉包使用
            weak var weakSelf = self
            let loggerCopy = self.logger
            
            // 使用流式 API 回應
            Task.detached {
                // 檢查是否有有效的 API 金鑰
                guard AppSettings.shared.hasValidAPIKeyForSelectedModel() else {
                    await MainActor.run {
                        AppState.shared.isProcessing = false
                        AppState.shared.errorMessage = "尚未設置 \(selectedModel.provider.displayName) API 金鑰，請前往偏好設定進行設置"
                        loggerCopy.error("API 金鑰未設置，無法處理文本。選擇的模型: \(selectedModel.displayName)")
                    }
                    return
                }
                
                do {
                    // 使用 OpenAIService 的流式 API 進行文字校正
                    var correctedText = ""
                    let streamingSpeed = AppSettings.shared.textStreamingSpeed
                    
                    try await aiService.streamOpenAiApi(
                        text: textToProcess,
                        apiKeyProvider: { AppSettings.shared.getAPIKeyForSelectedModel() },
                        systemPrompt: systemPromptCopy,
                        onNewContent: { newContent in
                            // 累積完整內容
                            correctedText += newContent
                            
                            // 實時更新UI顯示文字流效果
                            Task { @MainActor in
                                // 檢查應用程序是否仍在運行
                                guard NSApp.isRunning else { return }
                                
                                // 獲取當前的 textView
                                if let textView = self.currentTextView {
                                    // 字符級別的逐字顯示新內容
                                    var displayText = correctedText.dropLast(newContent.count) // 移除新內容，從之前的位置開始
                                    
                                    for char in newContent {
                                        // 添加當前字符到顯示文字
                                        displayText += String(char)
                                        
                                        // 清理文字（暫時不清理，避免打斷流效果）
                                        let cleanedText = String(displayText)
                                        
                                        // 設置段落樣式
                                        let paragraphStyle = NSMutableParagraphStyle()
                                        paragraphStyle.lineSpacing = 8
                                        paragraphStyle.lineBreakMode = .byWordWrapping
                                        
                                        // 創建帶樣式的文字
                                        let attributedString = NSAttributedString(
                                            string: cleanedText,
                                            attributes: [
                                                .font: NSFont.systemFont(ofSize: 22),
                                                .foregroundColor: NSColor.white,
                                                .paragraphStyle: paragraphStyle
                                            ]
                                        )
                                        
                                        // 更新文字顯示
                                        textView.textStorage?.setAttributedString(attributedString)
                                        
                                        // 自動滾動到底部
                                        textView.scrollToEndOfDocument(nil)
                                        
                                        // 更新窗口大小
                                        if let windowManager = self.textWindowManager, !windowManager.isDestroyed {
                                            windowManager.resizeWindowToFitContent()
                                        }
                                        
                                        // 等待指定的流動速度時間
                                        try? await Task.sleep(nanoseconds: UInt64(streamingSpeed * 1_000_000_000))
                                        
                                        // 檢查是否仍在運行
                                        guard NSApp.isRunning else { break }
                                    }
                                }
                            }
                        },
                        onError: { error in
                            print("OpenAI API error: \(error)")
                        }
                    )
                    
                    // 清理 LLM 輸出中的 markdown 標記
                    correctedText = extractMarkdownBlock(correctedText)
                    
                    // 等待完整回應後更新 UI（避免 stream 過程中的顯示問題）
                    await MainActor.run {
                        // 檢查應用程序是否仍在運行
                        guard NSApp.isRunning else { return }
                        
                        // 更新處理進度
                        AppState.shared.processingProgress = 0.8
                        
                        // 獲取當前的 textView（如果存在）
                        if let textView = currentTextView {
                            // 設置段落樣式
                            let paragraphStyle = NSMutableParagraphStyle()
                            paragraphStyle.lineSpacing = 8
                            paragraphStyle.lineBreakMode = .byWordWrapping
                            
                            // 使用固定字體大小和樣式
                            let attributedString = NSAttributedString(
                                string: correctedText,
                                attributes: [
                                    .font: NSFont.systemFont(ofSize: 22),
                                    .foregroundColor: NSColor.white,
                                    .paragraphStyle: paragraphStyle
                                ]
                            )
                            
                            // 更新 textView 顯示差異
                            if let windowManager = textWindowManager, !windowManager.isDestroyed {
                                windowManager.updateTextViewWithDiff(
                                    originalText: textToProcess,
                                    newText: correctedText,
                                    textView: textView
                                )
                                
                                // 更新窗口大小以適應內容
                                windowManager.resizeWindowToFitContent()
                            }
                        }
                    }
                    
                    // 完成處理
                    let processingTime = Date().timeIntervalSince(startTime)
                    
                    // 檢查應用程序是否正在運行
                    guard await NSApp.isRunning else {
                        return
                    }
                    
                    // 計算變更的詞數
                    let totalWordsChanged = TextProcessing.calculateChangedWords(
                        original: textToProcess,
                        rewritten: correctedText
                    )
                    
                    // 在主線程執行最終 UI 更新
                    await MainActor.run {
                        // 先存儲 weakSelf 的本地副本
                        guard let localSelf = weakSelf else { return }
                        
                        // 更新 AppState
                        AppState.shared.isProcessing = false
                        AppState.shared.processingProgress = 1.0
                        AppState.shared.lastProcessingTime = processingTime
                        
                        // 更新文本內容
                        AppState.shared.updateTextInfo(original: textToProcess, corrected: correctedText)
                        
                        // 只有當 UI 元素仍然可用時才更新
                        if !localSelf.isTerminating {
                            localSelf.showTextWindowWithDiff(original: textToProcess, rewritten: correctedText)
                            localSelf.logger.debug("文本處理完成，用時: \(String(format: "%.2f", processingTime))秒，變更詞數: \(totalWordsChanged)")
                        }
                    }
                    
                    // 發送系統通知
                    if NSApp.isRunning {
                        Task {
                            do {
                                try await NotificationManager.shared.sendCorrectionCompleteNotification(
                                    originalTextCount: textToProcess.count,
                                    correctedTextCount: correctedText.count,
                                    wordsChanged: 0  // 暫時使用 0，之後可以實現具體的計算
                                )
                            } catch {
                                loggerCopy.error("發送通知失敗: \(error.localizedDescription)")
                            }
                        }
                    }
                } catch {
                    // 錯誤處理
                    await MainActor.run {
                        AppState.shared.isProcessing = false
                        AppState.shared.processingProgress = 0.0
                        
                        if let aiError = error as? OpenAIError {
                            switch aiError {
                            case .invalidAPIKey:
                                AppState.shared.errorMessage = "API 金鑰無效，請檢查設定"
                            case .networkError:
                                AppState.shared.errorMessage = "網路連接錯誤，請檢查網路連接"
                            case .timeout:
                                AppState.shared.errorMessage = "請求超時，請稍後再試"
                            case .modelUnavailable:
                                AppState.shared.errorMessage = "所選模型暫時不可用，請稍後再試"
                            default:
                                AppState.shared.errorMessage = "處理文本時發生錯誤：\(aiError.localizedDescription)"
                            }
                        } else {
                            AppState.shared.errorMessage = "處理文本時發生未知錯誤：\(error.localizedDescription)"
                        }
                        
                        loggerCopy.error("文本處理失敗: \(error.localizedDescription)")
                    }
                }
            }
        }
    }

    // 添加缺少的 showTextWindowWithDiff 方法
    func showTextWindowWithDiff(original: String, rewritten: String) {
        logger.info("顯示文本差異窗口")
        
        // 如果文本窗口已經存在，就更新它
        if let existingWindow = textWindow, let textView = currentTextView {
            textWindowManager.updateTextViewWithDiff(
                originalText: original,
                newText: rewritten,
                textView: textView
            )
            
            // 如果窗口沒有顯示，就顯示它
            if !existingWindow.isVisible {
                existingWindow.makeKeyAndOrderFront(nil)
            }
            
            return
        }

        // 如果還沒有文本窗口，就創建并顯示 SwiftUI 窗口
        showSwiftUITextWindow(text: original)
    }
    
    // 模擬狀態欄點擊
    @objc func statusItemClicked(_ sender: Any?) {
        logger.info("狀態欄被點擊")
    }

    // 當顯示浮動按鈕時，通知AppState和AppKitBridge
    func showFloatingButton() {
        logger.info("嘗試顯示浮動按鈕")
        
        // 如果已有活躍的浮動按鈕，就不再創建新的
        if let existingButton = floatingButton, existingButton.isVisible {
            logger.info("已有活躍的浮動按鈕，不再創建新的")
            
            // 只需重置自動隱藏計時器，讓按鈕保持更長時間
            // 確保在主線程上操作
            Task { @MainActor in
                // 取消現有的隱藏計時器
                NSObject.cancelPreviousPerformRequests(withTarget: self, 
                                                      selector: #selector(hideFloatingButton), 
                                                      object: nil)
                
                // 設置新的自動隱藏計時器
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                    guard let self = self else { return }
                    if let window = self.floatingButton, window.isVisible {
                        self.hideFloatingButton()
                    }
                }
            }
            return
        }

        // 如果浮動按鈕已存在但不可見，先關閉它
        hideFloatingButton()
        
        // 確保沒有現存的浮動按鈕
        if floatingButton != nil {
            logger.warning("舊的浮動按鈕未正確清理，強制清理")
            Task { @MainActor in
                floatingButton?.close()
                floatingButton = nil
            }
        }
        
        // 創建和顯示浮動按鈕 - 確保在主線程上執行
        Task { @MainActor in
            // 獲取當前鼠標位置
            let mouseLocation = NSEvent.mouseLocation
            
            // 創建新的浮動按鈕窗口
            let buttonWindow = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 100, height: 40),
                                       styleMask: [.nonactivatingPanel, .hudWindow],
                                       backing: .buffered,
                                       defer: false)
            buttonWindow.level = .floating
            buttonWindow.isOpaque = false
            buttonWindow.backgroundColor = .clear
            buttonWindow.hasShadow = true
            buttonWindow.isMovable = true  // 允許用戶移動按鈕
            buttonWindow.alphaValue = 0.0  // 初始透明，為動畫做準備
            
            // 創建一個圓角矩形的背景視圖
            let visualEffectView = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: 100, height: 40))
            visualEffectView.material = .hudWindow
            visualEffectView.state = .active
            visualEffectView.wantsLayer = true
            visualEffectView.layer?.cornerRadius = 20  // 完全圓角效果
            visualEffectView.layer?.borderWidth = 1.0
            visualEffectView.layer?.borderColor = NSColor.systemBlue.withAlphaComponent(0.6).cgColor
            
            // 添加漸變效果
            let gradientLayer = CAGradientLayer()
            gradientLayer.frame = visualEffectView.bounds
            gradientLayer.cornerRadius = 20
            gradientLayer.colors = [
                NSColor(calibratedRed: 0.2, green: 0.4, blue: 0.9, alpha: 0.7).cgColor,
                NSColor(calibratedRed: 0.1, green: 0.2, blue: 0.5, alpha: 0.7).cgColor
            ]
            gradientLayer.startPoint = CGPoint(x: 0, y: 0)
            gradientLayer.endPoint = CGPoint(x: 1, y: 1)
            
            visualEffectView.layer?.insertSublayer(gradientLayer, at: 0)
            buttonWindow.contentView?.addSubview(visualEffectView)
            
            // 創建校正圖標
            let iconView = NSImageView(frame: NSRect(x: 10, y: 10, width: 20, height: 20))
            if let iconImage = NSImage(systemSymbolName: "checkmark.bubble.fill", accessibilityDescription: "文字校正") {
                iconView.image = iconImage
                iconView.contentTintColor = NSColor.white
                visualEffectView.addSubview(iconView)
            }
            
            // 創建文字標籤
            let label = NSTextField(labelWithString: "校正文字")
            label.frame = NSRect(x: 35, y: 10, width: 60, height: 20)
            label.textColor = .white
            label.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
            label.alignment = .left
            label.backgroundColor = .clear
            visualEffectView.addSubview(label)
            
            // 創建按鈕 - 覆蓋整個視圖以捕獲點擊
            let button = NSButton(frame: visualEffectView.bounds)
            button.bezelStyle = .roundRect
            button.isBordered = false
            button.title = ""  // 設置空標題，確保不顯示"button"字樣
            button.wantsLayer = true
            button.layer?.backgroundColor = NSColor.clear.cgColor
            button.target = self
            button.action = #selector(self.floatingButtonClicked(_:))
            button.toolTip = "點擊處理剪貼板中的文字"
            visualEffectView.addSubview(button)
            
            // 計算按鈕位置，確保在游標附近但不會超出螢幕邊界
            var positionX = mouseLocation.x - 50 // 按鈕寬度的一半
            var positionY = mouseLocation.y - 50 // 在游標下方一點
            
            // 檢查並調整位置以避免超出螢幕邊界
            if let mainScreen = NSScreen.main {
                let screenFrame = mainScreen.visibleFrame
                
                // 確保不超出右邊界
                if positionX + 100 > screenFrame.maxX {
                    positionX = screenFrame.maxX - 110
                }
                
                // 確保不超出左邊界
                if positionX < screenFrame.minX {
                    positionX = screenFrame.minX + 10
                }
                
                // 確保不超出上邊界
                if positionY + 40 > screenFrame.maxY {
                    positionY = screenFrame.maxY - 50
                }
                
                // 確保不超出下邊界
                if positionY < screenFrame.minY {
                    positionY = screenFrame.minY + 10
                }
            }
            
            // 設置窗口位置
            buttonWindow.setFrameOrigin(NSPoint(x: positionX, y: positionY))
            
            // 添加點擊外部自動關閉的功能
            NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
                guard let self = self else { return }
                if let window = self.floatingButton,
                   window.isVisible,
                   !NSPointInRect(event.locationInWindow, window.frame) {
                    self.hideFloatingButton()
                }
            }
            
            // 顯示窗口
            buttonWindow.orderFront(nil)
            
            // 添加浮動按鈕出現動畫
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                context.allowsImplicitAnimation = true
                buttonWindow.animator().alphaValue = 0.95
                
                // 輕微的彈跳效果
                let scale = CABasicAnimation(keyPath: "transform.scale")
                scale.fromValue = 0.8
                scale.toValue = 1.0
                scale.duration = 0.2
                scale.timingFunction = CAMediaTimingFunction(name: .easeOut)
                visualEffectView.layer?.add(scale, forKey: "scale")
            }
            
            // 設置窗口標識符以方便追蹤
            buttonWindow.title = "TextCorrectionFloatingButton"
            
            // 保存引用
            self.floatingButton = buttonWindow
            
            // 3 秒後自動隱藏
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                guard let self = self else { return }
                // 檢查按鈕窗口是否存在
                if let window = self.floatingButton, window.isVisible {
                    self.hideFloatingButton()
                }
            }
            
            // 更新UI狀態
            AppState.shared.isFloatingButtonVisible = true
            AppKitBridge.shared.notifyWindowStateChanged(type: "floatingButton", isVisible: true)
            
            self.logger.info("浮動按鈕已顯示在游標附近")
        }
    }
    
    // 浮動按鈕點擊處理
    @objc func floatingButtonClicked(_ sender: Any?) {
        logger.info("浮動按鈕被點擊")
        
        // 隱藏浮動按鈕
        hideFloatingButton()
        
        // 複製當前選中的文本 (直接從剪貼板獲取，確保最新)
        let pasteboard = NSPasteboard.general
        guard let clipboardText = pasteboard.string(forType: .string), !clipboardText.isEmpty else {
            logger.warning("剪貼板中沒有文本")
            return
        }
        
        // 立即設置 AppState 的原始文本，確保在任務開始前就準備好
        AppState.shared.originalText = clipboardText
        
        // 確保在主線程上操作 UI
        Task { @MainActor in
            // 先顯示文本校正窗口
            textWindowManager.showTextWindow(text: clipboardText)
            
            // 然後再次確認 AppState 有正確的原始文本
            AppState.shared.originalText = clipboardText
            
            // 現在開始重寫文本
            self.originalText = clipboardText
            rewriteText()
        }
        
        logger.info("開始處理剪貼板文本 - 文本長度: \(clipboardText.count)字符")
    }
    
    // 當隱藏浮動按鈕時，通知AppState和AppKitBridge
    @objc func hideFloatingButton() {
        logger.info("隱藏浮動按鈕")
        
        // 隱藏並釋放浮動按鈕窗口 - 確保在主線程操作
        Task { @MainActor in
            if let button = floatingButton {
                button.close()
                floatingButton = nil
            }
            
            // 更新UI狀態
            AppState.shared.isFloatingButtonVisible = false
            AppKitBridge.shared.notifyWindowStateChanged(type: "floatingButton", isVisible: false)
        }
    }

    // 獲取選中的文本 - 供HotKeyManager使用
    func getSelectedText() -> String? {
        // 從剪貼板獲取文本
        return NSPasteboard.general.string(forType: .string)
    }

    // 使用 SwiftUI 顯示文本校正視窗
    func showSwiftUITextWindow(text: String) {
        // 設置 AppState
        AppState.shared.originalText = text
        AppState.shared.correctedText = ""
        AppState.shared.errorMessage = ""
        AppState.shared.isProcessing = false
        
        // 確保所有 UI 操作在主線程執行
        Task { @MainActor in
            // 如果已有視窗管理器，則使用它來顯示文本視窗
            if let textWindowManager = self.textWindowManager {
                logger.info("使用TextWindowManager顯示文本視窗")
                textWindowManager.showTextWindow(text: text)
                return
            }
            
            // 如果沒有視窗管理器，則繼續創建正常視窗（不再創建額外的AI測豹視窗）
            // 創建 SwiftUI 視圖和託管控制器
            let correctionView = TextCorrectionView()
                .environmentObject(AppState.shared)
            let hostingController = NSHostingController(rootView: correctionView)
            
            // 計算視窗位置和大小
            let screenFrame = NSScreen.main?.visibleFrame ?? NSRect.zero
            let width = screenFrame.width * 0.5
            let height = screenFrame.height * 0.3  // 稍微增加高度
            let origin = NSPoint(
                x: screenFrame.midX - width / 2,
                y: screenFrame.midY - height / 2
            )
            let windowFrame = NSRect(origin: origin, size: NSSize(width: width, height: height))
            
            // 創建視窗
            let window = NSPanel(
                contentRect: windowFrame,
                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            
            window.title = "文本校正"
            window.titlebarAppearsTransparent = true
            window.isMovableByWindowBackground = true
            window.contentView?.wantsLayer = true
            window.isOpaque = false
            window.backgroundColor = .clear
            
            // 為視窗添加漸變背景
            window.contentView?.wantsLayer = true
            let gradient = CAGradientLayer()
            gradient.frame = window.contentView!.bounds
            gradient.colors = [
                NSColor(red: 0.1, green: 0.1, blue: 0.15, alpha: 0.95).cgColor,
                NSColor(red: 0.15, green: 0.15, blue: 0.2, alpha: 0.95).cgColor
            ]
            gradient.locations = [0.0, 1.0]
            window.contentView?.layer?.insertSublayer(gradient, at: 0)
            
            // 設置視窗的最小尺寸
            window.minSize = NSSize(width: 400, height: 300)
            
            // 設置內容控制器和顯示視窗
            window.contentViewController = hostingController
            window.center()
            window.makeKeyAndOrderFront(nil)
            
            // 保存視窗引用
            self.swiftUITextWindow = window
            
            // 開始處理文本
            self.processText(text)
        }
    }

    // 添加 createSettingsWindow 方法
    @MainActor
    private func createSettingsWindow() {
        logger.debug("創建設定視窗")
        
        // 創建 SettingsView 並注入 AppState 環境對象
        let settingsView = SettingsView()
            .environmentObject(AppState.shared)
        
        let hostingController = NSHostingController(rootView: settingsView)
        
        // 查找是否已有同標題窗口存在
        for existingWindow in NSApp.windows where existingWindow.title == "設定" && existingWindow.isVisible {
            existingWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            
            // 確保狀態一致
            AppState.shared.isSettingsWindowOpen = true
            AppKitBridge.shared.notifyWindowStateChanged(type: "settings", isVisible: true)
            
            // 保存已存在的窗口引用
            self.settingsWindow = existingWindow
            return
        }
        
        let newWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 450, height: 600),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        newWindow.title = "設定"
        newWindow.center()
        newWindow.isReleasedWhenClosed = false
        newWindow.delegate = self
        
        newWindow.contentViewController = hostingController
        newWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        
        // 添加窗口關閉通知
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(settingsWindowWillClose(_:)),
            name: NSWindow.willCloseNotification,
            object: newWindow
        )
        
        // 更新狀態
        AppState.shared.isSettingsWindowOpen = true
        AppKitBridge.shared.notifyWindowStateChanged(type: "settings", isVisible: true)
        
        // 設置窗口引用
        self.settingsWindow = newWindow
    }
    
    // 設定窗口關閉時的處理
    @objc private func settingsWindowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              window == self.settingsWindow else {
            return
        }
        
        logger.debug("設定窗口將要關閉")
        AppState.shared.isSettingsWindowOpen = false
        AppKitBridge.shared.notifyWindowStateChanged(type: "settings", isVisible: false)
        settingsWindow = nil
    }

    // 顯示設定視窗
    @objc func showSettings() {
        // 使用 NSHostingController 顯示 SwiftUI 設定視圖
        logger.info("打開設定視窗")
        
        // 確保所有 UI 操作在主線程執行
        Task { @MainActor in
            // 先檢查是否有現有的「設定」窗口已經打開（包括由其他方式創建的）
            for existingWindow in NSApp.windows where existingWindow.title == "設定" && existingWindow.isVisible {
                existingWindow.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
                
                // 確保狀態一致
                AppState.shared.isSettingsWindowOpen = true
                AppKitBridge.shared.notifyWindowStateChanged(type: "settings", isVisible: true)
                return
            }
            
            // 檢查窗口是否已存在
            if self.settingsWindow == nil {
                // 使用新的方法創建窗口
                self.createSettingsWindow()
            } else {
                // 如果窗口已存在，只需要顯示它
                self.settingsWindow?.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
                
                // 確保狀態一致
                AppState.shared.isSettingsWindowOpen = true
                AppKitBridge.shared.notifyWindowStateChanged(type: "settings", isVisible: true)
            }
        }
    }
    
    /// 顯示反饋表單視窗
    @objc func showFeedbackView() {
        logger.info("顯示反饋表單視窗")
        
        // 創建SwiftUI視圖
        let contentView = FeedbackView()
            .environmentObject(AppState.shared)
        
        // 創建視窗
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 580),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        
        // 配置視窗
        window.title = "提交反饋"
        window.center()
        window.contentView = NSHostingView(rootView: contentView)
        window.isReleasedWhenClosed = true
        window.level = .floating
        
        // 顯示視窗
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        
        // 設置狀態
        AppState.shared.isFeedbackViewOpen = true
        
        // 設置關閉回調
        window.delegate = self
    }
    
    // 添加 copyAndPasteRewrittenText 方法，因為 AppKitBridge 中引用了這個方法
    func copyAndPasteRewrittenText() {
        logger.info("複製並貼上重寫文本")
        
        let correctedText = AppState.shared.correctedText
        if correctedText.isEmpty {
            logger.warning("沒有可複製的校正文本")
                return
        }
        
        // 複製到剪貼板
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(correctedText, forType: .string)
        
        logger.info("已複製校正文本到剪貼板")
    }
    
    // 直接處理從熱鍵觸發的選中文本
    @MainActor
    func directlyProcessHotkeySelection(_ text: String) {
        // 確保在主線程上執行，因為這會更新UI
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.directlyProcessHotkeySelection(text)
            }
            return
        }
        
        guard !text.isEmpty else {
            logger.warning("熱鍵觸發處理選中文本，但文本為空")
            
            // 在處理空文本的情況下發送通知
            Task {
                do {
                    try await NotificationManager.shared.sendNotification(
                        title: "無法處理文本",
                        message: "選中的文本為空，請確保已選中文本再使用熱鍵。",
                        type: .warning,
                        delay: 0.1
                    )
                } catch {
                    self.logger.error("發送警告通知時發生錯誤: \(error.localizedDescription)")
                }
            }
            return
        }
        
        logger.info("熱鍵觸發直接處理選中文本，長度: \(text.count)")
        
        // 通知PasteboardManager這是熱鍵觸發，不要顯示浮動按鈕
        NotificationCenter.default.post(name: NSNotification.Name("HotkeyTriggered"), object: nil)
        
        // 保存選中的文本
        lastSelectedText = text
        
        // 使用 autoreleasepool 減少內存壓力
        autoreleasepool {
            // 安全處理：確保文本處理相關的管理器存在
            guard let textWindowManager = self.textWindowManager else {
                logger.error("無法處理文本：TextWindowManager 未初始化")
                return
            }
            
            // 立即設置 AppState 的原始文本，確保在任務開始前就準備好
            AppState.shared.originalText = text
            
            // 確保在主線程上操作 UI
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                
                // 顯示文本窗口
                textWindowManager.showTextWindow(text: text)
                
                // 再次確認 AppState 有正確的原始文本
                AppState.shared.originalText = text
                
                // 設置原始文本
                self.originalText = text
                
                // 開始處理文本前添加安全檢查
                guard self.openAIService != nil else {
                    logger.error("無法處理文本：OpenAIService 未初始化")
                    AppState.shared.errorMessage = "服務未初始化"
                    return
                }
                
                // 延遲一小段時間再開始處理，確保UI已完全更新
                try? await Task.sleep(nanoseconds: 100_000_000) // 0.1秒
                
                // 開始文本處理
                self.rewriteText()
            }
        }
    }

    // 處理文本方法
    func processText(_ text: String) {
        logger.info("開始處理文本，長度: \(text.count)")
        
        // 更新狀態 - 確保在主線程上執行
        DispatchQueue.main.async {
            AppState.shared.isProcessing = true
            AppState.shared.processingProgress = 0.0
            self.logger.info("[處理文本] 已設置處理狀態為true，進度為0.0")
        }
        
        // 使用弱引用避免循環引用
        weak var weakSelf = self
        
        // 模擬進度更新
        var progress: Double = 0.0
        _ = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { timer in
            // 安全地獲取 self
            guard let self = weakSelf else {
                timer.invalidate()
                // 因為self在guard失敗時尚未解包，無法使用，所以改用logger直接記錄
                Logger(subsystem: "com.yourcompany.TextCorrection", category: "AppDelegate")
                    .warning("[處理文本] 無法獲取self引用，計時器已停止")
                return
            }
            
            // 模擬進度增加
            progress += 0.025
            
            // 確保更新在主線程執行
            DispatchQueue.main.async {
                // 再次檢查 self 是否存在
                guard let _ = weakSelf else {
                    timer.invalidate()
                    self.logger.warning("[處理文本] 無法獲取self引用，計時器已停止")
                    return
                }
                
                AppState.shared.processingProgress = min(progress, 0.95)
                
                // 當到達一定進度時，開始模擬API調用完成
                if progress >= 1.0 {
                    timer.invalidate()
                    self.logger.info("[處理文本] 進度達到100%，準備調用completeTextProcessing")
                    self.completeTextProcessing(originalText: text)
                }
            }
        }
    }
    
    // 完成文本處理
    private func completeTextProcessing(originalText: String) {
        logger.info("完成文本處理")
        
        // 處理示例修正 (實際應用中應該使用真實的API調用結果)
        let correctedText = applySimpleCorrections(to: originalText)
        logger.info("[處理文本] 已生成修正文本，長度: \(correctedText.count)")
        
        // 更新狀態
        Task { @MainActor in
            self.logger.info("[處理文本] 在主線程上更新最終狀態")
            AppState.shared.isProcessing = false
            AppState.shared.processingProgress = 1.0
            
            // 將修正後的文本存儲在AppState和AppDelegate中
            AppState.shared.originalText = originalText
            AppState.shared.correctedText = correctedText
            AppState.shared.characterCount = correctedText.count
            
            // 計算處理時間
            let endTime = Date()
            if AppState.shared.lastProcessingTime > 0 {
                // 如果有上次的處理時間，計算時間差
                let processingTime = endTime.timeIntervalSinceReferenceDate - AppState.shared.lastProcessingTime
                logger.debug("文本處理耗時: \(String(format: "%.2f", processingTime))秒")
            }
            // 更新處理時間
            AppState.shared.lastProcessingTime = endTime.timeIntervalSinceReferenceDate
            
            // 啟用特效 (如果已啟用)
            // 特效將在TextCorrectionView中根據AppState.isParticleEffectsEnabled自動顯示
            
            // 更新文本視圖（如果存在）
            if let textView = self.currentTextView, let textWindowManager = self.textWindowManager {
                self.logger.info("[處理文本] 開始更新文本視圖，顯示差異")
                textWindowManager.updateTextViewWithDiff(
                    originalText: originalText,
                    newText: correctedText,
                    textView: textView
                )
                
                // 更新窗口大小以適應內容
                textWindowManager.resizeWindowToFitContent()
                self.logger.info("[處理文本] 文本視圖和窗口大小已更新")
            } else {
                self.logger.warning("[處理文本] 無法更新文本視圖：textView或textWindowManager為nil")
            }
        }
    }
    
    // 簡單的文本修正 (示例用途)
    private func applySimpleCorrections(to text: String) -> String {
        // 這只是一個示例實現，實際應用中應使用AI API或其他更複雜的校正邏輯
        var corrected = text
        
        // 簡單替換一些常見錯誤
        let corrections: [String: String] = [
            "錯別字": "錯別字",
            "而且": "而且",
            "因為": "因為",
            "所以": "所以",
            "會": "會",
            "可以": "可以",
            "有": "有",
            "是": "是",
            "在": "在",
            "把": "把"
        ]
        
        // 隨機選擇1-3個詞進行"校正"，以模擬校正效果
        let count = min(3, text.count / 20 + 1)
        var wordsChanged = 0
        
        for (key, value) in corrections {
            if text.contains(key) && wordsChanged < count {
                // 為了視覺效果，將一些詞"校正"為相同的詞，這樣在差異比較中會顯示出來
                corrected = corrected.replacingOccurrences(of: key, with: value)
                wordsChanged += 1
            }
        }
        
        // 確保至少有些變化，如果沒有找到任何需要替換的詞
        if wordsChanged == 0 && !text.isEmpty {
            // 在文末添加一個句號，如果沒有的話
            if !text.hasSuffix("。") {
                corrected = text + "。"
            } else {
                // 或者將第一個字符改為大寫（如果適用）
                if let firstChar = text.first, firstChar.isLowercase {
                    let index = text.startIndex
                    corrected = text.replacingCharacters(in: index...index, with: String(firstChar).uppercased())
                }
            }
        }
        
        // 記錄修改的字數
        AppState.shared.wordsChanged = wordsChanged
        return corrected
    }
    
    // 應用程式即將終止
    func applicationWillTerminate(_ notification: Notification) {
        // 標記應用程序正在終止
        isTerminating = true
        
        logger.info("應用程式即將終止，清理資源")
        
        // 先釋放文本窗口管理器，確保它的deinit被正確調用
        if textWindow != nil {
            textWindow?.close()
            textWindow = nil
        }
        textWindowManager = nil
        
        // 先停止熱鍵監聽，避免觸發回調而使用已釋放的資源
        hotKeyManager?.disableHotKey()
        hotKeyManager = nil
        
        // 停止剪貼簿監控
        pasteboardManager?.stopMonitoring()
        pasteboardManager = nil
        
        // 清理其他資源
        statusItemManager = nil
        openAIService = nil
        
        // 取消所有訂閱
        cancellables.removeAll()
        
        // 強制執行記憶體釋放
        autoreleasepool {
            NSApp.windows.forEach { $0.close() }
        }
    }

    private func initializeHotKeyManager(appDelegate: AppDelegate) {
        hotKeyManager = HotKeyManager(appDelegate: appDelegate)
        logger.info("熱鍵管理器初始化完成")
    }
    
    // MARK: - 視窗展示方法
    
    /// 顯示歡迎/使用指南視窗
    func showWelcomeView() {
        logger.info("顯示歡迎/使用指南視窗")
        
        // 查找並關閉所有 "WelcomeWindow" 類型的視窗
        for window in NSApp.windows where window.title == "歡迎使用錯字糾正" {
            window.close()
        }
        
        // 如果已有目前的歡迎視窗，關閉它
        if let existingWindow = welcomeWindow {
            existingWindow.close()
            welcomeWindow = nil
        }
        
        // 創建一個新的視窗
        let welcomeView = WelcomeView().environmentObject(AppState.shared)
        let hostingController = NSHostingController(rootView: welcomeView)
        
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 650),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        
        window.center()
        window.setFrameAutosaveName("WelcomeWindow")
        window.title = "歡迎使用錯字糾正"
        window.contentViewController = hostingController
        
        // 存儲窗口引用
        welcomeWindow = window
        
        // 設置窗口關閉時的通知
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(welcomeWindowWillClose(_:)),
            name: NSWindow.willCloseNotification,
            object: window
        )
        
        // 顯示窗口
        window.makeKeyAndOrderFront(nil)
    }
    
    /// 當歡迎窗口關閉時調用
    @objc func welcomeWindowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              window == welcomeWindow else {
            return
        }
        
        // 清除窗口引用
        welcomeWindow = nil
        
        // 標記歡迎頁面已顯示
        AppState.shared.markWelcomeScreenAsShown()
    }

    /// 顯示日誌視圖
    @objc func showLogsView() {
        logger.info("打開日誌視窗")
        
        // 如果日誌窗口已存在，則顯示它
        if let window = logsWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        
        // 創建日誌視圖
        let logsView = LogsView()
        
        // 創建窗口控制器
        let hostingController = NSHostingController(rootView: logsView)
        
        // 創建窗口
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        
        // 設置窗口屬性
        window.title = "應用程式日誌"
        window.contentViewController = hostingController
        window.center()
        window.setFrameAutosaveName("LogsWindow")
        
        // 設置窗口委託，處理窗口關閉事件
        window.delegate = self
        
        // 保存窗口引用
        logsWindow = window
        
        // 顯示窗口
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    /// 創建並分享診斷報告
    @objc func createDiagnosticReport() {
        logger.info("生成診斷報告")
        
        // 顯示等待提示
        let alert = NSAlert()
        alert.messageText = "生成診斷報告"
        alert.informativeText = "正在收集系統信息並創建診斷報告，請稍候..."
        alert.alertStyle = .informational
        
        let progressIndicator = NSProgressIndicator(frame: NSRect(x: 0, y: 0, width: 300, height: 20))
        progressIndicator.style = .bar
        progressIndicator.isIndeterminate = true
        progressIndicator.startAnimation(nil)
        
        alert.accessoryView = progressIndicator
        
        // 創建並顯示提示，但不阻塞用戶操作
        let window = alert.window
        window.level = .floating
        window.orderFront(nil)
        
        // 在後台線程創建診斷報告
        Task {
            if let reportURL = await LogManager.shared.exportDiagnosticReport() {
                // 切換到主線程顯示結果
                await MainActor.run {
                    // 關閉進度提示
                    window.orderOut(nil)
                    
                    // 顯示成功消息並提供打開報告的選項
                    let resultAlert = NSAlert()
                    resultAlert.messageText = "診斷報告已生成"
                    resultAlert.informativeText = "診斷報告已創建，您可以打開報告或將其發送給技術支援人員。"
                    resultAlert.alertStyle = .informational
                    resultAlert.addButton(withTitle: "打開報告位置")
                    resultAlert.addButton(withTitle: "確定")
                    
                    if resultAlert.runModal() == .alertFirstButtonReturn {
                        // 打開包含報告的文件夾
                        NSWorkspace.shared.activateFileViewerSelecting([reportURL])
                    }
                    
                    // 記錄日誌
                    self.logger.info("診斷報告已創建: \(reportURL.path)")
                }
            } else {
                // 處理錯誤
                await MainActor.run {
                    // 關閉進度提示
                    window.orderOut(nil)
                    
                    // 顯示錯誤消息
                    let errorAlert = NSAlert()
                    errorAlert.messageText = "無法創建診斷報告"
                    errorAlert.informativeText = "創建診斷報告時出現錯誤，請稍後再試。"
                    errorAlert.alertStyle = .critical
                    errorAlert.runModal()
                    
                    // 記錄錯誤
                    self.logger.error("創建診斷報告失敗")
                }
            }
        }
    }
}

// MARK: - NSWindowDelegate

extension AppDelegate: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        
        // 識別關閉的窗口
        if window == textWindow {
            self.logger.debug("文本窗口將要關閉")
            AppState.shared.isTextWindowOpen = false
            textWindow = nil
        } else if window == swiftUITextWindow {
            self.logger.debug("SwiftUI 文本窗口將要關閉")
            AppState.shared.isTextWindowOpen = false
            swiftUITextWindow = nil
        } else if window == feedbackWindow {
            self.logger.debug("反饋表單窗口將要關閉")
            AppState.shared.isFeedbackViewOpen = false
            feedbackWindow = nil
        } else if window == welcomeWindow {
            self.logger.debug("歡迎視窗將要關閉")
            AppState.shared.markWelcomeScreenAsShown()
            welcomeWindow = nil
        } else if window == logsWindow {
            self.logger.debug("日誌視窗將要關閉")
            logsWindow = nil
        }
    }
}

// 高效的 StringBuilder 實現，使用陣列累積避免頻繁的字串拼接
private struct StringBuilder {
    private var components: [String] = []
    private let maxCapacity = 10000
    
    var length: Int {
        return components.reduce(0) { $0 + $1.count }
    }
    
    mutating func append(_ string: String) {
        components.append(string)
        
        // 定期合併小段文字避免過多的陣列元素
        if components.count > 100 {
            let joinedString = components.joined()
            components = [joinedString]
            
            // 避免字符串過大導致記憶體問題
            if joinedString.count > maxCapacity {
                let keepLength = Int(Double(maxCapacity) * 0.8)
                let startIndex = joinedString.index(joinedString.endIndex, offsetBy: -keepLength)
                components = [String(joinedString[startIndex...])]
            }
        }
    }
    
    func toString() -> String {
        return components.joined()
    }
    
    mutating func clear() {
        components.removeAll()
    }
}
