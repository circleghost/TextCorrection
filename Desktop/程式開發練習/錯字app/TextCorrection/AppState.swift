import Foundation
import SwiftUI
import Combine
import os.log

/// AppState: 應用程序的狀態管理器
@MainActor
class AppState: ObservableObject {
    private let logger = Logger(subsystem: "com.yourcompany.TextCorrection", category: "AppState")
    
    /// 單例實例
    static let shared = AppState()
    
    // MARK: - 已發布的屬性
    
    // 基本設置
    @Published var isVisualEffectsEnabled: Bool = true
    @Published var isParticleEffectsEnabled: Bool = true
    @Published var isApiKeyValid: Bool = false
    @Published var isProcessing: Bool = false
    @Published var isOpenAIServiceAvailable: Bool = true
    @Published var isClipboardMonitoringEnabled: Bool = false
    
    // 文本相關
    @Published var originalText: String = ""
    @Published var correctedText: String = ""
    @Published var changedWordsCount: Int = 0
    @Published var textProcessingTime: TimeInterval = 0
    @Published var originalCharacterCount: Int = 0
    @Published var correctedCharacterCount: Int = 0
    
    // 通知和UI狀態
    @Published var notifications: [AppNotification] = []
    @Published var activeScreen: ActiveScreen = .text
    @Published var statusMessage: String = ""
    
    // 熱鍵設置
    @Published var isHotkeyActive: Bool = false
    @Published var correctionHotkeyString: String = ""
    
    // 其他設置
    @Published var apiKey: String = ""
    @Published var fontSize: CGFloat = 14
    
    // 窗口狀態
    @Published var windowStates: [String: Bool] = [
        "text": false,
        "settings": false,
        "floatingButton": false
    ]
    
    // MARK: - 公共訪問器（用於異步流）
    
    // 提供對isProcessing的異步流訪問
    var processingPublisher: Published<Bool>.Publisher {
        $isProcessing
    }
    
    // 提供對windowStates的異步流訪問
    var windowStatePublisher: Published<[String: Bool]>.Publisher {
        $windowStates
    }
    
    // MARK: - 窗口狀態更新方法
    
    /// 更新窗口狀態
    func updateWindowState(type: String, isOpen: Bool) {
        logger.debug("更新窗口狀態: \(type) -> \(isOpen)")
        windowStates[type] = isOpen
    }
    
    // MARK: - 私有屬性
    
    /// 用於取消訂閱的集合
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - 初始化
    
    private init() {
        logger.info("初始化AppState")
        
        // 載入設置
        Task {
            await loadSettings()
        }
    }
    
    // MARK: - 設置方法
    
    /// 更新視覺效果設置
    func updateVisualEffects(enabled: Bool) {
        isVisualEffectsEnabled = enabled
        Task {
            await saveSetting("visualEffects", value: enabled)
        }
    }
    
    /// 更新粒子效果設置
    func updateParticleEffects(enabled: Bool) {
        isParticleEffectsEnabled = enabled
        Task {
            await saveSetting("particleEffects", value: enabled)
        }
    }
    
    /// 更新熱鍵設置
    func updateHotkeySettings(enabled: Bool) {
        isHotkeyActive = enabled
        Task {
            await saveSetting("hotkeysEnabled", value: enabled)
        }
    }
    
    /// 更新剪貼板監控設置
    func updateClipboardMonitoring(enabled: Bool) {
        isClipboardMonitoringEnabled = enabled
        Task {
            await saveSetting("clipboardMonitoring", value: enabled)
        }
    }
    
    /// 更新API密鑰
    func updateApiKey(_ key: String) {
        apiKey = key
        Task {
            await saveSetting("apiKey", value: key)
        }
    }
    
    /// 更新字體大小
    func updateFontSize(_ size: CGFloat) {
        fontSize = size
        Task {
            await saveSetting("fontSize", value: size)
        }
    }
    
    /// 更新處理狀態
    func updateProcessingStatus(_ isProcessing: Bool) {
        self.isProcessing = isProcessing
    }
    
    /// 更新OpenAI服務可用性
    func updateOpenAIServiceAvailability(_ isAvailable: Bool) {
        isOpenAIServiceAvailable = isAvailable
    }
    
    /// 更新狀態訊息
    func updateStatusMessage(_ message: String) {
        statusMessage = message
    }
    
    // MARK: - 設置持久化
    
    /// 從UserDefaults加載設置
    @MainActor
    private func loadSettings() async {
        logger.info("從UserDefaults加載設置")
        
        let defaults = UserDefaults.standard
        
        isVisualEffectsEnabled = defaults.bool(forKey: "visualEffects")
        isParticleEffectsEnabled = defaults.bool(forKey: "particleEffects")
        isHotkeyActive = defaults.bool(forKey: "hotkeysEnabled")
        correctionHotkeyString = defaults.string(forKey: "correctionHotkey") ?? ""
        isClipboardMonitoringEnabled = defaults.bool(forKey: "clipboardMonitoring")
        apiKey = defaults.string(forKey: "apiKey") ?? ""
        fontSize = defaults.double(forKey: "fontSize") > 0 ? defaults.double(forKey: "fontSize") : 14
        
        // 驗證API密鑰
        isApiKeyValid = !apiKey.isEmpty
    }
    
    /// 保存設置到UserDefaults
    @MainActor
    private func saveSetting<T>(_ key: String, value: T) async {
        logger.info("保存設置: \(key)")
        
        let defaults = UserDefaults.standard
        defaults.set(value, forKey: key)
    }
    
    /// 重置所有設置
    func resetSettings() {
        logger.info("重置所有設置")
        
        isVisualEffectsEnabled = true
        isParticleEffectsEnabled = true
        isHotkeyActive = false
        correctionHotkeyString = ""
        isClipboardMonitoringEnabled = false
        apiKey = ""
        fontSize = 14
        
        // 清除UserDefaults中的設置
        let defaults = UserDefaults.standard
        let keys = ["visualEffects", "particleEffects", "hotkeysEnabled", 
                   "correctionHotkey", "clipboardMonitoring", "apiKey", "fontSize"]
        
        for key in keys {
            defaults.removeObject(forKey: key)
        }
    }
    
    // MARK: - 文本處理方法
    
    /// 更新文本統計信息
    func updateTextStats(originalCharCount: Int, correctedCharCount: Int, processingTime: TimeInterval) {
        logger.info("更新文本統計: 原始字符數: \(originalCharCount), 修正字符數: \(correctedCharCount), 處理時間: \(processingTime)秒")
        
        originalCharacterCount = originalCharCount
        correctedCharacterCount = correctedCharCount
        textProcessingTime = processingTime
    }
    
    // MARK: - 通知方法
    
    /// 添加通知
    func addNotification(type: NotificationType, message: String) {
        logger.info("添加通知: \(type.rawValue) - \(message)")
        
        let notification = AppNotification(
            id: UUID(),
            type: type,
            message: message,
            timestamp: Date()
        )
        
        // 限制通知數量，保留最新的10條
        if notifications.count >= 10 {
            notifications.removeFirst()
        }
        
        notifications.append(notification)
    }
    
    /// 移除通知
    func removeNotification(id: UUID) {
        logger.info("移除通知: \(id)")
        
        notifications.removeAll { $0.id == id }
    }
    
    /// 清除所有通知
    func clearAllNotifications() {
        logger.info("清除所有通知")
        
        notifications.removeAll()
    }
    
    // MARK: - 屏幕導航
    
    /// 設置活動屏幕
    func setActiveScreen(_ screen: ActiveScreen) {
        logger.debug("設置活動屏幕: \(screen.rawValue)")
        activeScreen = screen
    }
    
    /// 更新文本信息
    func updateTextInfo(originalText: String, correctedText: String) {
        logger.info("更新文本信息")
        
        self.originalText = originalText
        self.correctedText = correctedText
        
        // 計算更改的單詞數
        let originalWords = originalText.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        let correctedWords = correctedText.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        
        changedWordsCount = abs(originalWords.count - correctedWords.count)
        
        // 添加通知
        addNotification(type: .info, message: "文本已更新，更改了 \(changedWordsCount) 個單詞")
    }
    
    // MARK: - 調試方法
    
    /// 打印當前狀態用於調試
    func printDebugState() {
        logger.info("""
        === AppState 調試信息 ===
        視覺效果: \(self.isVisualEffectsEnabled)
        粒子效果: \(self.isParticleEffectsEnabled)
        API密鑰有效: \(self.isApiKeyValid)
        處理中: \(self.isProcessing)
        OpenAI服務可用: \(self.isOpenAIServiceAvailable)
        剪貼板監控: \(self.isClipboardMonitoringEnabled)
        熱鍵啟用: \(self.isHotkeyActive)
        熱鍵: \(self.correctionHotkeyString)
        字體大小: \(self.fontSize)
        原始文本長度: \(self.originalText.count)
        修正文本長度: \(self.correctedText.count)
        更改單詞數: \(self.changedWordsCount)
        處理時間: \(self.textProcessingTime)秒
        通知數量: \(self.notifications.count)
        活動螢幕: \(self.activeScreen.rawValue)
        窗口狀態: \(self.windowStates)
        === AppState 調試信息結束 ===
        """)
    }
    
    /// 重置狀態
    func resetState() {
        logger.info("重置狀態")
        
        originalText = ""
        correctedText = ""
        changedWordsCount = 0
        textProcessingTime = 0
        originalCharacterCount = 0
        correctedCharacterCount = 0
        notifications.removeAll()
        statusMessage = ""
        isProcessing = false
    }
}

// MARK: - 支持類型

/// 活動屏幕枚舉
enum ActiveScreen: String, CaseIterable {
    case text = "text"
    case settings = "settings"
    case about = "about"
}

/// 通知類型枚舉
enum NotificationType: String {
    case info
    case success
    case warning
    case error
}

/// 應用通知結構
struct AppNotification: Identifiable, Equatable {
    let id: UUID
    let type: NotificationType
    let message: String
    let timestamp: Date
    
    static func == (lhs: AppNotification, rhs: AppNotification) -> Bool {
        return lhs.id == rhs.id
    }
}

// 定義環境鍵
struct AppStateKey: EnvironmentKey {
    @MainActor
    static var defaultValue: AppState {
        AppState.shared
    }
}

// 擴展EnvironmentValues以包含AppState
extension EnvironmentValues {
    var appState: AppState {
        get { self[AppStateKey.self] }
        set { self[AppStateKey.self] = newValue }
    }
} 
