//
//  TextCorrectionApp.swift
//  TextCorrection
//
//  Created by 李元魁 on 2024/9/7.
//

import SwiftUI
import Cocoa
import ApplicationServices
import Carbon
import HotKey

func withTimeout<T>(seconds: TimeInterval, operation: @escaping () async throws -> T) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask {
            try await operation()
        }
        
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            throw TextCorrectionError.timeout
        }
        
        let result = try await group.next()!
        group.cancelAll()
        return result
    }
}

@main
struct TextCorrectionApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

struct OpenAIRequest: Encodable {
    let model: String
    let messages: [Message]
    let temperature: Double
    let maxTokens: Int
    let stream: Bool
    
    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case temperature
        case maxTokens = "max_tokens"
        case stream
    }
    
    struct Message: Codable {
        let role: String
        let content: String
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    var floatingButton: NSWindow?
    var textWindow: NSWindow?
    private var lastSelectedText: String?
    private var hotKey: HotKey?
    private var pasteboardObserver: NSObjectProtocol?
    private var lastPasteboardChangeCount: Int = 0
    private var apiKey: String?
    private var isRewriting = false
    private var originalText: String = ""
    
    // 新增顏色常量
    let addedTextColor = NSColor(red: 0.0, green: 0.5, blue: 0.0, alpha: 1.0) // 深綠色
    let deletedTextColor = NSColor(red: 0.8, green: 0.0, blue: 0.0, alpha: 1.0) // 深紅色
    
    private let compareThreshold = 100 // 累積多少字符後進行比較
    
    private var currentTextView: NSTextView?
    private var progressIndicator: NSProgressIndicator?
    private var rewriteButton: NSButton?
    private var copyButton: NSButton?
    private var animationTimer: Timer?
    private var loadingLabel: NSTextField?
    
    private var apiResponseText: String = ""
    private var apiReturnedText: String = ""

    actor RewriteState {
        private var apiReturnedText: String
        private var displayedText: String
        let compareThreshold: Int
        var isShowingRawResponse: Bool

        init(compareThreshold: Int) {
            self.apiReturnedText = ""
            self.displayedText = ""
            self.compareThreshold = compareThreshold
            self.isShowingRawResponse = true
        }

        func update(with newText: String) {
            apiReturnedText += newText
        }

        func getApiReturnedText() -> String {
            return apiReturnedText
        }

        func updateDisplayedText() -> (Bool, String) {
            let newContent = String(apiReturnedText.dropFirst(displayedText.count))
            let shouldUpdate = newContent.count >= compareThreshold
            if shouldUpdate {
                displayedText = apiReturnedText
            }
            return (shouldUpdate, newContent)
        }

        func toggleDisplayMode() {
            isShowingRawResponse.toggle()
        }
    }
    
    private let systemPrompt = """
    你是一名專業的臺灣繁體中文雜誌編輯，幫我檢查給定內容的錯字及語句文法。請特別注意以下規則：
    1. 中文與英文之間，中文與數字之間應有空格，例如 FLAC，JPEG，Google Search Console 。
    2. 以下情況不需調整：
       - 括弧內的說明，例如（圖一）、（加入產品圖示）。
       - 阿拉伯數字不用調整成中文。
       - 英文不一定要翻成中文。
       - emoji 或特殊符號是為了增加閱讀體驗，也不必調整。
    3. 請保留原文的段落和換行格式
    4. 請不要使用額外的 Markdown 語法。
    5. 請仔細審視給定的文字，將冗詞語法錯誤進行修改。
    6. 返回文字不要帶有 <text> 標籤。
    """
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        requestAccessibilityPermission()
        setupStatusItem()
        setupHotKey()
        setupPasteboardObserver()
        loadApiKey()
    }

    func requestAccessibilityPermission() {
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as NSString: true]
        let accessibilityEnabled = AXIsProcessTrustedWithOptions(options)
        
        if !accessibilityEnabled {
            print("請在系統偏好設置中啟用輔助功權限")
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = "要輔助功能權限"
                alert.informativeText = "請在系統好設為 TextCorrection 啟功能權限，便應用程序能夠正常工作。"
                alert.addButton(withTitle: "打開系統偏好設置")
                alert.addButton(withTitle: "取消")
                
                if alert.runModal() == .alertFirstButtonReturn {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                }
            }
        }
    }

    func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "text.quote", accessibilityDescription: "文字校正")
            button.action = #selector(statusItemClicked)
            button.target = self
        }
    }

    @objc func statusItemClicked() {
        if let event = NSApp.currentEvent, event.modifierFlags.contains(.option) {
            showPreferences()
        } else {
            copyAndRewriteSelectedText()
        }
    }

    func showPreferences() {
        // 現偏好設置視窗
    }

    func setupHotKey() {
        hotKey = HotKey(key: .space, modifiers: [.control, .shift])
        hotKey?.keyDownHandler = { [weak self] in
            self?.copyAndRewriteSelectedText()
        }
    }

    func setupPasteboardObserver() {
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] timer in
            DispatchQueue.global(qos: .userInitiated).async {
                if NSPasteboard.general.changeCount != self?.lastPasteboardChangeCount {
                    self?.lastPasteboardChangeCount = NSPasteboard.general.changeCount
                    DispatchQueue.main.async {
                        self?.showFloatingButton()
                    }
                }
            }
        }
    }

    func showFloatingButton() {
        if floatingButton == nil {
            let buttonWindow = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 30, height: 30),
                                       styleMask: [.nonactivatingPanel, .hudWindow],
                                       backing: .buffered,
                                       defer: false)
            buttonWindow.level = .floating
            buttonWindow.isOpaque = false
            buttonWindow.backgroundColor = .clear

            let button = NSButton(frame: NSRect(x: 0, y: 0, width: 30, height: 30))
            button.bezelStyle = .circular
            button.image = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: "複製")
            button.target = self
            button.action = #selector(showCopiedText)

            buttonWindow.contentView?.addSubview(button)
            floatingButton = buttonWindow
        }

        let mouseLocation = NSEvent.mouseLocation
        floatingButton?.setFrameOrigin(NSPoint(x: mouseLocation.x, y: mouseLocation.y - 40))
        floatingButton?.orderFront(nil)
        
        // 設個定時器，在5秒後自動隱藏按鈕
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            self?.hideFloatingButton()
        }
    }

    func hideFloatingButton() {
        floatingButton?.orderOut(nil)
    }

    @objc func showCopiedText() {
        if let copiedString = NSPasteboard.general.string(forType: .string) {
            showTextWindow(text: copiedString)
        } else {
            print("無法獲取剪貼板內容")
        }
        hideFloatingButton()
    }

    func copyAndRewriteSelectedText() {
        if let selectedText = getSelectedText() {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(selectedText, forType: .string)
            showTextWindow(text: selectedText)
        } else {
            print("無法獲取選中的文字")
        }
    }

    func getSelectedText() -> String? {
        let pasteboard = NSPasteboard.general
        let oldContents = pasteboard.string(forType: .string)
        
        let keyCode = UInt16(8) // 'C' key
        let source = CGEventSource(stateID: .hidSystemState)
        
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        
        keyDown?.flags = .maskCommand
        keyUp?.flags = .maskCommand
        
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
        
        // 給系統一些時間來處理複製操作
        Thread.sleep(forTimeInterval: 0.1)
        
        let newContents = pasteboard.string(forType: .string)
        
        return newContents != oldContents ? newContents : nil
    }

    func showTextWindow(text: String) {
        if textWindow == nil {
            textWindow = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 600, height: 500),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable],
                                  backing: .buffered, defer: false)
            textWindow?.title = "文字比較"
            textWindow?.minSize = NSSize(width: 400, height: 300)
        }
        
        let scrollView = NSScrollView(frame: (textWindow?.contentView?.bounds)!)
        scrollView.hasVerticalScroller = true
        scrollView.autoresizingMask = [.width, .height]
        
        let textView = NSTextView(frame: scrollView.bounds)
        textView.autoresizingMask = [.width, .height]
        textView.font = NSFont.systemFont(ofSize: 16)
        textView.string = ""  // 初始時不顯示文字
        textView.isEditable = false
        scrollView.documentView = textView
        
        let rewriteButton = NSButton(frame: NSRect(x: 10, y: 10, width: 120, height: 40))
        rewriteButton.title = "重寫文字"
        rewriteButton.bezelStyle = .rounded
        rewriteButton.font = NSFont.boldSystemFont(ofSize: 16)
        rewriteButton.target = self
        rewriteButton.action = #selector(rewriteText)
        rewriteButton.isHidden = true  // 初始時隱藏重寫按鈕

        let copyButton = NSButton(frame: NSRect(x: 10, y: 10, width: 120, height: 40))
        copyButton.title = "複製文字"
        copyButton.bezelStyle = .rounded
        copyButton.font = NSFont.boldSystemFont(ofSize: 16)
        copyButton.target = self
        copyButton.action = #selector(copyRewrittenText)
        copyButton.isHidden = true  // 初始時隱藏複製按鈕

        let loadingLabel = NSTextField(frame: NSRect(x: 10, y: 10, width: 120, height: 40))
        loadingLabel.stringValue = "AI 校正中..."
        loadingLabel.isEditable = false
        loadingLabel.isBordered = false
        loadingLabel.backgroundColor = .clear
        loadingLabel.alignment = .center
        loadingLabel.font = NSFont.boldSystemFont(ofSize: 16)
        loadingLabel.textColor = .gray

        let progressIndicator = NSProgressIndicator(frame: NSRect(x: 0, y: 0, width: 200, height: 20))
        progressIndicator.style = .bar
        progressIndicator.isIndeterminate = false
        progressIndicator.minValue = 0
        progressIndicator.maxValue = 100
        progressIndicator.doubleValue = 0

        let stackView = NSStackView(frame: (textWindow?.contentView?.bounds)!)
        stackView.orientation = .vertical
        stackView.spacing = 20
        stackView.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        stackView.addArrangedSubview(scrollView)
        stackView.addArrangedSubview(loadingLabel)
        stackView.addArrangedSubview(rewriteButton)
        stackView.addArrangedSubview(copyButton)
        stackView.addArrangedSubview(progressIndicator)
        
        stackView.setHuggingPriority(.defaultLow, for: .horizontal)
        stackView.setHuggingPriority(.defaultLow, for: .vertical)
        
        textWindow?.contentView?.subviews.forEach { $0.removeFromSuperview() }
        textWindow?.contentView?.addSubview(stackView)
        textWindow?.makeKeyAndOrderFront(nil)
        textWindow?.level = .floating
        NSApp.activate(ignoringOtherApps: true)
        
        self.currentTextView = textView
        self.originalText = text
        self.progressIndicator = progressIndicator
        self.rewriteButton = rewriteButton
        self.copyButton = copyButton
        self.loadingLabel = loadingLabel
        
        rewriteText()  // 自動開始重寫
    }

    @objc func rewriteText() {
        guard let textView = currentTextView, !isRewriting else {
            print("正在重寫中，請稍候...")
            return
        }
        
        guard !originalText.isEmpty else {
            print("錯誤：原始文字為空")
            return
        }
        
        isRewriting = true
        print("開始重寫文字，原始文字長度：\(originalText.count)")
        
        Task { [weak self] in
            guard let self = self else { return }
            do {
                await MainActor.run {
                    self.loadingLabel?.isHidden = false
                    self.rewriteButton?.isHidden = true
                    self.copyButton?.isHidden = true
                    self.progressIndicator?.doubleValue = 5
                }
                print("調用 OpenAI API...")
                
                self.apiReturnedText = ""  // 重置 API 返回的文字
                
                try await withTimeout(seconds: 30) {
                    try await self.streamOpenAiApi(text: self.originalText) { rewrittenText in
                        Task {
                            await MainActor.run {
                                self.apiReturnedText += rewrittenText
                                self.updateStreamText(textView: textView, newText: rewrittenText)
                                self.updateProgress()
                            }
                        }
                    }
                }
                
                print("API 返回的文字長度：\(self.apiReturnedText.count)")
                
                // 在這裡添加一個小延遲，確保所有更新都已完成
                try await Task.sleep(nanoseconds: 500_000_000)  // 0.5 秒延遲

                // API 返回完整結果後，進行比較並呈現結果
                await self.showComparisonResults(textView: textView)
                
                await MainActor.run {
                    self.isRewriting = false
                    self.loadingLabel?.isHidden = true
                    self.rewriteButton?.isHidden = true
                    self.copyButton?.isHidden = false
                }
                print("文字重寫完成")
            } catch {
                print("重寫文字時發生錯誤: \(error)")
                await MainActor.run {
                    self.showErrorAlert(message: "重寫文字時發生錯誤：\(error.localizedDescription)")
                    self.isRewriting = false
                    self.loadingLabel?.isHidden = true
                    self.rewriteButton?.isHidden = false
                    self.copyButton?.isHidden = true
                }
            }
        }
    }

    func updateStreamText(textView: NSTextView, newText: String) {
        let attributedString = NSAttributedString(string: newText, attributes: [
            .font: NSFont.systemFont(ofSize: 16),
            .foregroundColor: NSColor.textColor
        ])
        textView.textStorage?.append(attributedString)
        textView.scrollToEndOfDocument(nil)
    }

    func showComparisonResults(textView: NSTextView) async {
        guard !apiReturnedText.isEmpty else {
            print("錯誤：API 返回的文字為空")
            await MainActor.run {
                textView.string = "錯誤：API 未返回任何文字"
            }
            return
        }
        
        let originalTextCopy = self.originalText
        let apiReturnedTextCopy = self.apiReturnedText
        
        await MainActor.run {
            let comparisonResult = self.compareTexts(original: originalTextCopy, rewritten: apiReturnedTextCopy)
            print("比較結果的長度：\(comparisonResult.length)")
            textView.textStorage?.setAttributedString(comparisonResult)
            textView.scrollToEndOfDocument(nil)
        }
    }

    @objc func copyRewrittenText() {
        guard !apiReturnedText.isEmpty else {
            print("錯誤：API 返回的文字為空")
            return
        }
        
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(apiReturnedText, forType: .string)
        print("已複製 API 返回的糾正後文字")
        
        // 添加視覺反饋
        DispatchQueue.main.async {
            self.copyButton?.title = "已複製"
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                self.copyButton?.title = "複製文字"
            }
        }
    }

    func updateProgress() {
        let progress = Double(self.apiReturnedText.count) / Double(originalText.count) * 100
        self.progressIndicator?.doubleValue = min(progress, 100)
    }

    func streamOpenAiApi(text: String, onUpdate: @escaping (String) -> Void) async throws {
        guard let apiKey = self.apiKey else {
            throw TextCorrectionError.apiKeyNotSet
        }

        print("準備 API 請求...")
        
        let request = OpenAIRequest(
            model: "gpt-4o-mini",
            messages: [
                OpenAIRequest.Message(role: "system", content: systemPrompt),
                OpenAIRequest.Message(role: "user", content: "請將以下文字複寫，只需改掉錯字及語句不通順的地方。\n\n<text>\n\(text)\n</text>")
            ],
            temperature: 0.7,
            maxTokens: 1000,
            stream: true
        )

        let url = URL(string: "https://api.openai.com/v1/chat/completions")!
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.addValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let encoder = JSONEncoder()
        do {
            urlRequest.httpBody = try encoder.encode(request)
        } catch {
            print("編碼請求時發生錯誤：\(error)")
            throw TextCorrectionError.encodingError
        }

        print("發送 API 請求...")
        let (bytes, response) = try await URLSession.shared.bytes(for: urlRequest)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw TextCorrectionError.invalidResponse
        }
        
        print("收到 API 響應，狀態碼：\(httpResponse.statusCode)")
        
        guard httpResponse.statusCode == 200 else {
            throw TextCorrectionError.apiError(statusCode: httpResponse.statusCode)
        }
        
        print("開始解析流式響應...")
        var fullContent = ""
        for try await line in bytes.lines {
            if line.hasPrefix("data: "), let data = line.dropFirst(6).data(using: .utf8) {
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let choices = json["choices"] as? [[String: Any]],
                   let delta = choices.first?["delta"] as? [String: String],
                   let content = delta["content"] {
                    fullContent += content
                    onUpdate(content)
                }
            }
        }
        
        // 在這裡添加一個最終的更新，確保使用完整的內容
        onUpdate("\n")  // 添加一個換行符來觸發最後一次更新
        
        print("成功獲取重寫後的文字，總長度：\(fullContent.count)")
    }

    func showErrorAlert(message: String) {
        let alert = NSAlert()
        alert.messageText = "錯誤"
        alert.informativeText = message
        alert.addButton(withTitle: "確定")
        alert.runModal()
    }

    func loadApiKey() {
        if let apiKey = ProcessInfo.processInfo.environment["OPENAI_API_KEY"] {
            self.apiKey = apiKey
        } else {
            print("警告：未找到 OPENAI_API_KEY 環境變數")
            DispatchQueue.main.async {
                self.showErrorAlert(message: "未找到 OpenAI API 金鑰，請設置 OPENAI_API_KEY 環境變數")
            }
        }
    }

    deinit {
        if let observer = pasteboardObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    func compareTexts(original: String, rewritten: String) -> NSAttributedString {
        let attributedString = NSMutableAttributedString()
        
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 5 // 增加行間距
        
        let baseAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 16),
            .paragraphStyle: paragraphStyle
        ]
        
        let diff = diffStrings(original, rewritten)
        
        for change in diff {
            switch change {
            case .equal(let text):
                attributedString.append(NSAttributedString(string: text, attributes: baseAttributes))
            case .insert(let text):
                var attributes = baseAttributes
                attributes[.foregroundColor] = addedTextColor
                attributes[.backgroundColor] = addedTextColor.withAlphaComponent(0.1)
                attributedString.append(NSAttributedString(string: text, attributes: attributes))
            case .delete(let text):
                var attributes = baseAttributes
                attributes[.foregroundColor] = deletedTextColor
                attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
                attributes[.backgroundColor] = deletedTextColor.withAlphaComponent(0.1)
                attributedString.append(NSAttributedString(string: text, attributes: attributes))
            }
        }
        
        return attributedString
    }

    enum DiffChange {
        case equal(String)
        case insert(String)
        case delete(String)
    }

    func diffStrings(_ old: String, _ new: String) -> [DiffChange] {
        let oldChars = Array(old)
        let newChars = Array(new)
        let m = oldChars.count
        let n = newChars.count
        
        var dp = Array(repeating: Array(repeating: 0, count: n + 1), count: m + 1)
        
        for i in 1...m {
            for j in 1...n {
                if oldChars[i-1] == newChars[j-1] {
                    dp[i][j] = dp[i-1][j-1] + 1
                } else {
                    dp[i][j] = max(dp[i-1][j], dp[i][j-1])
                }
            }
        }
        
        var diff = [DiffChange]()
        var i = m, j = n
        
        while i > 0 || j > 0 {
            if i > 0 && j > 0 && oldChars[i-1] == newChars[j-1] {
                diff.insert(.equal(String(oldChars[i-1])), at: 0)
                i -= 1
                j -= 1
            } else if j > 0 && (i == 0 || dp[i][j-1] >= dp[i-1][j]) {
                diff.insert(.insert(String(newChars[j-1])), at: 0)
                j -= 1
            } else {
                diff.insert(.delete(String(oldChars[i-1])), at: 0)
                i -= 1
            }
        }
        
        return diff
    }
}

extension Notification.Name {
    static let didSelectText = Notification.Name("didSelectText")
}

struct OpenAIResponse: Codable {
    let choices: [Choice]
}

struct Choice: Codable {
    let message: Message
}

struct Message: Codable {
    let content: String
}

enum TextCorrectionError: Error {
    case apiKeyNotSet
    case invalidResponse
    case apiError(statusCode: Int)
    case timeout
    case encodingError
}
