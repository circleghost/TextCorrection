import Foundation
import SwiftUI
import Combine
import os.log

/// 應用程式狀態管理中心 - 使用Actor模型確保線程安全
actor AppState {
    // 單例模式，簡化實現
    static let shared = AppState()
    
    // 創建日誌對象，便於調試
    private let logger = Logger(subsystem: "com.yourcompany.TextCorrection", category: "AppState")
    
    // 基本設定，使用默認值而不是直接讀取 UserDefaults
    var isVisualEffectsEnabled: Bool = true 
    var isParticleEffectsEnabled: Bool = true
    var isAnimationsEnabled: Bool = true
    var isHighQualityEffectsEnabled: Bool = true
    
    // API 狀態
    var isApiKeyValid: Bool = false
    var isProcessing: Bool = false
    var processingProgress: Double = 0.0
    
    // 文本校正相關
    var originalText: String = ""
    var correctedText: String = ""
    var errorMessage: String = ""
    
    // 擴展：UI 狀態
    var activeScreen: ActiveScreen = .none
    var isTextWindowOpen: Bool = false
    var isSettingsWindowOpen: Bool = false
    var isFloatingButtonVisible: Bool = false
    
    // 擴展：文本處理統計
    var characterCount: Int = 0
    var originalCharacterCount: Int = 0
    var wordsChanged: Int = 0
    var lastProcessingTime: TimeInterval = 0
    
    // 擴展：熱鍵狀態
    var isHotkeyActive: Bool = true
    var hotKeyModifiers: [String] = ["shift", "control"]
    var hotKeyCharacter: String = "space"
    
    // 擴展：剪貼板監控
    var isClipboardMonitoringEnabled: Bool = true
    var lastClipboardChangeTime: Date = Date()
    
    // 擴展：通知
    var notifications: [AppNotification] = []

    // 添加缺少的屬性供 AppStateObserver 使用
    var lastError: String = ""
    var statusMessage: String = ""
    var fontSize: CGFloat = 12.0
    var apiKey: String = ""
    var isOpenAIServiceAvailable: Bool = true
    var isMonitoringClipboard: Bool = false
    var correctionHotkey: String = ""
    var hotkeysEnabled: Bool = true
    var changedWordsCount: Int = 0
    var textProcessingTime: TimeInterval = 0
    var correctedCharacterCount: Int = 0
    
    // 私有初始化器防止外部創建實例
    private init() {
        logger.debug("AppState 初始化")
        Task {
            await loadSettings()
        }
    }
    
    // MARK: - 基本設定更新方法
    
    func updateVisualEffects(_ enabled: Bool) {
        isVisualEffectsEnabled = enabled
        Task {
            await saveSettings()
        }
    }
    
    func updateParticleEffects(_ enabled: Bool) {
        isParticleEffectsEnabled = enabled
        Task {
            await saveSettings()
        }
    }
    
    func updateAnimations(enabled: Bool) {
        isAnimationsEnabled = enabled
        Task {
            await saveSettings()
        }
    }
    
    func updateHighQualityEffects(enabled: Bool) {
        isHighQualityEffectsEnabled = enabled
        Task {
            await saveSettings()
        }
    }
    
    func updateHotkey(active: Bool) {
        isHotkeyActive = active
        Task {
            await saveSettings()
        }
    }
    
    /// 更新熱鍵設定，包含狀態、修飾鍵和主鍵
    /// - Parameters:
    ///   - active: 是否啟用熱鍵
    ///   - modifiers: 修飾鍵陣列
    ///   - character: 主鍵字符
    func updateHotkeySettings(active: Bool, modifiers: [String]? = nil, character: String? = nil) {
        isHotkeyActive = active
        hotkeysEnabled = active
        
        if let modifiers = modifiers {
            hotKeyModifiers = modifiers
        }
        
        if let character = character {
            hotKeyCharacter = character
            correctionHotkey = character
        }
        
        Task {
            await saveSettings()
            
            // 如果有熱鍵管理器，通知其更新熱鍵設定
            // 需要在主線程上發布通知
            await MainActor.run {
                NotificationCenter.default.post(name: NSNotification.Name("HotKeySettingsChanged"), object: nil)
            }
        }
        
        logger.debug("熱鍵設定已更新: 狀態=\(active), 修飾鍵=\(self.hotKeyModifiers), 主鍵=\(self.hotKeyCharacter)")
    }
    
    func updateClipboardMonitoring(_ enabled: Bool) {
        isClipboardMonitoringEnabled = enabled
        isMonitoringClipboard = enabled
        Task {
            await saveSettings()
        }
    }
    
    /// 從 UserDefaults 載入設定
    func loadSettings() async {
        await MainActor.run {
            let defaults = UserDefaults.standard
            
            // 使用安全的方式讀取設定
            if defaults.object(forKey: "visualEffectsEnabled") != nil {
                self.isVisualEffectsEnabled = defaults.bool(forKey: "visualEffectsEnabled")
            }
            
            if defaults.object(forKey: "particleEffectsEnabled") != nil {
                self.isParticleEffectsEnabled = defaults.bool(forKey: "particleEffectsEnabled")
            }
            
            if defaults.object(forKey: "animationsEnabled") != nil {
                self.isAnimationsEnabled = defaults.bool(forKey: "animationsEnabled")
            }
            
            if defaults.object(forKey: "highQualityEffects") != nil {
                self.isHighQualityEffectsEnabled = defaults.bool(forKey: "highQualityEffects")
            } else {
                // 如果沒有儲存設定，根據設備性能設置高品質效果
                self.isHighQualityEffectsEnabled = !ProcessInfo.processInfo.isLowPowerModeEnabled && ProcessInfo.processInfo.processorCount >= 4
            }
            
            // 載入熱鍵設定
            if defaults.object(forKey: "isHotkeyActive") != nil {
                self.isHotkeyActive = defaults.bool(forKey: "isHotkeyActive")
                self.hotkeysEnabled = self.isHotkeyActive
            }
            
            if let modifiers = defaults.stringArray(forKey: "hotKeyModifiers") {
                self.hotKeyModifiers = modifiers
            }
            
            if let character = defaults.string(forKey: "hotKeyCharacter") {
                self.hotKeyCharacter = character
                self.correctionHotkey = character
            }
            
            // 載入剪貼板監控設定
            if defaults.object(forKey: "isClipboardMonitoringEnabled") != nil {
                self.isClipboardMonitoringEnabled = defaults.bool(forKey: "isClipboardMonitoringEnabled")
                self.isMonitoringClipboard = self.isClipboardMonitoringEnabled
            }
            
            // 載入API金鑰
            if let key = KeychainHelper.getAPIKey() {
                self.apiKey = key
            }
            
            self.logger.info("設定已載入")
        }
    }
    
    /// 保存單個設定到 UserDefaults
    private func saveSetting<T>(value: T, forKey key: String) async {
        await MainActor.run {
            UserDefaults.standard.set(value, forKey: key)
        }
    }
    
    /// 保存所有設定到 UserDefaults
    func saveSettings() async {
        await saveSetting(value: isVisualEffectsEnabled, forKey: "visualEffectsEnabled")
        await saveSetting(value: isParticleEffectsEnabled, forKey: "particleEffectsEnabled")
        await saveSetting(value: isAnimationsEnabled, forKey: "animationsEnabled")
        await saveSetting(value: isHighQualityEffectsEnabled, forKey: "highQualityEffects")
        await saveSetting(value: isHotkeyActive, forKey: "isHotkeyActive")
        await saveSetting(value: hotKeyModifiers, forKey: "hotKeyModifiers")
        await saveSetting(value: hotKeyCharacter, forKey: "hotKeyCharacter")
        await saveSetting(value: isClipboardMonitoringEnabled, forKey: "isClipboardMonitoringEnabled")
        logger.info("已保存所有設定")
    }
    
    /// 重置所有設定
    func resetSettings() {
        isVisualEffectsEnabled = true
        isParticleEffectsEnabled = true
        isAnimationsEnabled = true
        isHighQualityEffectsEnabled = true
        isHotkeyActive = true
        isClipboardMonitoringEnabled = true
        
        Task {
            await saveSettings()
        }
        
        logger.debug("已重置所有設定")
    }
    
    /// 重置文本校正狀態
    func resetCorrectionState() {
        logger.debug("重置文本校正狀態")
        
        originalText = ""
        correctedText = ""
        errorMessage = ""
        processingProgress = 0.0
        isProcessing = false
        characterCount = 0
        originalCharacterCount = 0
        wordsChanged = 0
        lastProcessingTime = 0
    }
    
    // MARK: - 新增方法，支持AppDelegate和AppKitBridge
    
    /// 更新API金鑰有效性
    func updateApiKeyValid(_ isValid: Bool) {
        isApiKeyValid = isValid
        logger.debug("API金鑰有效性已更新: \(isValid)")
    }
    
    /// 設置活動畫面
    func setActiveScreen(_ screen: ActiveScreen) {
        activeScreen = screen
        logger.debug("活動畫面已設置為: \(screen)")
    }
    
    /// 更新窗口狀態
    func updateWindowState(type: String, isOpen: Bool) {
        switch type {
        case "text":
            isTextWindowOpen = isOpen
        case "settings":
            isSettingsWindowOpen = isOpen
        default:
            logger.warning("未知的窗口類型: \(type)")
        }
        logger.debug("窗口狀態已更新 - 類型: \(type), 開啟: \(isOpen)")
    }
    
    /// 更新處理狀態
    func updateProcessingStatus(_ isProcessing: Bool) {
        self.isProcessing = isProcessing
        logger.debug("處理狀態已更新: \(isProcessing)")
    }
    
    /// 更新OpenAI服務可用性
    func updateOpenAIServiceAvailability(_ isAvailable: Bool) {
        isOpenAIServiceAvailable = isAvailable
        logger.debug("OpenAI服務可用性已更新: \(isAvailable)")
    }
    
    /// 更新錯誤訊息
    func updateErrorMessage(_ message: String) {
        lastError = message
        logger.error("錯誤訊息: \(message)")
    }
    
    /// 更新狀態訊息
    func updateStatusMessage(_ message: String) {
        statusMessage = message
        logger.info("狀態訊息: \(message)")
    }
    
    /// 更新文字大小
    func updateFontSize(_ size: CGFloat) {
        fontSize = size
        Task {
            await saveSetting(value: size, forKey: "fontSize")
        }
        logger.debug("字體大小已更新: \(size)")
    }
    
    /// 更新API金鑰
    func updateApiKey(_ key: String) {
        apiKey = key
        Task {
            await MainActor.run {
                KeychainHelper.saveAPIKey(key)
            }
        }
        logger.debug("API金鑰已更新")
    }
    
    /// 重置狀態
    func resetState() {
        resetCorrectionState()
        lastError = ""
        statusMessage = ""
        logger.debug("狀態已重置")
    }
    
    /// 更新文本處理統計
    func updateTextStats(originalCharCount: Int, correctedCharCount: Int, processingTime: TimeInterval) {
        originalCharacterCount = originalCharCount
        correctedCharacterCount = correctedCharCount
        textProcessingTime = processingTime
        
        logger.debug("文本統計已更新: 原始字符數 \(originalCharCount), 校正字符數 \(correctedCharCount), 處理時間 \(processingTime)秒")
    }
    
    /// 添加通知
    func addNotification(type: NotificationType, message: String) {
        let notification = AppNotification(
            id: UUID(),
            title: type.rawValue,
            message: message,
            type: type,
            timestamp: Date()
        )
        
        notifications.append(notification)
        
        // 最多保留最近的10條通知
        if notifications.count > 10 {
            notifications.removeFirst()
        }
        
        logger.debug("添加了新通知: \(type.rawValue) - \(message)")
    }
    
    /// 移除通知
    func removeNotification(id: UUID) {
        notifications.removeAll { $0.id == id }
        logger.debug("刪除了通知 ID: \(id)")
    }
    
    /// 清空所有通知
    func clearAllNotifications() {
        notifications.removeAll()
        logger.debug("清空了所有通知")
    }
    
    /// 打印當前狀態（用於調試）
    func printDebugState() {
        logger.debug("""
        ===== AppState 狀態 =====
        視覺效果: \(self.isVisualEffectsEnabled)
        粒子效果: \(self.isParticleEffectsEnabled)
        動畫: \(self.isAnimationsEnabled)
        高品質效果: \(self.isHighQualityEffectsEnabled)
        API有效: \(self.isApiKeyValid)
        處理中: \(self.isProcessing) (\(self.processingProgress))
        文本窗口: \(self.isTextWindowOpen)
        設置窗口: \(self.isSettingsWindowOpen)
        浮動按鈕: \(self.isFloatingButtonVisible)
        熱鍵狀態: \(self.isHotkeyActive)
        剪貼板監控: \(self.isClipboardMonitoringEnabled)
        通知數量: \(self.notifications.count)
        ===========================
        """)
    }
    
    // 當文本修正完成時調用此方法
    func updateTextInfo(originalText: String, correctedText: String) {
        self.originalText = originalText
        self.correctedText = correctedText
        originalCharacterCount = originalText.count
        correctedCharacterCount = correctedText.count
        
        // 計算差異
        changedWordsCount = TextProcessing.calculateChangedWords(
            original: originalText,
            rewritten: correctedText
        )
        
        // 記錄日誌
        logger.debug("文本已更新：原始字符數 \(self.originalCharacterCount)，校正後字符數 \(self.correctedCharacterCount)，變更詞數 \(self.changedWordsCount)")
    }
}

// MARK: - 輔助類型

/// 活動螢幕枚舉
enum ActiveScreen {
    case none
    case textCorrection
    case settings
    case about
    case main
}

/// 通知類型枚舉
enum NotificationType: String {
    case info = "信息"
    case success = "成功"
    case warning = "警告"
    case error = "錯誤"
}

/// 應用通知結構
struct AppNotification: Identifiable {
    let id: UUID
    let title: String
    let message: String
    let type: NotificationType
    let timestamp: Date
}

// 新增 KeychainHelper 結構體，用於處理 API 金鑰的存取
struct KeychainHelper {
    private static let service = "com.yourcompany.TextCorrection"
    private static let account = "OpenAIApiKey"
    
    static func saveAPIKey(_ key: String) {
        do {
            let keychain = KeychainAccess.Keychain(service: service)
            try keychain.set(key, key: account)
        } catch {
            print("無法儲存 API 金鑰: \(error.localizedDescription)")
        }
    }
    
    static func getAPIKey() -> String? {
        do {
            let keychain = KeychainAccess.Keychain(service: service)
            return try keychain.get(account)
        } catch {
            print("無法取得 API 金鑰: \(error.localizedDescription)")
            return nil
        }
    }
    
    static func deleteAPIKey() {
        do {
            let keychain = KeychainAccess.Keychain(service: service)
            try keychain.remove(account)
        } catch {
            print("無法刪除 API 金鑰: \(error.localizedDescription)")
        }
    }
} 