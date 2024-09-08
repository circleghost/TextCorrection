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

    func applicationDidFinishLaunching(_ notification: Notification) {
        requestAccessibilityPermission()
        setupStatusItem()
        setupHotKey()
        setupPasteboardObserver()
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
            button.image = NSImage(systemSymbolName: "text.quote", accessibilityDescription: "文字選擇")
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
        
        let textView = NSTextView(frame: (textWindow?.contentView?.bounds)!)
        textView.string = text
        textView.isEditable = false
        
        textWindow?.contentView?.subviews.forEach { $0.removeFromSuperview() }
        textWindow?.contentView?.addSubview(textView)
        textWindow?.makeKeyAndOrderFront(nil)
        textWindow?.level = .floating
        NSApp.activate(ignoringOtherApps: true)
    }

    func showErrorAlert() {
        let alert = NSAlert()
        alert.messageText = "文字選擇檢測失敗"
        alert.informativeText = "應用程無法正確檢測文字選擇。請確保已授予必要的權限，並重新啟動應用程序。"
        alert.addButton(withTitle: "確定")
        alert.runModal()
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
