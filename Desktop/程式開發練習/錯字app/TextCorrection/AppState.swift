import Foundation
import SwiftUI
import Combine
import os.log
import ApplicationServices

/// 應用程式狀態管理中心
class AppState: ObservableObject, @unchecked Sendable {
    // 單例模式，簡化實現
    static let shared = AppState()
    
    // 創建日誌對象，便於調試
    private let logger = Logger(subsystem: "com.yourcompany.TextCorrection", category: "AppState")
    
    // 序列化隊列，用於確保狀態修改的線程安全
    private let stateQueue = DispatchQueue(label: "com.yourcompany.TextCorrection.AppState", qos: .userInitiated)
    
    // 專用於熱鍵操作的隊列，解決多線程訪問問題
    private let hotKeyQueue = DispatchQueue(label: "com.yourcompany.TextCorrection.AppState.HotKey", qos: .userInitiated)
    
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
    
    // 私有初始化器防止外部創建實例
    private init() {
        logger.debug("AppState 初始化")
        loadSettings()
    }
    
    // MARK: - 線程安全的狀態更新方法
    
    /// 安全地更新屬性值
    /// - Parameters:
    ///   - keyPath: 要更新的屬性路徑
    ///   - value: 新的值
    func safelyUpdate<T>(_ keyPath: ReferenceWritableKeyPath<AppState, T>, value: T) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self[keyPath: keyPath] = value
        }
    }
    
    /// 安全地執行閉包操作
    /// - Parameter action: 要執行的閉包
    func safelyPerform(_ action: @escaping () -> Void) {
        DispatchQueue.main.async {
            action()
        }
    }
    
    // MARK: - 基本設定更新方法
    
    func updateVisualEffects(enabled: Bool) {
        safelyUpdate(\.isVisualEffectsEnabled, value: enabled)
        saveSettings()
    }
    
    func updateParticleEffects(enabled: Bool) {
        safelyUpdate(\.isParticleEffectsEnabled, value: enabled)
        saveSettings()
    }
    
    func updateAnimations(enabled: Bool) {
        safelyUpdate(\.isAnimationsEnabled, value: enabled)
        saveSettings()
    }
    
    func updateHighQualityEffects(enabled: Bool) {
        safelyUpdate(\.isHighQualityEffectsEnabled, value: enabled)
        saveSettings()
    }
    
    func updateHotkey(active: Bool) {
        safelyUpdate(\.isHotkeyActive, value: active)
        saveSettings()
    }
    
    /// 更新熱鍵設定，包含狀態、修飾鍵和主鍵
    /// - Parameters:
    ///   - active: 是否啟用熱鍵
    ///   - modifiers: 修飾鍵陣列
    ///   - character: 主鍵字符
    func updateHotkeySettings(active: Bool, modifiers: [String]? = nil, character: String? = nil) {
        logger.info("🔄 正在更新熱鍵設定: active=\(active), modifiers=\(modifiers?.description ?? "未變更"), character=\(character ?? "未變更")")
        
        // 如果要啟用熱鍵，先檢查權限
        if active {
            // 檢查輔助功能權限
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false]
            let accessEnabled = AXIsProcessTrustedWithOptions(options as CFDictionary)
            
            if !accessEnabled {
                logger.warning("⚠️ 嘗試啟用熱鍵但缺少輔助功能權限")
                
                // 在主線程上顯示權限請求對話框
                DispatchQueue.main.async {
                    if let appDelegate = NSApp.delegate as? AppDelegate {
                        appDelegate.checkAccessibilityPermissions()
                    } else {
                        // 如果無法獲取 AppDelegate，直接顯示提示
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
                }
                
                // 返回前將 active 設為 false，避免啟用時沒有權限
                // 使用專用的熱鍵隊列來確保線程安全
                hotKeyQueue.async { [weak self] in
                    guard let self = self else { return }
                    
                    // 將更新操作派發到主線程
                    DispatchQueue.main.async {
                        // 設定禁用狀態
                        self.isHotkeyActive = false
                        
                        if let modifiers = modifiers {
                            self.hotKeyModifiers = modifiers
                        }
                        
                        if let character = character {
                            self.hotKeyCharacter = character
                        }
                        
                        self.saveSettings()
                        
                        // 發送熱鍵設定變更通知
                        NotificationCenter.default.post(name: NSNotification.Name("HotKeySettingsChanged"), object: nil)
                        
                        self.logger.debug("熱鍵設定已更新(禁用，因權限不足): 狀態=false, 修飾鍵=\(self.hotKeyModifiers), 主鍵=\(self.hotKeyCharacter)")
                    }
                }
                
                return
            }
        }
        
        // 使用專用的熱鍵隊列來確保線程安全
        hotKeyQueue.async { [weak self] in
            guard let self = self else { return }
            
            // 將更新操作派發到主線程
            DispatchQueue.main.async {
                let oldActive = self.isHotkeyActive
                let oldModifiers = self.hotKeyModifiers
                let oldCharacter = self.hotKeyCharacter
                
                // 更新狀態
                self.isHotkeyActive = active
                
                if let modifiers = modifiers {
                    self.hotKeyModifiers = modifiers
                }
                
                if let character = character {
                    self.hotKeyCharacter = character
                }
                
                // 保存設定
                self.saveSettings()
                self.logger.info("✅ 熱鍵設定已保存")
                
                // 檢查是否有變化
                let hasChanges = (oldActive != active) || 
                                (modifiers != nil && oldModifiers != self.hotKeyModifiers) || 
                                (character != nil && oldCharacter != self.hotKeyCharacter)
                
                if hasChanges {
                    self.logger.info("📣 熱鍵設定有變更，發送通知")
                    // 發送熱鍵設定變更通知
                    NotificationCenter.default.post(name: NSNotification.Name("HotKeySettingsChanged"), object: nil)
                    
                    // 強制重新注冊熱鍵
                    if let appDelegate = NSApp.delegate as? AppDelegate, let hotKeyManager = appDelegate.hotKeyManager {
                        DispatchQueue.main.async {
                            self.logger.info("⚙️ 正在重新設置熱鍵...")
                            hotKeyManager.setupHotKey()
                        }
                    }
                } else {
                    self.logger.info("ℹ️ 熱鍵設定無變化，不發送通知")
                }
                
                self.logger.debug("熱鍵設定已更新: 狀態=\(active), 修飾鍵=\(self.hotKeyModifiers), 主鍵=\(self.hotKeyCharacter)")
            }
        }
    }
    
    func updateClipboardMonitoring(enabled: Bool) {
        safelyUpdate(\.isClipboardMonitoringEnabled, value: enabled)
        saveSettings()
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
            logger.info("從設定讀取熱鍵狀態: \(self.isHotkeyActive)")
        } else {
            // 首次執行，設置為預設值 (開啟)
            self.isHotkeyActive = true
            logger.info("首次執行，設置熱鍵狀態為默認開啟")
        }
        
        if let modifiers = defaults.stringArray(forKey: "hotKeyModifiers") {
            self.hotKeyModifiers = modifiers
            logger.info("從設定讀取熱鍵修飾鍵: \(modifiers)")
        } else {
            // 首次執行，設置為預設值
            self.hotKeyModifiers = ["shift", "control"]
            logger.info("首次執行，設置熱鍵修飾鍵為默認值: ['shift', 'control']")
        }
        
        if let character = defaults.string(forKey: "hotKeyCharacter") {
            self.hotKeyCharacter = character
            logger.info("從設定讀取熱鍵字符: \(character)")
        } else {
            // 首次執行，設置為預設值
            self.hotKeyCharacter = "space"
            logger.info("首次執行，設置熱鍵字符為默認值: 'space'")
        }
        
        // 載入剪貼板監控設定
        if defaults.object(forKey: "isClipboardMonitoringEnabled") != nil {
            self.isClipboardMonitoringEnabled = defaults.bool(forKey: "isClipboardMonitoringEnabled")
        }
        
        // 首次載入完成後保存設定，確保默認值被寫入
        if defaults.object(forKey: "isHotkeyActive") == nil {
            saveSettings()
            logger.info("首次執行，保存默認設定到 UserDefaults")
        }
        
        logger.info("設定已載入，當前熱鍵狀態: \(self.isHotkeyActive), 修飾鍵: \(self.hotKeyModifiers), 主鍵: \(self.hotKeyCharacter)")
    }
    
    /// 保存單個設定到 UserDefaults
    func saveSetting<T>(value: T, forKey key: String) {
        DispatchQueue.main.async {
            UserDefaults.standard.set(value, forKey: key)
        }
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
        safelyPerform { [weak self] in
            guard let self = self else { return }
            self.isVisualEffectsEnabled = true
            self.isParticleEffectsEnabled = true
            self.isAnimationsEnabled = true
            self.isHighQualityEffectsEnabled = true
            self.isHotkeyActive = true
            self.isClipboardMonitoringEnabled = true
            self.saveSettings()
        }
        logger.debug("已重置所有設定")
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