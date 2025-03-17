import HotKey
import os.log
import Cocoa
import Foundation
import Carbon
import Combine
import SwiftUI

// 完整的類實現，而不是擴展
class HotKeyManager: @unchecked Sendable {
    weak var appDelegate: AppDelegate?
    var cancellables = Set<AnyCancellable>()
    var hotKey: HotKey?
    var globalMonitor: Any?
    var carbonEventHandler: EventHandlerRef?
    private var carbonHotKeyID: UInt32?
    private var carbonHotKeyRef: EventHotKeyRef?
    
    // 創建日誌對象
    private var logger: Logger {
        return Logger(subsystem: "com.yourcompany.TextCorrection", category: "HotKeyManager")
    }
    
    // 默認熱鍵設置
    private var defaultHotKeyKey: Key {
        return .space
    }
    
    private var defaultHotKeyModifiers: NSEvent.ModifierFlags {
        return [.control, .shift]
    }
    
    deinit {
        cleanup()
        logger.info("HotKeyManager 已釋放")
        NotificationCenter.default.removeObserver(self)
    }
    
    init(appDelegate: AppDelegate) {
        self.appDelegate = appDelegate
        logger.info("HotKeyManager 初始化")
        
        // 設置訂閱
        setupSubscriptions()
        
        // 監聽熱鍵設定變更
        NotificationCenter.default.addObserver(self, 
                                              selector: #selector(hotKeySettingsChanged),
                                              name: NSNotification.Name("HotKeySettingsChanged"),
                                              object: nil)
        
        // 立即嘗試設置熱鍵(如果已啟用)
        if AppState.shared.isHotkeyActive {
            logger.info("🔄 應用啟動時熱鍵功能已開啟，立即設置熱鍵")
            // 直接使用 setupHotKey 方法設置熱鍵
            setupHotKey()
            
            // 在應用啟動時強制設置熱鍵
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                guard let self = self else { return }
                self.setupHotKey()
                self.logger.info("✅ 應用啟動後延遲1秒重新嘗試設置熱鍵")
            }
        } else {
            logger.info("⚠️ 應用啟動時熱鍵功能未開啟")
        }
    }
    
    // 設置與AppState的訂閱關係
    private func setupSubscriptions() {
        // 移除對 @Published 屬性的直接訂閱
        // 改為使用 NotificationCenter 觀察變更通知
        
        // 監聽熱鍵設定變更通知已在 init 方法中設置，不需要重複
        logger.info("設置熱鍵訂閱關係完成")
        
        // 使用計時器定期檢查設定的變化，以防萬一
        Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            
            // 檢查當前熱鍵狀態
            let isActive = AppState.shared.isHotkeyActive
            
            // 如果應該啟用但熱鍵為空，則設置熱鍵
            if isActive && self.hotKey == nil {
                DispatchQueue.main.async {
                    self.logger.debug("計時器檢測到熱鍵應啟用但未設置，重新設置熱鍵")
                    self.setupHotKey()
                }
            }
            // 如果應該禁用但熱鍵不為空，則禁用熱鍵
            else if !isActive && self.hotKey != nil {
                DispatchQueue.main.async {
                    self.logger.debug("計時器檢測到熱鍵應禁用但仍在設置，禁用熱鍵")
                    self.disableHotKey()
                }
            }
        }
    }
    
    // 清理所有資源，確保正確釋放
    private func cleanup() {
        logger.info("清理 HotKeyManager 資源")
        
        // 取消所有 Combine 訂閱
        cancellables.forEach { $0.cancel() }
        cancellables.removeAll()
        
        // 移除熱鍵
        hotKey = nil
        
        // 移除全局監聽器
        removeGlobalMonitor()
        
        // 使用 unregisterHotKey 代替 unregisterCarbonHotKey
        unregisterHotKey()
        
        // 移除通知中心觀察者
        NotificationCenter.default.removeObserver(self)
        
        // 清除 AppDelegate 引用，避免循環引用
        appDelegate = nil
        
        logger.info("HotKeyManager 資源清理完成")
    }
    
    // 禁用熱鍵
    func disableHotKey() {
        logger.info("禁用熱鍵")
        cleanup()
    }
    
    func setupHotKey() {
        logger.info("開始設置熱鍵 (無參數版本)")
        
        let appState = AppState.shared
        let isActive = appState.isHotkeyActive
        let modifiers = appState.hotKeyModifiers
        let keyCharacter = appState.hotKeyCharacter
        
        logger.info("從AppState獲取熱鍵設定: active=\(isActive), modifiers=\(modifiers), key=\(keyCharacter)")
        
        setupHotKey(isActive: isActive, modifiers: modifiers, keyCharacter: keyCharacter)
    }
    
    /// 設置熱鍵功能
    /// - Parameters:
    ///   - isActive: 是否啟用熱鍵
    ///   - modifiers: 修飾鍵列表
    ///   - keyCharacter: 主鍵字符
    func setupHotKey(isActive: Bool, modifiers: [String], keyCharacter: String) {
        // 先移除現有的熱鍵
        unregisterHotKey()
        
        if !isActive {
            logger.info("熱鍵功能已停用")
            return
        }
        
        logger.info("設置熱鍵: modifiers=\(modifiers), key=\(keyCharacter)")
        
        // 檢查輔助功能權限
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false]
        let accessEnabled = AXIsProcessTrustedWithOptions(options as CFDictionary)
        
        if !accessEnabled {
            logger.warning("嘗試啟用熱鍵但缺少輔助功能權限")
            DispatchQueue.main.async {
                self.promptForAccessibilityPermissions()
            }
            return
        }
        
        // 轉換修飾鍵
        var keyModifiers: NSEvent.ModifierFlags = []
        for modifier in modifiers {
            switch modifier.lowercased() {
            case "command":
                keyModifiers.insert(.command)
                logger.debug("添加修飾鍵: command")
            case "shift":
                keyModifiers.insert(.shift)
                logger.debug("添加修飾鍵: shift")
            case "option", "alt":
                keyModifiers.insert(.option)
                logger.debug("添加修飾鍵: option")
            case "control", "ctrl":
                keyModifiers.insert(.control)
                logger.debug("添加修飾鍵: control")
            default:
                logger.warning("未知修飾鍵: \(modifier)")
            }
        }
        
        // 轉換主鍵
        var keyString = keyCharacter
        if keyCharacter.lowercased() == "space" {
            keyString = " "
            logger.debug("主鍵轉換: 'space' -> ' '")
        }
        
        // 設置熱鍵
        logger.info("註冊熱鍵: \(keyModifiers.rawValue) + \(keyString)")
        
        if keyString.count == 1, let firstChar = keyString.first {
            let keyEquivalent = KeyEquivalent(firstChar)
            hotKey = HotKey(keyEquivalent: keyEquivalent, modifiers: keyModifiers)
            hotKey?.keyDownHandler = { [weak self] in
                self?.handleHotKeyPressed()
            }
            
            if hotKey != nil {
                logger.info("熱鍵註冊成功")
            } else {
                logger.error("熱鍵註冊失敗")
                
                // 嘗試使用特殊按鍵處理
                if keyString.lowercased() == "space" {
                    let spaceKeyEquivalent = KeyEquivalent(" ")
                    hotKey = HotKey(keyEquivalent: spaceKeyEquivalent, modifiers: keyModifiers)
                    hotKey?.keyDownHandler = { [weak self] in
                        self?.handleHotKeyPressed()
                    }
                    logger.info("空格鍵熱鍵註冊成功")
                } else {
                    // 嘗試其他方法註冊
                    registerCarbonHotKey(modifiers: keyModifiers, key: keyString)
                }
            }
        } else if keyString.lowercased() == "space" {
            // 直接使用空格字符
            let spaceKeyEquivalent = KeyEquivalent(" ")
            hotKey = HotKey(keyEquivalent: spaceKeyEquivalent, modifiers: keyModifiers)
            hotKey?.keyDownHandler = { [weak self] in
                self?.handleHotKeyPressed()
            }
            logger.info("空格鍵熱鍵註冊成功")
        } else {
            logger.error("無法創建KeyEquivalent，熱鍵註冊失敗: 字串長度不為1或無效字符")
            
            // 嘗試其他方法註冊
            registerCarbonHotKey(modifiers: keyModifiers, key: keyString)
        }
    }
    
    /// 注銷所有熱鍵
    private func unregisterHotKey() {
        logger.info("注銷現有熱鍵")
        
        // 注銷HotKey熱鍵
        if hotKey != nil {
            hotKey = nil
            logger.debug("HotKey熱鍵已注銷")
        }
        
        // 注銷Carbon熱鍵
        if let carbonHotKeyRef = carbonHotKeyRef {
            UnregisterEventHotKey(carbonHotKeyRef)
            self.carbonHotKeyRef = nil
            self.carbonHotKeyID = nil
            logger.debug("Carbon熱鍵已注銷")
        }
    }
    
    /// 使用Carbon API註冊熱鍵（備用方案）
    private func registerCarbonHotKey(modifiers: NSEvent.ModifierFlags, key: String) {
        logger.info("嘗試使用Carbon API註冊熱鍵")
        
        // 轉換為Carbon修飾鍵
        var carbonModifiers: UInt32 = 0
        if modifiers.contains(.command) {
            carbonModifiers |= UInt32(cmdKey)
        }
        if modifiers.contains(.shift) {
            carbonModifiers |= UInt32(shiftKey)
        }
        if modifiers.contains(.option) {
            carbonModifiers |= UInt32(optionKey)
        }
        if modifiers.contains(.control) {
            carbonModifiers |= UInt32(controlKey)
        }
        
        // 獲取按鍵代碼
        guard let firstChar = key.unicodeScalars.first else {
            logger.error("無法獲取按鍵代碼，Carbon熱鍵註冊失敗")
            return
        }
        
        let keyCode: UInt32
        if key == " " {
            keyCode = UInt32(kVK_Space)
        } else {
            keyCode = UInt32(firstChar.value)
        }
        
        // 生成唯一ID
        let hotKeyID = UInt32(arc4random_uniform(1000))
        carbonHotKeyID = hotKeyID
        
        // 構建事件類型
        var eventType = EventTypeSpec()
        eventType.eventClass = OSType(kEventClassKeyboard)
        eventType.eventKind = OSType(kEventHotKeyPressed)
        
        // 註冊事件處理器
        var handlerRef: EventHandlerRef?
        let handlerCallback: EventHandlerUPP = { (nextHandler, eventRef, userData) -> OSStatus in
            if let manager = unsafeBitCast(userData, to: HotKeyManager.self) as HotKeyManager? {
                manager.handleHotKeyPressed()
            }
            return noErr
        }
        
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            handlerCallback,
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &handlerRef
        )
        
        if status == noErr {
            logger.debug("Carbon事件處理器註冊成功")
            
            // 註冊熱鍵
            var hotKeyRef: EventHotKeyRef?
            let regStatus = RegisterEventHotKey(
                keyCode,
                carbonModifiers,
                EventHotKeyID(signature: OSType(keyCode), id: hotKeyID),
                GetApplicationEventTarget(),
                0,
                &hotKeyRef
            )
            
            if regStatus == noErr && hotKeyRef != nil {
                carbonHotKeyRef = hotKeyRef
                logger.info("Carbon熱鍵註冊成功")
            } else {
                logger.error("Carbon熱鍵註冊失敗，錯誤碼: \(regStatus)")
            }
        } else {
            logger.error("Carbon事件處理器註冊失敗，錯誤碼: \(status)")
        }
    }
    
    /// 處理熱鍵觸發事件
    private func handleHotKeyPressed() {
        logger.info("熱鍵已觸發")
        
        DispatchQueue.main.async {
            // 發送通知，通知應用執行文本處理操作
            NotificationCenter.default.post(name: NSNotification.Name("ProcessTextFromHotKey"), object: nil)
            NSSound.beep() // 播放提示音
        }
    }
    
    /// 提示用戶授予輔助功能權限
    private func promptForAccessibilityPermissions() {
        logger.info("顯示輔助功能權限提示")
        
        let alert = NSAlert()
        alert.messageText = "需要輔助功能權限"
        alert.informativeText = "熱鍵功能需要輔助功能權限。請前往「系統設定」→「隱私與安全性」→「輔助使用」允許本應用程式。授權後請重啟應用。"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "打開系統設定")
        alert.addButton(withTitle: "取消")
        
        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
        }
    }
    
    // 移除全局監聽器
    private func removeGlobalMonitor() {
        if let monitor = globalMonitor {
            NSEvent.removeMonitor(monitor)
            globalMonitor = nil
        }
    }
    
    // 註冊主熱鍵
    private func registerMainHotKey() {
        // 檢查用戶設定的熱鍵（如果有）
        let key = loadSavedHotKeyKey() ?? defaultHotKeyKey
        let modifiers = loadSavedHotKeyModifiers() ?? defaultHotKeyModifiers
        
        // 確認熱鍵設置合理
        logger.info("嘗試註冊主熱鍵: \(key.description) 修飾鍵: \(self.modifiersToString(modifiers))")
        
        // 安全檢查：確保修飾鍵不為空
        guard !modifiers.isEmpty else {
            logger.error("修飾鍵為空，使用默認修飾鍵")
            registerHotKey(key: key, modifiers: defaultHotKeyModifiers)
            return
        }
        
        // 註冊熱鍵
        registerHotKey(key: key, modifiers: modifiers)
        
        // 確認熱鍵已註冊
        if hotKey != nil {
            logger.info("主熱鍵設置成功: \(self.modifiersToString(modifiers))+\(key.description)")
        } else {
            logger.error("主熱鍵註冊失敗")
        }
    }
    
    // 註冊熱鍵
    func registerHotKey(key: Key, modifiers: NSEvent.ModifierFlags) {
        // 先清除現有熱鍵
        hotKey = nil
        
        // 創建新熱鍵
        logger.info("正在註冊熱鍵: \(key.description) 修飾鍵: \(self.modifiersToString(modifiers))")
        
        // 創建熱鍵，注意這不會拋出錯誤，因此不需要 try-catch
        hotKey = HotKey(key: key, modifiers: modifiers)
        
        if let hotKey = hotKey {
            // 設置按下時的處理程序
            hotKey.keyDownHandler = { [weak self] in
                guard let self = self else { return }
                
                self.logger.info("檢測到熱鍵按下")
                // 確保在主線程上調用 processSelectedText
                Task { @MainActor in
                    self.processSelectedText()
                }
            }
        }
    }
    
    // 處理選中的文本 - 這是需要與UI交互的方法，標記為MainActor
    @MainActor
    func processSelectedText() {
        logger.info("處理選中的文本")
        
        // 通知PasteboardManager這是熱鍵觸發
        NotificationCenter.default.post(name: NSNotification.Name("HotkeyTriggered"), object: nil)
        logger.info("[熱鍵觸發] 已發送HotkeyTriggered通知")
        
        // 先模擬按下 Command+C 來複製當前選中的文字
        simulateCopyKeyPress()
        logger.info("[熱鍵觸發] 已執行模擬複製操作")
        
        // 給系統一些時間處理複製操作
        Task { @MainActor in
            logger.info("[熱鍵觸發] 等待剪貼板更新")
            // 等待 0.2 秒
            try? await Task.sleep(nanoseconds: 200_000_000) // 0.2秒
            
            // 從剪貼板獲取文本
            guard let selectedText = NSPasteboard.general.string(forType: .string), !selectedText.isEmpty else {
                self.logger.warning("[熱鍵觸發] 未能從剪貼板獲取到文本")
                return
            }
            
            self.logger.info("[熱鍵觸發] 從剪貼板獲取到文本，長度: \(selectedText.count)")
            
            // 首先檢查實例變量中的 AppDelegate 引用
            if let appDelegate = self.appDelegate {
                self.logger.info("[熱鍵觸發] 使用實例變量中的 AppDelegate")
                appDelegate.directlyProcessHotkeySelection(selectedText)
                return
            }
            
            // 如果實例變量中沒有，則嘗試從 AppKitBridge 獲取
            if let appDelegate = AppKitBridge.shared.appDelegate {
                self.logger.info("[熱鍵觸發] 使用 AppKitBridge 中的 AppDelegate")
                appDelegate.directlyProcessHotkeySelection(selectedText)
                return
            }
            
            // 如果仍然無法獲取 AppDelegate，則直接使用 AppKitBridge 顯示文本窗口
            self.logger.warning("[熱鍵觸發] 無法獲取 AppDelegate，使用 AppKitBridge 顯示窗口")
            AppKitBridge.shared.showTextCorrectionWindow(withText: selectedText)
        }
    }
    
    // 模擬按下 Command+C 複製當前選中文字的方法
    private func simulateCopyKeyPress() {
        logger.info("模擬 Command+C 複製操作")
        
        // 注銷熱鍵
        if let key = hotKey {
            key.isPaused = true
            hotKey = nil
            logger.debug("熱鍵已注銷")
        }
        
        // 創建一個包含 Command+C 的事件
        let keyDownEvent = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(8), keyDown: true)
        let keyUpEvent = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(8), keyDown: false)
        
        // 設置 Command 修飾鍵
        keyDownEvent?.flags = .maskCommand
        keyUpEvent?.flags = .maskCommand
        
        // 發送事件
        keyDownEvent?.post(tap: .cghidEventTap)
        keyUpEvent?.post(tap: .cghidEventTap)
    }
    
    // 從用戶設置加載熱鍵
    private func loadSavedHotKeyKey() -> Key? {
        // 檢查字符串是否為空
        let keyChar = AppState.shared.hotKeyCharacter
        if keyChar.isEmpty {
            return nil
        }
        return Key(string: keyChar)
    }
    
    // 從用戶設置加載修飾鍵
    private func loadSavedHotKeyModifiers() -> NSEvent.ModifierFlags? {
        // 將字符串數組轉換為修飾鍵標誌
        var modifiers: NSEvent.ModifierFlags = []
        
        for modifierString in AppState.shared.hotKeyModifiers {
            switch modifierString.lowercased() {
            case "command", "cmd", "⌘":
                modifiers.insert(.command)
            case "option", "alt", "⌥":
                modifiers.insert(.option)
            case "control", "ctrl", "⌃":
                modifiers.insert(.control)
            case "shift", "⇧":
                modifiers.insert(.shift)
            default:
                break
            }
        }
        
        return modifiers.isEmpty ? nil : modifiers
    }
    
    // 將修飾鍵轉換為字符串表示
    private func modifiersToString(_ modifiers: NSEvent.ModifierFlags) -> String {
        var parts: [String] = []
        
        if modifiers.contains(.control) { parts.append("⌃") }
        if modifiers.contains(.option) { parts.append("⌥") }
        if modifiers.contains(.shift) { parts.append("⇧") }
        if modifiers.contains(.command) { parts.append("⌘") }
        
        return parts.joined()
    }
    
    // 熱鍵設定變更通知
    @objc func hotKeySettingsChanged() {
        // 確保在主線程執行
        if Thread.isMainThread {
            logger.debug("接收到熱鍵設定變更通知，重新設置熱鍵")
            setupHotKey()
        } else {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.logger.debug("接收到熱鍵設定變更通知（非主線程），重新設置熱鍵")
                self.setupHotKey()
            }
        }
    }
    
    // 熱鍵觸發時的處理函數
    private func hotKeyTriggered() {
        logger.debug("熱鍵被觸發")
        
        // 檢查輔助功能權限
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false]
        let accessEnabled = AXIsProcessTrustedWithOptions(options as CFDictionary)
        
        if !accessEnabled {
            logger.warning("熱鍵觸發但缺少輔助功能權限")
            // 在主線程上顯示警告
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                
                // 嘗試獲取 AppDelegate 參考
                if let appDelegate = self.appDelegate {
                    self.logger.info("熱鍵觸發時檢測到權限問題，請求檢查輔助功能權限")
                    appDelegate.checkAccessibilityPermissions()
                } else {
                    // 如果無法獲取 AppDelegate，直接顯示提示給用戶
                    let alert = NSAlert()
                    alert.messageText = "需要輔助功能權限"
                    alert.informativeText = "熱鍵功能需要輔助功能權限。請前往「系統設定」→「隱私與安全性」→「輔助使用」允許本應用程式。授權後請重啟應用。"
                    alert.alertStyle = .warning
                    alert.addButton(withTitle: "打開系統設定")
                    alert.addButton(withTitle: "取消")
                    
                    let response = alert.runModal()
                    if response == .alertFirstButtonReturn {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                    }
                }
                
                // 禁用熱鍵功能
                AppState.shared.updateHotkeySettings(active: false)
            }
            return
        }
        
        // 通知PasteboardManager這是熱鍵觸發
        NotificationCenter.default.post(name: NSNotification.Name("HotkeyTriggered"), object: nil)
        logger.info("[熱鍵觸發] 已發送HotkeyTriggered通知")
        
        // 首先模擬 Command+C 複製選中的文本
        simulateCopyKeyPress()
        logger.info("[熱鍵觸發] 已執行模擬複製操作")
        
        // 給系統一些時間處理複製操作
        Task { @MainActor in
            logger.info("[熱鍵觸發] 等待剪貼板更新")
            // 等待 0.2 秒
            try? await Task.sleep(nanoseconds: 200_000_000) // 0.2秒
            
            // 從剪貼板獲取文本
            guard let selectedText = NSPasteboard.general.string(forType: .string), !selectedText.isEmpty else {
                logger.warning("[熱鍵觸發] 未能從剪貼板獲取到文本")
                
                // 顯示錯誤提示
                DispatchQueue.main.async {
                    let alert = NSAlert()
                    alert.messageText = "無法獲取選中的文本"
                    alert.informativeText = "請確保已選中文本，並且應用程式擁有必要的權限。"
                    alert.alertStyle = .warning
                    alert.addButton(withTitle: "確定")
                    alert.runModal()
                }
                return
            }
            
            logger.info("[熱鍵觸發] 從剪貼板獲取到文本，長度: \(selectedText.count)")
            
            // 首先檢查實例變量中的 AppDelegate 引用
            if let appDelegate = self.appDelegate {
                logger.info("[熱鍵觸發] 使用實例變量中的 AppDelegate")
                appDelegate.directlyProcessHotkeySelection(selectedText)
                return
            }
            
            // 如果實例變量中沒有，則嘗試從 AppKitBridge 獲取
            if let appDelegate = AppKitBridge.shared.appDelegate {
                logger.info("[熱鍵觸發] 使用 AppKitBridge 中的 AppDelegate")
                appDelegate.directlyProcessHotkeySelection(selectedText)
                return
            }
            
            // 如果仍然無法獲取 AppDelegate，則直接使用 AppKitBridge 顯示文本窗口
            logger.warning("[熱鍵觸發] 無法獲取 AppDelegate，使用 AppKitBridge 顯示窗口")
            AppKitBridge.shared.showTextCorrectionWindow(withText: selectedText)
        }
    }
}