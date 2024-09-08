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

@main
struct TextCorrectionApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
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
            print("請在系統偏好設置中啟用輔助功能權限")
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = "需要輔助功能權限"
                alert.informativeText = "請在系統偏好設置中為 TextCorrection 啟用輔助功能權限，以便應用程序能夠正常工作。"
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
            button.image = NSImage(systemSymbolName: "text.quote", accessibilityDescription: "字選擇")
        }
    }

    func setupHotKey() {
        hotKey = HotKey(key: .space, modifiers: [.control, .shift])
        hotKey?.keyDownHandler = { [weak self] in
            self?.copyAndShowSelectedText()
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
        
        // 設置一個定時器，在5秒後自動隱藏按鈕
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

    func copyAndShowSelectedText() {
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
            textWindow = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 300, height: 200),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable],
                                  backing: .buffered, defer: false)
            textWindow?.title = "複製的文字"
        }
        
        let scrollView = NSScrollView(frame: (textWindow?.contentView?.bounds)!)
        let textView = NSTextView(frame: scrollView.bounds)
        textView.autoresizingMask = [.width, .height]
        textView.string = text
        textView.isEditable = false
        scrollView.documentView = textView
        
        let rewriteButton = NSButton(frame: NSRect(x: 10, y: 10, width: 100, height: 30))
        rewriteButton.title = "重寫文字"
        rewriteButton.bezelStyle = .rounded
        rewriteButton.target = self
        rewriteButton.action = #selector(rewriteText)
        
        let stackView = NSStackView(frame: (textWindow?.contentView?.bounds)!)
        stackView.orientation = .vertical
        stackView.addArrangedSubview(scrollView)
        stackView.addArrangedSubview(rewriteButton)
        
        textWindow?.contentView?.subviews.forEach { $0.removeFromSuperview() }
        textWindow?.contentView?.addSubview(stackView)
        textWindow?.makeKeyAndOrderFront(nil)
        textWindow?.level = .floating
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func rewriteText() {
        guard let stackView = textWindow?.contentView?.subviews.first as? NSStackView,
              let scrollView = stackView.arrangedSubviews.first as? NSScrollView,
              let textView = scrollView.documentView as? NSTextView else {
            print("錯誤：無法獲取文本視圖")
            return
        }
        
        let originalText = textView.string
        
        guard !isRewriting else {
            print("正在重寫中，請稍候...")
            return
        }
        
        isRewriting = true
        print("開始重寫文字...")
        
        Task {
            do {
                print("調用 OpenAI API...")
                let rewrittenText = try await callOpenAiApi(text: originalText)
                print("API 調用成功，更新文本視圖...")
                DispatchQueue.main.async { [weak self] in
                    textView.string = rewrittenText
                    self?.isRewriting = false
                    print("文字重寫完成")
                }
            } catch {
                print("重寫文字時發生錯誤: \(error)")
                DispatchQueue.main.async { [weak self] in
                    self?.isRewriting = false
                    self?.showErrorAlert(message: "重寫文字時發生錯誤：\(error.localizedDescription)")
                }
            }
        }
    }

    func callOpenAiApi(text: String) async throws -> String {
        guard let apiKey = self.apiKey else {
            print("錯誤：API 金鑰未設置")
            throw NSError(domain: "TextCorrection", code: 1, userInfo: [NSLocalizedDescriptionKey: "API 金鑰未設置"])
        }

        print("準備 API 請求...")
        let prompt = """
        你是一名專業的臺灣繁體中文雜誌編輯，幫我檢查給定內容的錯字及語句文法。請特別注意以下規則：
        1. 中文與英文之間，中文與數字之間應有空格，例如 FLAC，JPEG，Google Search Console 等。
        2. 以下情況不需調整：
           - 括弧內的說明，例如（圖一）、（加入產品圖示）。
           - 阿拉伯數字不用調整成中文。
           - 英文不一定要翻譯成中文。
           - emoji 或特殊符號是為了增加閱讀體驗，也不必調整。
        3. 請保留原文的段落和換行格式。
        4. 請不要使用額外的 Markdown 語法。
        5. 請仔細審視給定的文字，將冗詞、語法錯誤進行修改。
        """

        let url = URL(string: "https://api.openai.com/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let requestBody: [String: Any] = [
            "model": "gpt-4",
            "messages": [
                ["role": "system", "content": prompt],
                ["role": "user", "content": "請將以下文字複寫，中文語法正確並改掉錯字。\n\n<text>\n\(text)\n</text>"]
            ],
            "temperature": 0.7,
            "max_tokens": 1000
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        print("發送 API 請求...")
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            print("錯誤：無效的 HTTP 響應")
            throw NSError(domain: "TextCorrection", code: 2, userInfo: [NSLocalizedDescriptionKey: "無效的 HTTP 響應"])
        }
        
        print("收到 API 響應，狀態碼：\(httpResponse.statusCode)")
        
        if httpResponse.statusCode != 200 {
            print("API 錯誤：\(httpResponse.statusCode)")
            throw NSError(domain: "TextCorrection", code: 3, userInfo: [NSLocalizedDescriptionKey: "API 錯誤：\(httpResponse.statusCode)"])
        }
        
        print("解析 API 響應...")
        let apiResponse = try JSONDecoder().decode(OpenAIResponse.self, from: data)
        
        guard let content = apiResponse.choices.first?.message.content else {
            print("錯誤：API 響應中沒有內容")
            throw NSError(domain: "TextCorrection", code: 4, userInfo: [NSLocalizedDescriptionKey: "API 響應中沒有內容"])
        }
        
        print("成功獲取重寫後的文字")
        return content
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
