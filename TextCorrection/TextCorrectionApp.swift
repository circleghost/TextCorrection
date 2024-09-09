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

extension NSColor {
    convenience init?(hexString: String) {
        let hex = hexString.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int = UInt64()
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            return nil
        }
        self.init(red: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: CGFloat(a) / 255)
    }
}

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

func trimExtraWhitespace(_ text: String) -> String {
    return text.trimmingCharacters(in: .whitespacesAndNewlines)
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
    
    // 新增顏色常
    let addedTextColor = NSColor(red: 0.0, green: 0.5, blue: 0.0, alpha: 1.0) // 深綠色
    let deletedTextColor = NSColor(red: 0.8, green: 0.0, blue: 0.0, alpha: 1.0) // 深紅色
    
    private let compareThreshold = 100 // 累積多少字符後進行比較
    
    private var currentTextView: NSTextView?
    private var copyButton: NSButton?
    private var statsView: NSTextField?
    
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
    1. 中文與英文之間，中字之間應有空格，例如 FLAC，JPEG，Google Search Console 。
    2. 以下情調整：
       - 括弧內的說明，例如圖一）、（加入產品圖示）。
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
            print("請在統偏好設置中啟用助功權限")
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = "要輔助功能權限"
                alert.informativeText = "請在統好設 TextCorrection 功能權限，便應用程序能夠正常工作。"
                alert.addButton(withTitle: "打開統偏好設置")
                alert.addButton(withTitle: "消")
                
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
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            if let selectedText = self?.getSelectedText() {
                DispatchQueue.main.async {
                    // 重置舊的狀態
                    self?.resetState()
                    
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(selectedText, forType: .string)
                    self?.showTextWindow(text: selectedText)
                }
            } else {
                print("無法獲取選中文字")
            }
        }
    }

    func resetState() {
        self.apiReturnedText = ""
        self.originalText = ""
        self.currentTextView?.string = ""
        self.statsView?.stringValue = ""
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

    func showTextWindow(text: String) {
        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect.zero
        
        // 設定視窗大小為螢幕的 60%
        let width = screenFrame.width * 0.6
        let height = screenFrame.height * 0.6
        let size = NSSize(width: width, height: height)
        
        let mouseLocation = NSEvent.mouseLocation
        let windowFrame = NSRect(origin: mouseLocation, size: size)
        let adjustedFrame = screenFrame.intersection(windowFrame)
        
        if textWindow == nil {
            textWindow = NSPanel(contentRect: adjustedFrame,
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                                  backing: .buffered, defer: false)
            textWindow?.title = "AI 文字檢查"
            textWindow?.titlebarAppearsTransparent = false
            textWindow?.isMovableByWindowBackground = true
            
            // 添加霧化效果
            let visualEffect = NSVisualEffectView(frame: adjustedFrame)
            visualEffect.material = .windowBackground
            visualEffect.state = .active
            visualEffect.blendingMode = .behindWindow
            
            textWindow?.contentView = visualEffect
            textWindow?.backgroundColor = NSColor(hexString: "#1E1E26")?.withAlphaComponent(0.6) ?? .black.withAlphaComponent(0.6)
            
            textWindow?.minSize = NSSize(width: 400, height: 300)
            textWindow?.isOpaque = false
            textWindow?.hasShadow = true
            textWindow?.appearance = NSAppearance(named: .darkAqua)
            
            // 設置標題字體和大小
            if let titleFont = NSFont(name: "仓耳今楷01-W05", size: 18) {
                textWindow?.standardWindowButton(.closeButton)?.superview?.subviews.forEach { $0.removeFromSuperview() }
                textWindow?.title = "AI 文字檢查"
                textWindow?.titleVisibility = .visible
                textWindow?.titlebarAppearsTransparent = false
                textWindow?.styleMask.insert(.titled)
                textWindow?.standardWindowButton(.closeButton)?.superview?.layer?.backgroundColor = NSColor(hexString: "#1E1E26")?.cgColor
                
                if let titleView = textWindow?.standardWindowButton(.closeButton)?.superview {
                    titleView.wantsLayer = true
                    titleView.layer?.backgroundColor = NSColor(hexString: "#1E1E26")?.cgColor
                    
                    let titleLabel = NSTextField(frame: NSRect(x: 0, y: 0, width: titleView.frame.width, height: titleView.frame.height))
                    titleLabel.stringValue = "AI 文字檢查"
                    titleLabel.alignment = .center
                    titleLabel.font = titleFont
                    titleLabel.textColor = .white
                    titleLabel.isBezeled = false
                    titleLabel.isEditable = false
                    titleLabel.drawsBackground = false
                    titleView.addSubview(titleLabel)
                    
                    titleLabel.translatesAutoresizingMaskIntoConstraints = false
                    NSLayoutConstraint.activate([
                        titleLabel.centerXAnchor.constraint(equalTo: titleView.centerXAnchor),
                        titleLabel.centerYAnchor.constraint(equalTo: titleView.centerYAnchor),
                        titleLabel.widthAnchor.constraint(equalTo: titleView.widthAnchor),
                        titleLabel.heightAnchor.constraint(equalTo: titleView.heightAnchor)
                    ])
                }
            }
        } else {
            textWindow?.setFrame(adjustedFrame, display: true)
        }
        
        let contentView = NSView(frame: (textWindow?.contentView?.bounds)!)
        contentView.translatesAutoresizingMaskIntoConstraints = false
        textWindow?.contentView?.addSubview(contentView)

        // 移除所有現有的子視圖
        contentView.subviews.forEach { $0.removeFromSuperview() }

        // 主要區域
        let mainArea = NSView()
        mainArea.translatesAutoresizingMaskIntoConstraints = false
        mainArea.identifier = NSUserInterfaceItemIdentifier("mainArea")
        contentView.addSubview(mainArea)

        // 文字區域（圓角）
        let textContainer = NSView()
        textContainer.translatesAutoresizingMaskIntoConstraints = false
        textContainer.wantsLayer = true
        textContainer.layer?.backgroundColor = NSColor(hexString: "#2B2B35")?.cgColor
        textContainer.layer?.cornerRadius = 10
        textContainer.identifier = NSUserInterfaceItemIdentifier("textContainer")
        mainArea.addSubview(textContainer)

        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        textContainer.addSubview(scrollView)

        let textView = NSTextView(frame: scrollView.bounds)
        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.font = NSFont(name: "仓耳今楷01-W05", size: 24) ?? NSFont.systemFont(ofSize: 24)
        textView.string = ""
        textView.isEditable = false
        textView.textContainerInset = NSSize(width: 15, height: 15)  // 增加內邊距
        textView.backgroundColor = NSColor.clear
        textView.textColor = NSColor.white
        textView.alignment = .left
        scrollView.documentView = textView

        // 統計信息
        let statsView = NSTextField()
        statsView.translatesAutoresizingMaskIntoConstraints = false
        statsView.isEditable = false
        statsView.isBordered = false
        statsView.backgroundColor = .clear
        statsView.textColor = NSColor(hexString: "#727178") ?? .lightGray
        statsView.font = NSFont.systemFont(ofSize: 12)
        statsView.stringValue = ""
        statsView.lineBreakMode = .byTruncatingTail
        mainArea.addSubview(statsView)

        // 底部區域
        let bottomArea = NSView()
        bottomArea.translatesAutoresizingMaskIntoConstraints = false
        bottomArea.wantsLayer = true
        bottomArea.layer?.backgroundColor = NSColor(hexString: "#28252E")?.cgColor
        contentView.addSubview(bottomArea)

        // 複製按鈕
        let copyButton = NSButton()
        copyButton.translatesAutoresizingMaskIntoConstraints = false
        copyButton.title = "複製並貼上"
        copyButton.bezelStyle = .inline
        copyButton.isBordered = false
        copyButton.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        copyButton.target = self
        copyButton.action = #selector(copyRewrittenText)
        copyButton.contentTintColor = .white
        bottomArea.addSubview(copyButton)

        // Enter 符號
        let enterSymbolContainer = NSView()
        enterSymbolContainer.translatesAutoresizingMaskIntoConstraints = false
        enterSymbolContainer.wantsLayer = true
        enterSymbolContainer.layer?.backgroundColor = NSColor(hexString: "#3B3A42")?.cgColor
        enterSymbolContainer.layer?.cornerRadius = 5
        bottomArea.addSubview(enterSymbolContainer)

        let enterSymbol = NSTextField()
        enterSymbol.translatesAutoresizingMaskIntoConstraints = false
        enterSymbol.isEditable = false
        enterSymbol.isBordered = false
        enterSymbol.backgroundColor = .clear
        enterSymbol.textColor = .white
        enterSymbol.font = NSFont.systemFont(ofSize: 16)
        enterSymbol.stringValue = "⏎"
        enterSymbol.alignment = .center
        enterSymbolContainer.addSubview(enterSymbol)

        // 設置約束
        NSLayoutConstraint.activate([
            contentView.topAnchor.constraint(equalTo: textWindow!.contentView!.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: textWindow!.contentView!.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: textWindow!.contentView!.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: textWindow!.contentView!.bottomAnchor),

            mainArea.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 50),
            mainArea.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            mainArea.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            mainArea.bottomAnchor.constraint(equalTo: bottomArea.topAnchor),

            textContainer.topAnchor.constraint(equalTo: mainArea.topAnchor),
            textContainer.leadingAnchor.constraint(equalTo: mainArea.leadingAnchor, constant: 20),
            textContainer.trailingAnchor.constraint(equalTo: mainArea.trailingAnchor, constant: -20),
            textContainer.bottomAnchor.constraint(equalTo: statsView.topAnchor, constant: -10),
            textContainer.heightAnchor.constraint(greaterThanOrEqualToConstant: 100), // 添加最小高度約束

            scrollView.topAnchor.constraint(equalTo: textContainer.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: textContainer.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: textContainer.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: textContainer.bottomAnchor),

            textView.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
            textView.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: scrollView.contentView.trailingAnchor),
            textView.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),

            statsView.topAnchor.constraint(equalTo: textContainer.bottomAnchor, constant: 10),
            statsView.leadingAnchor.constraint(equalTo: mainArea.leadingAnchor, constant: 20),
            statsView.trailingAnchor.constraint(equalTo: mainArea.trailingAnchor, constant: -20),
            statsView.heightAnchor.constraint(equalToConstant: 20),

            bottomArea.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            bottomArea.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            bottomArea.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            bottomArea.heightAnchor.constraint(equalToConstant: 50),

            copyButton.trailingAnchor.constraint(equalTo: enterSymbolContainer.leadingAnchor, constant: -10),
            copyButton.centerYAnchor.constraint(equalTo: bottomArea.centerYAnchor),

            enterSymbolContainer.trailingAnchor.constraint(equalTo: bottomArea.trailingAnchor, constant: -20),
            enterSymbolContainer.centerYAnchor.constraint(equalTo: bottomArea.centerYAnchor),
            enterSymbolContainer.widthAnchor.constraint(equalToConstant: 30),
            enterSymbolContainer.heightAnchor.constraint(equalToConstant: 30),

            enterSymbol.centerXAnchor.constraint(equalTo: enterSymbolContainer.centerXAnchor),
            enterSymbol.centerYAnchor.constraint(equalTo: enterSymbolContainer.centerYAnchor)
        ])
        
        textWindow?.makeKeyAndOrderFront(nil)
        textWindow?.level = .floating
        NSApp.activate(ignoringOtherApps: true)
        
        // 重置文視圖
        textView.string = ""
        
        self.currentTextView = textView
        self.originalText = text
        self.copyButton = copyButton
        self.statsView = statsView
        
        // 設置文字變化監聽器
        NotificationCenter.default.addObserver(self, selector: #selector(textDidChange(_:)), name: NSText.didChangeNotification, object: textView)
        
        // 初始調整文字框大小
        self.adjustTextContainerHeight(textView: textView, textContainer: textContainer, mainArea: mainArea)

        // 添加視窗大小變化的監聽器
        NotificationCenter.default.addObserver(self, selector: #selector(windowDidResize(_:)), name: NSWindow.didResizeNotification, object: textWindow)

        // 添加調試代碼
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            print("mainArea frame: \(mainArea.frame)")
            print("textContainer frame: \(textContainer.frame)")
            print("scrollView frame: \(scrollView.frame)")
            print("textView frame: \(textView.frame)")
        }

        // 設置 textView 的框架大小
        textView.frame = scrollView.bounds
        scrollView.documentView = textView

        rewriteText()  // 自動開始重寫
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

    @objc func textDidChange(_ notification: Notification) {
        guard let textView = notification.object as? NSTextView,
              let textContainer = textView.superview?.superview,
              let mainArea = textContainer.superview else {
            return
        }

        adjustTextContainerHeight(textView: textView, textContainer: textContainer, mainArea: mainArea)
    }

    func adjustTextContainerHeight(textView: NSTextView, textContainer: NSView, mainArea: NSView) {
        let contentSize = textView.layoutManager?.usedRect(for: textView.textContainer!).size ?? .zero
        let newHeight = max(contentSize.height + 30, 100) // 設置最小高度為 100

        textView.frame.size.height = newHeight
        
        if let scrollView = textView.enclosingScrollView {
            scrollView.documentView?.frame.size = CGSize(width: contentSize.width, height: newHeight)
        }

        // 更新 textContainer 的高度約束
        if let heightConstraint = textContainer.constraints.first(where: { $0.firstAttribute == .height }) {
            heightConstraint.constant = newHeight
        } else {
            textContainer.heightAnchor.constraint(equalToConstant: newHeight).isActive = true
        }

        mainArea.layoutSubtreeIfNeeded()
        
        // 打印調試信息
        print("Adjusted heights - textView: \(textView.frame.height), textContainer: \(textContainer.frame.height), mainArea: \(mainArea.frame.height)")
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
        
        // 重置 API 返回的文字和清空 textView
        self.apiReturnedText = ""
        textView.string = ""
        
        Task { [weak self] in
            guard let self = self else { return }
            do {
                print("調用 OpenAI API...")
                
                try await withTimeout(seconds: 30) {
                    try await self.streamOpenAiApi(text: self.originalText) { rewrittenText in
                        Task {
                            await MainActor.run {
                                self.apiReturnedText += rewrittenText
                                self.updateStreamText(textView: textView, newText: rewrittenText)
                            }
                        }
                    }
                }
                
                print("API 返回的文字長度：\(self.apiReturnedText.count)")
                
                // 在這裡添加一個小延遲，確保所有新文字都已完成
                try await Task.sleep(nanoseconds: 500_000_000)  // 0.5 秒延遲

                // API 返回完整結果後，進行比較並呈現結果
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
            .font: NSFont(name: "仓耳今楷01-W05", size: 24) ?? NSFont.systemFont(ofSize: 24),
            .foregroundColor: NSColor.white
        ])
        textView.textStorage?.append(attributedString)
        textView.scrollToEndOfDocument(nil)
        
        // 調整文字框高度
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
            let comparisonResult = self.compareTexts(original: originalTextCopy, rewritten: apiReturnedTextCopy)
            print("比較結果的長度：\(comparisonResult.length)")
            textView.textStorage?.setAttributedString(comparisonResult)
            textView.scrollToEndOfDocument(nil)
            
            // 調整文字框大小
            if let textContainer = textView.enclosingScrollView?.superview,
               let mainArea = textContainer.superview {
                self.adjustTextContainerHeight(textView: textView, textContainer: textContainer, mainArea: mainArea)
            }
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
                self.copyButton?.title = "複製並貼上"
            }
        }
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
                OpenAIRequest.Message(role: "user", content: "請將以下文字複寫，只需改錯字及語句不通順的地方。\n\n<text>\n\(text)\n</text>")
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
        
        print("開始解析式響應...")
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
        
        // 在這裡添加一個最終的更新，確使用完整的內容
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
        paragraphStyle.lineSpacing = 8  // 增加行間距
        
        let baseAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont(name: "仓耳今楷01-W05", size: 24) ?? NSFont.systemFont(ofSize: 24),
            .foregroundColor: NSColor.white,
            .paragraphStyle: paragraphStyle
        ]
        
        let diff = diffStrings(original, rewritten)
        
        for change in diff {
            switch change {
            case .equal(let text):
                attributedString.append(NSAttributedString(string: text, attributes: baseAttributes))
            case .insert(let text):
                var attributes = baseAttributes
                attributes[.backgroundColor] = NSColor(red: 0.0, green: 0.5, blue: 0.0, alpha: 0.3)
                attributedString.append(NSAttributedString(string: text, attributes: attributes))
            case .delete(let text):
                var attributes = baseAttributes
                attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
                attributes[.strikethroughColor] = NSColor.red
                attributes[.backgroundColor] = NSColor(red: 0.5, green: 0.0, blue: 0.0, alpha: 0.3)
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

    func updateStats(rewrittenText: String) {
        let rewrittenCharCount = rewrittenText.count
        let changesCount = calculateChanges(rewritten: rewrittenText)
        
        DispatchQueue.main.async {
            self.statsView?.stringValue = "字元數: \(rewrittenCharCount) | 改變: \(changesCount) | 模型: GPT-4"
        }
    }

    func calculateChanges(rewritten: String) -> Int {
        let diff = diffStrings(originalText, rewritten)
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
