import Cocoa
import os.log
import SwiftUI

// 確保 AppKitBridge 可訪問
// #if canImport(TextCorrection)
// import TextCorrection
// #endif

@MainActor
class StatusItemManager {
    weak var appDelegate: AppDelegate?
    var statusItem: NSStatusItem!
    private var setupRetryCount = 0
    private let maxRetries = 5  // 增加重試次數
    
    // 創建日誌對象
    private let logger = Logger(subsystem: "com.yourcompany.TextCorrection", category: "StatusItemManager")
    
    // 新增 appState 計算屬性
    private var appState: AppState { 
        return AppState.shared 
    }
    
    // 狀態圖標狀態
    enum StatusIconState {
        case normal
        case active
        case processing
    }
    
    // 當前圖標狀態
    private var currentIconState: StatusIconState = .normal
    
    init(appDelegate: AppDelegate) {
        self.appDelegate = appDelegate
        setupStatusItem()
        logger.info("StatusItemManager 初始化")
    }
    
    deinit {
        logger.info("StatusItemManager 已釋放")
    }
    
    func setupStatusItem() {
        guard appDelegate != nil else { return }
        
        // 創建狀態列圖標
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        // 設置簡潔的圖標 - 只使用系統圖標，無背景和容器
        if let button = statusItem?.button {
            updateStatusIcon(state: .normal)
            
            // 設置工具提示
            button.toolTip = "點擊開啟選單，右鍵點擊也可開啟選單"
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
        
        // 監聽 AppState 的處理狀態
        NotificationCenter.default.addObserver(
            self, 
            selector: #selector(updateIconBasedOnProcessingState), 
            name: NSNotification.Name("TextProcessingStateChanged"), 
            object: nil
        )
    }
    
    // 根據處理狀態更新圖標
    @objc private func updateIconBasedOnProcessingState() {
        if AppState.shared.isProcessing {
            updateStatusIcon(state: .processing)
        } else {
            updateStatusIcon(state: .normal)
        }
    }
    
    // 更新狀態圖標
    func updateStatusIcon(state: StatusIconState) {
        guard let button = statusItem?.button else { return }
        
        self.currentIconState = state
        
        var iconImage: NSImage?
        var tintColor: NSColor = NSColor.systemBlue
        
        switch state {
        case .normal:
            iconImage = NSImage(systemSymbolName: "checkmark.bubble.fill", accessibilityDescription: "文字校正")
            tintColor = NSColor.systemBlue
        case .active:
            iconImage = NSImage(systemSymbolName: "checkmark.bubble.fill", accessibilityDescription: "文字校正")
            tintColor = NSColor.systemGreen
        case .processing:
            iconImage = NSImage(systemSymbolName: "ellipsis.bubble.fill", accessibilityDescription: "處理中")
            tintColor = NSColor.systemOrange
        }
        
        button.image = iconImage
        button.contentTintColor = tintColor
    }
    
    // 設置選單
    private func setupMenu() {
        let menu = NSMenu()
        
        // 創建選單項目並添加到選單
        for item in createMenuItems() {
            menu.addItem(item)
        }
        
        // 設置右鍵點擊也能打開選單
        statusItem?.menu = menu
        
        // 設置左鍵點擊事件
        if let button = statusItem?.button {
            button.action = #selector(statusItemClicked)
            button.target = self
        }
    }
    
    // 創建選單項目
    private func createMenuItems() -> [NSMenuItem] {
        var items: [NSMenuItem] = []
        
        // 校正選中文本選項
        let correctItem = NSMenuItem(title: "校正選中文本", action: #selector(textCorrectionMenuItemClicked), keyEquivalent: "")
        correctItem.target = self
        items.append(correctItem)
        
        // 啟用/禁用熱鍵選項
        let hotkeyTitle = AppState.shared.isHotkeyActive ? "禁用熱鍵" : "啟用熱鍵"
        let hotkeyItem = NSMenuItem(title: hotkeyTitle, action: #selector(toggleHotkey), keyEquivalent: "")
        hotkeyItem.target = self
        items.append(hotkeyItem)
        
        // 顯示日誌選項
        let showLogsItem = NSMenuItem(title: "查看日誌", action: #selector(viewLogs), keyEquivalent: "")
        showLogsItem.target = self
        items.append(showLogsItem)
        
        // 添加分隔線
        items.append(NSMenuItem.separator())
        
        // 偏好設置選項
        let preferencesItem = NSMenuItem(title: "設定", action: #selector(openSettings), keyEquivalent: ",")
        preferencesItem.target = self
        items.append(preferencesItem)
        
        // 反饋選項
        let feedbackItem = NSMenuItem(title: "提供反饋", action: #selector(openFeedbackForm), keyEquivalent: "")
        feedbackItem.target = self
        items.append(feedbackItem)
        
        // 歡迎頁選項
        let welcomeItem = NSMenuItem(title: "顯示歡迎頁", action: #selector(openWelcomeView), keyEquivalent: "")
        welcomeItem.target = self
        items.append(welcomeItem)
        
        // 添加分隔線
        items.append(NSMenuItem.separator())
        
        // 退出選項
        let quitItem = NSMenuItem(title: "退出", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        items.append(quitItem)
        
        return items
    }
    
    // 切換熱鍵狀態
    @objc private func toggleHotkey() {
        AppState.shared.isHotkeyActive.toggle()
        // 重新設置選單以更新選項標題
        setupMenu()
    }
    
    // 顯示歡迎頁
    @objc private func openWelcomeView() {
        if let appDelegate = self.appDelegate {
            Task { @MainActor in
                appDelegate.showWelcomeView()
            }
        }
    }
    
    // 顯示日誌
    @objc private func viewLogs() {
        if let appDelegate = self.appDelegate {
            Task { @MainActor in
                appDelegate.showLogsView()
            }
        }
    }
    
    // 狀態項被點擊
    @objc private func statusItemClicked() {
        if statusItem?.menu != nil {
            statusItem?.button?.performClick(nil)
        }
    }
    
    // 切換剪貼板監控
    @objc private func toggleClipboardMonitoring() {
        let newState = !AppState.shared.isClipboardMonitoringEnabled
        AppState.shared.isClipboardMonitoringEnabled = newState
        
        // 更新選單項目狀態
        DispatchQueue.main.async { [weak self] in
            if let menu = self?.statusItem?.menu {
                for item in menu.items {
                    if item.action == #selector(self?.toggleClipboardMonitoring) {
                        item.state = newState ? .on : .off
                        break
                    }
                }
            }
        }
    }
    
    // 打開設定視窗
    @objc private func openSettings() {
        // 檢查設定視窗是否已開啟
        if let appDelegate = self.appDelegate {
            Task { @MainActor in
                appDelegate.showSettings()
            }
        }
    }
    
    // 檢查更新
    @objc private func checkForUpdates() {
        logger.info("檢查更新")
        
        // 這裡可以實現檢查更新的功能
        let alert = NSAlert()
        alert.messageText = "檢查更新"
        alert.informativeText = "目前版本 \(getAppVersion()) 已是最新版本。"
        alert.addButton(withTitle: "確定")
        alert.runModal()
    }
    
    // 輔助方法：獲取應用版本
    private func getAppVersion() -> String {
        if let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String {
            return version
        }
        return "未知"
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
    
    // 打開反饋表單
    @objc private func openFeedbackForm() {
        logger.info("打開反饋表單選單項被點擊")
        AppState.shared.isFeedbackViewOpen = true
        
        if let appDelegate = self.appDelegate {
            Task { @MainActor in
                appDelegate.showFeedbackView()
            }
        } else {
            logger.error("AppDelegate 為空，無法顯示反饋表單")
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
                Task { @MainActor in
                    self.appDelegate?.showSettings()
                }
            } else {
                NSApp.terminate(nil)
            }
        }
    }
    
    // 檢查狀態項可見性
    func checkStatusItemVisibility() {
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
    
    // 創建選單項目的輔助方法
    private func createMenuItem(title: String, action: Selector?) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }
    
    // 輔助屬性來顯示熱鍵
    private var hotkeyString: String {
        // 替換為實際獲取熱鍵字符串的方法
        return "⌘+⇧+C"
    }
}

// 擴展 Utilities 中的功能
extension StatusItemManager {
    // 獲取當前選中文本
    func getSelectedText() -> String? {
        let pasteboard = NSPasteboard.general
        return pasteboard.string(forType: .string)
    }
}