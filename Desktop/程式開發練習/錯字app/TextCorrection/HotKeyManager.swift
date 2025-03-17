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
    }
    
    // 設置與AppState的訂閱關係
    private func setupSubscriptions() {
        // 監聽熱鍵狀態變化
        AppState.shared.$isHotkeyActive
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isActive in
                guard let self = self else { return }
                
                if isActive && self.hotKey == nil {
                    self.setupHotKey()
                } else if !isActive && self.hotKey != nil {
                    self.disableHotKey()
                }
            }
            .store(in: &cancellables)
        
        // 監聽熱鍵設定變化
        Publishers.CombineLatest3(
            AppState.shared.$hotKeyModifiers,
            AppState.shared.$hotKeyCharacter,
            AppState.shared.$isHotkeyActive
        )
        .receive(on: DispatchQueue.main)
        .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
        .sink { [weak self] (modifiers, character, isActive) in
            guard let self = self, isActive else { return }
            
            // 熱鍵設定有變更，重新設置
            self.logger.debug("熱鍵設定已變更，重新設置")
            self.setupHotKey()
        }
        .store(in: &cancellables)
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
        
        // 取消 Carbon 熱鍵註冊
        unregisterCarbonHotKey()
        
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
        // 先確保沒有現有的熱鍵
        disableHotKey()
        
        // 獲取熱鍵設定
        let isActive = AppState.shared.isHotkeyActive
        let modifiers = AppState.shared.hotKeyModifiers
        let keyCharacter = AppState.shared.hotKeyCharacter
        
        if !isActive {
            logger.info("熱鍵功能已禁用")
            return
        }
        
        // 轉換修飾鍵
        var modifierFlags: NSEvent.ModifierFlags = []
        for modifier in modifiers {
            switch modifier.lowercased() {
            case "command":
                modifierFlags.insert(.command)
            case "option":
                modifierFlags.insert(.option)
            case "control":
                modifierFlags.insert(.control)
            case "shift":
                modifierFlags.insert(.shift)
            default:
                break
            }
        }
        
        // 轉換按鍵
        var key: Key?
        switch keyCharacter.lowercased() {
        case "space":
            key = .space
        case "return":
            key = .return
        case "delete":
            key = .delete
        case "up":
            key = .upArrow
        case "down":
            key = .downArrow
        default:
            // 單字符按鍵
            if let keyCode = keyCharacter.first?.asciiValue {
                if let unwrappedKey = Key(carbonKeyCode: UInt32(keyCode - 97 + 0x00)) {
                    key = unwrappedKey
                } else {
                    logger.error("無法創建熱鍵: \(keyCharacter)")
                    return
                }
            } else {
                logger.error("無法識別熱鍵字符: \(keyCharacter)")
                return
            }
        }
        
        // 建立熱鍵
        if let unwrappedKey = key {
            hotKey = HotKey(key: unwrappedKey, modifiers: modifierFlags)
            
            // 設置熱鍵觸發的動作
            hotKey?.keyDownHandler = { [weak self] in
                self?.hotKeyTriggered()
            }
            
            logger.info("已設置熱鍵: \(unwrappedKey.description) 配合修飾鍵: \(modifierFlags)")
        } else {
            logger.error("無法建立熱鍵，key為nil")
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
    
    // 使用 Carbon API 註冊熱鍵
    private func registerCarbonHotKey() {
        // 確保先卸載任何現有的碳熱鍵
        unregisterCarbonHotKey()
        
        // 使用 Carbon API 註冊另一個快捷鍵作為備用（Cmd+Option+T）
        var eventType = EventTypeSpec()
        eventType.eventClass = OSType(kEventClassKeyboard)
        eventType.eventKind = OSType(kEventHotKeyPressed)
        
        // 安裝碳事件處理程序 - 使用弱引用避免循環引用
        // 在此使用unretained而不是retained來避免記憶體問題
        let selfPointer = Unmanaged.passUnretained(self).toOpaque()
        
        let status = InstallEventHandler(GetApplicationEventTarget(), { (_, event, userData) -> OSStatus in
            guard let userData = userData else {
                return noErr
            }
            
            // 使用 takeUnretainedValue 匹配 passUnretained
            let this = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
            this.logger.info("檢測到 Carbon 熱鍵按下")
            
            // 確保在主線程上調用 processSelectedText
            Task { @MainActor in
                this.processSelectedText()
            }
            
            return noErr
        }, 1, &eventType, selfPointer, &carbonEventHandler)
        
        // 註冊熱鍵
        if status == noErr {
            // Command + Option + T
            let keyCode: UInt32 = 17 // T key
            let modifiers: UInt32 = UInt32(cmdKey | optionKey) // Command + Option
            
            var hotKeyID = EventHotKeyID()
            hotKeyID.signature = OSType(fourCharCode(string: "TXCR"))
            hotKeyID.id = 1
            
            var hotKeyRef: EventHotKeyRef?
            
            let registerStatus = RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
            
            if registerStatus == noErr {
                logger.info("Carbon 熱鍵註冊成功: ⌘+⌥+T")
            } else {
                logger.error("Carbon 熱鍵註冊失敗: \(registerStatus)")
            }
        } else {
            logger.error("安裝 Carbon 事件處理程序失敗: \(status)")
            // 使用passUnretained時不需要釋放
        }
    }
    
    // 卸載 Carbon 熱鍵
    private func unregisterCarbonHotKey() {
        if let handler = carbonEventHandler {
            // 先將 handler 設為 nil 再調用 RemoveEventHandler，防止重複釋放
            let tempHandler = handler
            carbonEventHandler = nil
            RemoveEventHandler(tempHandler)
        }
    }
    
    // 將四個字符轉換為 OSType
    private func fourCharCode(string: String) -> UInt32 {
        var result: UInt32 = 0
        let chars = Array(string.utf8)
        for i in 0..<min(chars.count, 4) {
            // 修正位運算，避免溢出和非對齊問題
            result = (result << 8) | UInt32(chars[i])
        }
        return result
    }
    
    // 註冊額外的全局快捷鍵
    private func registerGlobalShortcut() {
        // 移除先前的監聽器
        removeGlobalMonitor()
        
        // 使用系統的事件監聽器註冊另一個熱鍵
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return }
            
            // Command + T
            let isCommandT = event.modifierFlags.contains(.command) && event.keyCode == 17
            
            // Control + Command + Space
            let isControlCmdSpace = event.modifierFlags.contains(.command) && event.modifierFlags.contains(.control) && event.keyCode == 49
            
            if isCommandT || isControlCmdSpace {
                let modString = isCommandT ? "Command+T" : "Control+Command+Space"
                self.logger.info("檢測到全局快捷鍵 \(modString)")
                
                // 確保在主線程上調用 processSelectedText
                Task { @MainActor in
                    self.processSelectedText()
                }
            }
        }
        
        logger.info("已註冊額外全局快捷鍵")
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