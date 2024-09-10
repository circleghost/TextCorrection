import Cocoa
import SwiftUI
import Carbon
import HotKey

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItemManager: StatusItemManager!
    var hotKeyManager: HotKeyManager!
    var pasteboardManager: PasteboardManager!
    var textWindowManager: TextWindowManager!
    var openAIService: OpenAIService!
    
    var floatingButton: NSWindow?
    var textWindow: NSWindow?
    private var lastSelectedText: String?
    private var isRewriting = false
    private var originalText: String = ""
    
    // 新增顏色常量
    let addedTextColor = NSColor(red: 0.0, green: 0.5, blue: 0.0, alpha: 1.0) // 深綠色
    let deletedTextColor = NSColor(red: 0.8, green: 0.0, blue: 0.0, alpha: 1.0) // 深紅色
    
    private let compareThreshold = 100 // 累積多少字符後進行比較
    
    var currentTextView: NSTextView?
    var copyButton: NSButton?
    var statsView: NSTextField?
    var shortcutView: NSTextField?
    
    private var apiResponseText: String = ""
    private var apiReturnedText: String = ""

    let customFont: NSFont

    private let systemPrompt = """
    你是一名專業的台灣繁體中文雜誌編輯，幫我檢查給定內容的錯字及語句文法。請特別注意以下規則：
    1. 中文與英文之間，中文與數字之間應有空格，例如 FLAC，JPEG，Google Search Console 。
    2. 以下情況不需調整：
       - 括弧內的說明，例如（圖一）、（加入產品圖示）。
       - 阿拉伯數字不用調整成中文。
       - 英文不一定要翻成中文。
       - emoji 或特殊符號是為了增加閱讀體驗，也不必調整。
    3. 請保留原文的段落和換行格式
    4. 請不要使用額外的 Markdown 語法。
    5. 請仔細審視給定的文字，將冗詞語法錯誤進行��改。
    6. 返回文字不要帶有 <text> 標籤。
    """

    override init() {
        self.customFont = NSFont(name: "Yuanti TC", size: 19) ?? NSFont.systemFont(ofSize: 19)
        super.init()
    }
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        AccessibilityManager.requestAccessibilityPermission()
        
        statusItemManager = StatusItemManager(appDelegate: self)
        statusItemManager.setupStatusItem()
        
        hotKeyManager = HotKeyManager(appDelegate: self)
        hotKeyManager.setupHotKey()
        
        pasteboardManager = PasteboardManager(appDelegate: self)
        pasteboardManager.setupPasteboardObserver()
        
        textWindowManager = TextWindowManager(appDelegate: self)
        
        loadApiKey()
    }

    private func loadApiKey() {
        if let apiKey = ProcessInfo.processInfo.environment["OPENAI_API_KEY"] {
            print("API Key loaded: \(apiKey.prefix(5))...") // 只打印前5個字符，以保護密鑰
            self.openAIService = OpenAIService(apiKey: apiKey, systemPrompt: systemPrompt)
        } else {
            print("警告：未找到 OPENAI_API_KEY 環境變數")
            DispatchQueue.main.async {
                self.showErrorAlert(message: "未找到 OpenAI API 金鑰，請設置 OPENAI_API_KEY 環境變數")
            }
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
        // 顯示偏好設置視窗
        print("顯示偏好設置視窗")
    }

    func copyAndRewriteSelectedText() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            if let selectedText = self?.getSelectedText() {
                DispatchQueue.main.async {
                    self?.resetState()
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(selectedText, forType: .string)
                    self?.textWindowManager.showTextWindow(text: selectedText)
                }
            } else {
                print("無法獲取選中文字")
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
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            self?.hideFloatingButton()
        }
    }

    func showErrorAlert(message: String) {
        let alert = NSAlert()
        alert.messageText = "錯誤"
        alert.informativeText = message
        alert.addButton(withTitle: "確定")
        alert.runModal()
    }

    @objc func showCopiedText() {
        if let copiedString = NSPasteboard.general.string(forType: .string) {
            textWindowManager.showTextWindow(text: copiedString)
        } else {
            print("無法獲取剪貼板內容")
        }
        hideFloatingButton()
    }

    func hideFloatingButton() {
        floatingButton?.orderOut(nil)
    }

    func resetState() {
        self.apiReturnedText = ""
        self.originalText = ""
        self.currentTextView?.string = ""
        self.statsView?.stringValue = ""
        self.shortcutView?.stringValue = ""
    }

    func getSelectedText() -> String? {
        let pasteboard = NSPasteboard.general
        let oldContents = pasteboard.string(forType: .string)
        
        let source = CGEventSource(stateID: .hidSystemState)
        
        let cmdDown = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: true)
        let cDown = CGEvent(keyboardEventSource: source, virtualKey: 0x08, keyDown: true)
        let cUp = CGEvent(keyboardEventSource: source, virtualKey: 0x08, keyDown: false)
        let cmdUp = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: false)
        
        cmdDown?.flags = .maskCommand
        cDown?.flags = .maskCommand
        cUp?.flags = .maskCommand
        cmdUp?.flags = .maskCommand
        
        cmdDown?.post(tap: .cghidEventTap)
        cDown?.post(tap: .cghidEventTap)
        cUp?.post(tap: .cghidEventTap)
        cmdUp?.post(tap: .cghidEventTap)
        
        Thread.sleep(forTimeInterval: 0.1)
        
        let newContents = pasteboard.string(forType: .string)
        
        if newContents != oldContents {
            return newContents
        }
        
        print("無法獲取選中的文字")
        return nil
    }

    func rewriteText() {
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
        
        self.apiReturnedText = ""
        textView.string = ""
        
        Task { [weak self] in
            guard let self = self else { return }
            do {
                print("調用 OpenAI API...")
                
                try await withTimeout(seconds: 30) {
                    try await self.openAIService.streamOpenAiApi(text: self.originalText) { rewrittenText in
                        Task {
                            await MainActor.run {
                                self.apiReturnedText += rewrittenText
                                self.updateStreamText(textView: textView, newText: rewrittenText)
                            }
                        }
                    }
                }
                
                print("API 返回的文字長度：\(self.apiReturnedText.count)")
                
                try await Task.sleep(nanoseconds: 500_000_000)  // 0.5 秒延遲

                await self.showComparisonResults(textView: textView)
                self.updateStats(rewrittenText: self.apiReturnedText)
                
                await MainActor.run {
                    self.isRewriting = false
                }
                print("文字重寫完成")
            } catch {
                print("重寫文字時發生錯誤: \(error)")
                await MainActor.run {
                    self.showErrorAlert(message: "重寫文字時發生錯誤：\(error.localizedDescription)")
                    self.isRewriting = false
                }
            }
        }
    }

    func updateStreamText(textView: NSTextView, newText: String) {
        let trimmedText = trimExtraWhitespace(newText)
        let attributedString = NSAttributedString(string: trimmedText, attributes: [
            .font: self.customFont,
            .foregroundColor: NSColor.white,
            .kern: 1.0  // 增加字距
        ])
        textView.textStorage?.append(attributedString)
        textView.scrollToEndOfDocument(nil)
        
        if let textContainer = textView.enclosingScrollView?.superview,
           let mainArea = textContainer.superview {
            adjustTextContainerHeight(textView: textView, textContainer: textContainer, mainArea: mainArea)
        }
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
        let apiReturnedTextCopy = trimExtraWhitespace(self.apiReturnedText)
        
        await MainActor.run {
            let comparisonResult = TextProcessing.compareTexts(original: originalTextCopy, rewritten: apiReturnedTextCopy, customFont: self.customFont)
            print("比較結果的長度：\(comparisonResult.length)")
            textView.textStorage?.setAttributedString(comparisonResult)
            textView.scrollToEndOfDocument(nil)
            
            if let textContainer = textView.enclosingScrollView?.superview,
               let mainArea = textContainer.superview {
                self.adjustTextContainerHeight(textView: textView, textContainer: textContainer, mainArea: mainArea)
            }
        }
    }

    @objc func copyAndPasteRewrittenText() {
        guard !apiReturnedText.isEmpty else {
            print("錯誤：API 返回的文字為空")
            return
        }
        
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(apiReturnedText, forType: .string)
        print("已複製 API 返回的糾正後文字")
        
        let source = CGEventSource(stateID: .hidSystemState)
        let cmdDown = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: true)
        let vDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true)
        let vUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
        let cmdUp = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: false)
        
        cmdDown?.flags = .maskCommand
        vDown?.flags = .maskCommand
        vUp?.flags = .maskCommand
        cmdUp?.flags = .maskCommand
        
        cmdDown?.post(tap: .cghidEventTap)
        vDown?.post(tap: .cghidEventTap)
        vUp?.post(tap: .cghidEventTap)
        cmdUp?.post(tap: .cghidEventTap)
        
        DispatchQueue.main.async {
            self.copyButton?.title = "已複製並貼上"
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                self.copyButton?.title = "複製並貼上"
            }
        }
    }

    func updateStats(rewrittenText: String) {
        let rewrittenCharCount = rewrittenText.count
        let changesCount = calculateChanges(rewritten: rewrittenText)
        
        DispatchQueue.main.async {
            self.statsView?.stringValue = "字元數: \(rewrittenCharCount) | 改變: \(changesCount) | 模型: GPT-4o-mini"
        }
    }

    func calculateChanges(rewritten: String) -> Int {
        let diff = TextProcessing.diffStrings(originalText, rewritten)
        var changesCount = 0
        
        for change in diff {
            switch change {
            case .insert, .delete:
                changesCount += 1
            case .equal:
                continue
            }
        }
        
        return changesCount
    }

    @objc func textDidChange(_ notification: Notification) {
        guard let textView = notification.object as? NSTextView,
              let textContainer = textView.superview?.superview,
              let mainArea = textContainer.superview else {
            return
        }

        adjustTextContainerHeight(textView: textView, textContainer: textContainer, mainArea: mainArea)
    }

    @objc func windowDidResize(_ notification: Notification) {
        if let window = notification.object as? NSWindow,
           let contentView = window.contentView,
           let mainArea = contentView.subviews.first(where: { $0.identifier?.rawValue == "mainArea" }),
           let textContainer = mainArea.subviews.first(where: { $0.identifier?.rawValue == "textContainer" }),
           let scrollView = textContainer.subviews.first as? NSScrollView,
           let textView = scrollView.documentView as? NSTextView {
            adjustTextContainerHeight(textView: textView, textContainer: textContainer, mainArea: mainArea)
        }
    }

    func adjustTextContainerHeight(textView: NSTextView, textContainer: NSView, mainArea: NSView) {
        let contentSize = textView.layoutManager?.usedRect(for: textView.textContainer!).size ?? .zero
        let newHeight = max(contentSize.height + 30, 100) // 設置最小高度為 100

        textView.frame.size.height = contentSize.height
        
        if let scrollView = textView.enclosingScrollView {
            scrollView.documentView?.frame.size = CGSize(width: contentSize.width, height: contentSize.height)
        }

        // 更新 textContainer 的高度約束
        if let heightConstraint = textContainer.constraints.first(where: { $0.firstAttribute == .height }) {
            let oldHeight = heightConstraint.constant
            heightConstraint.constant = newHeight
            
            // 計算高度變化
            let heightDifference = newHeight - oldHeight
            
            // 調整視窗大小
            if let window = textView.window {
                var frame = window.frame
                frame.size.height += heightDifference
                frame.origin.y -= heightDifference // 保持視窗頂部位置不變
                window.setFrame(frame, display: true, animate: true)
            }
        } else {
            let heightConstraint = textContainer.heightAnchor.constraint(equalToConstant: newHeight)
            heightConstraint.priority = .defaultHigh
            heightConstraint.isActive = true
        }

        mainArea.layoutSubtreeIfNeeded()
        
        // 確保字體正確應用
        textView.font = self.customFont
    }

    func resetWindowState() {
        textWindow?.close()
        textWindow = nil
        currentTextView = nil
        copyButton = nil
        statsView = nil
        shortcutView = nil
        apiReturnedText = ""
        originalText = ""
    }

    // 新增以下方法
    func setTextViewComponents(textView: NSTextView, originalText: String, copyButton: NSButton, statsView: NSTextField, shortcutView: NSTextField) {
        self.currentTextView = textView
        self.originalText = originalText
        self.copyButton = copyButton
        self.statsView = statsView
        self.shortcutView = shortcutView
    }
}