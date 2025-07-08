import Foundation
import SwiftUI
import Combine
import os.log
import ApplicationServices

/// 應用程式狀態管理中心
@MainActor
class AppState: ObservableObject {
    // 單例模式，簡化實現
    static let shared = AppState()
    
    // 創建日誌對象，便於調試
    private let logger = Logger(subsystem: "com.yourcompany.TextCorrection", category: "AppState")
    
    // 基本設定，使用默認值而不是直接讀取 UserDefaults
    @Published var isVisualEffectsEnabled: Bool = true 
    @Published var isParticleEffectsEnabled: Bool = true
    @Published var isAnimationsEnabled: Bool = true
    @Published var isHighQualityEffectsEnabled: Bool = true
    
    // API 狀態
    @Published var isApiKeyValid: Bool = false
    
    // 處理狀態
    @Published var isProcessing: Bool = false {
        didSet {
            if oldValue != isProcessing {
                NotificationCenter.default.post(name: NSNotification.Name("TextProcessingStateChanged"), object: nil)
            }
        }
    }
    
    @Published var processingProgress: Double = 0.0
    @Published var hasShownWelcomeScreen: Bool = false
    
    // 文本校正相關
    @Published var originalText: String = ""
    @Published var correctedText: String = ""
    @Published var errorMessage: String = ""
    
    // 擴展：UI 狀態
    @Published var activeScreen: ActiveScreen = .none
    @Published var isTextWindowOpen: Bool = false
    @Published var isSettingsWindowOpen: Bool = false
    @Published var isFloatingButtonVisible: Bool = false
    @Published var isFeedbackViewOpen: Bool = false
    
    // 擴展：文本處理統計
    @Published var characterCount: Int = 0
    @Published var originalCharacterCount: Int = 0
    @Published var wordsChanged: Int = 0
    @Published var lastProcessingTime: TimeInterval = 0
    
    // 熱鍵狀態
    @Published var isHotkeyActive: Bool = true
    @Published var hotKeyModifiers: [String] = ["shift", "control"]
    @Published var hotKeyCharacter: String = "space"
    
    // 擴展：剪貼板監控
    @Published var isClipboardMonitoringEnabled: Bool = true
    @Published var lastClipboardChangeTime: Date = Date()
    
    // 擴展：通知
    @Published var notifications: [AppNotification] = []
    
    // 私有初始化器防止外部創建實例
    private init() {
        logger.debug("AppState 初始化")
        // 檢查是否首次啟動
        hasShownWelcomeScreen = UserDefaults.standard.bool(forKey: "hasShownWelcomeScreen")
        loadSettings()
    }
    
    // MARK: - 設定更新方法
    
    func updateVisualEffects(enabled: Bool) {
        isVisualEffectsEnabled = enabled
        saveSettings()
    }
    
    func updateParticleEffects(enabled: Bool) {
        isParticleEffectsEnabled = enabled
        saveSettings()
    }
    
    func updateAnimations(enabled: Bool) {
        isAnimationsEnabled = enabled
        saveSettings()
    }
    
    func updateHighQualityEffects(enabled: Bool) {
        isHighQualityEffectsEnabled = enabled
        saveSettings()
    }
    
    func updateHotkey(active: Bool) {
        isHotkeyActive = active
        saveSettings()
    }
    
    /// 更新熱鍵設定，包含狀態、修飾鍵和主鍵
    /// - Parameters:
    ///   - active: 是否啟用熱鍵
    ///   - modifiers: 修飾鍵陣列
    ///   - character: 主鍵字符
    func updateHotkeySettings(active: Bool, modifiers: [String]? = nil, character: String? = nil) {
        logger.info("正在更新熱鍵設定: active=\(active), modifiers=\(modifiers?.description ?? "未變更"), character=\(character ?? "未變更")")
        
        isHotkeyActive = active
        
        if let modifiers = modifiers {
            hotKeyModifiers = modifiers
        }
        
        if let character = character {
            hotKeyCharacter = character
        }
        
        saveSettings()
        
        // 通知熱鍵設定變更
        NotificationCenter.default.post(name: NSNotification.Name("HotKeySettingsChanged"), object: nil)
        logger.info("熱鍵設定更新完成並已發送通知")
    }
    
    func updateClipboardMonitoring(enabled: Bool) {
        isClipboardMonitoringEnabled = enabled
        saveSettings()
    }
    
    /// 從 UserDefaults 載入設定
    func loadSettings() {
        let defaults = UserDefaults.standard
        
        // 載入基本設定
        if defaults.object(forKey: "visualEffectsEnabled") != nil {
            isVisualEffectsEnabled = defaults.bool(forKey: "visualEffectsEnabled")
        }
        
        if defaults.object(forKey: "particleEffectsEnabled") != nil {
            isParticleEffectsEnabled = defaults.bool(forKey: "particleEffectsEnabled")
        }
        
        if defaults.object(forKey: "animationsEnabled") != nil {
            isAnimationsEnabled = defaults.bool(forKey: "animationsEnabled")
        }
        
        if defaults.object(forKey: "highQualityEffects") != nil {
            isHighQualityEffectsEnabled = defaults.bool(forKey: "highQualityEffects")
        } else {
            // 如果沒有儲存設定，根據設備性能設置高品質效果
            isHighQualityEffectsEnabled = !ProcessInfo.processInfo.isLowPowerModeEnabled && ProcessInfo.processInfo.processorCount >= 4
        }
        
        // 載入熱鍵設定
        if defaults.object(forKey: "isHotkeyActive") != nil {
            isHotkeyActive = defaults.bool(forKey: "isHotkeyActive")
            logger.info("從設定讀取熱鍵狀態: \(isHotkeyActive)")
        } else {
            // 首次執行，設置為預設值 (開啟)
            isHotkeyActive = true
            logger.info("首次執行，設置熱鍵狀態為默認開啟")
        }
        
        if let modifiers = defaults.stringArray(forKey: "hotKeyModifiers") {
            hotKeyModifiers = modifiers
            logger.info("從設定讀取熱鍵修飾鍵: \(modifiers)")
        } else {
            // 首次執行，設置為預設值
            hotKeyModifiers = ["shift", "control"]
            logger.info("首次執行，設置熱鍵修飾鍵為默認值: ['shift', 'control']")
        }
        
        if let character = defaults.string(forKey: "hotKeyCharacter") {
            hotKeyCharacter = character
            logger.info("從設定讀取熱鍵字符: \(character)")
        } else {
            // 首次執行，設置為預設值
            hotKeyCharacter = "space"
            logger.info("首次執行，設置熱鍵字符為默認值: 'space'")
        }
        
        // 載入剪貼板監控設定
        if defaults.object(forKey: "isClipboardMonitoringEnabled") != nil {
            isClipboardMonitoringEnabled = defaults.bool(forKey: "isClipboardMonitoringEnabled")
        }
        
        // 首次載入完成後保存設定，確保默認值被寫入
        if defaults.object(forKey: "isHotkeyActive") == nil {
            saveSettings()
            logger.info("首次執行，保存默認設定到 UserDefaults")
            
            // 首次執行設置後主動發送設定變更通知
            NotificationCenter.default.post(name: NSNotification.Name("HotKeySettingsChanged"), object: nil)
            logger.info("首次執行，發送熱鍵設定變更通知")
        }
        
        logger.info("設定已載入，當前熱鍵狀態: \(isHotkeyActive), 修飾鍵: \(hotKeyModifiers), 主鍵: \(hotKeyCharacter)")
    }
    
    /// 保存單個設定到 UserDefaults
    func saveSetting<T>(value: T, forKey key: String) {
        UserDefaults.standard.set(value, forKey: key)
    }
    
    /// 保存所有設定到 UserDefaults
    func saveSettings() {
        saveSetting(value: isVisualEffectsEnabled, forKey: "visualEffectsEnabled")
        saveSetting(value: isParticleEffectsEnabled, forKey: "particleEffectsEnabled")
        saveSetting(value: isAnimationsEnabled, forKey: "animationsEnabled")
        saveSetting(value: isHighQualityEffectsEnabled, forKey: "highQualityEffects")
        saveSetting(value: isHotkeyActive, forKey: "isHotkeyActive")
        saveSetting(value: hotKeyModifiers, forKey: "hotKeyModifiers")
        saveSetting(value: hotKeyCharacter, forKey: "hotKeyCharacter")
        saveSetting(value: isClipboardMonitoringEnabled, forKey: "isClipboardMonitoringEnabled")
        logger.info("已保存所有設定")
    }
    
    /// 重置所有設定
    func resetSettings() {
        isVisualEffectsEnabled = true
        isParticleEffectsEnabled = true
        isAnimationsEnabled = true
        isHighQualityEffectsEnabled = true
        isHotkeyActive = true
        hotKeyModifiers = ["shift", "control"]
        hotKeyCharacter = "space"
        isClipboardMonitoringEnabled = true
        saveSettings()
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
    
    /// 更新文本處理統計
    func updateTextStats(original: String, corrected: String, processingTime: TimeInterval, wordsChanged: Int) {
        originalCharacterCount = original.count
        characterCount = corrected.count
        lastProcessingTime = processingTime
        self.wordsChanged = wordsChanged
        
        logger.debug("文本統計已更新: \(characterCount)字符, \(self.wordsChanged)個修改, 處理時間 \(processingTime)秒")
    }
    
    /// 添加通知
    func addNotification(title: String, message: String, type: NotificationType = .info) {
        let notification = AppNotification(
            id: UUID().uuidString,
            title: title,
            message: message,
            type: type,
            timestamp: Date()
        )
        
        notifications.append(notification)
        
        // 最多保留最近的10條通知
        if notifications.count > 10 {
            notifications.removeFirst()
        }
        
        logger.debug("添加了新通知: \(title)")
    }
    
    /// 刪除通知
    func removeNotification(id: String) {
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
        視覺效果: \(isVisualEffectsEnabled)
        粒子效果: \(isParticleEffectsEnabled)
        動畫: \(isAnimationsEnabled)
        高品質效果: \(isHighQualityEffectsEnabled)
        API有效: \(isApiKeyValid)
        處理中: \(isProcessing) (\(processingProgress))
        文本窗口: \(isTextWindowOpen)
        設置窗口: \(isSettingsWindowOpen)
        浮動按鈕: \(isFloatingButtonVisible)
        熱鍵狀態: \(isHotkeyActive)
        剪貼板監控: \(isClipboardMonitoringEnabled)
        通知數量: \(notifications.count)
        ===========================
        """)
    }
    
    // 當文本修正完成時調用此方法
    func updateTextInfo(original: String, corrected: String) {
        originalText = original
        correctedText = corrected
        originalCharacterCount = original.count
        characterCount = corrected.count
        
        // 計算差異
        wordsChanged = TextProcessing.calculateChangedWords(
            original: original,
            rewritten: corrected
        )
        
        // 發送通知
        logger.debug("文本已更新：原始字符數 \(originalCharacterCount)，校正後字符數 \(characterCount)，變更詞數 \(wordsChanged)")
    }
    
    /// 標記歡迎頁面已顯示
    func markWelcomeScreenAsShown() {
        hasShownWelcomeScreen = true
        UserDefaults.standard.set(true, forKey: "hasShownWelcomeScreen")
    }
}

// MARK: - 輔助類型

/// 活動螢幕枚舉
enum ActiveScreen {
    case none
    case textCorrection
    case settings
    case about
}

/// 通知類型枚舉
enum NotificationType {
    case info
    case success
    case warning
    case error
}

/// 應用通知結構
struct AppNotification: Identifiable {
    let id: String
    let title: String
    let message: String
    let type: NotificationType
    let timestamp: Date
} 