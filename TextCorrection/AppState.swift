import Foundation
import SwiftUI
import Combine
import os.log

/// 應用程式狀態管理中心
class AppState: ObservableObject, @unchecked Sendable {
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
    @Published var isProcessing: Bool = false
    @Published var processingProgress: Double = 0.0
    
    // 文本校正相關
    @Published var originalText: String = ""
    @Published var correctedText: String = ""
    @Published var errorMessage: String = ""
    
    // 擴展：UI 狀態
    @Published var activeScreen: ActiveScreen = .none
    @Published var isTextWindowOpen: Bool = false
    @Published var isSettingsWindowOpen: Bool = false
    @Published var isFloatingButtonVisible: Bool = false
    
    // 擴展：文本處理統計
    @Published var characterCount: Int = 0
    @Published var originalCharacterCount: Int = 0
    @Published var wordsChanged: Int = 0
    @Published var lastProcessingTime: TimeInterval = 0
    
    // 擴展：熱鍵狀態
    @Published var isHotkeyActive: Bool = true
    @Published var hotKeyModifiers: [String] = ["shift", "control"]
    @Published var hotKeyCharacter: String = "space"
    
    // 擴展：剪貼板監控
    @Published var isClipboardMonitoringEnabled: Bool = true
    @Published var lastClipboardChangeTime: Date = Date()
    
    // 擴展：通知
    @Published var notifications: [AppNotification] = []
    
    // 私有初始化方法以實現單例模式
    private init() {
        logger.info("初始化 AppState")
        // 從 UserDefaults 加載設定，但不使用監聽器
        loadSettings()
    }
    
    /// 從 UserDefaults 載入設定，在主線程上執行
    func loadSettings() {
        if Thread.isMainThread {
            doLoadSettings()
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.doLoadSettings()
            }
        }
    }
    
    /// 實際執行設定載入的方法
    private func doLoadSettings() {
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
        }
        
        if let modifiers = defaults.stringArray(forKey: "hotKeyModifiers") {
            self.hotKeyModifiers = modifiers
        }
        
        if let character = defaults.string(forKey: "hotKeyCharacter") {
            self.hotKeyCharacter = character
        }
        
        // 載入剪貼板監控設定
        if defaults.object(forKey: "isClipboardMonitoringEnabled") != nil {
            self.isClipboardMonitoringEnabled = defaults.bool(forKey: "isClipboardMonitoringEnabled")
        }
        
        logger.info("設定已載入")
    }
    
    /// 保存單個設定到 UserDefaults
    func saveSetting<T>(value: T, forKey key: String) {
        DispatchQueue.main.async {
            UserDefaults.standard.set(value, forKey: key)
        }
    }
    
    /// 更新視覺效果設定
    func updateVisualEffects(enabled: Bool) {
        self.isVisualEffectsEnabled = enabled
        saveSetting(value: enabled, forKey: "visualEffectsEnabled")
        logger.debug("視覺效果已\(enabled ? "啟用" : "禁用")")
    }
    
    /// 更新粒子效果設定
    func updateParticleEffects(enabled: Bool) {
        self.isParticleEffectsEnabled = enabled
        saveSetting(value: enabled, forKey: "particleEffectsEnabled")
        logger.debug("粒子效果已\(enabled ? "啟用" : "禁用")")
    }
    
    /// 更新動畫設定
    func updateAnimations(enabled: Bool) {
        self.isAnimationsEnabled = enabled
        saveSetting(value: enabled, forKey: "animationsEnabled")
        logger.debug("動畫已\(enabled ? "啟用" : "禁用")")
    }
    
    /// 更新高品質效果設定
    func updateHighQualityEffects(enabled: Bool) {
        self.isHighQualityEffectsEnabled = enabled
        saveSetting(value: enabled, forKey: "highQualityEffects")
        logger.debug("高品質效果已\(enabled ? "啟用" : "禁用")")
    }
    
    /// 更新熱鍵設定
    func updateHotkey(active: Bool, modifiers: [String]? = nil, character: String? = nil) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            self.isHotkeyActive = active
            saveSetting(value: active, forKey: "isHotkeyActive")
            
            if let modifiers = modifiers {
                self.hotKeyModifiers = modifiers
                saveSetting(value: modifiers, forKey: "hotKeyModifiers")
            }
            
            if let character = character {
                self.hotKeyCharacter = character
                saveSetting(value: character, forKey: "hotKeyCharacter")
            }
            
            logger.debug("熱鍵設定已更新，狀態: \(active ? "啟用" : "禁用")")
        }
    }
    
    /// 更新剪貼板監控設定
    func updateClipboardMonitoring(enabled: Bool) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            self.isClipboardMonitoringEnabled = enabled
            saveSetting(value: enabled, forKey: "isClipboardMonitoringEnabled")
            logger.debug("剪貼板監控已\(enabled ? "啟用" : "禁用")")
        }
    }
    
    /// 重置所有設定
    func resetSettings() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            logger.info("重置所有設定")
            
            self.isVisualEffectsEnabled = true
            self.isParticleEffectsEnabled = true
            self.isAnimationsEnabled = true
            self.isHighQualityEffectsEnabled = !ProcessInfo.processInfo.isLowPowerModeEnabled && ProcessInfo.processInfo.processorCount >= 4
            self.isHotkeyActive = true
            self.hotKeyModifiers = ["shift", "control"]
            self.hotKeyCharacter = "space"
            self.isClipboardMonitoringEnabled = true
            
            // 保存到 UserDefaults
            let defaults = UserDefaults.standard
            defaults.set(true, forKey: "visualEffectsEnabled")
            defaults.set(true, forKey: "particleEffectsEnabled")
            defaults.set(true, forKey: "animationsEnabled")
            defaults.set(self.isHighQualityEffectsEnabled, forKey: "highQualityEffects")
            defaults.set(true, forKey: "isHotkeyActive")
            defaults.set(["shift", "control"], forKey: "hotKeyModifiers")
            defaults.set("space", forKey: "hotKeyCharacter")
            defaults.set(true, forKey: "isClipboardMonitoringEnabled")
        }
    }
    
    /// 重置文本校正狀態
    func resetCorrectionState() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            logger.debug("重置文本校正狀態")
            
            self.originalText = ""
            self.correctedText = ""
            self.errorMessage = ""
            self.processingProgress = 0.0
            self.isProcessing = false
            self.characterCount = 0
            self.originalCharacterCount = 0
            self.wordsChanged = 0
            self.lastProcessingTime = 0
        }
    }
    
    /// 更新文本處理統計
    func updateTextStats(original: String, corrected: String, processingTime: TimeInterval, wordsChanged: Int) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            self.originalCharacterCount = original.count
            self.characterCount = corrected.count
            self.lastProcessingTime = processingTime
            self.wordsChanged = wordsChanged
            
            logger.debug("文本統計已更新: \(self.characterCount)字符, \(self.wordsChanged)個修改, 處理時間 \(processingTime)秒")
        }
    }
    
    /// 添加通知
    func addNotification(title: String, message: String, type: NotificationType = .info) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            let notification = AppNotification(
                id: UUID().uuidString,
                title: title,
                message: message,
                type: type,
                timestamp: Date()
            )
            
            self.notifications.append(notification)
            
            // 最多保留最近的10條通知
            if self.notifications.count > 10 {
                self.notifications.removeFirst()
            }
            
            logger.debug("添加了新通知: \(title)")
        }
    }
    
    /// 刪除通知
    func removeNotification(id: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            self.notifications.removeAll { $0.id == id }
            logger.debug("刪除了通知 ID: \(id)")
        }
    }
    
    /// 清空所有通知
    func clearAllNotifications() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            self.notifications.removeAll()
            logger.debug("清空了所有通知")
        }
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
    func updateTextInfo(original: String, corrected: String) {
        self.originalText = original
        self.correctedText = corrected
        self.originalCharacterCount = original.count
        self.characterCount = corrected.count
        
        // 計算差異
        self.wordsChanged = TextProcessing.calculateChangedWords(
            original: original,
            rewritten: corrected
        )
        
        // 發送通知
        logger.debug("文本已更新：原始字符數 \(self.originalCharacterCount)，校正後字符數 \(self.characterCount)，變更詞數 \(self.wordsChanged)")
        self.objectWillChange.send()
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