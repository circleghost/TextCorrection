import Cocoa
import os.log
import SwiftUI

// 確保 AppKitBridge 可訪問
// #if canImport(TextCorrection)
// import TextCorrection
// #endif

class StatusItemManager: @unchecked Sendable {
    weak var appDelegate: AppDelegate?
    var statusItem: NSStatusItem?
    private var setupRetryCount = 0
    private let maxRetries = 5  // 增加重試次數
    
    // 創建日誌對象
    private let logger = Logger(subsystem: "com.yourcompany.TextCorrection", category: "StatusItemManager")
    
    init(appDelegate: AppDelegate) {
        self.appDelegate = appDelegate
        setupStatusItem()
        logger.info("StatusItemManager 初始化")
    }
    
    deinit {
        logger.info("StatusItemManager 已釋放")
    }
    
    func setupStatusItem() {
        guard let appDelegate = appDelegate else { return }
        
        // 創建狀態列圖標
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        // 設置簡潔的圖標 - 只使用系統圖標，無背景和容器
        if let button = statusItem?.button {
            if let iconImage = NSImage(systemSymbolName: "checkmark.bubble.fill", accessibilityDescription: "文字校正") {
                button.image = iconImage
                button.contentTintColor = NSColor.systemBlue
            }
            
            // 設置動作
            button.action = #selector(appDelegate.statusItemClicked(_:))
            button.target = appDelegate
            
            // 設置工具提示
            button.toolTip = "點擊校正選中的文字，右鍵點擊開啟選項"
        }
        
        // 添加標準選單
        setupMenu()
        
        logger.info("狀態列項目設置成功 - 使用簡潔圖標")
        
        // 重置重試計數
        setupRetryCount = 0
        
        // 確保狀態項可見
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.checkStatusItemVisibility()
        }
    }
    
    // 設置選單
    private func setupMenu() {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "文字校正", action: #selector(textCorrectionMenuItemClicked), keyEquivalent: "c"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "設定...", action: #selector(appDelegate?.showSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "退出", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        
        // 設置選單
        statusItem?.menu = menu
    }
    
    // 文字校正選單項被點擊
    @objc private func textCorrectionMenuItemClicked() {
        logger.info("文字校正選單項被點擊")
        
        // 獲取當前選擇的文本
        guard let selectedText = getCurrentSelectedText(), !selectedText.isEmpty else {
            logger.warning("沒有選擇文本或文本為空")
            return
        }
        
        // 直接使用 AppDelegate 顯示文本窗口
        if let appDelegate = self.appDelegate {
            // 使用 Task 包裝 @MainActor 方法調用，確保在主線程上執行
            Task { @MainActor in
                appDelegate.showSwiftUITextWindow(text: selectedText)
            }
        } else {
            logger.error("AppDelegate 為空，無法顯示文本窗口")
        }
    }
    
    // 獲取當前選擇的文本
    private func getCurrentSelectedText() -> String? {
        // 獲取前端應用程序
        guard let frontmostApp = NSWorkspace.shared.frontmostApplication else {
            logger.warning("無法獲取前端應用程序")
            return nil
        }
        
        logger.debug("前端應用程序: \(frontmostApp.localizedName ?? "未知")")
        
        // 嘗試獲取剪貼板內容
        let pasteboard = NSPasteboard.general
        guard let type = pasteboard.availableType(from: [.string]) else {
            logger.warning("剪貼板中沒有可用的文本")
            return nil
        }
        
        // 執行複製動作
        let keyCode = UInt16(9) // 'V' key code
        let source = CGEventSource(stateID: .combinedSessionState)
        
        // Command+C 按下
        if let cmdDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true) {
            cmdDown.flags = CGEventFlags.maskCommand
            cmdDown.post(tap: .cgAnnotatedSessionEventTap)
        }
        
        // Command+C 釋放
        if let cmdUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) {
            cmdUp.flags = CGEventFlags.maskCommand
            cmdUp.post(tap: .cgAnnotatedSessionEventTap)
        }
        
        // 給予操作系統一些時間來處理複製
        usleep(10000) // 10ms
        
        // 讀取剪貼板
        guard let clipboardContent = pasteboard.string(forType: type), !clipboardContent.isEmpty else {
            logger.warning("無法讀取剪貼板內容")
            return nil
        }
        
        logger.debug("從剪貼板獲取到文本，長度: \(clipboardContent.count)")
        return clipboardContent
    }
    
    // 重試設置狀態列圖標
    private func retrySetupIfNeeded() {
        setupRetryCount += 1
        if self.setupRetryCount < maxRetries {
            logger.info("嘗試重新設置狀態列圖標，第 \(self.setupRetryCount) 次")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                self?.setupStatusItem()
            }
        } else {
            logger.error("多次嘗試設置狀態列圖標失敗")
            
            // 在重試失敗後，顯示一個臨時視窗作為備用
            DispatchQueue.main.async { [weak self] in
                self?.showFallbackWindow()
            }
        }
    }
    
    // 顯示備用窗口
    private func showFallbackWindow() {
        logger.info("顯示備用窗口")
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            let alert = NSAlert()
            alert.messageText = "TextCorrection 已啟動"
            alert.informativeText = "應用程式已啟動，但無法顯示狀態列圖標。您仍可以使用設定功能。"
            alert.addButton(withTitle: "打開設定")
            alert.addButton(withTitle: "退出應用程式")
            
            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                self.appDelegate?.showSettings()
            } else {
                NSApp.terminate(nil)
            }
        }
    }
    
    // 檢查狀態項可見性
    private func checkStatusItemVisibility() {
        if let button = statusItem?.button {
            if (button.image == nil || button.image?.size.width == 0) && button.title.isEmpty {
                logger.warning("狀態列按鈕沒有圖標或文字，嘗試修復")
                button.title = "校正"
            }
        } else {
            logger.warning("狀態列按鈕為空，嘗試重新設置")
            retrySetupIfNeeded()
        }
    }
    
    // 重新顯示狀態列圖標
    func resetStatusItem() {
        // 先移除舊的狀態列圖標
        if let statusItem = statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
        }
        
        // 重置重試計數
        setupRetryCount = 0
        
        // 重新設置狀態列圖標
        setupStatusItem()
    }
}